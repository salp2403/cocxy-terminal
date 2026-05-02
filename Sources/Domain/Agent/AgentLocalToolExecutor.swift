// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLocalToolExecutor.swift - Local Agent write and command tool execution.

import Foundation

struct AgentToolApprovalContext: Sendable, Equatable {
    let approvedWriteCallIDs: Set<String>
    let approvedCommandCallIDs: Set<String>
    let userInputResponsesByCallID: [String: String]

    init(
        approvedWriteCallIDs: Set<String> = [],
        approvedCommandCallIDs: Set<String> = [],
        userInputResponsesByCallID: [String: String] = [:]
    ) {
        self.approvedWriteCallIDs = approvedWriteCallIDs
        self.approvedCommandCallIDs = approvedCommandCallIDs
        self.userInputResponsesByCallID = userInputResponsesByCallID
    }

    func approvesWrite(callID: String) -> Bool {
        approvedWriteCallIDs.contains(callID)
    }

    func approvesCommand(callID: String) -> Bool {
        approvedCommandCallIDs.contains(callID)
    }

    func userInputResponse(callID: String) -> String? {
        userInputResponsesByCallID[callID]
    }
}

struct AgentLocalToolExecutor: AgentToolExecuting, AgentToolPreviewing {
    let workspace: AgentWorkspace
    let approvals: AgentToolApprovalContext
    let processRunner: any AgentProcessRunning
    let shellExecutableURL: URL
    let readOnlyExecutor: AgentReadOnlyToolExecutor
    let maxFileBytes: Int
    let defaultCommandTimeoutSeconds: TimeInterval
    let maxCommandTimeoutSeconds: TimeInterval

    init(
        workspace: AgentWorkspace,
        approvals: AgentToolApprovalContext = AgentToolApprovalContext(),
        processRunner: any AgentProcessRunning = AgentProcessRunner(),
        terminalOutputProvider: (any AgentTerminalOutputProviding)? = nil,
        lspDiagnosticsProvider: (any AgentLSPDiagnosticsProviding)? = nil,
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        shellExecutableURL: URL = URL(fileURLWithPath: "/bin/zsh"),
        maxFileBytes: Int = 1_000_000,
        defaultCommandTimeoutSeconds: TimeInterval = 60,
        maxCommandTimeoutSeconds: TimeInterval = 300
    ) {
        self.workspace = workspace
        self.approvals = approvals
        self.processRunner = processRunner
        self.shellExecutableURL = shellExecutableURL
        self.maxFileBytes = maxFileBytes
        self.defaultCommandTimeoutSeconds = defaultCommandTimeoutSeconds
        self.maxCommandTimeoutSeconds = maxCommandTimeoutSeconds
        self.readOnlyExecutor = AgentReadOnlyToolExecutor(
            workspace: workspace,
            processRunner: processRunner,
            terminalOutputProvider: terminalOutputProvider,
            lspDiagnosticsProvider: lspDiagnosticsProvider,
            gitExecutableURL: gitExecutableURL,
            maxFileBytes: maxFileBytes
        )
    }

    func execute(_ call: AgentToolCall) async throws -> AgentToolResult {
        do {
            switch call.toolID {
            case "read_file",
                 "list_directory",
                 "search_files",
                 "grep",
                 "git_status",
                 "git_diff",
                 "read_terminal_output",
                 "read_lsp_diagnostics":
                return try await readOnlyExecutor.execute(call)
            case "write_file":
                return try writeFile(call)
            case "apply_diff":
                return try applyDiff(call)
            case "run_command":
                return try runCommand(call)
            case "ask_user":
                return try askUser(call)
            default:
                return failure(
                    call,
                    code: "unsupported_tool",
                    message: "Local executor does not support tool: \(call.toolID)"
                )
            }
        } catch let error as AgentWorkspaceError {
            return failure(call, code: error.code, message: error.message)
        } catch let error as AgentLocalToolError {
            return failure(call, code: error.code, message: error.message)
        } catch {
            return failure(call, code: "tool_execution_failed", message: String(describing: error))
        }
    }

    func preview(for call: AgentToolCall) async throws -> AgentToolApprovalPreview {
        switch call.toolID {
        case "write_file":
            return try writeFilePreview(call)
        case "apply_diff":
            return try applyDiffPreview(call)
        case "run_command":
            return try runCommandPreview(call)
        case "ask_user":
            return AgentToolApprovalPreview(
                kind: .userInput,
                title: "Agent requested input",
                body: call.arguments["prompt"]?.stringValue ?? "The agent requested user input."
            )
        default:
            throw AgentLocalToolError.unsupportedTool(call.toolID)
        }
    }

    private func writeFile(_ call: AgentToolCall) throws -> AgentToolResult {
        guard approvals.approvesWrite(callID: call.id) else {
            throw AgentLocalToolError.approvalRequired(toolID: call.toolID)
        }

        let path = try requiredStringArgument("path", in: call)
        let content = try stringArgument("content", in: call, allowEmpty: true)
        let create = call.arguments["create"]?.boolValue ?? false
        let url = try workspace.resolveWritableFile(path, allowCreate: create)
        let relativePath = workspace.relativePath(for: url)
        let oldContent = try existingTextContent(at: url, relativePath: relativePath)

        try content.write(to: url, atomically: true, encoding: .utf8)

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "path": .string(relativePath),
                "bytes": .number(Double(Data(content.utf8).count)),
                "diff": .string(unifiedDiff(path: relativePath, oldContent: oldContent, newContent: content)),
            ])
        )
    }

    private func writeFilePreview(_ call: AgentToolCall) throws -> AgentToolApprovalPreview {
        let path = try requiredStringArgument("path", in: call)
        let content = try stringArgument("content", in: call, allowEmpty: true)
        let create = call.arguments["create"]?.boolValue ?? false
        let url = try workspace.resolveWritableFile(path, allowCreate: create)
        let relativePath = workspace.relativePath(for: url)
        let oldContent = try existingTextContent(at: url, relativePath: relativePath)

        return AgentToolApprovalPreview(
            kind: .diff,
            title: "Review changes to \(relativePath)",
            body: unifiedDiff(path: relativePath, oldContent: oldContent, newContent: content)
        )
    }

    private func applyDiff(_ call: AgentToolCall) throws -> AgentToolResult {
        guard approvals.approvesWrite(callID: call.id) else {
            throw AgentLocalToolError.approvalRequired(toolID: call.toolID)
        }

        let path = try requiredStringArgument("path", in: call)
        let oldText = try requiredStringArgument("oldText", in: call)
        let newText = try stringArgument("newText", in: call, allowEmpty: true)
        let url = try workspace.requireRegularFile(path)
        let relativePath = workspace.relativePath(for: url)
        let oldContent = try existingTextContent(at: url, relativePath: relativePath)
        let ranges = matchingRanges(of: oldText, in: oldContent)

        guard !ranges.isEmpty else {
            throw AgentLocalToolError.oldTextNotFound(path: relativePath)
        }
        guard ranges.count == 1, let range = ranges.first else {
            throw AgentLocalToolError.ambiguousOldText(path: relativePath)
        }

        var nextContent = oldContent
        nextContent.replaceSubrange(range, with: newText)
        try nextContent.write(to: url, atomically: true, encoding: .utf8)

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "path": .string(relativePath),
                "replacements": .number(1),
                "diff": .string(unifiedDiff(path: relativePath, oldContent: oldContent, newContent: nextContent)),
            ])
        )
    }

    private func applyDiffPreview(_ call: AgentToolCall) throws -> AgentToolApprovalPreview {
        let path = try requiredStringArgument("path", in: call)
        let oldText = try requiredStringArgument("oldText", in: call)
        let newText = try stringArgument("newText", in: call, allowEmpty: true)
        let url = try workspace.requireRegularFile(path)
        let relativePath = workspace.relativePath(for: url)
        let oldContent = try existingTextContent(at: url, relativePath: relativePath)
        let ranges = matchingRanges(of: oldText, in: oldContent)

        guard !ranges.isEmpty else {
            throw AgentLocalToolError.oldTextNotFound(path: relativePath)
        }
        guard ranges.count == 1, let range = ranges.first else {
            throw AgentLocalToolError.ambiguousOldText(path: relativePath)
        }

        var nextContent = oldContent
        nextContent.replaceSubrange(range, with: newText)
        return AgentToolApprovalPreview(
            kind: .diff,
            title: "Review changes to \(relativePath)",
            body: unifiedDiff(path: relativePath, oldContent: oldContent, newContent: nextContent)
        )
    }

    private func runCommand(_ call: AgentToolCall) throws -> AgentToolResult {
        let command = try requiredStringArgument("command", in: call)
        guard !AgentShellCommandSafety.isDangerous(command) else {
            throw AgentLocalToolError.dangerousCommand(command)
        }
        guard approvals.approvesCommand(callID: call.id) else {
            throw AgentLocalToolError.approvalRequired(toolID: call.toolID)
        }

        let cwd = try workspace.requireDirectory(call.arguments["cwd"]?.stringValue ?? ".")
        let timeout = boundedTimeout(from: call)
        let result = try processRunner.run(
            executableURL: shellExecutableURL,
            arguments: ["-lc", command],
            workingDirectory: cwd,
            timeoutSeconds: timeout
        )

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "command": .string(command),
                "cwd": .string(workspace.relativePath(for: cwd)),
                "exitCode": .number(Double(result.exitCode)),
                "stdout": .string(result.stdout),
                "stderr": .string(result.stderr),
                "timeoutSeconds": .number(timeout),
            ])
        )
    }

    private func runCommandPreview(_ call: AgentToolCall) throws -> AgentToolApprovalPreview {
        let command = try requiredStringArgument("command", in: call)
        guard !AgentShellCommandSafety.isDangerous(command) else {
            throw AgentLocalToolError.dangerousCommand(command)
        }
        let cwd = try workspace.requireDirectory(call.arguments["cwd"]?.stringValue ?? ".")
        let timeout = boundedTimeout(from: call)
        let timeoutText = timeout.rounded(.down) == timeout
            ? "\(Int(timeout))"
            : "\(timeout)"
        return AgentToolApprovalPreview(
            kind: .command,
            title: "Approve command",
            body: [
                "command: \(command)",
                "cwd: \(workspace.relativePath(for: cwd))",
                "timeout: \(timeoutText)s",
            ].joined(separator: "\n")
        )
    }

    private func askUser(_ call: AgentToolCall) throws -> AgentToolResult {
        let prompt = call.arguments["prompt"]?.stringValue ?? "The agent requested user input."
        guard let answer = approvals.userInputResponse(callID: call.id),
              !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AgentLocalToolError.userInputRequired(toolID: call.toolID)
        }

        return .success(
            callID: call.id,
            toolID: call.toolID,
            content: .object([
                "prompt": .string(prompt),
                "answer": .string(answer),
            ])
        )
    }

    private func existingTextContent(at url: URL, relativePath: String) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ""
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard fileSize <= maxFileBytes else {
            throw AgentWorkspaceError.fileTooLarge(path: relativePath, maxBytes: maxFileBytes)
        }

        let data = try Data(contentsOf: url)
        guard !data.contains(0) else {
            throw AgentWorkspaceError.binaryFile(relativePath)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw AgentWorkspaceError.nonUTF8File(relativePath)
        }
        return content
    }

    private func matchingRanges(of oldText: String, in content: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = content.startIndex..<content.endIndex

        while let range = content.range(of: oldText, options: [], range: searchRange) {
            ranges.append(range)
            searchRange = range.upperBound..<content.endIndex
        }

        return ranges
    }

    private func requiredStringArgument(_ name: String, in call: AgentToolCall) throws -> String {
        try stringArgument(name, in: call, allowEmpty: false)
    }

    private func stringArgument(_ name: String, in call: AgentToolCall, allowEmpty: Bool) throws -> String {
        guard let value = call.arguments[name]?.stringValue else {
            throw AgentLocalToolError.missingArgument(name)
        }
        guard allowEmpty || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentLocalToolError.missingArgument(name)
        }
        return value
    }

    private func boundedTimeout(from call: AgentToolCall) -> TimeInterval {
        let rawTimeout = call.arguments["timeoutSeconds"]?.numberValue ?? defaultCommandTimeoutSeconds
        return min(max(rawTimeout, 1), maxCommandTimeoutSeconds)
    }

    private func failure(_ call: AgentToolCall, code: String, message: String) -> AgentToolResult {
        .failure(callID: call.id, toolID: call.toolID, code: code, message: message)
    }
}

private enum AgentLocalToolError: Error, Sendable, Equatable {
    case approvalRequired(toolID: String)
    case missingArgument(String)
    case oldTextNotFound(path: String)
    case ambiguousOldText(path: String)
    case dangerousCommand(String)
    case unsupportedTool(String)
    case userInputRequired(toolID: String)

    var code: String {
        switch self {
        case .approvalRequired:
            return "approval_required"
        case .missingArgument:
            return "missing_argument"
        case .oldTextNotFound:
            return "edit_old_text_not_found"
        case .ambiguousOldText:
            return "edit_ambiguous_old_text"
        case .dangerousCommand:
            return "dangerous_command"
        case .unsupportedTool:
            return "unsupported_tool"
        case .userInputRequired:
            return "user_input_required"
        }
    }

    var message: String {
        switch self {
        case .approvalRequired(let toolID):
            return "Tool requires explicit approval before execution: \(toolID)"
        case .missingArgument(let name):
            return "Missing required argument: \(name)"
        case .oldTextNotFound(let path):
            return "Text to replace was not found in \(path)"
        case .ambiguousOldText(let path):
            return "Text to replace matched more than once in \(path)"
        case .dangerousCommand(let command):
            return "Command is blocked by the Agent safety policy: \(command)"
        case .unsupportedTool(let toolID):
            return "Local preview does not support tool: \(toolID)"
        case .userInputRequired(let toolID):
            return "Tool requires a user response before execution: \(toolID)"
        }
    }
}

private func unifiedDiff(path: String, oldContent: String, newContent: String) -> String {
    var lines = [
        "--- a/\(path)",
        "+++ b/\(path)",
        "@@ -1,\(max(diffLines(oldContent).count, 1)) +1,\(max(diffLines(newContent).count, 1)) @@",
    ]
    lines.append(contentsOf: diffLines(oldContent).map { "-\($0)" })
    lines.append(contentsOf: diffLines(newContent).map { "+\($0)" })
    return lines.joined(separator: "\n") + "\n"
}

private func diffLines(_ content: String) -> [String] {
    var lines = content.components(separatedBy: "\n")
    if content.hasSuffix("\n") {
        lines.removeLast()
    }
    return lines
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
}
