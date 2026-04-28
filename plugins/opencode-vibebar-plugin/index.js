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
  process.env.VIBEBAR_PLUGIN_INTERACTION_TIMEOUT_MS ?? "3600000",
  10
);
const INTERACTION_RETRY_DELAY_MS = Number.parseInt(
  process.env.VIBEBAR_PLUGIN_INTERACTION_RETRY_DELAY_MS ?? "1000",
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
  if (!rawRequestID) return Promise.resolve(null);
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

export async function createPluginRuntime(ctx = {}, hooks = {}) {
  const { directory, client: sdkClient, serverUrl } = ctx;
  const instanceID = hooks.instanceID ?? `opencode-${process.pid}`;
  const tty = hooks.processTTY?.() ?? processTTY();
  const sendEventFn = hooks.sendEvent ?? sendEvent;
  const sendInteractionRequestFn = hooks.sendInteractionRequest ?? sendInteractionRequest;
  const sendInteractionResponseFn = hooks.sendInteractionResponse ?? sendInteractionResponse;
  const scheduleTimeout = hooks.setTimeout ?? setTimeout;
  const scheduleInterval = hooks.setInterval ?? setInterval;
  const heartbeatMs = hooks.heartbeatMs ?? HEARTBEAT_MS;
  let currentStatus = "idle";
  let permissionPending = false;
  let currentTitle = null;
  let currentTask = null;
  let lastUserMessage = null;
  let runningSummary = null;
  let activeInteraction = null;
  const interactionQueue = [];
  const resolvedInteractionIDs = new Set();
  const messageRoles = new Map();

  function normalizedBaseURL(candidate) {
    if (!candidate) return null;

    try {
      if (candidate instanceof URL) {
        return candidate;
      }

      const text = String(candidate).trim();
      if (!text) return null;
      return new URL(text);
    } catch {
      return null;
    }
  }

  function replyBaseURL(interaction) {
    const explicit = normalizedBaseURL(serverUrl)
      || normalizedBaseURL(interaction?.transport_context?.server_url);
    if (explicit) return explicit;

    const port = (process.env.OPENCODE_PORT || "4096").trim() || "4096";
    return normalizedBaseURL(`http://127.0.0.1:${port}`);
  }

  function buildReplyURL(interaction, requestID, kind, action = "reply") {
    const baseURL = replyBaseURL(interaction);
    if (!baseURL || !requestID) return null;

    let route;
    if (kind === "permission") {
      route = `permission/${requestID}/reply`;
    } else if (kind === "question" && action === "reject") {
      route = `question/${requestID}/reject`;
    } else if (kind === "question") {
      route = `question/${requestID}/reply`;
    } else {
      return null;
    }

    return new URL(route, baseURL);
  }

  async function postReplyJSON(url, body, label) {
    if (!url) return false;

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(2000),
      });
      if (!response.ok) {
        console.error(`[vibebar-opencode] ${label} failed with status ${response.status}`);
        return false;
      }
      return true;
    } catch (error) {
      console.error(`[vibebar-opencode] ${label} failed`, error);
      return false;
    }
  }

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

  function hasPendingInteractions() {
    return Boolean(activeInteraction || interactionQueue.length > 0);
  }

  function shouldPreserveAwaitingInput() {
    return currentStatus === "awaiting_input" || permissionPending || hasPendingInteractions();
  }

  function emitStatusChanged(status = currentStatus, metadata = {}) {
    return sendEventFn(makeEvent("status_changed", status, metadata));
  }

  function interactionExpiresAt() {
    return new Date(Date.now() + INTERACTION_TIMEOUT_MS).toISOString();
  }

  function refreshInteractionTiming(interaction) {
    interaction.requested_at = new Date().toISOString();
    interaction.expires_at = interactionExpiresAt();
  }

  function opencodeSessionID(event) {
    return event?.properties?.sessionID || event?.properties?.session?.id;
  }

  function eventRequestID(properties = {}) {
    return properties.requestID || properties.permissionID || properties.id;
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
      expires_at: interactionExpiresAt(),
      transport_context: {
        source: "opencode-plugin",
        request_kind: "permission",
        opencode_request_id: event.properties.id,
        opencode_session_id: opencodeSessionID(event),
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
      expires_at: interactionExpiresAt(),
      transport_context: {
        source: "opencode-plugin",
        request_kind: "question",
        opencode_request_id: event.properties.id,
        opencode_session_id: opencodeSessionID(event),
        question_header: question.header || "",
      },
    });
  }

  function sdkResultOK(result, label) {
    if (!result) return true;
    if (result.error) {
      console.error(`[vibebar-opencode] ${label} failed`, result.error);
      return false;
    }
    if (result.response && !result.response.ok) {
      console.error(`[vibebar-opencode] ${label} failed with status ${result.response.status}`);
      return false;
    }
    return true;
  }

  function questionAnswersFromDecision(decision, interaction) {
    if (!decision) return null;

    const text = decision.text?.trim();
    if (text) {
      return [[text]];
    }

    if (decision.optionID) {
      const label = interaction.options?.find((option) => option.id === decision.optionID)?.label?.trim();
      if (label) {
        return [[label]];
      }
    }

    const metadata = decision.metadata || {};
    const answerKeys = Object.keys(metadata)
      .filter((key) => key.startsWith("answer."))
      .sort();
    if (answerKeys.length === 0) return null;

    const answers = answerKeys
      .map((key) => String(metadata[key] || "").trim())
      .filter(Boolean)
      .map((value) => [value]);

    return answers.length > 0 ? answers : null;
  }

  async function replyPermission(requestID, interaction, responseEnvelope) {
    const decision = responseEnvelope?.response?.decision;
    if (!decision) return false;
    if (isBrokerGeneratedDecision(decision)) return false;

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
    if (!["once", "always", "reject"].includes(reply)) return false;

    const message = decision?.text || decision?.metadata?.reason;

    try {
      if (sdkClient?.permission?.reply) {
        const result = await sdkClient.permission.reply(clean({ requestID, directory, reply, message }));
        if (sdkResultOK(result, "SDK permission.reply")) {
          return true;
        }
      }
    } catch (error) {
      console.error("[vibebar-opencode] SDK permission reply failed", error);
    }

    try {
      if (sdkClient?.postSessionIdPermissionsPermissionId) {
        const sessionID = interaction?.transport_context?.opencode_session_id;
        if (!sessionID) {
          console.error("[vibebar-opencode] default SDK permission reply missing sessionID");
          return false;
        }
        const result = await sdkClient.postSessionIdPermissionsPermissionId(clean({
          path: { id: sessionID, permissionID: requestID },
          query: clean({ directory }),
          body: { response: reply },
        }));
        return sdkResultOK(result, "SDK postSessionIdPermissionsPermissionId");
      }
    } catch (error) {
      console.error("[vibebar-opencode] default SDK permission reply failed", error);
    }

    return postReplyJSON(
      buildReplyURL(interaction, requestID, "permission"),
      clean({ reply, message }),
      "HTTP permission.reply"
    );
  }

  async function replyQuestion(requestID, interaction, responseEnvelope) {
    const decision = responseEnvelope?.response?.decision;
    if (!decision) return false;
    if (isBrokerGeneratedDecision(decision)) return false;

    const shouldReject = decision.behavior === "deny" || decision.optionID === "reject";
    if (shouldReject) {
      try {
        if (sdkClient?.question?.reject) {
          const result = await sdkClient.question.reject(clean({ requestID, directory }));
          return sdkResultOK(result, "SDK question.reject");
        }
      } catch (error) {
        console.error("[vibebar-opencode] SDK question reject failed", error);
      }

      return postReplyJSON(
        buildReplyURL(interaction, requestID, "question", "reject"),
        null,
        "HTTP question.reject"
      );
    }

    const answers = questionAnswersFromDecision(decision, interaction);
    if (!answers) return false;

    try {
      if (sdkClient?.question?.reply) {
        const result = await sdkClient.question.reply(clean({ requestID, directory, answers }));
        return sdkResultOK(result, "SDK question.reply");
      }
    } catch (error) {
      console.error("[vibebar-opencode] SDK question reply failed", error);
    }

    return postReplyJSON(
      buildReplyURL(interaction, requestID, "question"),
      { answers },
      "HTTP question.reply"
    );
  }

  function isBrokerGeneratedDecision(decision) {
    const reason = decision?.metadata?.reason;
    return reason === "timeout" || reason === "superseded";
  }

  function isSupersededResponse(responseEnvelope) {
    return responseEnvelope?.response?.decision?.metadata?.reason === "superseded";
  }

  function removeInteractionID(interactionID) {
    if (!interactionID) return;
    resolvedInteractionIDs.add(interactionID);
    if (activeInteraction?.interaction?.id === interactionID) {
      activeInteraction = null;
    }

    for (let index = interactionQueue.length - 1; index >= 0; index -= 1) {
      if (interactionQueue[index]?.interaction?.id === interactionID) {
        interactionQueue.splice(index, 1);
      }
    }
  }

  async function completeResolvedInteraction(requestID, hasQueuedInteractions = false) {
    await acknowledgeResolvedInteraction(requestID);
    if (hasQueuedInteractions) return;

    permissionPending = false;
    setStatus("running", true);
    await emitStatusChanged("running");
  }

  function enqueueInteraction(requestID, interaction, reply) {
    if (activeInteraction?.interaction?.id === interaction.id) return;
    if (interactionQueue.some((item) => item.interaction?.id === interaction.id)) return;
    interactionQueue.push({ requestID, interaction, reply });
    processInteractionQueue();
  }

  function processInteractionQueue() {
    if (activeInteraction || interactionQueue.length === 0) return;

    const item = interactionQueue.shift();
    activeInteraction = item;
    refreshInteractionTiming(item.interaction);

    void sendInteractionRequestFn(item.interaction).then(async (response) => {
      if (resolvedInteractionIDs.has(item.interaction.id)) {
        if (activeInteraction === item) {
          activeInteraction = null;
        }
        processInteractionQueue();
        return;
      }

      if (isSupersededResponse(response)) {
        resolvedInteractionIDs.add(item.interaction.id);
        if (activeInteraction === item) {
          activeInteraction = null;
        }
        processInteractionQueue();
        return;
      }

      const success = await item.reply(item.requestID, item.interaction, response);
      if (success) {
        resolvedInteractionIDs.add(item.interaction.id);
        if (activeInteraction === item) {
          activeInteraction = null;
        }
        await completeResolvedInteraction(item.requestID, interactionQueue.length > 0);
        processInteractionQueue();
        return;
      }

      if (activeInteraction !== item) {
        processInteractionQueue();
        return;
      }

      activeInteraction = null;
      interactionQueue.unshift(item);
      scheduleTimeout(processInteractionQueue, INTERACTION_RETRY_DELAY_MS).unref?.();
    });
  }

  function removeQueuedInteraction(requestID) {
    if (!requestID) return;
    removeInteractionID(makeInteractionID(requestID));
  }

  function requestPermissionDecision(requestID, interaction) {
    enqueueInteraction(requestID, interaction, replyPermission);
  }

  function requestQuestionDecision(requestID, interaction) {
    enqueueInteraction(requestID, interaction, replyQuestion);
  }

  function acknowledgeResolvedInteraction(requestID) {
    return sendInteractionResponseFn(requestID);
  }

  await sendEventFn(makeEvent("session_started", "idle"));

  if (heartbeatMs > 0) {
    const timer = scheduleInterval(() => {
      void sendEventFn(makeEvent("heartbeat"));
    }, heartbeatMs);
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
          await sendEventFn(makeEvent("session_started", "idle"));
          return;

        case "session.updated":
          if (properties?.info?.title && !properties.info.title.startsWith("New session")) {
            currentTitle = properties.info.title;
            syncLegacyCurrentTask();
            await emitStatusChanged(currentStatus, {
              title: currentTitle,
            });
          }
          return;

        case "session.status": {
          const next = properties?.status?.type;
          if (next === "busy" || next === "retry") {
            if (shouldPreserveAwaitingInput()) {
              await emitStatusChanged("awaiting_input");
              return;
            }
            setStatus("running");
            if (!runningSummary) {
              runningSummary = "处理中";
              syncLegacyCurrentTask();
            }
          } else if (next === "idle") {
            if (hasPendingInteractions()) {
              await emitStatusChanged("awaiting_input");
              return;
            }
            permissionPending = false;
            setStatus("idle", true);
          }
          await emitStatusChanged();
          return;
        }

        case "session.idle":
          if (hasPendingInteractions()) {
            await emitStatusChanged("awaiting_input");
            return;
          }
          permissionPending = false;
          setStatus("idle", true);
          await emitStatusChanged();
          return;

        case "session.error":
          if (hasPendingInteractions()) {
            await emitStatusChanged("awaiting_input", {
              current_task: currentTask,
            });
            return;
          }
          permissionPending = false;
          setStatus("idle", true);
          syncLegacyCurrentTask();
          await emitStatusChanged("idle", {
            current_task: currentTask,
          });
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
            const metadata = {
              prompt: part.text,
              last_user_message: lastUserMessage,
              running_summary: runningSummary,
              current_task: currentTask,
            };
            if (shouldPreserveAwaitingInput()) {
              await emitStatusChanged("awaiting_input", metadata);
              return;
            }
            setStatus("running");
            await emitStatusChanged("running", metadata);
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
            const metadata = {
              running_summary: runningSummary,
              current_task: currentTask,
            };
            if (shouldPreserveAwaitingInput()) {
              await emitStatusChanged("awaiting_input", metadata);
              return;
            }
            if (currentStatus === "running") {
              await emitStatusChanged("running", metadata);
            }
          }
          return;
        }

        case "permission.asked": {
          const interaction = buildPermissionInteraction(event);
          runningSummary = interaction.title || interaction.message;
          syncLegacyCurrentTask();
          setStatus("awaiting_input", true);
          await emitStatusChanged("awaiting_input");
          requestPermissionDecision(properties.id, interaction);
          return;
        }

        case "permission.replied": {
          const requestID = eventRequestID(properties);
          removeQueuedInteraction(requestID);
          permissionPending = false;
          setStatus("running", true);
          await acknowledgeResolvedInteraction(requestID);
          processInteractionQueue();
          await emitStatusChanged("running");
          return;
        }

        case "question.asked": {
          const interaction = buildQuestionInteraction(event);
          if (!interaction) return;
          runningSummary = interaction.title || interaction.message;
          syncLegacyCurrentTask();
          setStatus("awaiting_input", true);
          await emitStatusChanged("awaiting_input");
          requestQuestionDecision(properties.id, interaction);
          return;
        }

        case "question.replied":
        case "question.rejected": {
          const requestID = eventRequestID(properties);
          removeQueuedInteraction(requestID);
          permissionPending = false;
          setStatus("running", true);
          await acknowledgeResolvedInteraction(requestID);
          processInteractionQueue();
          await emitStatusChanged("running");
          return;
        }

        default:
          return;
      }
    },
  };
}

export const VibeBarOpenCodePlugin = async (ctx = {}) => createPluginRuntime(ctx);

export default VibeBarOpenCodePlugin;
