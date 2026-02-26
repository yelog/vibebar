import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const DEFAULT_SOCKET_PATH = path.join(
  os.homedir(),
  "Library/Application Support/VibeBar/runtime/agent.sock"
);
const HEARTBEAT_MS = Number.parseInt(
  process.env.VIBEBAR_PLUGIN_HEARTBEAT_MS ?? "15000",
  10
);

function socketPath() {
  const custom = process.env.VIBEBAR_AGENT_SOCKET;
  return custom?.trim() || DEFAULT_SOCKET_PATH;
}

function sendToAgent(payload) {
  const line = `${JSON.stringify(payload)}\n`;
  const target = socketPath();

  return new Promise((resolve) => {
    const client = net.createConnection({ path: target }, () => {
      client.end(line);
    });
    client.setTimeout(1500);
    client.once("timeout", () => client.destroy());
    client.once("error", () => resolve());
    client.once("close", () => resolve());
  });
}

function clean(obj) {
  for (const key of Object.keys(obj)) {
    if (obj[key] === undefined || obj[key] === null) {
      delete obj[key];
    }
  }
  return obj;
}

// ---------------------------------------------------------------------------
// One record per OpenCode process.  The "session_id" sent to VibeBar is
// derived from process.pid so that each OpenCode instance maps to exactly
// one row in the VibeBar status bar.
// ---------------------------------------------------------------------------

export const VibeBarOpenCodePlugin = async (ctx = {}) => {
  const { directory } = ctx;
  const instanceID = `opencode-${process.pid}`;
  let currentStatus = "idle";
  let activeToolCalls = 0;  // Track active tool executions to detect subagent activity

  // -- helpers --------------------------------------------------------------

  function makePayload(eventType, status) {
    return clean({
      version: 1,
      source: "opencode-plugin",
      tool: "opencode",
      session_id: instanceID,
      event_type: eventType,
      timestamp: new Date().toISOString(),
      status: status ?? currentStatus,
      pid: process.pid,
      cwd: directory,
      command: ["opencode"],
    });
  }

  function setStatus(next) {
    if (next && next !== currentStatus) {
      currentStatus = next;
    }
  }

  // -- clean up stale sessions from previous runs ---------------------------
  // OpenCode kills plugins with SIGKILL on exit, so exit handlers never run.
  // On startup, delete all old opencode-plugin session files to avoid ghosts.

  const sessionsDir = path.join(
    os.homedir(),
    "Library/Application Support/VibeBar/sessions"
  );

  try {
    for (const file of fs.readdirSync(sessionsDir)) {
      if (file.startsWith("plugin-opencode-plugin-") && file.endsWith(".json")) {
        try { fs.unlinkSync(path.join(sessionsDir, file)); } catch {}
      }
    }
  } catch {}

  // -- initial report (idle on startup) -------------------------------------

  await sendToAgent(makePayload("session_started", "idle"));

  // -- heartbeat ------------------------------------------------------------

  if (HEARTBEAT_MS > 0) {
    const timer = setInterval(() => {
      void sendToAgent(makePayload("heartbeat"));
    }, HEARTBEAT_MS);
    timer.unref?.();
  }

  // -- event handler --------------------------------------------------------

  return {
    event: async ({ event }) => {
      const eventType = event?.type;
      if (!eventType) return;

      let nextStatus;

      switch (eventType) {
        // Session lifecycle
        case "session.status": {
          const st = event.properties?.status?.type;
          if (st === "busy") nextStatus = "running";
          else if (st === "retry") nextStatus = "running";
          else if (st === "idle") {
            // Force reset tool counter when session reports idle status
            activeToolCalls = 0;
            nextStatus = "idle";
          }
          break;
        }
        case "session.idle":
          // Force reset tool counter when session goes idle
          activeToolCalls = 0;
          nextStatus = "idle";
          break;
        case "session.created":
        case "session.updated":
          // Don't override status for mere metadata updates
          break;
        case "session.error":
          // Force reset tool counter on error
          activeToolCalls = 0;
          nextStatus = "idle";
          break;

        // Tool execution tracking (detects subagent activity)
        case "tool.execute.before":
          activeToolCalls++;
          nextStatus = "running";
          break;

        case "tool.execute.after":
          activeToolCalls = Math.max(0, activeToolCalls - 1);
          if (activeToolCalls === 0) {
            nextStatus = "idle";
          }
          break;

        // Permission
        case "permission.updated":
        case "permission.asked":
          nextStatus = "awaiting_input";
          break;

        // Ignore noisy / irrelevant events
        default:
          return;
      }

      if (nextStatus) {
        setStatus(nextStatus);
      }

      await sendToAgent(makePayload("status_changed"));
    },
  };
};

export default VibeBarOpenCodePlugin;
