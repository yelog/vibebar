import { test } from "node:test";
import assert from "node:assert/strict";
import { createVibeBarExtension } from "./runtime.js";

function makeHarness(options = {}) {
  const sent = [];
  const handlers = {};
  const pendingTimers = [];

  const pi = {
    on(eventName, handler) {
      handlers[eventName] = handler;
    },
  };

  const runtime = createVibeBarExtension({
    source: options.source ?? "pi-extension",
    tool: options.tool ?? "pi",
    executable: options.executable ?? "pi",
    settledEvent: options.settledEvent ?? "agent_settled",
    transport: options.transport ?? {
      sendEvent: async (event) => {
        sent.push(event);
        return true;
      },
    },
    scheduleTimeout: (fn, ms) => {
      pendingTimers.push({ fn, ms });
    },
    clearScheduled: () => {},
  });

  const register = runtime;
  register(pi);

  return {
    sent,
    handlers,
    pendingTimers,
    async fire(name, event = {}, ctx = {}) {
      const handler = handlers[name];
      assert.ok(handler, `no handler registered for ${name}`);
      await handler(event, { sessionManager: {}, cwd: "/work/project", ...ctx });
    },
    flushTimers() {
      for (const timer of pendingTimers.splice(0)) {
        timer.fn();
      }
    },
  };
}

test("pi events carry pi source, tool, and command", async () => {
  const h = makeHarness({ source: "pi-extension", tool: "pi", executable: "pi" });
  await h.fire("session_start", { reason: "startup" });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].source, "pi-extension");
  assert.equal(h.sent[0].tool, "pi");
  assert.deepEqual(h.sent[0].command, ["pi"]);
});

test("omp events carry oh-my-pi source, tool, and command", async () => {
  const h = makeHarness({
    source: "oh-my-pi-extension",
    tool: "oh-my-pi",
    executable: "omp",
  });
  await h.fire("session_start", { reason: "startup" });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].source, "oh-my-pi-extension");
  assert.equal(h.sent[0].tool, "oh-my-pi");
  assert.deepEqual(h.sent[0].command, ["omp"]);
});

test("session_start emits idle with full metadata", async () => {
  const h = makeHarness();
  const sessionManager = {
    getSessionId: () => "abc123",
    getSessionName: () => "Refactor auth",
    getSessionFile: () => "/home/u/.pi/agent/sessions/x/abc123.jsonl",
    getCwd: () => "/work/project",
  };
  await h.fire(
    "session_start",
    { reason: "new" },
    {
      sessionManager,
      cwd: "/work/project",
    }
  );

  assert.equal(h.sent.length, 1);
  const event = h.sent[0];
  assert.equal(event.session_id, "abc123");
  assert.equal(event.event_type, "status_changed");
  assert.equal(event.status, "idle");
  assert.equal(event.cwd, "/work/project");
  assert.equal(event.pid, process.pid);
  assert.equal(event.parent_pid, process.ppid);
  assert.equal(event.metadata.title, "Refactor auth");
  assert.equal(event.metadata.transcript_path, "/home/u/.pi/agent/sessions/x/abc123.jsonl");
  assert.equal(event.metadata.TERM_PROGRAM, process.env.TERM_PROGRAM ?? undefined);
});

test("session_start tolerates missing optional session manager accessors", async () => {
  const h = makeHarness();
  await h.fire("session_start", { reason: "startup" }, { sessionManager: {} });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].session_id, `pid-${process.pid}`);
  assert.equal(h.sent[0].metadata.title, undefined);
});

test("input emits running with user message metadata", async () => {
  const h = makeHarness();
  await h.fire("input", { text: "fix the flaky test" });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].status, "running");
  assert.equal(h.sent[0].metadata.last_user_message, "fix the flaky test");
  assert.equal(h.sent[0].metadata.current_task, "fix the flaky test");
});

test("agent_start emits running with model metadata", async () => {
  const h = makeHarness();
  await h.fire("agent_start", { model: "anthropic/claude-sonnet" });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].status, "running");
  assert.equal(h.sent[0].metadata.model, "anthropic/claude-sonnet");
});

test("tool_execution_start emits running with bounded tool summary", async () => {
  const h = makeHarness();
  await h.fire("tool_execution_start", {
    toolCallId: "call_1",
    toolName: "bash",
    args: { command: "npm test -- --run" },
  });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].status, "running");
  assert.equal(h.sent[0].metadata.tool_name, "bash");
  assert.equal(h.sent[0].metadata.tool_input_summary, "npm test -- --run");
});

test("pi agent_settled emits idle", async () => {
  const h = makeHarness({ settledEvent: "agent_settled" });
  await h.fire("agent_settled", {});
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].status, "idle");
});

test("omp session_stop emits idle", async () => {
  const h = makeHarness({ settledEvent: "session_stop" });
  await h.fire("session_stop", {});
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].status, "idle");
});

test("session_shutdown emits session_ended without status", async () => {
  const h = makeHarness();
  await h.fire("session_shutdown", { reason: "quit" });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].event_type, "session_ended");
  assert.equal(h.sent[0].status, undefined);
  assert.equal(h.sent[0].metadata.shutdown_reason, "quit");
});

test("message_update coalesces into one trailing bounded summary", async () => {
  const h = makeHarness();
  const longText = "x".repeat(500);
  for (let i = 0; i < 5; i += 1) {
    await h.fire("message_update", {
      message: { content: [{ type: "text", text: `update ${i}` }] },
    });
  }
  assert.equal(h.sent.length, 0);
  h.flushTimers();
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].status, "running");
  assert.ok(h.sent[0].metadata.running_summary.length <= 200);
});

test("message_update summary is bounded", async () => {
  const h = makeHarness();
  await h.fire("message_update", {
    message: { content: [{ type: "text", text: longText() }] },
  });
  h.flushTimers();
  assert.equal(h.sent.length, 1);
  assert.ok(h.sent[0].metadata.running_summary.length <= 200);
});

test("session_shutdown clears pending summary timer", async () => {
  let cleared = false;
  const sent = [];
  const handlers = {};
  const timers = [];
  const pi = { on: (n, fn) => (handlers[n] = fn) };
  createVibeBarExtension({
    source: "pi-extension",
    tool: "pi",
    executable: "pi",
    settledEvent: "agent_settled",
    transport: {
      sendEvent: async (event) => {
        sent.push(event);
        return true;
      },
    },
    scheduleTimeout: (fn) => timers.push(fn),
    clearScheduled: () => {
      cleared = true;
    },
  })(pi);

  await handlers.message_update(
    { message: { content: [{ type: "text", text: "partial" }] } },
    { sessionManager: {} }
  );
  assert.equal(cleared, false);
  await handlers.session_shutdown({ reason: "quit" }, { sessionManager: {} });
  assert.equal(cleared, true);
  assert.equal(timers.length, 1);
});

test("socket transport failure does not throw", async () => {
  const h = makeHarness({
    transport: {
      sendEvent: async () => {
        throw new Error("socket unavailable");
      },
    },
  });
  await h.fire("session_start", { reason: "startup" });
  await h.fire("input", { text: "hello" });
  assert.equal(h.sent.length, 0);
});

function longText() {
  return "y".repeat(1000);
}

test("rename via /rename is reflected on subsequent events", async () => {
  const h = makeHarness();
  let sessionName = undefined;
  const sessionManager = {
    getSessionId: () => "rename-sess",
    getSessionName: () => sessionName,
    getSessionFile: () => "/home/u/.omp/agent/sessions/x/rename-sess.jsonl",
  };

  await h.fire("session_start", { reason: "new" }, { sessionManager });
  assert.equal(h.sent.length, 1);
  assert.equal(h.sent[0].metadata.title, undefined);

  sessionName = "测试 oh-my-pi";
  await h.fire("input", { text: "继续" }, { sessionManager });
  const last = h.sent[h.sent.length - 1];
  assert.equal(last.metadata.title, "测试 oh-my-pi");
});

test("title falls back to header title when getSessionName is unavailable", async () => {
  const h = makeHarness();
  await h.fire(
    "input",
    { text: "go" },
    {
      sessionManager: {
        getHeader: () => ({ title: "from-header" }),
      },
    }
  );
  const last = h.sent[h.sent.length - 1];
  assert.equal(last.metadata.title, "from-header");
});
