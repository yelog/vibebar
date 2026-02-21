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

function firstDefined(...values) {
  for (const value of values) {
    if (value !== undefined && value !== null) {
      return value;
    }
  }
  return undefined;
}

function asString(value) {
  if (typeof value === "string" && value.trim().length > 0) {
    return value.trim();
  }
  return undefined;
}

function asInt(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string" && value.trim().length > 0) {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return undefined;
}

function normalizeStatus(value) {
  const raw = asString(value)?.toLowerCase();
  if (!raw) return undefined;

  if (raw === "running" || raw === "busy" || raw === "working") return "running";
  if (raw === "idle" || raw === "ready") return "idle";
  if (
    raw === "awaiting_input" ||
    raw === "awaiting-input" ||
    raw === "awaiting" ||
    raw === "waiting" ||
    raw === "permission"
  ) {
    return "awaiting_input";
  }
  return undefined;
}

function socketPath() {
  const custom = asString(process.env.VIBEBAR_AGENT_SOCKET);
  return custom ?? DEFAULT_SOCKET_PATH;
}

async function sendToAgent(payload) {
  const line = `${JSON.stringify(payload)}\n`;
  const target = socketPath();

  await new Promise((resolve) => {
    const client = net.createConnection({ path: target }, () => {
      client.end(line);
    });

    client.setTimeout(1500);
    client.once("timeout", () => client.destroy());
    client.once("error", () => resolve());
    client.once("close", () => resolve());
  });
}

function buildPayload(session, eventType, status, extras = {}) {
  const payload = {
    version: 1,
    source: "opencode-plugin",
    tool: "opencode",
    session_id: session.sessionID,
    event_type: eventType,
    timestamp: new Date().toISOString(),
    status: status ?? session.status,
    cwd: session.cwd,
    pid: session.pid,
    command: ["opencode"],
    metadata: extras,
  };

  // 删除 undefined 字段，保持事件体简洁。
  for (const key of Object.keys(payload)) {
    if (payload[key] === undefined || payload[key] === null) {
      delete payload[key];
    }
  }

  if (!payload.metadata || Object.keys(payload.metadata).length === 0) {
    delete payload.metadata;
  }

  return payload;
}

function deriveSessionID(context, event) {
  return asString(
    firstDefined(
      event?.sessionID,
      event?.sessionId,
      event?.session_id,
      event?.session?.id,
      event?.properties?.sessionID,
      event?.properties?.sessionId,
      event?.properties?.session_id,
      event?.properties?.session?.id,
      context?.session?.id
    )
  );
}

function deriveCWD(context, event) {
  return asString(
    firstDefined(
      event?.cwd,
      event?.properties?.cwd,
      event?.session?.cwd,
      context?.directory
    )
  );
}

function derivePID(event) {
  return asInt(
    firstDefined(
      event?.pid,
      event?.processID,
      event?.processId,
      event?.properties?.pid,
      event?.properties?.processID,
      event?.properties?.processId
    )
  );
}

function deriveStatus(eventName, event) {
  const name = asString(eventName)?.toLowerCase() ?? "";
  const propertyStatus = normalizeStatus(
    firstDefined(
      event?.status,
      event?.properties?.status,
      event?.properties?.session?.status
    )
  );
  if (propertyStatus) return propertyStatus;

  const idleFlag = firstDefined(event?.idle, event?.properties?.idle);
  if (typeof idleFlag === "boolean") {
    return idleFlag ? "idle" : "running";
  }

  if (name === "permission.asked" || name.includes("permission")) {
    return "awaiting_input";
  }
  if (name.includes("idle")) {
    return "idle";
  }
  if (name.includes("error")) {
    return "idle";
  }
  if (
    name.includes("tool.") ||
    name.includes("execute") ||
    name.includes("progress") ||
    name.includes("start") ||
    name.includes("status")
  ) {
    return "running";
  }
  return undefined;
}

function isTerminalEvent(eventName) {
  const name = asString(eventName)?.toLowerCase() ?? "";
  return (
    name.includes("session.end") ||
    name.includes("session.ended") ||
    name.includes("session.deleted") ||
    name.includes("session.exit")
  );
}

export const VibeBarOpenCodePlugin = async (context = {}) => {
  const sessions = new Map();

  const sendHeartbeat = async () => {
    for (const session of sessions.values()) {
      const payload = buildPayload(session, "heartbeat", session.status);
      await sendToAgent(payload);
    }
  };

  if (HEARTBEAT_MS > 0) {
    const timer = setInterval(() => {
      void sendHeartbeat();
    }, HEARTBEAT_MS);
    timer.unref?.();
  }

  return {
    name: "vibebar-opencode-plugin",
    description: "Report OpenCode runtime state to VibeBar agent",
    event: async ({ event }) => {
      const eventName = asString(event?.type) ?? "unknown";
      const sessionID = deriveSessionID(context, event);
      if (!sessionID) {
        return;
      }

      const cwd = deriveCWD(context, event);
      const pid = derivePID(event);
      const nextStatus = deriveStatus(eventName, event);

      let session = sessions.get(sessionID);
      if (!session) {
        session = {
          sessionID,
          status: nextStatus ?? "running",
          cwd,
          pid,
        };
        sessions.set(sessionID, session);
        await sendToAgent(buildPayload(session, "session_started", session.status));
      }

      if (cwd) session.cwd = cwd;
      if (pid !== undefined) session.pid = pid;

      if (isTerminalEvent(eventName)) {
        await sendToAgent(
          buildPayload(session, "session_ended", session.status, { raw_event: eventName })
        );
        sessions.delete(sessionID);
        return;
      }

      if (nextStatus) {
        session.status = nextStatus;
      }

      await sendToAgent(
        buildPayload(session, "status_changed", session.status, { raw_event: eventName })
      );
    },
  };
};

export default VibeBarOpenCodePlugin;
