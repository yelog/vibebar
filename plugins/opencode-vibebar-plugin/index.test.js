import assert from "node:assert/strict";
import test from "node:test";

process.env.VIBEBAR_PLUGIN_HEARTBEAT_MS = "0";

const { createPluginRuntime } = await import("./index.js");

function deferred() {
  let resolve;
  const promise = new Promise((value) => {
    resolve = value;
  });
  return { promise, resolve };
}

function questionAskedEvent(questions = [
  {
    header: "工作模式",
    question: "接下来怎么做？",
    options: [
      { label: "直接实现", description: "本会话继续修改" },
      { label: "只保留计划", description: "先不写代码" },
    ],
  },
]) {
  return {
    event: {
      type: "question.asked",
      properties: {
        id: "que_123",
        sessionID: "ses_123",
        questions,
      },
    },
  };
}

function permissionAskedEvent() {
  return {
    event: {
      type: "permission.asked",
      properties: {
        id: "per_123",
        permission: "bash",
        patterns: ["swift test"],
      },
    },
  };
}

async function makeFixture({ ctx = {}, interactionResponse, hooks = {} } = {}) {
  const events = [];
  const interactionRequests = [];
  const interactionResponses = [];
  const scheduledTimeouts = [];
  const pendingInteractionResponse = deferred();
  const interactionCompleted = deferred();

  const plugin = await createPluginRuntime(
    { directory: "/tmp/vibebar-opencode-test", client: {}, ...ctx },
    {
      heartbeatMs: 0,
      instanceID: "opencode-test-session",
      processTTY: () => "ttys999",
      sendEvent: async (event) => {
        events.push(event);
        return null;
      },
      sendInteractionRequest: async (request) => {
        interactionRequests.push(request);
        return interactionResponse ?? pendingInteractionResponse.promise;
      },
      sendInteractionResponse: async (rawRequestID, decision) => {
        interactionResponses.push({ rawRequestID, decision });
        interactionCompleted.resolve();
        return null;
      },
      setInterval: () => ({ unref() {} }),
      setTimeout: (callback) => {
        scheduledTimeouts.push(callback);
        return { unref() {} };
      },
      ...hooks,
    },
  );

  events.length = 0;

  return {
    plugin,
    events,
    interactionRequests,
    interactionResponses,
    pendingInteractionResponse,
    flushInteraction: () => interactionCompleted.promise,
    scheduledTimeouts,
  };
}

function statusSequence(events) {
  return events
    .filter((event) => event.event_type === "status_changed")
    .map((event) => event.status);
}

test("question.asked emits awaiting_input before sending interaction_request", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event(questionAskedEvent());

  assert.deepEqual(statusSequence(fixture.events), ["awaiting_input"]);
  assert.equal(fixture.interactionRequests.length, 1);
  assert.equal(fixture.interactionRequests[0].kind, "question");
});

test("question.asked preserves every question as an ordered prompt", async () => {
  const fixture = await makeFixture();
  const questions = [
    {
      header: "工作模式",
      question: "接下来怎么做？",
      options: [{ label: "直接实现", description: "继续修改" }],
      custom: false,
    },
    {
      header: "验证范围",
      question: "运行哪些检查？",
      options: [
        { label: "相关测试", description: "只运行相关测试" },
        { label: "完整测试", description: "运行完整测试" },
      ],
      multiple: true,
      custom: true,
    },
  ];

  await fixture.plugin.event(questionAskedEvent(questions));

  const interaction = fixture.interactionRequests[0];
  assert.equal(interaction.prompts.length, 2);
  assert.deepEqual(
    interaction.prompts.map((prompt) => prompt.id),
    ["question.0", "question.1"],
  );
  assert.equal(interaction.prompts[0].title, "接下来怎么做？");
  assert.equal(interaction.prompts[1].allows_multiple_selection, true);
  assert.equal(interaction.prompts[1].allows_free_text, true);
  assert.equal(interaction.prompts[1].metadata.question_index, "1");
  assert.equal(interaction.transport_context.opencode_session_id, "ses_123");
  assert.equal(interaction.title, "工作模式");
  assert.equal(interaction.message, "接下来怎么做？");
  assert.deepEqual(interaction.options, interaction.prompts[0].options);
});

test("question reply reconstructs ordered answers for every prompt", async () => {
  const replies = [];
  const fixture = await makeFixture({
    ctx: {
      client: {
        question: {
          reply: async (parameters) => {
            replies.push(parameters);
            return {};
          },
        },
      },
    },
    interactionResponse: {
      response: {
        decision: {
          behavior: "select",
          metadata: {
            "answer.question.0": "直接实现",
            "selected_values.question.1": "[\"相关测试\",\"完整测试\"]",
          },
        },
      },
    },
  });

  await fixture.plugin.event(questionAskedEvent([
    {
      header: "工作模式",
      question: "接下来怎么做？",
      options: [{ label: "直接实现" }],
    },
    {
      header: "验证范围",
      question: "运行哪些检查？",
      multiple: true,
      options: [{ label: "相关测试" }, { label: "完整测试" }],
    },
  ]));
  await fixture.flushInteraction();

  assert.deepEqual(replies[0].answers, [
    ["直接实现"],
    ["相关测试", "完整测试"],
  ]);
  assert.deepEqual(fixture.interactionResponses, [
    { rawRequestID: "que_123", decision: undefined },
  ]);
});

test("failed question reply stays pending and sends no running or ack", async () => {
  const fixture = await makeFixture({
    ctx: {
      client: {
        question: {
          reply: async () => ({ error: "not available" }),
        },
      },
      serverUrl: new URL("http://127.0.0.1:1"),
    },
    hooks: {
      fetch: async () => ({ ok: false, status: 503 }),
    },
    interactionResponse: {
      response: {
        decision: { behavior: "select", optionID: "0", metadata: {} },
      },
    },
  });

  await fixture.plugin.event(questionAskedEvent());
  await new Promise((resolve) => setImmediate(resolve));

  assert.deepEqual(fixture.interactionResponses, []);
  assert.equal(fixture.events.some((event) => event.status === "running"), false);
  assert.equal(fixture.scheduledTimeouts.length, 1);
});

test("question.replied racing SDK completion resolves exactly once", async () => {
  const sdkCompleted = deferred();
  const fixture = await makeFixture({
    ctx: {
      client: {
        question: {
          reply: async () => {
            await sdkCompleted.promise;
            return {};
          },
        },
      },
    },
    interactionResponse: {
      response: {
        decision: { behavior: "select", optionID: "0", metadata: {} },
      },
    },
  });

  await fixture.plugin.event(questionAskedEvent());
  await new Promise((resolve) => setImmediate(resolve));
  fixture.events.length = 0;
  await fixture.plugin.event({
    event: {
      type: "question.replied",
      properties: { id: "que_123" },
    },
  });
  sdkCompleted.resolve();
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(
    fixture.interactionResponses.filter((item) => item.rawRequestID === "que_123").length,
    1,
  );
  assert.deepEqual(statusSequence(fixture.events), ["running"]);
  assert.equal(fixture.scheduledTimeouts.length, 0);
});

test("permission.asked emits awaiting_input before sending interaction_request", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event(permissionAskedEvent());

  assert.deepEqual(statusSequence(fixture.events), ["awaiting_input"]);
  assert.equal(fixture.interactionRequests.length, 1);
  assert.equal(fixture.interactionRequests[0].kind, "permission");
});

test("pending question stays awaiting_input during assistant, user, and session progress", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event(questionAskedEvent());
  fixture.events.length = 0;

  await fixture.plugin.event({
    event: {
      type: "message.updated",
      properties: { info: { id: "assistant-msg", role: "assistant" } },
    },
  });
  await fixture.plugin.event({
    event: {
      type: "message.part.updated",
      properties: {
        part: {
          type: "text",
          messageID: "assistant-msg",
          text: "我正在继续分析状态机。",
        },
      },
    },
  });
  await fixture.plugin.event({
    event: {
      type: "message.updated",
      properties: { info: { id: "user-msg", role: "user" } },
    },
  });
  await fixture.plugin.event({
    event: {
      type: "message.part.updated",
      properties: {
        part: {
          type: "text",
          messageID: "user-msg",
          text: "1",
        },
      },
    },
  });
  await fixture.plugin.event({
    event: {
      type: "session.status",
      properties: { status: { type: "busy" } },
    },
  });

  assert.deepEqual(statusSequence(fixture.events), [
    "awaiting_input",
    "awaiting_input",
    "awaiting_input",
  ]);
  assert.equal(
    fixture.events.some((event) => event.status === "running"),
    false,
  );
});

test("question.replied clears pending question and emits running", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event(questionAskedEvent());
  fixture.events.length = 0;

  await fixture.plugin.event({
    event: {
      type: "question.replied",
      properties: { id: "que_123" },
    },
  });

  assert.deepEqual(statusSequence(fixture.events), ["running"]);
  assert.deepEqual(fixture.interactionResponses, [
    { rawRequestID: "que_123", decision: undefined },
  ]);
});

test("assistant tool-calls finish keeps running without idle", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event({
    event: {
      type: "message.updated",
      properties: {
        info: { id: "assistant-msg", role: "assistant", finish: "tool-calls" },
      },
    },
  });

  assert.deepEqual(statusSequence(fixture.events), []);
  assert.equal(
    fixture.events.some((event) => event.status === "idle"),
    false,
  );
});

test("assistant stop finish emits idle", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event({
    event: {
      type: "message.updated",
      properties: {
        info: { id: "assistant-msg", role: "assistant", finish: "stop" },
      },
    },
  });

  assert.deepEqual(statusSequence(fixture.events), ["idle"]);
});

test("assistant stop finish with pending question stays awaiting_input", async () => {
  const fixture = await makeFixture();

  await fixture.plugin.event(questionAskedEvent());
  fixture.events.length = 0;

  await fixture.plugin.event({
    event: {
      type: "message.updated",
      properties: {
        info: { id: "assistant-msg", role: "assistant", finish: "stop" },
      },
    },
  });

  assert.deepEqual(statusSequence(fixture.events), ["awaiting_input"]);
});
