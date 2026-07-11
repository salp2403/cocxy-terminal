// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolPermission.swift - Agent Mode permission decisions.

import CryptoKit
import Foundation

/// A single tool request before execution.
struct AgentToolInvocation: Sendable, Equatable {
    let toolID: String
    let capability: AgentToolCapability
    let command: String?

    init(toolID: String, capability: AgentToolCapability, command: String? = nil) {
        self.toolID = AgentToolDescriptor.normalizedID(toolID)
        self.capability = capability
        self.command = command
    }
}

enum AgentToolPromptReason: Sendable, Equatable {
    case diffPreviewRequired(toolID: String)
    case commandApprovalRequired(command: String)
    case computerUseApprovalRequired(toolID: String)
    case externalToolApprovalRequired(toolID: String)
    case sensitiveDataAccessRequired(toolID: String)
    case userInputRequired(toolID: String)
}

enum AgentToolApprovalPreviewKind: String, Sendable, Equatable {
    case diff
    case command
    case computerUse
    case externalTool
    case sensitiveData
    case userInput
}

struct AgentToolApprovalPreview: Sendable, Equatable {
    let kind: AgentToolApprovalPreviewKind
    let title: String
    let body: String
}

enum AgentToolApprovalTargetKind: String, Sendable, Equatable {
    case writeFile
    case applyDiffFile
    case commandWorkingDirectory
}

enum AgentToolApprovalError: Error, Sendable, Equatable {
    case staleContext
    case identityUnavailable
}

extension AgentToolApprovalError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .staleContext:
            return "This approval is no longer valid because its workspace context changed. Review the tool request again."
        case .identityUnavailable:
            return "The tool approval context could not be verified. Review the tool request again."
        }
    }
}

/// Opaque identity captured with a tool preview and revalidated before execution.
/// Only digests are retained so local paths and file contents cannot leak through logs.
struct AgentToolApprovalBinding: Sendable, Equatable {
    private let targetKind: AgentToolApprovalTargetKind
    private let callDigest: String
    private let previewDigest: String
    private let workspaceDigest: String
    private let targetDigest: String

    init(
        call: AgentToolCall,
        preview: AgentToolApprovalPreview,
        workspace: AgentWorkspace,
        targetURL: URL,
        targetKind: AgentToolApprovalTargetKind,
        observedFileContents: Data? = nil,
        fileManager: FileManager = .default
    ) throws {
        guard Self.targetKind(for: call) == targetKind,
              workspace.contains(targetURL)
        else {
            throw AgentToolApprovalError.identityUnavailable
        }

        self.targetKind = targetKind
        self.callDigest = try Self.callDigest(for: call)
        self.previewDigest = Self.previewDigest(for: preview)
        self.workspaceDigest = try Self.workspaceDigest(for: workspace, fileManager: fileManager)
        self.targetDigest = try Self.targetDigest(
            for: targetURL,
            kind: targetKind,
            observedFileContents: observedFileContents,
            fileManager: fileManager
        )
    }

    static func targetKind(for call: AgentToolCall) -> AgentToolApprovalTargetKind? {
        switch call.toolID {
        case "write_file":
            return .writeFile
        case "apply_diff":
            return .applyDiffFile
        case "run_command":
            return .commandWorkingDirectory
        default:
            return nil
        }
    }

    func validatesRequest(call: AgentToolCall, preview: AgentToolApprovalPreview) -> Bool {
        guard Self.targetKind(for: call) == targetKind,
              let currentCallDigest = try? Self.callDigest(for: call)
        else {
            return false
        }

        return currentCallDigest == callDigest
            && Self.previewDigest(for: preview) == previewDigest
    }

    func validatesWorkspace(_ workspace: AgentWorkspace, fileManager: FileManager = .default) -> Bool {
        guard let currentDigest = try? Self.workspaceDigest(for: workspace, fileManager: fileManager) else {
            return false
        }
        return currentDigest == workspaceDigest
    }

    func validatesExecution(
        call: AgentToolCall,
        workspace: AgentWorkspace,
        targetURL: URL,
        targetKind: AgentToolApprovalTargetKind,
        observedFileContents: Data? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        guard self.targetKind == targetKind,
              Self.targetKind(for: call) == targetKind,
              workspace.contains(targetURL),
              let currentCallDigest = try? Self.callDigest(for: call),
              let currentWorkspaceDigest = try? Self.workspaceDigest(for: workspace, fileManager: fileManager),
              let currentTargetDigest = try? Self.targetDigest(
                  for: targetURL,
                  kind: targetKind,
                  observedFileContents: observedFileContents,
                  fileManager: fileManager
              )
        else {
            return false
        }

        return currentCallDigest == callDigest
            && currentWorkspaceDigest == workspaceDigest
            && currentTargetDigest == targetDigest
    }

    private static func callDigest(for call: AgentToolCall) throws -> String {
        digest([try AgentToolProtocolCodec.encode(call)])
    }

    private static func previewDigest(for preview: AgentToolApprovalPreview) -> String {
        digest([
            Data(preview.kind.rawValue.utf8),
            Data(preview.title.utf8),
            Data(preview.body.utf8),
        ])
    }

    private static func workspaceDigest(
        for workspace: AgentWorkspace,
        fileManager: FileManager
    ) throws -> String {
        try fileSystemIdentityDigest(
            for: workspace.rootURL,
            namespace: "workspace",
            fileManager: fileManager
        )
    }

    private static func targetDigest(
        for targetURL: URL,
        kind: AgentToolApprovalTargetKind,
        observedFileContents: Data?,
        fileManager: FileManager
    ) throws -> String {
        var parts = [
            Data(kind.rawValue.utf8),
            Data(try fileSystemIdentityDigest(
                for: targetURL,
                namespace: "target",
                fileManager: fileManager
            ).utf8),
        ]
        if let observedFileContents {
            parts.append(Data("file-contents".utf8))
            parts.append(observedFileContents)
        } else {
            parts.append(Data("metadata-only".utf8))
        }
        return digest(parts)
    }

    private static func fileSystemIdentityDigest(
        for url: URL,
        namespace: String,
        fileManager: FileManager
    ) throws -> String {
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) {
            let resolved = standardized.resolvingSymlinksInPath()
            let attributes = try fileManager.attributesOfItem(atPath: resolved.path)
            let objectIdentity = try fileSystemObjectIdentity(from: attributes)
            return digest([
                Data(namespace.utf8),
                Data("present".utf8),
                Data(resolved.path.utf8),
                Data(isDirectory.boolValue ? "directory".utf8 : "file".utf8),
                Data(objectIdentity.utf8),
            ])
        }

        let resolvedParent = standardized
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var parentIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedParent.path, isDirectory: &parentIsDirectory),
              parentIsDirectory.boolValue
        else {
            throw AgentToolApprovalError.identityUnavailable
        }
        let parentAttributes = try fileManager.attributesOfItem(atPath: resolvedParent.path)
        let parentIdentity = try fileSystemObjectIdentity(from: parentAttributes)
        let resolvedTarget = resolvedParent.appendingPathComponent(standardized.lastPathComponent).standardizedFileURL
        return digest([
            Data(namespace.utf8),
            Data("absent".utf8),
            Data(resolvedTarget.path.utf8),
            Data(resolvedParent.path.utf8),
            Data(parentIdentity.utf8),
        ])
    }

    private static func fileSystemObjectIdentity(
        from attributes: [FileAttributeKey: Any]
    ) throws -> String {
        guard let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else {
            throw AgentToolApprovalError.identityUnavailable
        }
        return "\(device):\(inode)"
    }

    private static func digest(_ parts: [Data]) -> String {
        var payload = Data()
        for part in parts {
            payload.append(contentsOf: String(part.count).utf8)
            payload.append(0x3A)
            payload.append(part)
            payload.append(0)
        }
        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct AgentApprovedSensitiveRead: Sendable, Equatable {
    let callID: String
    let provider: AgentProviderKind
    let selection: AgentTerminalOutputSelection
    let contextDigest: String
}

private final class AgentSensitiveReadApprovalState: @unchecked Sendable {
    private enum Phase {
        case pending
        case approved
        case disclosed
    }

    private let lock = NSLock()
    private var phase: Phase = .pending

    func approve() -> Bool {
        lock.withLock {
            guard phase == .pending else { return false }
            phase = .approved
            return true
        }
    }

    func issueDisclosure() -> Bool {
        lock.withLock {
            guard phase == .approved else { return false }
            phase = .disclosed
            return true
        }
    }
}

struct AgentSensitiveReadApprovalBinding: Sendable, Equatable {
    private let bindingID: UUID
    private let callID: String
    private let callDigest: String
    private let previewDigest: String
    private let scopeDigest: String
    private let provider: AgentProviderKind
    private let selection: AgentTerminalOutputSelection
    private let contextDigest: String
    private let state: AgentSensitiveReadApprovalState

    init(
        call: AgentToolCall,
        preview: AgentToolApprovalPreview,
        provider: AgentProviderKind,
        approvalScopeID: String,
        selection: AgentTerminalOutputSelection
    ) throws {
        let normalizedScope = approvalScopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard call.toolID == "read_terminal_output",
              preview.kind == .sensitiveData,
              !normalizedScope.isEmpty,
              selection.source != .unavailable,
              selection.surfaceID != nil,
              !selection.blockReferences.isEmpty,
              selection.blockLimit > 0
        else {
            throw AgentToolApprovalError.identityUnavailable
        }

        let bindingID = UUID()
        let callDigest = try Self.callDigest(for: call)
        let previewDigest = Self.previewDigest(for: preview)
        let scopeDigest = Self.digest([Data(normalizedScope.utf8)])
        self.bindingID = bindingID
        self.callID = call.id
        self.callDigest = callDigest
        self.previewDigest = previewDigest
        self.scopeDigest = scopeDigest
        self.provider = provider
        self.selection = selection
        self.state = AgentSensitiveReadApprovalState()
        self.contextDigest = Self.digest([
            Data(bindingID.uuidString.utf8),
            Data(callDigest.utf8),
            Data(previewDigest.utf8),
            Data(scopeDigest.utf8),
            Data(provider.rawValue.utf8),
            Data(selection.source.rawValue.utf8),
            Data((selection.surfaceID ?? "unavailable").utf8),
            Data(String(selection.blockLimit).utf8),
            Data(selection.blockReferences.map {
                "\($0.id):\($0.endTimeNs)"
            }.joined(separator: ",").utf8),
        ])
    }

    func validatesRequest(
        call: AgentToolCall,
        preview: AgentToolApprovalPreview,
        provider: AgentProviderKind,
        approvalScopeID: String
    ) -> Bool {
        let normalizedScope = approvalScopeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard call.toolID == "read_terminal_output",
              call.id == callID,
              preview.kind == .sensitiveData,
              provider == self.provider,
              !normalizedScope.isEmpty,
              let currentCallDigest = try? Self.callDigest(for: call)
        else {
            return false
        }

        return currentCallDigest == callDigest
            && Self.previewDigest(for: preview) == previewDigest
            && Self.digest([Data(normalizedScope.utf8)]) == scopeDigest
    }

    func approvedRead(
        call: AgentToolCall,
        preview: AgentToolApprovalPreview,
        provider: AgentProviderKind,
        approvalScopeID: String
    ) -> AgentApprovedSensitiveRead? {
        guard validatesRequest(
            call: call,
            preview: preview,
            provider: provider,
            approvalScopeID: approvalScopeID
        ), state.approve() else {
            return nil
        }
        return AgentApprovedSensitiveRead(
            callID: call.id,
            provider: provider,
            selection: selection,
            contextDigest: contextDigest
        )
    }

    func consent(for toolResult: AgentToolResult, encodedToolResult: String) -> AgentSensitiveDataConsent? {
        guard toolResult.callID == callID,
              toolResult.toolID == AgentSensitiveDataPolicy.terminalOutputToolID,
              state.issueDisclosure() else {
            return nil
        }
        return AgentSensitiveDataPolicy.consent(
            toolCallID: callID,
            provider: provider,
            contextDigest: contextDigest,
            encodedToolResult: encodedToolResult
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bindingID == rhs.bindingID
            && lhs.callID == rhs.callID
            && lhs.callDigest == rhs.callDigest
            && lhs.previewDigest == rhs.previewDigest
            && lhs.scopeDigest == rhs.scopeDigest
            && lhs.provider == rhs.provider
            && lhs.selection == rhs.selection
            && lhs.contextDigest == rhs.contextDigest
    }

    private static func callDigest(for call: AgentToolCall) throws -> String {
        digest([try AgentToolProtocolCodec.encode(call)])
    }

    private static func previewDigest(for preview: AgentToolApprovalPreview) -> String {
        digest([
            Data(preview.kind.rawValue.utf8),
            Data(preview.title.utf8),
            Data(preview.body.utf8),
        ])
    }

    private static func digest(_ parts: [Data]) -> String {
        var payload = Data()
        for part in parts {
            payload.append(contentsOf: String(part.count).utf8)
            payload.append(0x3A)
            payload.append(part)
            payload.append(0)
        }
        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct AgentToolApprovalPreviewContext: Sendable, Equatable {
    let preview: AgentToolApprovalPreview
    let binding: AgentToolApprovalBinding?
    let sensitiveReadBinding: AgentSensitiveReadApprovalBinding?

    init(
        preview: AgentToolApprovalPreview,
        binding: AgentToolApprovalBinding? = nil,
        sensitiveReadBinding: AgentSensitiveReadApprovalBinding? = nil
    ) {
        self.preview = preview
        self.binding = binding
        self.sensitiveReadBinding = sensitiveReadBinding
    }
}

struct AgentToolApprovalRequest: Identifiable, Sendable, Equatable {
    let id: String
    let call: AgentToolCall
    let reason: AgentToolPromptReason
    let preview: AgentToolApprovalPreview
    let binding: AgentToolApprovalBinding?
    let sensitiveReadBinding: AgentSensitiveReadApprovalBinding?

    init(
        call: AgentToolCall,
        reason: AgentToolPromptReason,
        preview: AgentToolApprovalPreview,
        binding: AgentToolApprovalBinding? = nil,
        sensitiveReadBinding: AgentSensitiveReadApprovalBinding? = nil
    ) {
        self.id = call.id
        self.call = call
        self.reason = reason
        self.preview = preview
        self.binding = binding
        self.sensitiveReadBinding = sensitiveReadBinding
    }
}

protocol AgentToolPreviewing {
    func preview(for call: AgentToolCall) async throws -> AgentToolApprovalPreview
    func approvalPreview(for call: AgentToolCall) async throws -> AgentToolApprovalPreviewContext
}

extension AgentToolPreviewing {
    func approvalPreview(for call: AgentToolCall) async throws -> AgentToolApprovalPreviewContext {
        AgentToolApprovalPreviewContext(preview: try await preview(for: call))
    }
}

enum AgentToolDenyReason: Sendable, Equatable {
    case missingCommand(toolID: String)
    case dangerousCommand(command: String)
    case previewUnavailable(toolID: String)
}

enum AgentToolPermissionDecision: Sendable, Equatable {
    case allow
    case prompt(AgentToolPromptReason)
    case deny(AgentToolDenyReason)
}

enum AgentCommandAllowRule: Sendable, Equatable {
    case exact(String)
    case prefix(String)

    /// Returns whether this rule may bypass the per-call command approval.
    /// Prefix entries remain parseable for compatibility, but always prompt.
    func allowsAutomaticApproval(for command: String) -> Bool {
        switch self {
        case .exact(let allowed):
            return command.utf8.elementsEqual(allowed.utf8)
        case .prefix:
            return false
        }
    }
}

/// Pure decision engine for Agent tool permissions.
///
/// This type does not execute tools and does not show UI. It only encodes the
/// default Phase F safety contract so UI and CLI callers can present the right
/// approval flow later.
struct AgentToolPermissionPolicy: Sendable, Equatable {
    let autoModeEnabled: Bool
    let computerUseConfirm: Bool
    let commandAllowRules: [AgentCommandAllowRule]

    init(
        autoModeEnabled: Bool = false,
        computerUseConfirm: Bool = true,
        commandAllowRules: [AgentCommandAllowRule] = []
    ) {
        self.autoModeEnabled = autoModeEnabled
        self.computerUseConfirm = computerUseConfirm
        self.commandAllowRules = commandAllowRules
    }

    func decision(for invocation: AgentToolInvocation) -> AgentToolPermissionDecision {
        switch invocation.capability {
        case .read:
            if invocation.toolID == "read_terminal_output" {
                return .prompt(.sensitiveDataAccessRequired(toolID: invocation.toolID))
            }
            return .allow
        case .write:
            return .prompt(.diffPreviewRequired(toolID: invocation.toolID))
        case .command:
            return commandDecision(for: invocation)
        case .computerUse:
            return computerUseConfirm
                ? .prompt(.computerUseApprovalRequired(toolID: invocation.toolID))
                : .allow
        case .external:
            return .prompt(.externalToolApprovalRequired(toolID: invocation.toolID))
        case .userInteraction:
            return .prompt(.userInputRequired(toolID: invocation.toolID))
        }
    }

    private func commandDecision(for invocation: AgentToolInvocation) -> AgentToolPermissionDecision {
        guard let command = invocation.command,
              !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .deny(.missingCommand(toolID: invocation.toolID))
        }

        guard !AgentShellCommandSafety.isDangerous(command) else {
            return .deny(.dangerousCommand(command: command))
        }

        if commandAllowRules.contains(where: { $0.allowsAutomaticApproval(for: command) }) {
            return .allow
        }

        return .prompt(.commandApprovalRequired(command: command))
    }
}

enum AgentShellCommandSafety {
    static func normalized(_ command: String) -> String {
        command
            .lowercased()
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isDangerous(_ command: String) -> Bool {
        let normalized = normalized(command)
        let compact = normalized.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )

        if compact.contains(":(){:|:&};:") {
            return true
        }

        if containsRecursiveForceRootRemove(normalized) {
            return true
        }

        return dangerousPatterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func containsRecursiveForceRootRemove(_ command: String, depth: Int = 0) -> Bool {
        guard depth < 4 else { return false }
        return shellCommandSegments(command).contains { segmentDeletesRootWithRM($0, depth: depth) }
    }

    private static func segmentDeletesRootWithRM(_ tokens: [String], depth: Int) -> Bool {
        guard var index = executableIndex(in: tokens),
              let executable = tokens[safe: index]
        else { return false }

        if executable.contains(where: \.isWhitespace) {
            return containsRecursiveForceRootRemove(executable, depth: depth + 1)
        }

        if !isRMExecutable(executable) {
            return shellInvocationDeletesRootWithRM(tokens, executableAt: index, depth: depth)
        }

        index += 1
        var recursive = false
        var force = false
        var endOfOptions = false
        var targets: [String] = []

        while index < tokens.count {
            let token = tokens[index]
            index += 1

            if !endOfOptions, token == "--" {
                endOfOptions = true
                continue
            }

            if !endOfOptions, token.hasPrefix("--") {
                switch token {
                case "--recursive", "--force":
                    if token == "--recursive" { recursive = true }
                    if token == "--force" { force = true }
                default:
                    continue
                }
                continue
            }

            if !endOfOptions, token.hasPrefix("-"), token.count > 1 {
                if token.contains("r") { recursive = true }
                if token.contains("f") { force = true }
                continue
            }

            targets.append(token)
        }

        return recursive && force && targets.contains(where: isRootDeleteTarget)
    }

    private static func shellInvocationDeletesRootWithRM(
        _ tokens: [String],
        executableAt index: Int,
        depth: Int
    ) -> Bool {
        guard isShellExecutable(tokens[index]) else { return false }
        var optionIndex = index + 1

        while let token = tokens[safe: optionIndex], token.hasPrefix("-") {
            optionIndex += 1
            let options = token.dropFirst()
            guard options.contains("c") else { continue }
            guard let nestedCommand = tokens[safe: optionIndex] else { return false }
            return containsRecursiveForceRootRemove(nestedCommand, depth: depth + 1)
        }

        return false
    }

    private static func isRMExecutable(_ executable: String) -> Bool {
        executableBasename(executable) == "rm"
    }

    private static func isShellExecutable(_ executable: String) -> Bool {
        ["sh", "bash", "zsh", "dash"].contains(executableBasename(executable))
    }

    private static func executableBasename(_ executable: String) -> String {
        executable.split(separator: "/").last.map(String.init) ?? executable
    }

    private static func executableIndex(in tokens: [String]) -> Int? {
        var index = 0
        var consumedWrapper = true

        while consumedWrapper, let token = tokens[safe: index] {
            consumedWrapper = false
            switch token {
            case "sudo":
                index = sudoCommandIndex(in: tokens, after: index)
                consumedWrapper = true
            case "env":
                index = envCommandIndex(in: tokens, after: index)
                consumedWrapper = true
            case "command":
                index += 1
                consumedWrapper = true
            default:
                break
            }
        }

        return tokens.indices.contains(index) ? index : nil
    }

    private static func sudoCommandIndex(in tokens: [String], after sudoIndex: Int) -> Int {
        var index = sudoIndex + 1

        while let token = tokens[safe: index], token.hasPrefix("-") {
            index += 1
            guard token != "--" else { break }
            if sudoOptionRequiresValue(token), tokens.indices.contains(index) {
                index += 1
            }
        }

        return index
    }

    private static func envCommandIndex(in tokens: [String], after envIndex: Int) -> Int {
        var index = envIndex + 1

        while let token = tokens[safe: index],
              token.contains("=") || token.hasPrefix("-") {
            index += 1
        }

        return index
    }

    private static func sudoOptionRequiresValue(_ option: String) -> Bool {
        if option.hasPrefix("--") {
            guard !option.contains("=") else { return false }
            return sudoLongOptionsWithValues.contains(option)
        }

        let optionCharacters = Array(option.dropFirst())
        guard let valueOptionIndex = optionCharacters.firstIndex(where: sudoShortOptionsWithValues.contains) else {
            return false
        }
        guard let lastIndex = optionCharacters.indices.last else { return false }

        return valueOptionIndex == lastIndex
    }

    private static func isRootDeleteTarget(_ target: String) -> Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        return trimmed.dropFirst().allSatisfy { character in
            character == "/" || character == "." || character == "*"
        }
    }

    private static func shellCommandSegments(_ command: String) -> [[String]] {
        var segments: [[String]] = [[]]
        var token = ""
        var quote: Character?
        var escaped = false

        func flushToken() {
            guard !token.isEmpty else { return }
            segments[segments.count - 1].append(token)
            token = ""
        }

        func flushSegment() {
            flushToken()
            if segments.last?.isEmpty == false {
                segments.append([])
            }
        }

        for character in command {
            if escaped {
                token.append(character)
                escaped = false
                continue
            }

            if character == "\\" {
                escaped = true
                continue
            }

            if let currentQuote = quote {
                if character == currentQuote {
                    quote = nil
                } else {
                    token.append(character)
                }
                continue
            }

            if character == "'" || character == "\"" {
                quote = character
            } else if character == ";" || character == "&" || character == "|" {
                flushSegment()
            } else if character.isWhitespace {
                flushToken()
            } else {
                token.append(character)
            }
        }

        flushSegment()
        return segments.filter { !$0.isEmpty }
    }

    private static let dangerousPatterns: [String] = [
        #"(?:^|[;&|]\s*)(?:sudo\s+)?diskutil\s+erasedisk(?:\s|$)"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?mkfs(?:\.[a-z0-9]+)?\s+/dev/"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?dd\s+.*\bof=/dev/(?:disk|rdisk)"#,
        #"(?:^|[;&|]\s*)(?:sudo\s+)?chmod\s+-r\s+777\s+/(?:\s|$)"#,
    ]

    private static let sudoShortOptionsWithValues: Set<Character> = [
        "b", "C", "c", "D", "g", "h", "p", "R", "r", "T", "t", "U", "u"
    ]

    private static let sudoLongOptionsWithValues: Set<String> = [
        "--background",
        "--chdir",
        "--chroot",
        "--close-from",
        "--command-timeout",
        "--group",
        "--host",
        "--login-class",
        "--other-user",
        "--prompt",
        "--role",
        "--type",
        "--user",
    ]
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
