// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLocalToolExecutorSwiftTestingTests.swift - Approved write and command Agent tools.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentLocalToolExecutor")
struct AgentLocalToolExecutorSwiftTestingTests {

    @Test("write_file refuses to modify disk until the call is approved")
    func writeFileRequiresApproval() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Sources/App.swift")
        try "let value = 1\n".write(to: target, atomically: true, encoding: .utf8)
        let executor = AgentLocalToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let result = try await executor.execute(AgentToolCall(
            id: "call-write",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string("let value = 2\n"),
            ]
        ))

        #expect(result.status == .failure)
        #expect(result.error?.code == "approval_required")
        #expect(try String(contentsOf: target, encoding: .utf8) == "let value = 1\n")
    }

    @Test("approved write_file overwrites UTF-8 file and returns a diff preview")
    func approvedWriteFileOverwritesFileAndReturnsDiff() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Sources/App.swift")
        try "let value = 1\n".write(to: target, atomically: true, encoding: .utf8)
        let workspace = AgentWorkspace(rootURL: root)
        let call = AgentToolCall(
            id: "call-write",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string("let value = 2\n"),
            ]
        )
        let binding = try #require(
            try await AgentLocalToolExecutor(workspace: workspace)
                .approvalPreview(for: call)
                .binding
        )
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedWriteCallIDs: [call.id],
                workspaceBindingsByCallID: [call.id: binding]
            )
        )

        let result = try await executor.execute(call)
        let content = try contentObject(result)

        #expect(result.status == .success)
        #expect(content["path"]?.stringValue == "Sources/App.swift")
        #expect(content["diff"]?.stringValue?.contains("-let value = 1") == true)
        #expect(content["diff"]?.stringValue?.contains("+let value = 2") == true)
        #expect(try String(contentsOf: target, encoding: .utf8) == "let value = 2\n")
    }

    @Test("write_file creates new files only with create flag and still blocks sensitive paths")
    func writeFileCreateFlagAndSensitivePaths() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let createdURL = root.appendingPathComponent("Sources/NewFile.swift")
        let workspace = AgentWorkspace(rootURL: root)
        let missingCall = AgentToolCall(
            id: "call-missing",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/NewFile.swift"),
                "content": .string("let created = true\n"),
            ]
        )
        let createCall = AgentToolCall(
            id: "call-create",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/NewFile.swift"),
                "content": .string("let created = true\n"),
                "create": .bool(true),
            ]
        )
        let sensitiveCall = AgentToolCall(
            id: "call-sensitive",
            toolID: "write_file",
            arguments: [
                "path": .string(".env"),
                "content": .string("API_KEY=secret\n"),
                "create": .bool(true),
            ]
        )
        let bindings: [String: AgentToolApprovalBinding] = try [missingCall, createCall, sensitiveCall]
            .reduce(into: [:]) { result, call in
            let target = call.id == sensitiveCall.id
                ? root.appendingPathComponent(".env")
                : createdURL
            result[call.id] = try testBinding(
                for: call,
                workspace: workspace,
                targetURL: target,
                targetKind: .writeFile,
                observedFileContents: Data()
            )
        }
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedWriteCallIDs: Set(bindings.keys),
                workspaceBindingsByCallID: bindings
            )
        )

        let missing = try await executor.execute(missingCall)
        let created = try await executor.execute(createCall)
        let sensitive = try await executor.execute(sensitiveCall)

        #expect(missing.status == .failure)
        #expect(missing.error?.code == "workspace_not_found")
        #expect(created.status == .success)
        #expect(try String(contentsOf: createdURL, encoding: .utf8) == "let created = true\n")
        #expect(sensitive.status == .failure)
        #expect(sensitive.error?.code == "workspace_sensitive_path")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".env").path))
    }

    @Test("apply_diff replaces exactly one matching range after approval")
    func applyDiffRequiresSingleMatch() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Sources/App.swift")
        let originalContent = "alpha\nbeta\nalpha\n"
        try originalContent.write(to: target, atomically: true, encoding: .utf8)
        let workspace = AgentWorkspace(rootURL: root)
        let ambiguousCall = AgentToolCall(
            id: "call-ambiguous",
            toolID: "apply_diff",
            arguments: [
                "path": .string("Sources/App.swift"),
                "oldText": .string("alpha"),
                "newText": .string("gamma"),
            ]
        )
        let applyCall = AgentToolCall(
            id: "call-apply",
            toolID: "apply_diff",
            arguments: [
                "path": .string("Sources/App.swift"),
                "oldText": .string("beta"),
                "newText": .string("delta"),
            ]
        )
        let bindings: [String: AgentToolApprovalBinding] = try [ambiguousCall, applyCall]
            .reduce(into: [:]) { result, call in
            result[call.id] = try testBinding(
                for: call,
                workspace: workspace,
                targetURL: target,
                targetKind: .applyDiffFile,
                observedFileContents: Data(originalContent.utf8)
            )
        }
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedWriteCallIDs: Set(bindings.keys),
                workspaceBindingsByCallID: bindings
            )
        )

        let ambiguous = try await executor.execute(ambiguousCall)
        let applied = try await executor.execute(applyCall)
        let content = try contentObject(applied)

        #expect(ambiguous.status == .failure)
        #expect(ambiguous.error?.code == "edit_ambiguous_old_text")
        #expect(applied.status == .success)
        #expect(content["diff"]?.stringValue?.contains("-beta") == true)
        #expect(content["diff"]?.stringValue?.contains("+delta") == true)
        #expect(try String(contentsOf: target, encoding: .utf8) == "alpha\ndelta\nalpha\n")
    }

    @Test("approved write_file and apply_diff allow empty replacement content")
    func writeAndApplyDiffAllowEmptyContent() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Sources/App.swift")
        try "alpha\nbeta\n".write(to: target, atomically: true, encoding: .utf8)
        let workspace = AgentWorkspace(rootURL: root)
        let deleteCall = AgentToolCall(
            id: "call-delete",
            toolID: "apply_diff",
            arguments: [
                "path": .string("Sources/App.swift"),
                "oldText": .string("beta\n"),
                "newText": .string(""),
            ]
        )
        let deleteBinding = try #require(
            try await AgentLocalToolExecutor(workspace: workspace)
                .approvalPreview(for: deleteCall)
                .binding
        )
        let delete = try await AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedWriteCallIDs: [deleteCall.id],
                workspaceBindingsByCallID: [deleteCall.id: deleteBinding]
            )
        ).execute(deleteCall)

        let emptyCall = AgentToolCall(
            id: "call-empty",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string(""),
            ]
        )
        let emptyBinding = try #require(
            try await AgentLocalToolExecutor(workspace: workspace)
                .approvalPreview(for: emptyCall)
                .binding
        )
        let empty = try await AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedWriteCallIDs: [emptyCall.id],
                workspaceBindingsByCallID: [emptyCall.id: emptyBinding]
            )
        ).execute(emptyCall)

        #expect(delete.status == .success)
        #expect(empty.status == .success)
        #expect(try String(contentsOf: target, encoding: .utf8) == "")
    }

    @Test("run_command uses injected shell runner and validates cwd inside workspace")
    func runCommandUsesInjectedRunnerAndWorkspaceCWD() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingLocalAgentProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "ok\n", stderr: ""),
        ])
        let workspace = AgentWorkspace(rootURL: root)
        let call = AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: [
                "command": .string("swift test --filter AgentLocalToolExecutor"),
                "cwd": .string("Sources"),
                "timeoutSeconds": .number(5),
            ]
        )
        let binding = try #require(
            try await AgentLocalToolExecutor(workspace: workspace)
                .approvalPreview(for: call)
                .binding
        )
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedCommandCallIDs: [call.id],
                workspaceBindingsByCallID: [call.id: binding]
            ),
            processRunner: runner,
            shellExecutableURL: URL(fileURLWithPath: "/bin/zsh")
        )

        let result = try await executor.execute(call)
        let content = try contentObject(result)

        #expect(result.status == .success)
        #expect(content["exitCode"]?.numberValue == 0)
        #expect(content["stdout"]?.stringValue == "ok\n")
        #expect(runner.calls == [
            AgentProcessCall(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", "swift test --filter AgentLocalToolExecutor"],
                workingDirectory: root.appendingPathComponent("Sources").standardizedFileURL.resolvingSymlinksInPath(),
                timeoutSeconds: 5
            ),
        ])
    }

    @Test("sandboxed run_command cannot read or write outside the workspace")
    func sandboxedRunCommandCannotEscapeWorkspace() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec"),
              FileManager.default.isExecutableFile(atPath: "/bin/sh")
        else {
            return
        }

        let sandboxRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/cocxy-agent-sandbox-tests/\(UUID().uuidString)", isDirectory: true)
        let root = sandboxRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: sandboxRoot) }
        let outsideReadURL = sandboxRoot.appendingPathComponent("outside-read.txt")
        let outsideWriteURL = sandboxRoot.appendingPathComponent("outside-write.txt")
        let allowedURL = root.appendingPathComponent("allowed.txt")
        try "outside-secret\n".write(to: outsideReadURL, atomically: true, encoding: .utf8)
        let command = [
            "cat ../\(outsideReadURL.lastPathComponent)",
            "printf ok > allowed.txt",
            "printf denied > ../\(outsideWriteURL.lastPathComponent)",
        ].joined(separator: "; ")
        let call = AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: [
                "command": .string(command),
                "timeoutSeconds": .number(5),
            ]
        )
        let workspace = AgentWorkspace(rootURL: root)
        let binding = try #require(
            try await AgentLocalToolExecutor(workspace: workspace)
                .approvalPreview(for: call)
                .binding
        )
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedCommandCallIDs: [call.id],
                workspaceBindingsByCallID: [call.id: binding]
            ),
            processRunner: AgentSandboxedProcessRunner(
                base: AgentProcessRunner(),
                workspaceURL: root
            ),
            shellExecutableURL: URL(fileURLWithPath: "/bin/sh")
        )

        let result = try await executor.execute(call)
        let content = try contentObject(result)

        #expect(result.status == .success)
        #expect((content["exitCode"]?.numberValue ?? 0) != 0)
        #expect(content["stdout"]?.stringValue?.contains("outside-secret") == false)
        #expect(FileManager.default.fileExists(atPath: allowedURL.path))
        #expect(!FileManager.default.fileExists(atPath: outsideWriteURL.path))
    }

    @Test("run_command refuses non-dangerous commands until the call is approved")
    func runCommandRequiresApproval() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingLocalAgentProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "should-not-run\n", stderr: ""),
        ])
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: ["command": .string("swift test --filter AgentLocalToolExecutor")]
        ))

        #expect(result.status == .failure)
        #expect(result.error?.code == "approval_required")
        #expect(runner.calls.isEmpty)
    }

    @Test("run_command auto executes only byte-identical exact allow rules")
    func runCommandExactAllowRuleRequiresSameText() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingLocalAgentProcessRunner(results: [.init(exitCode: 0, stdout: "allowed\n", stderr: "")])
        let allowedCommand = "printf allowed"
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(commandAllowRules: [.exact(allowedCommand)]),
            processRunner: runner
        )
        let allowed = try await executor.execute(AgentToolCall(
            id: "call-exact",
            toolID: "run_command",
            arguments: ["command": .string(allowedCommand)]
        ))
        let differentWhitespace = try await executor.execute(AgentToolCall(
            id: "call-not-exact",
            toolID: "run_command",
            arguments: ["command": .string("printf  allowed")]
        ))
        #expect(allowed.status == .success)
        #expect(differentWhitespace.status == .failure)
        #expect(differentWhitespace.error?.code == "approval_required")
        #expect(runner.calls.map(\.arguments) == [["-lc", allowedCommand]])
    }

    @Test("run_command prefix allow rules never bypass approval")
    func runCommandPrefixAllowRulesNeverBypassApproval() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingLocalAgentProcessRunner(results: [])
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(commandAllowRules: [.prefix("printf allowed")]),
            processRunner: runner
        )
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
        for (index, command) in commands.enumerated() {
            let result = try await executor.execute(AgentToolCall(
                id: "call-prefix-\(index)",
                toolID: "run_command",
                arguments: ["command": .string(command)]
            ))
            #expect(result.status == .failure)
            #expect(result.error?.code == "approval_required")
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("run_command denies dangerous commands before invoking the runner")
    func runCommandDeniesDangerousCommandsBeforeRunner() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingLocalAgentProcessRunner(results: [])
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-danger",
            toolID: "run_command",
            arguments: ["command": .string("rm -rf /")]
        ))

        #expect(result.status == .failure)
        #expect(result.error?.code == "dangerous_command")
        #expect(runner.calls.isEmpty)
    }

    @Test("run_command denies normalized root delete variants before invoking the runner")
    func runCommandDeniesRootDeleteVariantsBeforeRunner() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingLocalAgentProcessRunner(results: [])
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )
        let commands = [
            "rm -rf /.",
            "rm -rf /*",
            "/bin/rm -rf /.",
            "sudo rm -fr -- /.",
            "sudo -u root rm -fr -- /.",
            "sh -c 'rm -rf /.'",
            "env -S 'rm -rf /.'",
        ]

        for command in commands {
            let result = try await executor.execute(AgentToolCall(
                id: "call-danger-\(command)",
                toolID: "run_command",
                arguments: ["command": .string(command)]
            ))

            #expect(result.status == .failure)
            #expect(result.error?.code == "dangerous_command")
        }
        #expect(runner.calls.isEmpty)
    }

    @Test("ask_user returns approved human answer as a tool result")
    func askUserReturnsApprovedHumanAnswer() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let call = AgentToolCall(
            id: "call-ask",
            toolID: "ask_user",
            arguments: ["prompt": .string("Which branch should I use?")]
        )
        let pending = try await AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root)
        ).execute(call)
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(userInputResponsesByCallID: [
                "call-ask": "Use main.",
            ])
        )

        let result = try await executor.execute(call)
        let content = try contentObject(result)

        #expect(pending.status == .failure)
        #expect(pending.error?.code == "user_input_required")
        #expect(result.status == .success)
        #expect(content["prompt"]?.stringValue == "Which branch should I use?")
        #expect(content["answer"]?.stringValue == "Use main.")
    }

    @Test("terminal output approval is bound redacted and consumed once")
    func terminalOutputApprovalIsBoundRedactedAndConsumedOnce() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = AgentWorkspace(rootURL: root)
        let call = AgentToolCall(
            id: "call-terminal-output",
            toolID: "read_terminal_output",
            arguments: ["limit": .number(70)]
        )
        let provider = StaticLocalTerminalOutputProvider(output: """
        build completed
        API_KEY=synthetic-secret-value
        ghp_abcdefghijklmnopqrstuvwxyz123456
        """)
        let previewExecutor = AgentLocalToolExecutor(
            workspace: workspace,
            terminalOutputProvider: provider,
            providerKind: .openai,
            approvalScopeID: "terminal-consent-test"
        )
        let previewContext = try await previewExecutor.approvalPreview(for: call)
        let binding = try #require(previewContext.sensitiveReadBinding)
        let changedCall = AgentToolCall(
            id: call.id,
            toolID: call.toolID,
            arguments: ["limit": .number(2)]
        )

        #expect(previewContext.preview.kind == .sensitiveData)
        #expect(previewContext.preview.body.contains("Destination: OpenAI"))
        #expect(previewContext.preview.body.contains("Command blocks: 2 of at most 64"))
        #expect(previewContext.preview.body.contains("Terminal text has not been read yet."))
        #expect(!previewContext.preview.body.contains("build completed"))
        #expect(!previewContext.preview.body.contains("synthetic-secret-value"))
        #expect(!previewContext.preview.body.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        #expect(provider.requestedLimits == [70])
        #expect(provider.capturedSelections.isEmpty)
        #expect(binding.approvedRead(
            call: changedCall,
            preview: previewContext.preview,
            provider: .openai,
            approvalScopeID: "terminal-consent-test"
        ) == nil)
        #expect(binding.approvedRead(
            call: call,
            preview: previewContext.preview,
            provider: .google,
            approvalScopeID: "terminal-consent-test"
        ) == nil)
        #expect(binding.approvedRead(
            call: call,
            preview: previewContext.preview,
            provider: .openai,
            approvalScopeID: "different-session"
        ) == nil)
        let approvedRead = try #require(binding.approvedRead(
            call: call,
            preview: previewContext.preview,
            provider: .openai,
            approvalScopeID: "terminal-consent-test"
        ))
        #expect(binding.approvedRead(
            call: call,
            preview: previewContext.preview,
            provider: .openai,
            approvalScopeID: "terminal-consent-test"
        ) == nil)

        let unapproved = try await previewExecutor.execute(call)
        #expect(unapproved.status == .failure)
        #expect(unapproved.error?.code == "approval_required")
        #expect(provider.capturedSelections.isEmpty)

        let approvedExecutor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedSensitiveReadsByCallID: [call.id: approvedRead]
            ),
            terminalOutputProvider: provider,
            providerKind: .openai,
            approvalScopeID: "terminal-consent-test"
        )
        let result = try await approvedExecutor.execute(call)
        let content = try contentObject(result)
        let redactedOutput = try #require(content["output"]?.stringValue)

        #expect(result.status == .success)
        #expect(content["limit"]?.numberValue == 64)
        #expect(content["blocks"]?.numberValue == 2)
        #expect(redactedOutput.contains("build completed"))
        #expect(!redactedOutput.contains("synthetic-secret-value"))
        #expect(!redactedOutput.contains("ghp_abcdefghijklmnopqrstuvwxyz123456"))
        #expect(redactedOutput.contains("[redacted]"))
        #expect(redactedOutput.contains("[redacted-token]"))
        #expect(provider.capturedSelections == [approvedRead.selection])

        let replay = try await approvedExecutor.execute(call)
        #expect(replay.status == .failure)
        #expect(replay.error?.code == "approval_required")
        #expect(provider.requestedLimits == [70])
        #expect(provider.capturedSelections.count == 1)
    }

    @Test("terminal output snapshot enforces a UTF-8 byte budget without splitting characters")
    func terminalOutputSnapshotEnforcesUTF8Budget() {
        let prefixBudget = AgentTerminalOutputSnapshot.maximumOutputBytes
            - AgentTerminalOutputSnapshot.truncationMarker.utf8.count
        let oversized = String(repeating: "a", count: prefixBudget - 1)
            + "é"
            + String(repeating: "b", count: 64)
        let snapshot = AgentTerminalOutputSnapshot(
            source: .activeTerminal,
            surfaceID: "surface-budget",
            blockLimit: 1,
            blockCount: 1,
            output: oversized
        )

        #expect(snapshot.outputByteCount <= AgentTerminalOutputSnapshot.maximumOutputBytes)
        #expect(snapshot.output.hasSuffix(AgentTerminalOutputSnapshot.truncationMarker))
        #expect(!snapshot.output.contains("�"))
    }

    @Test("terminal output capture fails closed when selected block identity changes")
    func terminalOutputCaptureRejectsChangedBlockIdentity() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = AgentWorkspace(rootURL: root)
        let call = AgentToolCall(
            id: "call-terminal-retargeted",
            toolID: "read_terminal_output",
            arguments: ["limit": .number(2)]
        )
        let provider = StaticLocalTerminalOutputProvider(
            output: "synthetic-secret-output",
            capturedBlockReferences: [
                TerminalCommandBlockReference(id: 1, endTimeNs: 999),
                TerminalCommandBlockReference(id: 2, endTimeNs: 200),
            ]
        )
        let previewExecutor = AgentLocalToolExecutor(
            workspace: workspace,
            terminalOutputProvider: provider,
            providerKind: .openai,
            approvalScopeID: "terminal-retarget-test"
        )
        let previewContext = try await previewExecutor.approvalPreview(for: call)
        let binding = try #require(previewContext.sensitiveReadBinding)
        let approvedRead = try #require(binding.approvedRead(
            call: call,
            preview: previewContext.preview,
            provider: .openai,
            approvalScopeID: "terminal-retarget-test"
        ))
        let executor = AgentLocalToolExecutor(
            workspace: workspace,
            approvals: AgentToolApprovalContext(
                approvedSensitiveReadsByCallID: [call.id: approvedRead]
            ),
            terminalOutputProvider: provider,
            providerKind: .openai,
            approvalScopeID: "terminal-retarget-test"
        )

        let result = try await executor.execute(call)

        #expect(result.status == .failure)
        #expect(result.content == nil)
        #expect(result.error?.code == "tool_execution_failed")
        #expect(result.error?.message.contains("synthetic-secret-output") == false)
        #expect(provider.capturedSelections.count == 1)
    }

    @Test("terminal output redactor removes common credential shapes and preserves ordinary text")
    func terminalOutputRedactorRemovesCredentialShapes() {
        let input = """
        build completed
        Authorization: Bearer synthetic-bearer-value
        password="synthetic password"
        AKIA1234567890ABCDEF
        eyJheader.payload.signature
        https://demo-user:demo-password@example.invalid/path
        -----BEGIN PRIVATE KEY-----
        synthetic-private-key-material
        -----END PRIVATE KEY-----
        tokenization completed
        """

        let output = AgentSensitiveOutputRedactor.redacted(input)

        #expect(output.contains("build completed"))
        #expect(output.contains("tokenization completed"))
        #expect(!output.contains("synthetic-bearer-value"))
        #expect(!output.contains("synthetic password"))
        #expect(!output.contains("AKIA1234567890ABCDEF"))
        #expect(!output.contains("eyJheader.payload.signature"))
        #expect(!output.contains("demo-password"))
        #expect(!output.contains("synthetic-private-key-material"))
        #expect(output.contains("[redacted-private-key]"))
    }

    @Test("computer use tools refuse execution until the call is approved")
    func computerUseToolsRequireApproval() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = RecordingAgentComputerUseController(result: .keyboardTyped(characters: 6))
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            computerUseController: controller
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-computer",
            toolID: "computer_type_text",
            arguments: ["text": .string("secret")]
        ))

        #expect(result.status == .failure)
        #expect(result.error?.code == "approval_required")
        #expect(await controller.actions.isEmpty)
    }

    @Test("approved computer type text tool executes without returning typed text")
    func approvedComputerTypeTextDoesNotEchoText() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = RecordingAgentComputerUseController(result: .keyboardTyped(characters: 6))
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedComputerUseCallIDs: ["call-computer"]),
            computerUseController: controller
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-computer",
            toolID: "computer_type_text",
            arguments: ["text": .string("secret")]
        ))
        let content = try contentObject(result)

        #expect(result.status == .success)
        #expect(await controller.actions == [.keyboard(.typeText("secret"))])
        #expect(await controller.promptFlags == [true])
        #expect(content["characters"]?.numberValue == 6)
        #expect(content["text"] == nil)
    }

    @Test("approved computer screenshot tool returns only local screenshot metadata")
    func approvedComputerScreenshotReturnsMetadata() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let screenshotURL = URL(fileURLWithPath: "/tmp/cocxy-agent-computer-use.png")
        let controller = RecordingAgentComputerUseController(result: .screenshot(
            fileURL: screenshotURL,
            width: 1440,
            height: 900
        ))
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedComputerUseCallIDs: ["call-shot"]),
            computerUseController: controller
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-shot",
            toolID: "computer_screenshot"
        ))
        let content = try contentObject(result)

        #expect(result.status == .success)
        #expect(await controller.actions == [.screenshot(.mainDisplay)])
        #expect(await controller.promptFlags == [true])
        #expect(content["path"]?.stringValue == screenshotURL.path)
        #expect(content["width"]?.numberValue == 1440)
        #expect(content["height"]?.numberValue == 900)
        #expect(content["image"] == nil)
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-local-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    private func contentObject(_ result: AgentToolResult) throws -> [String: AgentJSONValue] {
        guard case .object(let object)? = result.content else {
            throw AgentLocalToolExecutorTestError.missingObjectContent
        }
        return object
    }

    private func testBinding(
        for call: AgentToolCall,
        workspace: AgentWorkspace,
        targetURL: URL,
        targetKind: AgentToolApprovalTargetKind,
        observedFileContents: Data? = nil
    ) throws -> AgentToolApprovalBinding {
        try AgentToolApprovalBinding(
            call: call,
            preview: AgentToolApprovalPreview(
                kind: targetKind == .commandWorkingDirectory ? .command : .diff,
                title: "Test approval",
                body: "Bound test preview"
            ),
            workspace: workspace,
            targetURL: targetURL,
            targetKind: targetKind,
            observedFileContents: observedFileContents
        )
    }
}

private enum AgentLocalToolExecutorTestError: Error {
    case missingObjectContent
}

private final class RecordingLocalAgentProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls: [AgentProcessCall] = []
    private var results: [AgentProcessResult]

    init(results: [AgentProcessResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        calls.append(AgentProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds
        ))
        return results.isEmpty
            ? AgentProcessResult(exitCode: 0, stdout: "", stderr: "")
            : results.removeFirst()
    }
}

private final class StaticLocalTerminalOutputProvider: AgentTerminalOutputProviding, @unchecked Sendable {
    private let output: String
    private let capturedBlockReferences: [TerminalCommandBlockReference]?
    private(set) var requestedLimits: [Int] = []
    private(set) var capturedSelections: [AgentTerminalOutputSelection] = []

    init(
        output: String,
        capturedBlockReferences: [TerminalCommandBlockReference]? = nil
    ) {
        self.output = output
        self.capturedBlockReferences = capturedBlockReferences
    }

    func latestCommandBlockSelection(limit: Int) -> AgentTerminalOutputSelection {
        requestedLimits.append(limit)
        return AgentTerminalOutputSelection(
            source: .focusedSplit,
            surfaceID: "00000000-0000-0000-0000-000000000001",
            blockLimit: limit,
            blockReferences: [
                TerminalCommandBlockReference(id: 1, endTimeNs: 100),
                TerminalCommandBlockReference(id: 2, endTimeNs: 200),
            ]
        )
    }

    func captureCommandBlockOutputs(selection: AgentTerminalOutputSelection) -> AgentTerminalOutputSnapshot {
        capturedSelections.append(selection)
        let blockReferences = capturedBlockReferences ?? selection.blockReferences
        return AgentTerminalOutputSnapshot(
            source: selection.source,
            surfaceID: selection.surfaceID,
            blockLimit: selection.blockLimit,
            blockCount: blockReferences.count,
            blockReferences: blockReferences,
            output: output
        )
    }
}

private actor RecordingAgentComputerUseController: ComputerUseControlling {
    private(set) var actions: [ComputerUseAction] = []
    private(set) var promptFlags: [Bool] = []
    let result: ComputerUseResult

    init(result: ComputerUseResult) {
        self.result = result
    }

    func perform(_ action: ComputerUseAction, promptForPermission: Bool) async throws -> ComputerUseResult {
        actions.append(action)
        promptFlags.append(promptForPermission)
        return result
    }
}

private struct AgentProcessCall: Equatable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval?
}

private extension AgentJSONValue {
    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}
