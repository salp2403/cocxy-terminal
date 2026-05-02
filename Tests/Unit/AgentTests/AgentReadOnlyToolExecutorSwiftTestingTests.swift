// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentReadOnlyToolExecutorSwiftTestingTests.swift - Safe read-only Agent tools.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentReadOnlyToolExecutor")
struct AgentReadOnlyToolExecutorSwiftTestingTests {

    @Test("read_file and list_directory stay inside workspace and return structured content")
    func readFileAndListDirectoryReturnStructuredContent() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "let answer = 42\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "notes\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        let executor = AgentReadOnlyToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let read = try await executor.execute(AgentToolCall(
            id: "call-read",
            toolID: "read_file",
            arguments: ["path": .string("Sources/App.swift")]
        ))
        let readContent = try contentObject(read)
        #expect(read.status == .success)
        #expect(readContent["path"]?.stringValue == "Sources/App.swift")
        #expect(readContent["content"]?.stringValue == "let answer = 42\n")

        let list = try await executor.execute(AgentToolCall(
            id: "call-list",
            toolID: "list_directory",
            arguments: ["path": .string(".")]
        ))
        let listContent = try contentObject(list)
        let entries = try arrayValue(listContent["entries"])
        #expect(entries.contains(AgentJSONValue.object([
            "name": .string("README.md"),
            "path": .string("README.md"),
            "type": .string("file"),
        ])))
        #expect(entries.contains(AgentJSONValue.object([
            "name": .string("Sources"),
            "path": .string("Sources"),
            "type": .string("directory"),
        ])))
    }

    @Test("read_file rejects traversal and symlinks outside the workspace")
    func readFileRejectsTraversalAndExternalSymlink() async throws {
        let root = try makeWorkspace()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-outside-\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try "secret\n".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("leak.txt"),
            withDestinationURL: outside
        )
        let executor = AgentReadOnlyToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let traversal = try await executor.execute(AgentToolCall(
            id: "call-traversal",
            toolID: "read_file",
            arguments: ["path": .string("../outside.txt")]
        ))
        let symlink = try await executor.execute(AgentToolCall(
            id: "call-link",
            toolID: "read_file",
            arguments: ["path": .string("leak.txt")]
        ))

        #expect(traversal.status == AgentToolResultStatus.failure)
        #expect(traversal.error?.code == "workspace_outside_root")
        #expect(symlink.status == AgentToolResultStatus.failure)
        #expect(symlink.error?.code == "workspace_outside_root")
    }

    @Test("read tools block sensitive files even when they are inside the workspace")
    func readToolsBlockSensitiveFilesInsideWorkspace() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "API_KEY=secret\n".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "private-key\n".write(to: root.appendingPathComponent("id_rsa"), atomically: true, encoding: .utf8)
        let runner = RecordingAgentProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "", stderr: ""),
        ])
        let executor = AgentReadOnlyToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let readEnv = try await executor.execute(AgentToolCall(
            id: "call-env",
            toolID: "read_file",
            arguments: ["path": .string(".env")]
        ))
        let diffKey = try await executor.execute(AgentToolCall(
            id: "call-diff-key",
            toolID: "git_diff",
            arguments: ["path": .string("id_rsa")]
        ))
        let list = try await executor.execute(AgentToolCall(
            id: "call-list-sensitive",
            toolID: "list_directory",
            arguments: ["path": .string(".")]
        ))
        let search = try await executor.execute(AgentToolCall(
            id: "call-search-sensitive",
            toolID: "search_files",
            arguments: ["pattern": .string("*")]
        ))

        #expect(readEnv.status == AgentToolResultStatus.failure)
        #expect(readEnv.error?.code == "workspace_sensitive_path")
        #expect(diffKey.status == AgentToolResultStatus.failure)
        #expect(diffKey.error?.code == "workspace_sensitive_path")
        #expect(runner.calls.isEmpty)

        let listedPaths = try arrayValue(contentObject(list)["entries"]).compactMap { entry -> String? in
            guard case .object(let object) = entry else { return nil }
            return object["path"]?.stringValue
        }
        let searchedPaths = try arrayValue(contentObject(search)["paths"]).compactMap(\.stringValue)
        #expect(!listedPaths.contains(".env"))
        #expect(!listedPaths.contains("id_rsa"))
        #expect(!searchedPaths.contains(".env"))
        #expect(!searchedPaths.contains("id_rsa"))
    }

    @Test("search_files matches glob patterns and skips hidden and gitignored files")
    func searchFilesMatchesGlobAndSkipsIgnoredFiles() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "*.log\nGenerated/\n".write(
            to: root.appendingPathComponent(".gitignore"),
            atomically: true,
            encoding: .utf8
        )
        try "swift\n".write(to: root.appendingPathComponent("Sources/App.swift"), atomically: true, encoding: .utf8)
        try "log\n".write(to: root.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        try "generated\n".write(
            to: root.appendingPathComponent("Generated/Ignored.swift"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "git\n".write(to: root.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        let executor = AgentReadOnlyToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let result = try await executor.execute(AgentToolCall(
            id: "call-search",
            toolID: "search_files",
            arguments: ["pattern": .string("*.swift")]
        ))
        let resultContent = try contentObject(result)
        let paths = try arrayValue(resultContent["paths"]).compactMap(\.stringValue)

        #expect(result.status == AgentToolResultStatus.success)
        #expect(paths == ["Sources/App.swift"])
    }

    @Test("grep returns regex matches with line numbers and honors result limit")
    func grepReturnsRegexMatchesWithLineNumbersAndLimit() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "alpha\nBeta\nalpha two\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "alpha ignored\n".write(to: root.appendingPathComponent(".hidden.swift"), atomically: true, encoding: .utf8)
        let executor = AgentReadOnlyToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let result = try await executor.execute(AgentToolCall(
            id: "call-grep",
            toolID: "grep",
            arguments: [
                "pattern": .string("alpha"),
                "caseSensitive": .bool(false),
                "limit": .number(2),
            ]
        ))
        let resultContent = try contentObject(result)
        let matches = try arrayValue(resultContent["matches"])

        #expect(result.status == AgentToolResultStatus.success)
        #expect(matches.count == 2)
        #expect(matches.first == AgentJSONValue.object([
            "path": .string("Sources/App.swift"),
            "line": .number(1),
            "preview": .string("alpha"),
        ]))
    }

    @Test("grep path argument scopes recursive search")
    func grepPathArgumentScopesRecursiveSearch() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let other = root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "target in scope\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "target out of scope\n".write(
            to: other.appendingPathComponent("Ignored.swift"),
            atomically: true,
            encoding: .utf8
        )
        let executor = AgentReadOnlyToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let result = try await executor.execute(AgentToolCall(
            id: "call-grep-scope",
            toolID: "grep",
            arguments: [
                "path": .string("Sources"),
                "pattern": .string("target"),
            ]
        ))
        let resultContent = try contentObject(result)
        let matches = try arrayValue(resultContent["matches"])

        #expect(matches == [
            AgentJSONValue.object([
                "path": .string("Sources/App.swift"),
                "line": .number(1),
                "preview": .string("target in scope"),
            ]),
        ])
    }

    @Test("git_status executes read-only git status in workspace")
    func gitStatusExecutesReadOnlyGitStatusInWorkspace() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingAgentProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "## main\n M Package.swift\n", stderr: ""),
        ])
        let executor = AgentReadOnlyToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let result = try await executor.execute(AgentToolCall(id: "call-status", toolID: "git_status"))
        let resultContent = try contentObject(result)

        #expect(result.status == AgentToolResultStatus.success)
        #expect(resultContent["stdout"]?.stringValue == "## main\n M Package.swift\n")
        #expect(runner.calls == [
            AgentProcessCall(
                executableURL: URL(fileURLWithPath: "/usr/bin/git"),
                arguments: ["status", "--short", "--branch"],
                workingDirectory: root.standardizedFileURL.resolvingSymlinksInPath()
            ),
        ])
    }

    @Test("git_diff validates optional path before invoking git")
    func gitDiffValidatesOptionalPathBeforeInvokingGit() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "let value = 1\n".write(
            to: root.appendingPathComponent("Sources/App.swift"),
            atomically: true,
            encoding: .utf8
        )
        let runner = RecordingAgentProcessRunner(results: [
            AgentProcessResult(exitCode: 0, stdout: "diff --git a/Sources/App.swift b/Sources/App.swift\n", stderr: ""),
        ])
        let executor = AgentReadOnlyToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-diff",
            toolID: "git_diff",
            arguments: ["path": .string("Sources/App.swift")]
        ))
        let outside = try await executor.execute(AgentToolCall(
            id: "call-outside",
            toolID: "git_diff",
            arguments: ["path": .string("../outside.swift")]
        ))

        let resultContent = try contentObject(result)
        #expect(result.status == AgentToolResultStatus.success)
        #expect(resultContent["stdout"]?.stringValue?.hasPrefix("diff --git") == true)
        #expect(runner.calls.first?.arguments == ["diff", "--", "Sources/App.swift"])
        #expect(outside.status == AgentToolResultStatus.failure)
        #expect(outside.error?.code == "workspace_outside_root")
        #expect(runner.calls.count == 1)
    }

    @Test("git failures return structured tool errors")
    func gitFailuresReturnStructuredToolErrors() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingAgentProcessRunner(results: [
            AgentProcessResult(exitCode: 128, stdout: "", stderr: "fatal: not a git repository\n"),
        ])
        let executor = AgentReadOnlyToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            processRunner: runner
        )

        let result = try await executor.execute(AgentToolCall(id: "call-status", toolID: "git_status"))

        #expect(result.status == AgentToolResultStatus.failure)
        #expect(result.error?.code == "git_status_failed")
        #expect(result.error?.message.contains("fatal: not a git repository") == true)
    }

    @Test("read_terminal_output uses injected terminal output provider")
    func readTerminalOutputUsesInjectedProvider() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let terminalProvider = RecordingTerminalOutputProvider(output: "block one\nblock two\n")
        let executor = AgentReadOnlyToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            terminalOutputProvider: terminalProvider
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-terminal",
            toolID: "read_terminal_output",
            arguments: ["limit": .number(2)]
        ))
        let resultContent = try contentObject(result)

        #expect(result.status == AgentToolResultStatus.success)
        #expect(resultContent["output"]?.stringValue == "block one\nblock two\n")
        #expect(terminalProvider.requestedLimits == [2])
    }

    @Test("read_terminal_output fails closed without terminal provider")
    func readTerminalOutputFailsClosedWithoutProvider() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let executor = AgentReadOnlyToolExecutor(workspace: AgentWorkspace(rootURL: root))

        let result = try await executor.execute(AgentToolCall(
            id: "call-terminal",
            toolID: "read_terminal_output"
        ))

        #expect(result.status == AgentToolResultStatus.failure)
        #expect(result.error?.code == "terminal_output_unavailable")
    }

    @Test("read_lsp_diagnostics uses injected diagnostics provider with limit")
    func readLSPDiagnosticsUsesInjectedProviderWithLimit() async throws {
        let root = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnosticsProvider = StaticAgentLSPDiagnosticsProvider(diagnostics: [
            AgentLSPDiagnostic(
                path: "Sources/App.swift",
                line: 4,
                column: 12,
                severity: "error",
                message: "Cannot find symbol",
                source: "sourcekit"
            ),
            AgentLSPDiagnostic(
                path: "Sources/Other.swift",
                line: 7,
                column: 2,
                severity: "warning",
                message: "Unused value",
                source: nil
            ),
        ])
        let executor = AgentReadOnlyToolExecutor(
            workspace: AgentWorkspace(rootURL: root),
            lspDiagnosticsProvider: diagnosticsProvider
        )

        let result = try await executor.execute(AgentToolCall(
            id: "call-diagnostics",
            toolID: "read_lsp_diagnostics",
            arguments: ["limit": .number(1)]
        ))
        let resultContent = try contentObject(result)
        let diagnostics = try arrayValue(resultContent["diagnostics"])

        #expect(result.status == AgentToolResultStatus.success)
        #expect(diagnostics == [
            AgentJSONValue.object([
                "path": .string("Sources/App.swift"),
                "line": .number(4),
                "column": .number(12),
                "severity": .string("error"),
                "message": .string("Cannot find symbol"),
                "source": .string("sourcekit"),
            ]),
        ])
    }

    private func makeWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Generated", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root
    }

    private func contentObject(_ result: AgentToolResult) throws -> [String: AgentJSONValue] {
        guard case .object(let object)? = result.content else {
            throw AgentReadOnlyToolExecutorTestError.missingObjectContent
        }
        return object
    }

    private func arrayValue(_ value: AgentJSONValue?) throws -> [AgentJSONValue] {
        guard case .array(let array)? = value else {
            throw AgentReadOnlyToolExecutorTestError.missingArrayContent
        }
        return array
    }
}

private enum AgentReadOnlyToolExecutorTestError: Error {
    case missingObjectContent
    case missingArrayContent
}

private final class RecordingAgentProcessRunner: AgentProcessRunning {
    private(set) var calls: [AgentProcessCall] = []
    private var results: [AgentProcessResult]

    init(results: [AgentProcessResult]) {
        self.results = results
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL
    ) throws -> AgentProcessResult {
        calls.append(AgentProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory
        ))
        return results.isEmpty
            ? AgentProcessResult(exitCode: 0, stdout: "", stderr: "")
            : results.removeFirst()
    }
}

private struct AgentProcessCall: Equatable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
}

private final class RecordingTerminalOutputProvider: AgentTerminalOutputProviding {
    private(set) var requestedLimits: [Int] = []
    private let output: String

    init(output: String) {
        self.output = output
    }

    func latestCommandBlockOutputs(limit: Int) -> String {
        requestedLimits.append(limit)
        return output
    }
}

private struct StaticAgentLSPDiagnosticsProvider: AgentLSPDiagnosticsProviding {
    let diagnostics: [AgentLSPDiagnostic]

    func currentDiagnostics(limit: Int) -> [AgentLSPDiagnostic] {
        Array(diagnostics.prefix(limit))
    }
}
