// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookCommandProcessGuard.swift - Shared shell guard for globally installed hook commands.

public enum HookCommandProcessGuard {
    /// The command must already be shell-escaped and derived from trusted local configuration.
    public static func wrapTrustedShellCommand(_ command: String) -> String {
        #"if [ "${COCXY_HOOKS_DISABLED:-0}" != "1" ] && { [ "${COCXY_CLAUDE_HOOKS:-0}" = "1" ] || [ -n "${COCXY_RESOURCES_DIR:-}" ] || [ -n "${COCXY_SHELL_INTEGRATION_DIR:-}" ]; }; then exec \#(command); fi"#
    }
}
