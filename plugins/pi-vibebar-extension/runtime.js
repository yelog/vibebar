import net from "node:net";
import os from "node:os";
import path from "node:path";

const DEFAULT_SOCKET_PATH = path.join(
  os.homedir(),
  "Library/Application Support/VibeBar/runtime/agent.sock"
);

const SUMMARY_THROTTLE_MS = 500;
const SUMMARY_LIMIT = 200;
const TOOL_SUMMARY_LIMIT = 120;

const TERMINAL_ENV_KEYS = [
  "TERM_PROGRAM",
  "TERM_SESSION_ID",
  "ITERM_SESSION_ID",
  "KITTY_WINDOW_ID",
  "KITTY_LISTEN_ON",
  "GHOSTTY_SURFACE_ID",
  "WEZTERM_PANE",
  "WEZTERM_UNIX_SOCKET",
  "TMUX",
  "TMUX_PANE",
  "ZELLIJ",
  "ZELLIJ_SESSION_NAME",
  "ZELLIJ_PANE_ID",
  "ZELLIJ_TAB_NAME",
  "ZELLIJ_TAB_INDEX",
  "__CFBundleIdentifier",
];

function socketPath() {
  const custom = process.env.VIBEBAR_AGENT_SOCKET;
  return custom?.trim() || DEFAULT_SOCKET_PATH;
}

function defaultSendEvent(event) {
  const payload = `${JSON.stringify({ kind: "event", event })}\n`;
  return new Promise((resolve) => {
    const client = net.createConnection({ path: socketPath() }, () => {
      client.write(payload);
      client.end();
      resolve(true);
    });
    client.setTimeout(1500);
    client.once("timeout", () => {
      client.destroy();
      resolve(false);
    });
    client.once("error", () => resolve(false));
  });
}

function clean(value) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function bound(value, limit = SUMMARY_LIMIT) {
  const trimmed = clean(value);
  if (!trimmed) return undefined;
  if (trimmed.length <= limit) return trimmed;
  return `${trimmed.slice(0, limit - 1)}…`;
}

function terminalMetadata() {
  const metadata = {};
  for (const key of TERMINAL_ENV_KEYS) {
    const value = clean(process.env[key]);
    if (value) metadata[key] = value;
  }
  return metadata;
}

function sessionIDFrom(ctx, event) {
  const sessionManager = ctx?.sessionManager;
  const direct = clean(event?.sessionId ?? event?.sessionID ?? event?.id);
  if (direct) return direct;
  if (sessionManager && typeof sessionManager.getSessionId === "function") {
    const value = clean(sessionManager.getSessionId());
    if (value) return value;
  }
  return `pid-${process.pid}`;
}

function sessionFileFrom(ctx) {
  const sessionManager = ctx?.sessionManager;
  if (sessionManager && typeof sessionManager.getSessionFile === "function") {
    return clean(sessionManager.getSessionFile());
  }
  return undefined;
}

function sessionTitleFrom(ctx) {
  const sessionManager = ctx?.sessionManager;
  if (sessionManager && typeof sessionManager.getSessionName === "function") {
    const value = clean(sessionManager.getSessionName());
    if (value) return value;
  }
  if (sessionManager && typeof sessionManager.getHeader === "function") {
    try {
      const header = sessionManager.getHeader();
      return clean(header?.title);
    } catch {
      return undefined;
    }
  }
  return undefined;
}

function cwdFrom(ctx) {
  return clean(ctx?.cwd) ?? undefined;
}

function toolInputSummary(toolName, args) {
  const candidates = [
    args?.command,
    args?.path,
    args?.file_path,
    args?.url,
    args?.pattern,
  ];
  for (const candidate of candidates) {
    const value = bound(candidate, TOOL_SUMMARY_LIMIT);
    if (value) return value;
  }
  if (toolName === "read" || toolName === "edit" || toolName === "write") {
    const pathValue = args?.path ?? args?.file_path;
    if (pathValue) return bound(pathValue, TOOL_SUMMARY_LIMIT);
  }
  return undefined;
}

function assistantText(message) {
  if (!message || typeof message !== "object") return undefined;
  const content = message.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    const text = content
      .filter((block) => block && block.type === "text" && typeof block.text === "string")
      .map((block) => block.text)
      .join(" ");
    return text.length > 0 ? text : undefined;
  }
  return undefined;
}

export function createVibeBarExtension(options) {
  const {
    source,
    tool,
    executable,
    settledEvent,
    transport = { sendEvent: defaultSendEvent },
    scheduleTimeout = setTimeout,
    clearScheduled = clearTimeout,
  } = options;

  let summaryTimer = null;
  let pendingSummary = null;

  function send(event) {
    const payload = {
      version: 1,
      source,
      tool,
      session_id: event.sessionID,
      event_type: event.eventType,
      timestamp: new Date().toISOString(),
      pid: process.pid,
      parent_pid: process.ppid,
      cwd: event.cwd,
      command: [executable],
      metadata: event.metadata,
    };
    if (event.status) payload.status = event.status;
    if (event.notes) payload.notes = event.notes;

    try {
      const result = transport.sendEvent(payload);
      if (result && typeof result.catch === "function") {
        result.catch(() => {});
      }
    } catch {
      // Socket failures must never break the host agent.
    }
  }

  function baseEvent(ctx, event, eventType, status, extraMetadata = {}) {
    return {
      sessionID: sessionIDFrom(ctx, event),
      eventType,
      status,
      cwd: cwdFrom(ctx),
      metadata: {
        ...terminalMetadata(),
        ...extraMetadata,
      },
    };
  }

  function queueSummary(ctx, event, summary) {
    const boundedSummary = bound(summary, SUMMARY_LIMIT);
    if (!boundedSummary) return;
    pendingSummary = boundedSummary;
    if (summaryTimer) return;

    summaryTimer = scheduleTimeout(() => {
      summaryTimer = null;
      const summary = pendingSummary;
      pendingSummary = null;
      if (!summary) return;
      send(
        baseEvent(ctx, event, "status_changed", "running", {
          running_summary: summary,
        })
      );
    }, SUMMARY_THROTTLE_MS);
  }

  function register(pi) {
    pi.on("session_start", (event, ctx) => {
      const extra = {};
      const title = sessionTitleFrom(ctx);
      if (title) extra.title = title;
      const transcriptPath = sessionFileFrom(ctx);
      if (transcriptPath) extra.transcript_path = transcriptPath;

      send(baseEvent(ctx, event, "status_changed", "idle", extra));
    });

    pi.on("input", (event, ctx) => {
      const text = bound(event?.text ?? event?.prompt);
      const extra = {};
      if (text) {
        extra.last_user_message = text;
        extra.current_task = text;
      }
      send(baseEvent(ctx, event, "status_changed", "running", extra));
    });

    pi.on("agent_start", (event, ctx) => {
      const extra = {};
      const title = sessionTitleFrom(ctx);
      if (title) extra.title = title;
      const model = bound(event?.model ?? event?.modelId);
      if (model) extra.model = model;
      send(baseEvent(ctx, event, "status_changed", "running", extra));
    });

    pi.on("message_update", (event, ctx) => {
      queueSummary(ctx, event, assistantText(event?.message));
    });

    pi.on("tool_execution_start", (event, ctx) => {
      const extra = { tool_name: bound(event?.toolName) ?? "tool" };
      const summary = toolInputSummary(event?.toolName, event?.args);
      if (summary) extra.tool_input_summary = summary;
      send(baseEvent(ctx, event, "status_changed", "running", extra));
    });

    pi.on("tool_execution_update", (event, ctx) => {
      const extra = { tool_name: bound(event?.toolName) ?? "tool" };
      send(baseEvent(ctx, event, "status_changed", "running", extra));
    });

    pi.on(settledEvent, (event, ctx) => {
      send(baseEvent(ctx, event, "status_changed", "idle"));
    });

    pi.on("session_shutdown", (event, ctx) => {
      if (summaryTimer) {
        clearScheduled(summaryTimer);
        summaryTimer = null;
        pendingSummary = null;
      }
      const extra = {};
      const reason = bound(event?.reason);
      if (reason) extra.shutdown_reason = reason;
      send(baseEvent(ctx, event, "session_ended", undefined, extra));
    });
  }

  return register;
}

export default createVibeBarExtension;
