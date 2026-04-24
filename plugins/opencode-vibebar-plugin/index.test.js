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

function questionAskedEvent() {
  return {
    event: {
      type: "question.asked",
      properties: {
        id: "que_123",
        questions: [
          {
            header: "工作模式",
            question: "接下来怎么做？",
            options: [
              { label: "直接实现", description: "本会话继续修改" },
              { label: "只保留计划", description: "先不写代码" },
            ],
          },
        ],
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

async function makeFixture() {
  const events = [];
  const interactionRequests = [];
  const interactionResponses = [];
  const pendingInteractionResponse = deferred();

  const plugin = await createPluginRuntime(
    { directory: "/tmp/vibebar-opencode-test", client: {} },
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
        return pendingInteractionResponse.promise;
      },
      sendInteractionResponse: async (rawRequestID, decision) => {
        interactionResponses.push({ rawRequestID, decision });
        return null;
      },
      setInterval: () => ({ unref() {} }),
      setTimeout: () => ({ unref() {} }),
    },
  );

  events.length = 0;

  return {
    plugin,
    events,
    interactionRequests,
    interactionResponses,
    pendingInteractionResponse,
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
