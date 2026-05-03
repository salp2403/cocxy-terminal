// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolPermissionSwiftTestingTests.swift - Phase F permission foundation.

import Testing
@testable import CocxyTerminal

@Suite("AgentToolPermissionPolicy")
struct AgentToolPermissionSwiftTestingTests {

    @Test("read-only built-in tools auto allow")
    func readOnlyBuiltInToolsAutoAllow() {
        let policy = AgentToolPermissionPolicy()
        let readToolIDs = [
            "read_file",
            "list_directory",
            "search_files",
            "grep",
            "read_terminal_output",
            "git_status",
            "git_diff",
            "read_lsp_diagnostics",
        ]

        for toolID in readToolIDs {
            let invocation = AgentToolInvocation(toolID: toolID, capability: .read)
            #expect(policy.decision(for: invocation) == .allow)
        }
    }

    @Test("write tools require diff preview even when auto mode is enabled")
    func writeToolsRequireDiffPreview() {
        let policy = AgentToolPermissionPolicy(autoModeEnabled: true)

        let writeFile = AgentToolInvocation(toolID: "write_file", capability: .write)
        let applyDiff = AgentToolInvocation(toolID: "apply_diff", capability: .write)

        #expect(policy.decision(for: writeFile) == .prompt(.diffPreviewRequired(toolID: "write_file")))
        #expect(policy.decision(for: applyDiff) == .prompt(.diffPreviewRequired(toolID: "apply_diff")))
    }

    @Test("run command prompts unless explicitly allowlisted")
    func runCommandPromptsUnlessAllowlisted() {
        let defaultPolicy = AgentToolPermissionPolicy()
        let allowlistedPolicy = AgentToolPermissionPolicy(
            commandAllowRules: [.exact("swift test --filter AgentModeConfigRoundTripTests")]
        )
        let invocation = AgentToolInvocation(
            toolID: "run_command",
            capability: .command,
            command: "swift test --filter AgentModeConfigRoundTripTests"
        )

        #expect(defaultPolicy.decision(for: invocation) == .prompt(.commandApprovalRequired(command: invocation.command!)))
        #expect(allowlistedPolicy.decision(for: invocation) == .allow)
    }

    @Test("dangerous commands are denied before allowlist checks")
    func dangerousCommandsDeniedBeforeAllowlist() {
        let policy = AgentToolPermissionPolicy(commandAllowRules: [.prefix("rm")])
        let commands = [
            "rm -rf /",
            "rm -rf /.",
            "rm -rf /*",
            "rm -rf \"/\"",
            "rm -rf '/'",
            "rm -r -f /",
            "rm --recursive --force /",
            "rm -rf --no-preserve-root /",
            "/bin/rm -rf /.",
            "sudo rm -fr -- /",
            "sudo rm -fr -- /.",
            "sudo -n rm -fr /.",
            "sudo /bin/rm -fr /.",
            "sudo -u root rm -fr /.",
            "sudo --user root rm -rf /.",
            "env COCXY_SMOKE=1 rm -rf /*",
            "env -S 'rm -rf /.'",
            "env --split-string 'rm -rf /.'",
            "command rm -rf /",
            "command sudo -n rm -rf /.",
            "sh -c 'rm -rf /.'",
            "/bin/sh -c 'rm -rf /.'",
            "bash -lc \"rm -rf /.\"",
            "zsh -c 'sudo -u root rm -rf /.'",
            "diskutil eraseDisk APFS Cocxy /dev/disk4",
            "mkfs.ext4 /dev/disk2",
            "dd if=/dev/zero of=/dev/disk3 bs=1m",
            "chmod -R 777 /",
            ":(){ :|:& };:",
        ]

        for command in commands {
            let invocation = AgentToolInvocation(
                toolID: "run_command",
                capability: .command,
                command: command
            )
            #expect(policy.decision(for: invocation) == .deny(.dangerousCommand(command: command)))
        }
    }

    @Test("safe rm commands still require approval instead of being denied")
    func safeRMCommandsStillRequireApproval() {
        let policy = AgentToolPermissionPolicy()
        let commands = [
            "rm -rf /tmp/cocxy-agent-smoke",
            "rm -rf ./build",
            "rm --recursive --force Sources",
        ]

        for command in commands {
            let invocation = AgentToolInvocation(
                toolID: "run_command",
                capability: .command,
                command: command
            )
            #expect(policy.decision(for: invocation) == .prompt(.commandApprovalRequired(command: command)))
        }
    }

    @Test("malformed command invocations are denied")
    func malformedCommandInvocationsDenied() {
        let policy = AgentToolPermissionPolicy()
        let invocation = AgentToolInvocation(toolID: "run_command", capability: .command)

        #expect(policy.decision(for: invocation) == .deny(.missingCommand(toolID: "run_command")))
    }

    @Test("ask user tool always prompts")
    func askUserAlwaysPrompts() {
        let policy = AgentToolPermissionPolicy(autoModeEnabled: true)
        let invocation = AgentToolInvocation(toolID: "ask_user", capability: .userInteraction)

        #expect(policy.decision(for: invocation) == .prompt(.userInputRequired(toolID: "ask_user")))
    }
}
