// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolApprovalPreviewSwiftTestingTests.swift - Approval preview contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentToolApprovalPreview")
struct AgentToolApprovalPreviewSwiftTestingTests {

    @Test("write_file preview returns a diff without modifying disk")
    func writeFilePreviewReturnsDiffWithoutModifyingDisk() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Sources/App.swift")
        try "let value = 1\n".write(to: target, atomically: true, encoding: .utf8)
        let executor = AgentLocalToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let preview = try await executor.preview(for: AgentToolCall(
            id: "call-write",
            toolID: "write_file",
            arguments: [
                "path": .string("Sources/App.swift"),
                "content": .string("let value = 2\n"),
            ]
        ))

        #expect(preview.kind == .diff)
        #expect(preview.title == "Review changes to Sources/App.swift")
        #expect(preview.body.contains("-let value = 1"))
        #expect(preview.body.contains("+let value = 2"))
        #expect(try String(contentsOf: target, encoding: .utf8) == "let value = 1\n")
    }

    @Test("run_command preview describes command and cwd without executing")
    func runCommandPreviewDescribesCommandAndCWD() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingPreviewProcessRunner()
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let preview = try await executor.preview(for: AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: [
                "command": .string("swift test --filter Agent"),
                "cwd": .string("Sources"),
                "timeoutSeconds": .number(30),
            ]
        ))

        #expect(preview.kind == .command)
        #expect(preview.title == "Approve command")
        #expect(preview.body.contains("swift test --filter Agent"))
        #expect(preview.body.contains("cwd: Sources"))
        #expect(preview.body.contains("timeout: 30s"))
        #expect(runner.calls == 0)
    }

    @Test("run_command preview refuses normalized root delete variants")
    func runCommandPreviewRefusesRootDeleteVariants() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingPreviewProcessRunner()
        let executor = AgentLocalToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        for command in ["rm -rf /.", "/bin/rm -rf /.", "sh -c 'rm -rf /.'", "env -S 'rm -rf /.'"] {
            await #expect(throws: (any Error).self) {
                _ = try await executor.preview(for: AgentToolCall(
                    id: "call-danger-\(command)",
                    toolID: "run_command",
                    arguments: ["command": .string(command)]
                ))
            }
        }
        #expect(runner.calls == 0)
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }
}

private final class RecordingPreviewProcessRunner: AgentProcessRunning, @unchecked Sendable {
    private(set) var calls = 0

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        calls += 1
        return AgentProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
