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
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedWriteCallIDs: ["call-write"])
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-write",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string("let value = 2\n"),
            ]
        ))
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
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedWriteCallIDs: [
                "call-missing",
                "call-create",
                "call-sensitive",
            ])
        )

        let missing = try await executor.execute(AgentToolCall(
            id: "call-missing",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/NewFile.swift"),
                "content": .string("let created = true\n"),
            ]
        ))
        let created = try await executor.execute(AgentToolCall(
            id: "call-create",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/NewFile.swift"),
                "content": .string("let created = true\n"),
                "create": .bool(true),
            ]
        ))
        let sensitive = try await executor.execute(AgentToolCall(
            id: "call-sensitive",
            toolID: "write_file",
            arguments: [
                "path": .string(".env"),
                "content": .string("API_KEY=secret\n"),
                "create": .bool(true),
            ]
        ))

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
        try "alpha\nbeta\nalpha\n".write(to: target, atomically: true, encoding: .utf8)
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedWriteCallIDs: ["call-ambiguous", "call-apply"])
        )

        let ambiguous = try await executor.execute(AgentToolCall(
            id: "call-ambiguous",
            toolID: "apply_diff",
            arguments: [
                "path": .string("Sources/App.swift"),
                "oldText": .string("alpha"),
                "newText": .string("gamma"),
            ]
        ))
        let applied = try await executor.execute(AgentToolCall(
            id: "call-apply",
            toolID: "apply_diff",
            arguments: [
                "path": .string("Sources/App.swift"),
                "oldText": .string("beta"),
                "newText": .string("delta"),
            ]
        ))
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
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedWriteCallIDs: ["call-delete", "call-empty"])
        )

        let delete = try await executor.execute(AgentToolCall(
            id: "call-delete",
            toolID: "apply_diff",
            arguments: [
                "path": .string("Sources/App.swift"),
                "oldText": .string("beta\n"),
                "newText": .string(""),
            ]
        ))
        let empty = try await executor.execute(AgentToolCall(
            id: "call-empty",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string(""),
            ]
        ))

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
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            approvals: AgentToolApprovalContext(approvedCommandCallIDs: ["call-run"]),
            processRunner: runner,
            shellExecutableURL: URL(fileURLWithPath: "/bin/zsh")
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: [
                "command": .string("swift test --filter AgentLocalToolExecutor"),
                "cwd": .string("Sources"),
                "timeoutSeconds": .number(5),
            ]
        ))
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
