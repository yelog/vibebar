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

function sendInteractionResponse(rawRequestID, decision) {
  return sendEnvelope({
    kind: "interaction_response",
    response: clean({
      request_id: makeInteractionID(rawRequestID),
      decision,
    }),
  });
}

function makeInteractionID(rawID) {
  return `opencode-${rawID}`;
}

export const VibeBarOpenCodePlugin = async (ctx = {}) => {
  const { directory, serverUrl, client: sdkClient } = ctx;
  const instanceID = `opencode-${process.pid}`;
  const tty = processTTY();
  const effectiveServerURL = resolveServerURL(serverUrl);
  let currentStatus = "idle";
  let permissionPending = false;
  let currentTitle = null;
  let currentTask = null;
  let lastUserMessage = null;
  let runningSummary = null;
  const messageRoles = new Map();

  function summarizeText(text, maxLength = 120) {
    if (!text || typeof text !== "string") return undefined;
    const normalized = text
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find((line) => line.length > 0)
      ?.replace(/\s+/g, " ");

    if (!normalized) return undefined;
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return `${normalized.slice(0, maxLength - 1)}…`;
  }

  function summarizeAssistantPart(part) {
    if (!part || typeof part !== "object") return undefined;

    switch (part.type) {
      case "text":
      case "reasoning":
        return summarizeText(part.text);
      case "tool":
        if (part.state && typeof part.state === "object") {
          if (typeof part.state.title === "string") {
            return summarizeText(part.state.title);
          }
          if (part.state.input && typeof part.state.input === "object") {
            if (typeof part.state.input.description === "string") {
              return summarizeText(part.state.input.description);
            }
            if (typeof part.state.input.command === "string") {
              return summarizeText(part.state.input.command);
            }
          }
        }
        if (typeof part.tool === "string" && part.tool.trim().length > 0) {
          return part.tool.trim();
        }
        return undefined;
      case "patch":
        if (Array.isArray(part.files) && part.files.length > 0) {
          if (part.files.length === 1) {
            const raw = String(part.files[0] ?? "");
            return `更新 ${path.basename(raw)}`;
          }
          return `更新 ${part.files.length} 个文件`;
        }
        return "正在修改文件";
      case "step-start":
        return "处理中";
      case "step-finish":
        return part.reason === "tool-calls" ? "处理中" : undefined;
      default:
        return undefined;
    }
  }

  function isLowSignalUserMessage(text) {
    if (!text || typeof text !== "string") return true;
    const normalized = text.trim().toLowerCase();
    if (!normalized) return true;

    const exactMatches = new Set([
      "好",
      "好的",
      "行",
      "可以",
      "嗯",
      "哦",
      "要",
      "是",
      "否",
      "继续",
      "继续吧",
      "ok",
      "okay",
      "yes",
      "no",
      "continue",
    ]);
    if (exactMatches.has(normalized)) {
      return true;
    }

    return normalized.length <= 2;
  }

  function updateLastUserMessage(text) {
    const summary = summarizeText(text) ?? text;
    if (!summary) return;

    if (lastUserMessage && isLowSignalUserMessage(summary) && !isLowSignalUserMessage(lastUserMessage)) {
      return;
    }

    lastUserMessage = summary;
  }

  function syncLegacyCurrentTask() {
    currentTask = runningSummary ?? lastUserMessage ?? currentTitle;
  }

  function eventMetadata(extra = {}) {
    return clean({
      title: currentTitle,
      current_task: currentTask,
      last_user_message: lastUserMessage,
      running_summary: runningSummary,
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

  function buildServerURL(pathname) {
    if (!effectiveServerURL) return null;
    return new URL(pathname.replace(/^\//, ""), effectiveServerURL);
  }

  async function postJSON(pathname, body) {
    const target = buildServerURL(pathname);
    if (!target) return false;

    try {
      const response = await fetch(target, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      return response.ok;
    } catch (error) {
      console.error("[vibebar-opencode] request failed", pathname, error);
      return false;
    }
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
      options: [
        { id: "once", label: "Allow once" },
        { id: "always", label: "Allow always" },
        { id: "reject", label: "Reject" },
      ],
      allows_free_text: false,
      requested_at: new Date().toISOString(),
      transport_context: {
        source: "opencode-plugin",
        request_kind: "permission",
        opencode_request_id: event.properties.id,
        server_url: effectiveServerURL,
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
        server_url: effectiveServerURL,
      },
    });
  }

  async function replyPermission(requestID, responseEnvelope) {
    const decision = responseEnvelope?.response?.decision;
    if (!decision) return;

    let reply = decision.optionID;
    if (!reply) {
      switch (decision.behavior) {
        case "allow":
          reply = "once";
          break;
        case "deny":
          reply = "reject";
          break;
        default:
          break;
      }
    }
    if (!["once", "always", "reject"].includes(reply)) return;

    const message = decision?.text || decision?.metadata?.reason;

    try {
      if (sdkClient?.permission?.reply) {
        await sdkClient.permission.reply(clean({ requestID, reply, message }));
        return;
      }
    } catch (error) {
      console.error("[vibebar-opencode] SDK permission reply failed", error);
    }

    await postJSON(`permission/${requestID}/reply`, clean({ reply, message }));
  }

  async function replyQuestion(requestID, interaction, responseEnvelope) {
    const decision = responseEnvelope?.response?.decision;
    if (!decision) return;

    let answer = decision.text;
    if (!answer && decision.optionID) {
      answer = interaction.options?.find((option) => option.id === decision.optionID)?.label;
    }
    if (!answer) return;

    try {
      if (sdkClient?.question?.reply) {
        await sdkClient.question.reply({ requestID, answers: [[answer]] });
        return;
      }
    } catch (error) {
      console.error("[vibebar-opencode] SDK question reply failed", error);
    }

    await postJSON(`question/${requestID}/reply`, { answers: [[answer]] });
  }

  function requestPermissionDecision(requestID, interaction) {
    void sendInteractionRequest(interaction).then((response) => replyPermission(requestID, response));
  }

  function requestQuestionDecision(requestID, interaction) {
    void sendInteractionRequest(interaction).then((response) => replyQuestion(requestID, interaction, response));
  }

  function acknowledgeResolvedInteraction(requestID) {
    void sendInteractionResponse(requestID);
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
            syncLegacyCurrentTask();
            await sendEvent(makeEvent("status_changed", currentStatus, {
              title: currentTitle,
            }));
          }
          return;

        case "session.status": {
          const next = properties?.status?.type;
          if (next === "busy" || next === "retry") {
            setStatus("running");
            if (!runningSummary) {
              runningSummary = "处理中";
              syncLegacyCurrentTask();
            }
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
          syncLegacyCurrentTask();
          await sendEvent(makeEvent("status_changed", "idle", {
            current_task: currentTask,
          }));
          return;

        case "message.updated":
          if (properties?.info?.id && properties?.info?.role) {
            messageRoles.set(properties.info.id, properties.info.role);
          }
          return;

        case "message.part.updated": {
          const role = properties?.part?.messageID
            ? messageRoles.get(properties.part.messageID)
            : undefined;
          const part = properties?.part;
          if (!part) return;

          if ((part.type === "text" || part.type === "reasoning") && role === "user" && part.text) {
            updateLastUserMessage(part.text);
            runningSummary = "处理中";
            syncLegacyCurrentTask();
            setStatus("running");
            await sendEvent(makeEvent("status_changed", "running", {
              prompt: part.text,
              last_user_message: lastUserMessage,
              running_summary: runningSummary,
              current_task: currentTask,
            }));
            return;
          }

          if (role === "assistant") {
            const summary = summarizeAssistantPart(part);
            if (!summary) return;

            runningSummary = summary;
            syncLegacyCurrentTask();
            if (!currentTitle && part.type === "text") {
              currentTitle = summary.slice(0, 60);
            }
            if (currentStatus === "running") {
              await sendEvent(makeEvent("status_changed", "running", {
                running_summary: runningSummary,
                current_task: currentTask,
              }));
            }
          }
          return;
        }

        case "permission.asked": {
          const interaction = buildPermissionInteraction(event);
          runningSummary = interaction.title || interaction.message;
          syncLegacyCurrentTask();
          setStatus("awaiting_input", true);
          requestPermissionDecision(properties.id, interaction);
          return;
        }

        case "permission.replied":
          permissionPending = false;
          setStatus("running", true);
          acknowledgeResolvedInteraction(properties.requestID);
          await sendEvent(makeEvent("status_changed", "running"));
          return;

        case "question.asked": {
          const interaction = buildQuestionInteraction(event);
          if (!interaction) return;
          runningSummary = interaction.title || interaction.message;
          syncLegacyCurrentTask();
          setStatus("awaiting_input", true);
          requestQuestionDecision(properties.id, interaction);
          return;
        }

        case "question.replied":
        case "question.rejected":
          permissionPending = false;
          setStatus("running", true);
          acknowledgeResolvedInteraction(properties.requestID);
          await sendEvent(makeEvent("status_changed", "running"));
          return;

        default:
          return;
      }
    },
  };
};

function resolveServerURL(serverUrl) {
  if (!serverUrl) return null;

  try {
    const raw = serverUrl.toString();
    const parsed = new URL(raw);
    if (parsed.port === "0") {
      const fallbackPort = process.env.OPENCODE_PORT?.trim() || "4096";
      return `http://127.0.0.1:${fallbackPort}`;
    }
    return raw;
  } catch {
    return null;
  }
}

export default VibeBarOpenCodePlugin;
