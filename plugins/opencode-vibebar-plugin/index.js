import net from "node:net";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const DEFAULT_SOCKET_PATH = path.join(
  os.homedir(),
  "Library/Application Support/VibeBar/runtime/agent.sock"
);
const HEARTBEAT_MS = Number.parseInt(
  process.env.VIBEBAR_PLUGIN_HEARTBEAT_MS ?? "15000",
  10
);
const INTERACTION_TIMEOUT_MS = Number.parseInt(
  process.env.VIBEBAR_PLUGIN_INTERACTION_TIMEOUT_MS ?? "300000",
  10
);

function socketPath() {
  const custom = process.env.VIBEBAR_AGENT_SOCKET;
  return custom?.trim() || DEFAULT_SOCKET_PATH;
}

function clean(obj) {
  for (const key of Object.keys(obj)) {
    if (obj[key] === undefined || obj[key] === null) {
      delete obj[key];
    }
  }
  return obj;
}

function processTTY() {
  try {
    const tty = execFileSync(
      "/bin/ps",
      ["-o", "tty=", "-p", String(process.pid)],
      { encoding: "utf8" }
    ).trim();
    return tty && tty !== "??" ? tty : undefined;
  } catch {
    return undefined;
  }
}

function sendEnvelope(envelope, waitForResponse = false, timeoutMs = 1500) {
  const payload = `${JSON.stringify(envelope)}\n`;
  const target = socketPath();

  return new Promise((resolve) => {
    const client = net.createConnection({ path: target }, () => {
      client.write(payload);
      client.end();
      if (!waitForResponse) {
        resolve(null);
      }
    });

    let buffer = "";
    client.setTimeout(timeoutMs);
    client.on("data", (chunk) => {
      buffer += chunk.toString();
    });
    client.once("timeout", () => {
      client.destroy();
      resolve(null);
    });
    client.once("error", () => resolve(null));
    client.once("close", () => {
      if (!waitForResponse) return;
      try {
        resolve(JSON.parse(buffer.trim()));
      } catch {
        resolve(null);
      }
    });
  });
}

function sendEvent(event) {
  return sendEnvelope({ kind: "event", event });
}

function sendInteractionRequest(request, timeoutMs = INTERACTION_TIMEOUT_MS) {
  return sendEnvelope({ kind: "interaction_request", request }, true, timeoutMs);
}

function makeInteractionID(rawID) {
  return `opencode-${rawID}`;
}

export const VibeBarOpenCodePlugin = async (ctx = {}) => {
  const { directory, client, serverUrl } = ctx;
  const instanceID = `opencode-${process.pid}`;
  const serverPort = serverUrl ? parseInt(serverUrl.port, 10) || 4096 : 4096;
  const internalFetch = client?._client?.getConfig?.()?.fetch || null;
  const tty = processTTY();
  let currentStatus = "idle";
  let permissionPending = false;
  let currentTitle = null;
  let currentTask = null;
  const messageRoles = new Map();

  function eventMetadata(extra = {}) {
    return clean({
      title: currentTitle,
      current_task: currentTask,
      source: "cli",
      _tty: tty,
      TERM_PROGRAM: process.env.TERM_PROGRAM,
      TERM_SESSION_ID: process.env.TERM_SESSION_ID,
      ITERM_SESSION_ID: process.env.ITERM_SESSION_ID,
      KITTY_WINDOW_ID: process.env.KITTY_WINDOW_ID,
      KITTY_LISTEN_ON: process.env.KITTY_LISTEN_ON,
      GHOSTTY_SURFACE_ID: process.env.GHOSTTY_SURFACE_ID,
      WEZTERM_PANE: process.env.WEZTERM_PANE,
      WEZTERM_UNIX_SOCKET: process.env.WEZTERM_UNIX_SOCKET,
      TMUX: process.env.TMUX,
      TMUX_PANE: process.env.TMUX_PANE,
      ZELLIJ: process.env.ZELLIJ,
      ZELLIJ_SESSION_NAME: process.env.ZELLIJ_SESSION_NAME,
      ZELLIJ_PANE_ID: process.env.ZELLIJ_PANE_ID,
      ZELLIJ_TAB_NAME: process.env.ZELLIJ_TAB_NAME,
      ZELLIJ_TAB_INDEX: process.env.ZELLIJ_TAB_INDEX,
      __CFBundleIdentifier: process.env.__CFBundleIdentifier,
      ...extra,
    });
  }

  function makeEvent(eventType, status, metadata = {}) {
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
      metadata: eventMetadata(metadata),
    });
  }

  function setStatus(next, force = false) {
    if (!next) return;
    if (force) {
      currentStatus = next;
      return;
    }
    if (next === "awaiting_input") {
      permissionPending = true;
      currentStatus = next;
      return;
    }
    if (permissionPending && next === "running") {
      permissionPending = false;
    }
    currentStatus = next;
  }

  function buildPermissionInteraction(event) {
    const permission = event?.properties?.permission || "operation";
    const patterns = event?.properties?.patterns || [];
    const label = permission.charAt(0).toUpperCase() + permission.slice(1);
    const message = patterns.length > 0 ? patterns.join(" · ") : `允许 ${label} 继续执行`;
    return clean({
      id: makeInteractionID(event.properties.id),
      session_id: instanceID,
      tool: "opencode",
      kind: "permission",
      title: `需要确认：${label}`,
      message,
      options: [],
      allows_free_text: false,
      requested_at: new Date().toISOString(),
      transport_context: {
        source: "opencode-plugin",
        request_kind: "permission",
        opencode_request_id: event.properties.id,
      },
    });
  }

  function buildQuestionInteraction(event) {
    const question = event?.properties?.questions?.[0];
    if (!question) return null;

    const options = (question.options || []).map((option, index) => ({
      id: String(index),
      label: option.label,
      detail: option.description,
    }));

    return clean({
      id: makeInteractionID(event.properties.id),
      session_id: instanceID,
      tool: "opencode",
      kind: "question",
      title: question.header || "需要回答",
      message: question.question || "请选择一个选项",
      options,
      allows_free_text: Boolean(question.text),
      requested_at: new Date().toISOString(),
      transport_context: {
        source: "opencode-plugin",
        request_kind: "question",
        opencode_request_id: event.properties.id,
        question_header: question.header || "",
      },
    });
  }

  async function replyPermission(requestID, responseEnvelope) {
    if (!internalFetch) return;
    const decision = responseEnvelope?.response?.decision;
    const behavior = decision?.behavior;
    if (!behavior) return;

    const reply = behavior === "allow" ? "once" : "reject";
    const message = decision?.text || decision?.metadata?.reason;

    try {
      await internalFetch(new Request(`http://localhost:${serverPort}/permission/${requestID}/reply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(clean({ reply, message })),
      }));
    } catch {}
  }

  async function replyQuestion(requestID, interaction, responseEnvelope) {
    if (!internalFetch) return;
    const decision = responseEnvelope?.response?.decision;
    if (!decision) return;

    let answer = decision.text;
    if (!answer && decision.optionID) {
      answer = interaction.options?.find((option) => option.id === decision.optionID)?.label;
    }
    if (!answer) return;

    try {
      await internalFetch(new Request(`http://localhost:${serverPort}/question/${requestID}/reply`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ answers: [[answer]] }),
      }));
    } catch {}
  }

  await sendEvent(makeEvent("session_started", "idle"));

  if (HEARTBEAT_MS > 0) {
    const timer = setInterval(() => {
      void sendEvent(makeEvent("heartbeat"));
    }, HEARTBEAT_MS);
    timer.unref?.();
  }

  return {
    event: async ({ event }) => {
      const eventType = event?.type;
      const properties = event?.properties || {};
      if (!eventType) return;

      switch (eventType) {
        case "session.created":
          currentStatus = "idle";
          await sendEvent(makeEvent("session_started", "idle"));
          return;

        case "session.updated":
          if (properties?.info?.title && !properties.info.title.startsWith("New session")) {
            currentTitle = properties.info.title;
            if (!currentTask) {
              currentTask = properties.info.title;
            }
            await sendEvent(makeEvent("status_changed", currentStatus, {
              title: currentTitle,
            }));
          }
          return;

        case "session.status": {
          const next = properties?.status?.type;
          if (next === "busy" || next === "retry") {
            setStatus("running");
          } else if (next === "idle") {
            permissionPending = false;
            setStatus("idle", true);
          }
          await sendEvent(makeEvent("status_changed"));
          return;
        }

        case "session.idle":
          permissionPending = false;
          setStatus("idle", true);
          await sendEvent(makeEvent("status_changed"));
          return;

        case "session.error":
          permissionPending = false;
          setStatus("idle", true);
          await sendEvent(makeEvent("status_changed", "idle", {
            current_task: currentTask,
          }));
          return;

        case "message.updated":
          if (properties?.info?.id && properties?.info?.role) {
            messageRoles.set(properties.info.id, properties.info.role);
          }
          return;

        case "message.part.updated":
          if (properties?.part?.type === "text") {
            const role = properties?.part?.messageID
              ? messageRoles.get(properties.part.messageID)
              : undefined;
            const text = properties?.part?.text || "";
            if (role === "user" && text) {
              currentTask = text;
              setStatus("running");
              await sendEvent(makeEvent("status_changed", "running", {
                prompt: text,
                current_task: text,
              }));
            } else if (role === "assistant" && text && !currentTitle) {
              currentTitle = text.slice(0, 60);
            }
          }
          return;

        case "permission.asked": {
          const interaction = buildPermissionInteraction(event);
          currentTask = interaction.title || interaction.message;
          setStatus("awaiting_input", true);
          const response = await sendInteractionRequest(interaction);
          await replyPermission(properties.id, response);
          return;
        }

        case "permission.replied":
          permissionPending = false;
          setStatus("running", true);
          await sendEvent(makeEvent("status_changed", "running"));
          return;

        case "question.asked": {
          const interaction = buildQuestionInteraction(event);
          if (!interaction) return;
          currentTask = interaction.title || interaction.message;
          setStatus("awaiting_input", true);
          const response = await sendInteractionRequest(interaction);
          await replyQuestion(properties.id, interaction, response);
          return;
        }

        case "question.replied":
        case "question.rejected":
          permissionPending = false;
          setStatus("running", true);
          await sendEvent(makeEvent("status_changed", "running"));
          return;

        default:
          return;
      }
    },
  };
};

export default VibeBarOpenCodePlugin;
