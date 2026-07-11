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
            "git_status",
            "git_diff",
            "read_lsp_diagnostics",
        ]

        for toolID in readToolIDs {
            let invocation = AgentToolInvocation(toolID: toolID, capability: .read)
            #expect(policy.decision(for: invocation) == .allow)
        }
    }

    @Test("terminal output always requires per-call sensitive data approval")
    func terminalOutputRequiresSensitiveDataApproval() {
        let invocation = AgentToolInvocation(toolID: "read_terminal_output", capability: .read)

        #expect(AgentToolPermissionPolicy().decision(for: invocation) == .prompt(
            .sensitiveDataAccessRequired(toolID: "read_terminal_output")
        ))
        #expect(AgentToolPermissionPolicy(autoModeEnabled: true).decision(for: invocation) == .prompt(
            .sensitiveDataAccessRequired(toolID: "read_terminal_output")
        ))
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

    @Test("exact command rules require the same command text")
    func exactCommandRulesRequireSameCommandText() {
        let allowedCommand = "printf allowed"
        let policy = AgentToolPermissionPolicy(commandAllowRules: [.exact(allowedCommand)])

        #expect(policy.decision(for: AgentToolInvocation(
            toolID: "run_command",
            capability: .command,
            command: allowedCommand
        )) == .allow)

        let nonExactCommands = [
            "PRINTF allowed",
            "printf  allowed",
            "printf\tallowed",
            "printf\nallowed",
            " printf allowed",
            "printf allowed ",
            "printf allowed; printf appended",
        ]
        for command in nonExactCommands {
            let invocation = AgentToolInvocation(
                toolID: "run_command",
                capability: .command,
                command: command
            )
            #expect(policy.decision(for: invocation) == .prompt(.commandApprovalRequired(command: command)))
        }

        let composedUnicode = "printf caf\u{00E9}"
        let decomposedUnicode = "printf cafe\u{0301}"
        let unicodePolicy = AgentToolPermissionPolicy(commandAllowRules: [.exact(composedUnicode)])
        #expect(unicodePolicy.decision(for: AgentToolInvocation(
            toolID: "run_command",
            capability: .command,
            command: decomposedUnicode
        )) == .prompt(.commandApprovalRequired(command: decomposedUnicode)))
    }

    @Test("prefix command rules always require per-call approval")
    func prefixCommandRulesAlwaysRequireApproval() {
        let policy = AgentToolPermissionPolicy(commandAllowRules: [.prefix("printf allowed")])
        let commands = [
            "printf allowed",
            "printf allowed extra",
            "printf allowed; printf appended",
            "printf allowed && printf appended",
            "printf allowed || printf appended",
            "printf allowed | cat",
            "printf allowed\nprintf appended",
            "printf allowed > result.txt",
            "printf allowed >> result.txt",
            "printf allowed < input.txt",
            "printf allowed 2> error.log",
            "printf allowed $(printf appended)",
            "printf allowed `printf appended`",
            "printf allowed & printf appended",
            "printf allowedness",
        ]

        for command in commands {
            let invocation = AgentToolInvocation(
                toolID: "run_command",
                capability: .command,
                command: command
            )
            #expect(policy.decision(for: invocation) == .prompt(.commandApprovalRequired(command: command)))
        }

        let lookalike = "github-helper status"
        let lookalikePolicy = AgentToolPermissionPolicy(commandAllowRules: [.prefix("git")])
        #expect(lookalikePolicy.decision(for: AgentToolInvocation(
            toolID: "run_command",
            capability: .command,
            command: lookalike
        )) == .prompt(.commandApprovalRequired(command: lookalike)))
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

    @Test("computer use prompts by default and can be explicitly configured for no per-action prompt")
    func computerUsePromptsByDefaultAndCanBeConfigured() {
        let defaultPolicy = AgentToolPermissionPolicy(autoModeEnabled: true)
        let noPromptPolicy = AgentToolPermissionPolicy(
            autoModeEnabled: true,
            computerUseConfirm: false
        )
        let invocation = AgentToolInvocation(toolID: "computer_type_text", capability: .computerUse)

        #expect(defaultPolicy.decision(for: invocation) == .prompt(.computerUseApprovalRequired(
            toolID: "computer_type_text"
        )))
        #expect(noPromptPolicy.decision(for: invocation) == .allow)
    }
}
