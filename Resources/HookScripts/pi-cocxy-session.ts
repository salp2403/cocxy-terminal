// Cocxy managed Pi session bridge
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

function shellQuote(value: string): string {
  return "'" + value.replace(/'/g, "'\\''") + "'";
}

function sessionID(ctx: ExtensionContext): string {
  return process.env.PI_SESSION_ID || ctx.sessionManager.getSessionFile?.() || "";
}

function payloadFor(eventName: string, sourceEvent: string, event: unknown, ctx: ExtensionContext): string {
  const input = event && typeof event === "object" && "input" in event ? (event as { input?: unknown }).input : undefined;
  const toolName = event && typeof event === "object" && "toolName" in event ? (event as { toolName?: unknown }).toolName : undefined;
  return JSON.stringify({
    hook_event_name: eventName,
    agent_type: "pi",
    session_id: sessionID(ctx),
    cwd: ctx.cwd,
    source_event_type: sourceEvent,
    input,
    tool_name: toolName,
  });
}

async function sendToCocxy(
  pi: ExtensionAPI,
  eventName: string,
  sourceEvent: string,
  event: unknown,
  ctx: ExtensionContext
): Promise<void> {
  if (process.env.COCXY_PI_HOOKS_DISABLED === "1") return;
  const session = sessionID(ctx);
  const payload = shellQuote(payloadFor(eventName, sourceEvent, event, ctx));
  const command = `printf %s ${payload} | COCXY_CLAUDE_HOOKS=1 COCXY_HOOK_AGENT=pi PI_SESSION_ID=${shellQuote(session)} ${shellQuote(COCXY_CLI)} hook-handler`;
  await pi.exec("sh", ["-lc", command], { signal: ctx.signal, timeout: 5000 });
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (event, ctx) => {
    await sendToCocxy(pi, "SessionStart", "session_start", event, ctx);
  });
  pi.on("input", async (event, ctx) => {
    await sendToCocxy(pi, "UserPromptSubmit", "input", event, ctx);
  });
  pi.on("tool_call", async (event, ctx) => {
    await sendToCocxy(pi, "PreToolUse", "tool_call", event, ctx);
  });
  pi.on("tool_result", async (event, ctx) => {
    await sendToCocxy(pi, "PostToolUse", "tool_result", event, ctx);
  });
  pi.on("session_shutdown", async (event, ctx) => {
    await sendToCocxy(pi, "Stop", "session_shutdown", event, ctx);
  });
}
