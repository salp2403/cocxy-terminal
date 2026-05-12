// Cocxy managed OpenCode feed bridge
const COCXY_CLI = process.env.COCXY_CLI || "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy";

function sessionID(event) {
  return event?.session?.id || event?.sessionID || event?.id || process.env.OPENCODE_SESSION_ID || "";
}

async function sendToCocxy(eventName, event, cwd) {
  if (process.env.COCXY_OPENCODE_HOOKS_DISABLED === "1") return;
  if (typeof Bun === "undefined" || !Bun.spawn) return;
  const id = sessionID(event);
  const payload = {
    hook_event_name: eventName,
    session_id: id,
    agent_type: "opencode",
    cwd,
    source_event_type: event?.type || eventName,
    input: event?.input || event?.text || event?.command || "",
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

export const CocxyFeedBridge = async ({ directory, worktree }) => {
  const cwd = worktree || directory || process.cwd();
  return {
    "tui.prompt.append": async (input) => {
      await sendToCocxy("UserPromptSubmit", { type: "tui.prompt.append", input }, cwd);
    },
    "tui.command.execute": async (input) => {
      await sendToCocxy("UserPromptSubmit", { type: "tui.command.execute", command: input?.command }, cwd);
    },
    event: async ({ event }) => {
      switch (event?.type) {
        case "notification.created":
        case "permission.requested":
          await sendToCocxy("Notification", event, cwd);
          break;
        default:
          break;
      }
    },
  };
};
