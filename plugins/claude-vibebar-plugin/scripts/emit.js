import net from "node:net";
import os from "node:os";
import path from "node:path";

const DEFAULT_SOCKET_PATH = path.join(
  os.homedir(),
  "Library/Application Support/VibeBar/runtime/agent.sock"
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

async function sendToAgent(payload) {
  const line = `${JSON.stringify(payload)}\n`;
  const target = resolveSocketPath();
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

function mapStatus(hookEvent, payload) {
  const event = hookEvent.toLowerCase();
  const notificationType = asString(payload.notification_type ?? payload.notificationType)?.toLowerCase();

  if (event === "sessionstart") {
    return { eventType: "session_started", status: "idle" };
  }
  if (event === "sessionend") {
    return { eventType: "session_ended", terminal: true };
  }
  if (event === "permissionrequest") {
    return { eventType: "status_changed", status: "awaiting_input" };
  }
  if (event === "userpromptsubmit") {
    return { eventType: "status_changed", status: "running" };
  }
  if (event === "stop" || event === "taskcompleted") {
    return { eventType: "status_changed", status: "idle" };
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

function buildMetadata(hookEvent, payload) {
  const metadata = {
    hook_event: hookEvent,
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

  return metadata;
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

  const mapped = mapStatus(hookEvent, payload);
  const sessionID = buildSessionID(payload);
  const pid = asInt(payload.pid ?? payload.process_id ?? payload.processId) ?? process.ppid;
  const cwd = buildCWD(payload);

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

  await sendToAgent(body);
}

void main();
