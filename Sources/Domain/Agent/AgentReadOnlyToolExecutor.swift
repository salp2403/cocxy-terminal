// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentReadOnlyToolExecutor.swift - Safe read-only Agent tool execution.

import Darwin
import Foundation

struct AgentProcessResult: Sendable, Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol AgentProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult
}

extension AgentProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL
    ) throws -> AgentProcessResult {
        try run(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: nil
        )
    }
}

protocol AgentTerminalOutputProviding: Sendable {
    func latestCommandBlockOutputs(limit: Int) -> String
}

struct AgentLSPDiagnostic: Sendable, Equatable {
    let path: String
    let line: Int
    let column: Int
    let severity: String
    let message: String
    let source: String?
}

protocol AgentLSPDiagnosticsProviding: Sendable {
    func currentDiagnostics(limit: Int) -> [AgentLSPDiagnostic]
}

struct AgentProcessRunner: AgentProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = AgentProcessOutputBuffer()
        let stderrBuffer = AgentProcessOutputBuffer()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBuffer.read(from: stdoutPipe.fileHandleForReading)
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBuffer.read(from: stderrPipe.fileHandleForReading)
            group.leave()
        }

        try process.run()
        let timedOut = wait(for: process, timeoutSeconds: timeoutSeconds)
        if timedOut {
            terminate(process)
        }
        group.wait()

        var stderr = String(data: stderrBuffer.data(), encoding: .utf8) ?? ""
        if timedOut {
            if !stderr.isEmpty, !stderr.hasSuffix("\n") {
                stderr.append("\n")
            }
            stderr.append("Command timed out after \(Int(timeoutSeconds ?? 0)) seconds.\n")
        }

        return AgentProcessResult(
            exitCode: timedOut ? 124 : process.terminationStatus,
            stdout: String(data: stdoutBuffer.data(), encoding: .utf8) ?? "",
            stderr: stderr
        )
    }

    private func wait(for process: Process, timeoutSeconds: TimeInterval?) -> Bool {
        guard let timeoutSeconds else {
            process.waitUntilExit()
            return false
        }

        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        return process.isRunning
    }

    private func terminate(_ process: Process) {
        process.terminate()
        Thread.sleep(forTimeInterval: 0.05)
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}

private final class AgentProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func read(from fileHandle: FileHandle) {
        let data = fileHandle.readDataToEndOfFile()
        lock.lock()
        storage = data
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

struct AgentReadOnlyToolExecutor: AgentToolExecuting {
    let workspace: AgentWorkspace
    let processRunner: any AgentProcessRunning
    let terminalOutputProvider: (any AgentTerminalOutputProviding)?
    let lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)?
    let gitExecutableURL: URL
    let maxFileBytes: Int
    let defaultLimit: Int
    let maxLimit: Int
    let skillRegistry: SkillRegistry
    let codebaseSemanticIndex: CodebaseSemanticIndex?

    init(
        workspace: AgentWorkspace,
        processRunner: any AgentProcessRunning = AgentProcessRunner(),
        terminalOutputProvider: (any AgentTerminalOutputProviding)? = nil,
        lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)? = nil,
        skillRegistry: SkillRegistry? = nil,
        codebaseSemanticIndex: CodebaseSemanticIndex? = nil,
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        maxFileBytes: Int = 1_000_000,
        defaultLimit: Int = 50,
        maxLimit: Int = 200
    ) {
        self.workspace = workspace
        self.processRunner = processRunner
        self.terminalOutputProvider = terminalOutputProvider
        self.lspDiagnosticsProvider = lspDiagnosticsProvider
        self.gitExecutableURL = gitExecutableURL
        self.maxFileBytes = maxFileBytes
        self.defaultLimit = defaultLimit
        self.maxLimit = maxLimit
        self.skillRegistry = skillRegistry ?? SkillRegistry.localDefault(projectRoot: workspace.rootURL)
        self.codebaseSemanticIndex = codebaseSemanticIndex
    }

    func execute(_ call: AgentToolCall) async throws -> AgentToolResult {
        do {
            switch call.toolID {
            case "read_file":
                return try readFile(call)
            case "list_directory":
                return try listDirectory(call)
            case "search_files":
                return try searchFiles(call)
            case "search_codebase":
                return try searchCodebase(call)
            case "list_skills":
                return try listSkills(call)
            case "use_skill":
                return try useSkill(call)
            case "grep":
                return try grep(call)
            case "git_status":
                return try gitStatus(call)
            case "git_diff":
                return try gitDiff(call)
            case "read_terminal_output":
                return readTerminalOutput(call)
            case "read_lsp_diagnostics":
                return readLSPDiagnostics(call)
            default:
                return failure(
                    call,
                    code: "unsupported_tool",
                    message: "Read-only executor does not support tool: \(call.toolID)"
                )
            }
        } catch let error as AgentWorkspaceError {
            return failure(call, code: error.code, message: error.message)
        } catch let error as AgentReadOnlyToolError {
            return failure(call, code: error.code, message: error.message)
        } catch let error as SkillError {
            return failure(call, code: "skill_error", message: error.localizedDescription)
        } catch {
            return failure(call, code: "tool_execution_failed", message: String(describing: error))
        }
    }

    private func readFile(_ call: AgentToolCall) throws -> AgentToolResult {
        let path = try requiredStringArgument("path", in: call)
        let url = try workspace.requireRegularFile(path)
        let relativePath = workspace.relativePath(for: url)
        let content = try readUTF8File(url, relativePath: relativePath, failOnBinary: true)

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "path": .string(relativePath),
                "content": .string(content),
            ])
        )
    }

    private func listDirectory(_ call: AgentToolCall) throws -> AgentToolResult {
        let path = call.arguments["path"]?.stringValue ?? "."
        let directory = try workspace.requireDirectory(path)
        let ignoreRules = AgentWorkspaceIgnoreRules(rootURL: workspace.rootURL)
        let entries = try FileManager.default
            .contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            .compactMap { url -> AgentJSONValue? in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                let relativePath = workspace.relativePath(for: url)
                let isDirectory = values?.isDirectory == true
                guard !ignoreRules.isIgnored(relativePath: relativePath, isDirectory: isDirectory) else {
                    return nil
                }
                let type = isDirectory ? "directory" : "file"
                return .object([
                    "name": .string(url.lastPathComponent),
                    "path": .string(relativePath),
                    "type": .string(type),
                ])
            }
            .sorted { lhs, rhs in
                (lhs.objectValue?["path"]?.stringValue ?? "") < (rhs.objectValue?["path"]?.stringValue ?? "")
            }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "path": .string(workspace.relativePath(for: directory)),
                "entries": .array(entries),
            ])
        )
    }

    private func searchFiles(_ call: AgentToolCall) throws -> AgentToolResult {
        let pattern = try requiredStringArgument("pattern", in: call)
        let limit = boundedLimit(from: call)
        let ignoreRules = AgentWorkspaceIgnoreRules(rootURL: workspace.rootURL)
        var paths: [AgentJSONValue] = []

        for url in regularFiles(ignoreRules: ignoreRules) {
            guard paths.count < limit else { break }
            let relativePath = workspace.relativePath(for: url)
            guard glob(pattern, matches: relativePath) || glob(pattern, matches: url.lastPathComponent) else {
                continue
            }
            paths.append(.string(relativePath))
        }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object(["paths": .array(paths)])
        )
    }

    private func searchCodebase(_ call: AgentToolCall) throws -> AgentToolResult {
        let query = try requiredStringArgument("query", in: call)
        let index = CodebaseIndex(
            workspace: workspace,
            maxFileBytes: maxFileBytes,
            semanticIndex: preparedSemanticIndex()
        )
        let response = try index.search(CodebaseSearchRequest(
            query: query,
            scopePath: call.arguments["path"]?.stringValue,
            limit: boundedLimit(from: call)
        ))

        let results = response.results.map { result -> AgentJSONValue in
            var payload: [String: AgentJSONValue] = [
                "path": .string(result.path),
                "preview": .string(result.preview),
                "score": .number(result.score),
                "matchKind": .string(result.matchKind.rawValue),
            ]
            if let line = result.line {
                payload["line"] = .number(Double(line))
            }
            return .object(payload)
        }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "query": .string(response.query),
                "mode": .string(response.mode.rawValue),
                "results": .array(results),
            ])
        )
    }

    private func preparedSemanticIndex() -> CodebaseSemanticIndex? {
        guard let codebaseSemanticIndex else {
            return nil
        }
        do {
            _ = try codebaseSemanticIndex.rebuildIfNeeded()
            return codebaseSemanticIndex
        } catch {
            return nil
        }
    }

    private func listSkills(_ call: AgentToolCall) throws -> AgentToolResult {
        let entries = try skillRegistry.loadSkills().map { skill -> AgentJSONValue in
            .object([
                "id": .string(skill.id),
                "name": .string(skill.name),
                "description": .string(skill.summary),
                "source": .string(skill.source.rawValue),
            ])
        }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "count": .number(Double(entries.count)),
                "skills": .array(entries),
            ])
        )
    }

    private func useSkill(_ call: AgentToolCall) throws -> AgentToolResult {
        let id = try requiredStringArgument("id", in: call).lowercased()
        let invocation = try SkillInvoker(registry: skillRegistry).makeInvocation(skillIDs: [id])

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "skillIDs": .array(invocation.skillIDs.map { .string($0) }),
                "instructions": .string(invocation.instructions),
            ])
        )
    }

    private func grep(_ call: AgentToolCall) throws -> AgentToolResult {
        let pattern = try requiredStringArgument("pattern", in: call)
        let searchRoot = call.arguments["path"]?.stringValue ?? "."
        let directory = try workspace.requireDirectory(searchRoot)
        let caseSensitive = call.arguments["caseSensitive"]?.boolValue ?? true
        let limit = boundedLimit(from: call)
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        let regex: NSRegularExpression

        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw AgentReadOnlyToolError.invalidRegex(pattern)
        }

        let ignoreRules = AgentWorkspaceIgnoreRules(rootURL: workspace.rootURL)
        var matches: [AgentJSONValue] = []

        for url in regularFiles(startingAt: directory, ignoreRules: ignoreRules) {
            guard matches.count < limit else { break }
            let relativePath = workspace.relativePath(for: url)
            guard let content = try? readUTF8File(url, relativePath: relativePath, failOnBinary: false) else {
                continue
            }

            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                guard matches.count < limit else { break }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard regex.firstMatch(in: line, options: [], range: range) != nil else {
                    continue
                }
                matches.append(.object([
                    "path": .string(relativePath),
                    "line": .number(Double(index + 1)),
                    "preview": .string(line.trimmingCharacters(in: .whitespacesAndNewlines)),
                ]))
            }
        }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object(["matches": .array(matches)])
        )
    }

    private func readTerminalOutput(_ call: AgentToolCall) -> AgentToolResult {
        guard let terminalOutputProvider else {
            return failure(
                call,
                code: "terminal_output_unavailable",
                message: "No terminal output provider is available for this Agent run."
            )
        }

        let limit = boundedLimit(from: call)
        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "limit": .number(Double(limit)),
                "output": .string(terminalOutputProvider.latestCommandBlockOutputs(limit: limit)),
            ])
        )
    }

    private func readLSPDiagnostics(_ call: AgentToolCall) -> AgentToolResult {
        guard let lspDiagnosticsProvider else {
            return failure(
                call,
                code: "lsp_diagnostics_unavailable",
                message: "No LSP diagnostics provider is available for this Agent run."
            )
        }

        let limit = boundedLimit(from: call)
        let diagnostics = lspDiagnosticsProvider
            .currentDiagnostics(limit: limit)
            .map { diagnostic in
                var payload: [String: AgentJSONValue] = [
                    "path": .string(diagnostic.path),
                    "line": .number(Double(diagnostic.line)),
                    "column": .number(Double(diagnostic.column)),
                    "severity": .string(diagnostic.severity),
                    "message": .string(diagnostic.message),
                ]
                if let source = diagnostic.source {
                    payload["source"] = .string(source)
                }
                return AgentJSONValue.object(payload)
            }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "limit": .number(Double(limit)),
                "diagnostics": .array(diagnostics),
            ])
        )
    }

    private func gitStatus(_ call: AgentToolCall) throws -> AgentToolResult {
        try runGit(
            call,
            arguments: ["status", "--short", "--branch"],
            failureCode: "git_status_failed"
        )
    }

    private func gitDiff(_ call: AgentToolCall) throws -> AgentToolResult {
        var arguments = ["diff", "--"]
        if let rawPath = call.arguments["path"]?.stringValue {
            let url = try workspace.resolveExistingPath(rawPath)
            arguments.append(workspace.relativePath(for: url))
        }

        return try runGit(
            call,
            arguments: arguments,
            failureCode: "git_diff_failed"
        )
    }

    private func runGit(
        _ call: AgentToolCall,
        arguments: [String],
        failureCode: String
    ) throws -> AgentToolResult {
        let result = try processRunner.run(
            executableURL: gitExecutableURL,
            arguments: arguments,
            workingDirectory: workspace.rootURL
        )

        guard result.exitCode == 0 else {
            return failure(
                call,
                code: failureCode,
                message: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "exitCode": .number(Double(result.exitCode)),
                "stdout": .string(result.stdout),
                "stderr": .string(result.stderr),
            ])
        )
    }

    private func regularFiles(
        startingAt rootURL: URL? = nil,
        ignoreRules: AgentWorkspaceIgnoreRules
    ) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: rootURL ?? workspace.rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var files: [URL] = []

        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            let relativePath = workspace.relativePath(for: url)
            let isDirectory = values?.isDirectory == true

            if ignoreRules.isIgnored(relativePath: relativePath, isDirectory: isDirectory) {
                if isDirectory {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            files.append(url)
        }

        return files.sorted { workspace.relativePath(for: $0) < workspace.relativePath(for: $1) }
    }

    private func readUTF8File(
        _ url: URL,
        relativePath: String,
        failOnBinary: Bool
    ) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard fileSize <= maxFileBytes else {
            throw AgentWorkspaceError.fileTooLarge(path: relativePath, maxBytes: maxFileBytes)
        }

        let data = try Data(contentsOf: url)
        if data.contains(0) {
            if failOnBinary {
                throw AgentWorkspaceError.binaryFile(relativePath)
            }
            throw AgentReadOnlyToolError.skippedBinary(relativePath)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            if failOnBinary {
                throw AgentWorkspaceError.nonUTF8File(relativePath)
            }
            throw AgentReadOnlyToolError.skippedNonUTF8(relativePath)
        }
        return content
    }

    private func requiredStringArgument(_ name: String, in call: AgentToolCall) throws -> String {
        guard let value = call.arguments[name]?.stringValue,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AgentReadOnlyToolError.missingArgument(name)
        }
        return value
    }

    private func boundedLimit(from call: AgentToolCall) -> Int {
        let rawLimit = call.arguments["limit"]?.numberValue.map(Int.init) ?? defaultLimit
        return min(max(rawLimit, 1), maxLimit)
    }

    private func failure(_ call: AgentToolCall, code: String, message: String) -> AgentToolResult {
        .failure(callID: call.id, toolID: call.toolID, code: code, message: message)
    }
}

private enum AgentReadOnlyToolError: Error, Sendable, Equatable {
    case missingArgument(String)
    case invalidRegex(String)
    case skippedBinary(String)
    case skippedNonUTF8(String)

    var code: String {
        switch self {
        case .missingArgument:
            return "missing_argument"
        case .invalidRegex:
            return "invalid_regex"
        case .skippedBinary:
            return "binary_file"
        case .skippedNonUTF8:
            return "non_utf8_file"
        }
    }

    var message: String {
        switch self {
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .invalidRegex(let pattern):
            return "Invalid regex pattern: \(pattern)"
        case .skippedBinary(let path):
            return "Skipped binary file: \(path)"
        case .skippedNonUTF8(let path):
            return "Skipped non-UTF-8 file: \(path)"
        }
    }
}

private struct AgentWorkspaceIgnoreRules {
    private let rules: [AgentWorkspaceIgnoreRule]

    init(rootURL: URL) {
        let gitignore = rootURL.appendingPathComponent(".gitignore")
        guard let content = try? String(contentsOf: gitignore, encoding: .utf8) else {
            self.rules = []
            return
        }
        self.rules = content
            .components(separatedBy: .newlines)
            .compactMap(AgentWorkspaceIgnoreRule.init(rawPattern:))
    }

    func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        if AgentSensitivePathPolicy.isProtected(relativePath: relativePath, isDirectory: isDirectory) {
            return true
        }
        if relativePath == ".git" || relativePath.hasPrefix(".git/") {
            return true
        }
        return rules.contains { $0.matches(relativePath: relativePath, isDirectory: isDirectory) }
    }
}

private struct AgentWorkspaceIgnoreRule {
    let pattern: String
    let directoryOnly: Bool

    init?(rawPattern: String) {
        let trimmed = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !trimmed.hasPrefix("!") else {
            return nil
        }

        self.directoryOnly = trimmed.hasSuffix("/")
        self.pattern = String(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    func matches(relativePath: String, isDirectory: Bool) -> Bool {
        guard !directoryOnly || isDirectory || relativePath.hasPrefix(pattern + "/") else {
            return false
        }
        if relativePath == pattern || relativePath.hasPrefix(pattern + "/") {
            return true
        }
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        return glob(pattern, matches: name) || glob(pattern, matches: relativePath)
    }
}

private func glob(_ pattern: String, matches value: String) -> Bool {
    pattern.withCString { patternPointer in
        value.withCString { valuePointer in
            fnmatch(patternPointer, valuePointer, 0) == 0
        }
    }
}

private extension AgentJSONValue {
    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var objectValue: [String: AgentJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
