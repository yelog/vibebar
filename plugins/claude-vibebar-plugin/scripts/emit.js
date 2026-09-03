import net from "node:net";
import os from "node:os";
import path from "node:path";

const DEFAULT_SOCKET_PATH = path.join(
  os.homedir(),
  "Library/Application Support/VibeBar/runtime/agent.sock"
);
const INTERACTION_TIMEOUT_MS = Number.parseInt(
  process.env.VIBEBAR_PLUGIN_INTERACTION_TIMEOUT_MS ?? "300000",
  10
);

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

function readStdin() {
  return new Promise((resolve) => {
    let raw = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => {
      raw += chunk;
    });
    process.stdin.on("end", () => resolve(raw));
    process.stdin.on("error", () => resolve(raw));
  });
}

function resolveSocketPath() {
  const custom = asString(process.env.VIBEBAR_AGENT_SOCKET);
  return custom ?? DEFAULT_SOCKET_PATH;
}

function sendEnvelope(envelope, waitForResponse = false, timeoutMs = 1500) {
  const line = `${JSON.stringify(envelope)}\n`;
  const target = resolveSocketPath();
  return new Promise((resolve) => {
    const client = net.createConnection({ path: target }, () => {
      client.write(line);
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

function sendInteractionRequest(request) {
  return sendEnvelope(
    { kind: "interaction_request", request },
    true,
    INTERACTION_TIMEOUT_MS
  );
}

function buildSessionID(payload) {
  const direct = asString(payload.session_id ?? payload.sessionId ?? payload.session?.id);
  if (direct) {
    return direct;
  }

  const transcriptPath = asString(payload.transcript_path ?? payload.transcriptPath);
  if (transcriptPath) {
    return path.basename(transcriptPath, path.extname(transcriptPath));
  }

  return `pid-${process.ppid}`;
}

function buildCWD(payload) {
  const cwd = asString(payload.cwd ?? payload.working_directory ?? payload.workingDirectory);
  if (cwd) {
    return cwd;
  }
  return process.env.CLAUDE_PROJECT_DIR || process.cwd();
}

function currentTaskFor(payload, hookEvent) {
  const candidates = [
    payload.current_task,
    payload.prompt,
    payload.question,
    payload.message,
    payload.tool_name,
    payload.title,
    payload.first_user_message,
  ];

  for (const candidate of candidates) {
    const value = asString(candidate);
    if (value) {
      return value;
    }
  }

  if (hookEvent === "PreToolUse" || hookEvent === "PostToolUse") {
    return asString(payload.tool_name);
  }

  return undefined;
}

function mapStatus(hookEvent, payload) {
  const event = hookEvent.toLowerCase();
  const notificationType = asString(payload.notification_type ?? payload.notificationType)?.toLowerCase();

  if (event === "sessionstart") {
    return { eventType: "session_started", status: "idle" };
  }
  if (event === "sessionend") {
    return { eventType: "session_ended", terminal: true };
  }
  if (event === "permissionrequest" || event === "elicitation") {
    return { eventType: "status_changed", status: "awaiting_input" };
  }
  if (event === "userpromptsubmit") {
    return { eventType: "status_changed", status: "running" };
  }
  if (event === "stop") {
    return { eventType: "stop", status: "idle" };
  }
  if (event === "taskcompleted") {
    return { eventType: "task_completed" };
  }
  if (event === "notification") {
    if (notificationType === "permission_prompt" || notificationType === "elicitation_dialog") {
      return { eventType: "status_changed", status: "awaiting_input" };
    }
    if (notificationType === "idle_prompt") {
      return { eventType: "status_changed", status: "idle" };
    }
    return { eventType: "status_changed" };
  }
  if (
    event === "pretooluse" ||
    event === "posttooluse" ||
    event === "posttoolusefailure" ||
    event === "subagentstart" ||
    event === "subagentstop"
  ) {
    return { eventType: "status_changed", status: "running" };
  }

  return { eventType: "status_changed" };
}

function summarizeToolInput(toolInput) {
  if (!toolInput || typeof toolInput !== "object") {
    return undefined;
  }
  return asString(toolInput.command ?? toolInput.file_path ?? toolInput.path ?? toolInput.url);
}

function buildMetadata(hookEvent, payload) {
  const metadata = {
    hook_event: hookEvent,
    TERM_PROGRAM: asString(process.env.TERM_PROGRAM),
    TERM_SESSION_ID: asString(process.env.TERM_SESSION_ID),
    ITERM_SESSION_ID: asString(process.env.ITERM_SESSION_ID),
    KITTY_WINDOW_ID: asString(process.env.KITTY_WINDOW_ID),
    KITTY_LISTEN_ON: asString(process.env.KITTY_LISTEN_ON),
    GHOSTTY_SURFACE_ID: asString(process.env.GHOSTTY_SURFACE_ID),
    WEZTERM_PANE: asString(process.env.WEZTERM_PANE),
    WEZTERM_UNIX_SOCKET: asString(process.env.WEZTERM_UNIX_SOCKET),
    TMUX: asString(process.env.TMUX),
    TMUX_PANE: asString(process.env.TMUX_PANE),
    ZELLIJ: asString(process.env.ZELLIJ),
    ZELLIJ_SESSION_NAME: asString(process.env.ZELLIJ_SESSION_NAME),
    ZELLIJ_PANE_ID: asString(process.env.ZELLIJ_PANE_ID),
    ZELLIJ_TAB_NAME: asString(process.env.ZELLIJ_TAB_NAME),
    ZELLIJ_TAB_INDEX: asString(process.env.ZELLIJ_TAB_INDEX),
    __CFBundleIdentifier: asString(process.env.__CFBundleIdentifier),
  };

  const notificationType = asString(payload.notification_type ?? payload.notificationType);
  if (notificationType) {
    metadata.notification_type = notificationType;
  }

  const toolName = asString(payload.tool_name ?? payload.toolName);
  if (toolName) {
    metadata.tool_name = toolName;
  }

  const reason = asString(payload.reason);
  if (reason) {
    metadata.reason = reason;
  }

  const title = asString(payload.title ?? payload.custom_title ?? payload.thread_name);
  if (title) {
    metadata.title = title;
  }

  const prompt = asString(payload.prompt ?? payload.message ?? payload.first_user_message);
  if (prompt) {
    metadata.prompt = prompt;
  }

  const currentTask = currentTaskFor(payload, hookEvent);
  if (currentTask) {
    metadata.current_task = currentTask;
  }

  const inputSummary = summarizeToolInput(payload.tool_input);
  if (inputSummary) {
    metadata.tool_input_summary = inputSummary;
  }

  return metadata;
}

function buildPermissionInteraction(payload, sessionID) {
  const toolName = asString(payload.tool_name ?? payload.toolName) ?? "操作";
  const toolInput = payload.tool_input || {};
  const message = summarizeToolInput(toolInput) || `允许 ${toolName} 继续执行`;

  return {
    id: `claude-permission-${sessionID}-${Date.now()}`,
    session_id: sessionID,
    tool: "claude-code",
    kind: "permission",
    title: `需要确认：${toolName}`,
    message,
    options: [],
    allows_free_text: false,
    requested_at: new Date().toISOString(),
    transport_context: {
      source: "claude-plugin",
      request_kind: "permission",
      tool_name: toolName,
    },
  };
}

function parseElicitationSchema(payload) {
  const schema = payload.requested_schema;
  const properties = schema?.properties || {};
  const keys = Object.keys(properties);
  if (keys.length !== 1) {
    return { key: undefined, options: [], valueType: undefined, allowsFreeText: true };
  }

  const key = keys[0];
  const property = properties[key] || {};
  if (Array.isArray(property.enum) && property.enum.length > 0) {
    return {
      key,
      valueType: "enum",
      allowsFreeText: false,
      options: property.enum.map((value) => ({
        id: String(value),
        label: String(value),
        detail: asString(property.description),
      })),
    };
  }
  if (property.type === "boolean") {
    return {
      key,
      valueType: "boolean",
      allowsFreeText: false,
      options: [
        { id: "true", label: "是" },
        { id: "false", label: "否" },
      ],
    };
  }

  return { key, options: [], valueType: property.type, allowsFreeText: true };
}

function buildElicitationInteraction(payload, sessionID) {
  const schemaInfo = parseElicitationSchema(payload);
  return {
    id: `claude-elicitation-${asString(payload.elicitation_id) ?? `${sessionID}-${Date.now()}`}`,
    session_id: sessionID,
    tool: "claude-code",
    kind: "question",
    title: asString(payload.mcp_server_name) ?? "需要回答",
    message: asString(payload.message) ?? "请选择一个答案",
    options: schemaInfo.options,
    allows_free_text: schemaInfo.allowsFreeText,
    requested_at: new Date().toISOString(),
    transport_context: {
      source: "claude-plugin",
      request_kind: "elicitation",
      schema_key: schemaInfo.key ?? "",
      schema_value_type: schemaInfo.valueType ?? "",
      mode: asString(payload.mode) ?? "",
    },
  };
}

function permissionResponseJson(responseEnvelope) {
  const behavior = responseEnvelope?.response?.decision?.behavior === "allow" ? "allow" : "deny";
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior,
      },
    },
  });
}

function elicitationResponseJson(payload, interaction, responseEnvelope) {
  const decision = responseEnvelope?.response?.decision;
  if (!decision || decision.behavior === "deny") {
    return JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "Elicitation",
        action: "decline",
        content: {},
      },
    });
  }

  const schemaKey = asString(interaction.transport_context?.schema_key);
  if (!schemaKey) {
    return JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "Elicitation",
        action: "decline",
        content: {},
      },
    });
  }

  let value = decision.text;
  if (!value && decision.optionID) {
    value = interaction.options.find((option) => option.id === decision.optionID)?.label;
  }

  if (interaction.transport_context?.schema_value_type === "boolean") {
    value = decision.optionID === "false" ? false : true;
  }

  if (value === undefined || value === null || value === "") {
    return JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "Elicitation",
        action: "decline",
        content: {},
      },
    });
  }

  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "Elicitation",
      action: "accept",
      content: {
        [schemaKey]: value,
      },
    },
  });
}

async function main() {
  const hookEvent = asString(process.argv[2]) ?? "Unknown";
  const inputRaw = await readStdin();

  let payload = {};
  if (inputRaw.trim().length > 0) {
    try {
      payload = JSON.parse(inputRaw);
    } catch {
      payload = {};
    }
  }

  const sessionID = buildSessionID(payload);
  const pid = asInt(payload.pid ?? payload.process_id ?? payload.processId) ?? process.ppid;
  const cwd = buildCWD(payload);

  if (hookEvent === "PermissionRequest") {
    const request = buildPermissionInteraction(payload, sessionID);
    const response = await sendInteractionRequest(request);
    process.stdout.write(permissionResponseJson(response));
    return;
  }

  if (hookEvent === "Elicitation") {
    const interaction = buildElicitationInteraction(payload, sessionID);
    const response = await sendInteractionRequest(interaction);
    process.stdout.write(elicitationResponseJson(payload, interaction, response));
    return;
  }

  const mapped = mapStatus(hookEvent, payload);
  const body = {
    version: 1,
    source: "claude-plugin",
    tool: "claude-code",
    session_id: sessionID,
    event_type: mapped.eventType,
    timestamp: new Date().toISOString(),
    pid,
    cwd,
    command: ["claude"],
    metadata: buildMetadata(hookEvent, payload),
  };

  if (!mapped.terminal && mapped.status) {
    body.status = mapped.status;
  }

  if (mapped.terminal) {
    body.status = "idle";
  }

  await sendEvent(body);
}

void main();
