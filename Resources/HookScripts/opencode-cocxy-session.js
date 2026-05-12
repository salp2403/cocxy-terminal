// Cocxy managed OpenCode session bridge
const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

function sessionID(event) {
  return event?.session?.id || event?.sessionID || event?.id || process.env.OPENCODE_SESSION_ID || "";
}

async function sendToCocxy(eventName, event, cwd) {
  if (typeof Bun === "undefined" || !Bun.spawn) return;
  const id = sessionID(event);
  const payload = {
    hook_event_name: eventName,
    session_id: id,
    agent_type: "opencode",
    cwd,
    source_event_type: event?.type || eventName,
  };
  const proc = Bun.spawn([COCXY_CLI, "hook-handler"], {
    stdin: "pipe",
    stdout: "ignore",
    stderr: "ignore",
    env: {
      ...process.env,
      COCXY_CLAUDE_HOOKS: "1",
      COCXY_HOOK_AGENT: "opencode",
      OPENCODE_SESSION_ID: id,
    },
  });
  proc.stdin.write(JSON.stringify(payload));
  proc.stdin.end();
  await proc.exited;
}

export const CocxySessionBridge = async ({ directory, worktree }) => {
  const cwd = worktree || directory || process.cwd();
  return {
    "shell.env": async (_input, output) => {
      output.env = {
        ...(output.env || {}),
        COCXY_CLAUDE_HOOKS: "1",
        COCXY_HOOK_AGENT: "opencode",
      };
    },
    event: async ({ event }) => {
      switch (event?.type) {
        case "session.created":
          await sendToCocxy("SessionStart", event, cwd);
          break;
        case "session.idle":
        case "session.deleted":
          await sendToCocxy("Stop", event, cwd);
          break;
        case "session.updated":
        case "message.updated":
          await sendToCocxy("UserPromptSubmit", event, cwd);
          break;
        default:
          break;
      }
    },
    "tool.execute.before": async (input) => {
      await sendToCocxy("PreToolUse", { type: "tool.execute.before", tool: input?.tool }, cwd);
    },
    "tool.execute.after": async (input) => {
      await sendToCocxy("PostToolUse", { type: "tool.execute.after", tool: input?.tool }, cwd);
    },
  };
};
