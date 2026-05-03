// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProviderClient.swift - User-keyed Agent LLM provider clients.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct AgentHTTPRequest: Sendable, Equatable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data

    init(
        url: URL,
        method: String = "POST",
        headers: [String: String],
        body: Data
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

struct AgentHTTPResponse: Sendable, Equatable {
    let statusCode: Int
    let data: Data
}

protocol AgentHTTPTransport: Sendable {
    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse
}

struct URLSessionAgentHTTPTransport: AgentHTTPTransport {
    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return AgentHTTPResponse(statusCode: statusCode, data: data)
    }
}

enum AgentProviderClientError: Error, Sendable, Equatable {
    case invalidRequestBody
    case invalidResponseBody
    case httpStatus(Int, String)
    case attachmentUnavailable(String)
    case missingResponseChoice
}

extension AgentProviderClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidRequestBody:
            return "Agent provider request could not be encoded."
        case .invalidResponseBody:
            return "Agent provider response could not be decoded."
        case .httpStatus(let statusCode, let message):
            return "Agent provider request failed with HTTP \(statusCode): \(message)"
        case .attachmentUnavailable(let displayName):
            return "Image attachment is unavailable: \(displayName)."
        case .missingResponseChoice:
            return "Agent provider response did not include a usable message."
        }
    }
}

struct AgentProviderModelCatalog: Sendable, Equatable {
    let openAI: String
    let anthropic: String
    let google: String

    static let defaults = AgentProviderModelCatalog(
        openAI: "gpt-5.1",
        anthropic: "claude-sonnet-4-20250514",
        google: "gemini-2.5-flash"
    )
}

enum AgentProviderClientFactoryError: Error, Sendable, Equatable {
    case agentModeDisabled
    case explicitProviderChoiceRequired
    case missingAPIKey(AgentProviderKind)
    case foundationModelsClientUnavailable
}

extension AgentProviderClientFactoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .agentModeDisabled:
            return "Agent Mode is disabled."
        case .explicitProviderChoiceRequired:
            return "Choose an Agent Mode provider in Settings."
        case .missingAPIKey(let provider):
            return "Add an API key for \(provider.displayName) in Settings."
        case .foundationModelsClientUnavailable:
            return "On-device Foundation Models are unavailable in this build."
        }
    }
}

struct AgentProviderClientFactory: Sendable {
    let secrets: AgentSecrets
    let foundationModelsAvailable: Bool
    let transport: any AgentHTTPTransport
    let modelCatalog: AgentProviderModelCatalog

    init(
        secrets: AgentSecrets = AgentSecrets(),
        foundationModelsAvailable: Bool = FoundationModelsAgentLLMClient.isAvailable,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        modelCatalog: AgentProviderModelCatalog = .defaults
    ) {
        self.secrets = secrets
        self.foundationModelsAvailable = foundationModelsAvailable
        self.transport = transport
        self.modelCatalog = modelCatalog
    }

    func makeClient(configuration: AgentModeConfig) throws -> any AgentLLMClient {
        try makeClient(configuration: configuration, toolRegistry: .minimumBuiltIns())
    }

    func makeClient(
        configuration: AgentModeConfig,
        toolRegistry: AgentToolRegistry
    ) throws -> any AgentLLMClient {
        guard configuration.enabled else {
            throw AgentProviderClientFactoryError.agentModeDisabled
        }

        switch configuration.effectiveProvider(foundationModelsAvailable: foundationModelsAvailable) {
        case .explicitChoiceRequired:
            throw AgentProviderClientFactoryError.explicitProviderChoiceRequired
        case .provider(let provider):
            return try makeClient(provider: provider, toolRegistry: toolRegistry)
        }
    }

    private func makeClient(
        provider: AgentProviderKind,
        toolRegistry: AgentToolRegistry
    ) throws -> any AgentLLMClient {
        switch provider {
        case .foundationModelsOnDevice:
            return FoundationModelsAgentLLMClient(toolRegistry: toolRegistry)
        case .openai:
            return OpenAIAgentLLMClient(
                apiKey: try requiredAPIKey(for: provider),
                model: modelCatalog.openAI,
                transport: transport,
                toolRegistry: toolRegistry
            )
        case .anthropic:
            return AnthropicAgentLLMClient(
                apiKey: try requiredAPIKey(for: provider),
                model: modelCatalog.anthropic,
                transport: transport,
                toolRegistry: toolRegistry
            )
        case .google:
            return GoogleAgentLLMClient(
                apiKey: try requiredAPIKey(for: provider),
                model: modelCatalog.google,
                transport: transport,
                toolRegistry: toolRegistry
            )
        }
    }

    private func requiredAPIKey(for provider: AgentProviderKind) throws -> String {
        guard let apiKey = try secrets.apiKey(for: provider) else {
            throw AgentProviderClientFactoryError.missingAPIKey(provider)
        }
        return apiKey
    }
}

struct FoundationModelsAgentLLMClient: AgentLLMClient {
    let toolRegistry: AgentToolRegistry

    init(toolRegistry: AgentToolRegistry = .minimumBuiltIns()) {
        self.toolRegistry = toolRegistry
    }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelsAgentRuntime.isAvailable
        }
        #endif
        return false
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await FoundationModelsAgentRuntime.nextResponse(
                for: messages,
                toolRegistry: toolRegistry
            )
        }
        #endif
        throw AgentProviderClientFactoryError.foundationModelsClientUnavailable
    }
}

#if canImport(FoundationModels)
enum FoundationModelsAgentPromptBuilder {
    static let maxInstructionsCharacters = 3_000
    static let maxPromptCharacters = 5_000
    static let maxMessageCharacters = 2_000

    private static let omittedTranscriptMarker = "[Earlier transcript omitted to fit the on-device context window.]"
    private static let omittedContentMarker = "[Earlier content omitted to fit the on-device context window.]"

    static func instructions(from messages: [AgentMessage]) -> String {
        let systemMessages = messages
            .filter { $0.role == .system }
            .map(\.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let baseInstructions = [
            "You are Cocxy Agent Mode running fully on this Mac.",
            "You are using the on-device Foundation Models provider. Request local tools when repository, terminal, app, or file state is needed.",
            "Cocxy captures tool requests and runs them only through local permission rules before any action happens.",
            "Never claim you read files, ran commands, changed repositories, opened apps, checked logs, installed software, monitored system performance, or verified local state unless a message labeled \"Local tool result\" explicitly contains that result.",
            "If a local action is needed, request the relevant tool or explain the needed action clearly instead of saying it already happened.",
            "Follow direct user formatting instructions exactly when they do not conflict with safety.",
        ]

        let systemContext = boundedJoined(
            systemMessages.map {
                boundedKeepingEnd(
                    $0,
                    maxCharacters: maxMessageCharacters,
                    marker: omittedContentMarker
                )
            },
            maxCharacters: maxInstructionsCharacters / 2,
            marker: "[Earlier system instructions omitted to fit the on-device context window.]"
        )

        let parts = systemContext.isEmpty
            ? baseInstructions
            : systemMessagesHeader(systemContext) + baseInstructions
        return boundedJoined(
            parts,
            maxCharacters: maxInstructionsCharacters,
            marker: "[Earlier instructions omitted to fit the on-device context window.]"
        )
    }

    static func prompt(from messages: [AgentMessage]) -> String {
        let blocks = messages
            .filter { $0.role != .system }
            .map(block)
            .filter { !$0.isEmpty }

        guard !blocks.isEmpty else {
            return "User:\nHello"
        }

        let transcript = blocks.joined(separator: "\n\n")
        guard transcript.count > maxPromptCharacters else {
            return transcript
        }

        return boundedJoinedKeepingEnd(
            blocks,
            maxCharacters: maxPromptCharacters,
            marker: omittedTranscriptMarker
        )
    }

    private static func systemMessagesHeader(_ context: String) -> [String] {
        [
            """
            Additional local system context:
            \(context)
            """,
        ]
    }

    private static func block(for message: AgentMessage) -> String {
        let content = boundedKeepingEnd(
            message.content.trimmingCharacters(in: .whitespacesAndNewlines),
            maxCharacters: maxMessageCharacters,
            marker: omittedContentMarker
        )
        guard !content.isEmpty else { return "" }

        switch message.role {
        case .user:
            return "User:\n\(content)"
        case .assistant:
            return "Assistant:\n\(content)"
        case .tool:
            let name = message.toolName ?? "tool"
            return "Local tool result (\(name)):\n\(content)"
        case .system:
            return ""
        }
    }

    private static func boundedJoined(
        _ parts: [String],
        maxCharacters: Int,
        marker: String
    ) -> String {
        let joined = parts
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        guard joined.count > maxCharacters else { return joined }
        return boundedKeepingEnd(joined, maxCharacters: maxCharacters, marker: marker)
    }

    private static func boundedJoinedKeepingEnd(
        _ parts: [String],
        maxCharacters: Int,
        marker: String
    ) -> String {
        let separator = "\n\n"
        let prefix = marker + separator
        let budget = max(0, maxCharacters - prefix.count)
        var kept: [String] = []
        var used = 0

        for part in parts.reversed() {
            let separatorCost = kept.isEmpty ? 0 : separator.count
            let remaining = budget - used - separatorCost
            guard remaining > 0 else { break }

            if part.count <= remaining {
                kept.insert(part, at: 0)
                used += separatorCost + part.count
            } else if kept.isEmpty {
                kept.insert(
                    boundedKeepingEnd(part, maxCharacters: remaining, marker: omittedContentMarker),
                    at: 0
                )
                break
            } else {
                break
            }
        }

        return prefix + kept.joined(separator: separator)
    }

    private static func boundedKeepingEnd(
        _ text: String,
        maxCharacters: Int,
        marker: String
    ) -> String {
        guard text.count > maxCharacters else { return text }
        guard maxCharacters > marker.count + 1 else {
            return String(text.suffix(max(0, maxCharacters)))
        }

        let suffixCount = maxCharacters - marker.count - 1
        return marker + "\n" + String(text.suffix(suffixCount))
    }
}

@available(macOS 26.0, *)
enum FoundationModelsAgentToolBridge {
    static let maxRuntimeTools = 6

    static func tools(from registry: AgentToolRegistry) throws -> [any Tool] {
        try registry.descriptors.map(FoundationModelsAgentTool.init(descriptor:))
    }

    static func tools(
        from registry: AgentToolRegistry,
        matching prompt: String
    ) throws -> [any Tool] {
        try selectedDescriptors(from: registry, matching: prompt)
            .map(FoundationModelsAgentTool.init(descriptor:))
    }

    static func selectedDescriptors(
        from registry: AgentToolRegistry,
        matching prompt: String,
        maxTools: Int = maxRuntimeTools
    ) -> [AgentToolDescriptor] {
        let promptIndex = PromptIndex(prompt)
        let exactMatches = registry.descriptors
            .filter { promptIndex.referencesTool($0) }
            .sorted {
                if priority(for: $0.id) != priority(for: $1.id) {
                    return priority(for: $0.id) > priority(for: $1.id)
                }
                return $0.id < $1.id
            }
        if !exactMatches.isEmpty {
            return Array(exactMatches.prefix(max(0, maxTools)))
        }

        let scoredDescriptors = registry.descriptors
            .compactMap { descriptor -> (score: Int, priority: Int, descriptor: AgentToolDescriptor)? in
                let score = score(descriptor, promptIndex: promptIndex)
                guard score > 0 else { return nil }
                return (score, priority(for: descriptor.id), descriptor)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.descriptor.id < $1.descriptor.id
            }

        return Array(scoredDescriptors.prefix(max(0, maxTools)).map(\.descriptor))
    }

    static func response(
        from content: String,
        transcriptEntries: ArraySlice<Transcript.Entry>
    ) -> AgentLLMResponse {
        let toolCalls = toolCalls(from: transcriptEntries)
        return AgentLLMResponse(
            content: toolCalls.isEmpty ? content : "",
            toolCalls: toolCalls
        )
    }

    private static func toolCalls(from transcriptEntries: ArraySlice<Transcript.Entry>) -> [AgentToolCall] {
        let calls = transcriptEntries.flatMap { entry -> [AgentToolCall] in
            guard case .toolCalls(let calls) = entry else { return [] }
            return calls.map { call in
                AgentToolCall(
                    id: call.id,
                    toolID: call.toolName,
                    arguments: agentObject(from: call.arguments)
                )
            }
        }
        return deduplicatedToolCalls(calls)
    }

    private static func deduplicatedToolCalls(_ calls: [AgentToolCall]) -> [AgentToolCall] {
        var seenKeys: Set<String> = []
        var result: [AgentToolCall] = []

        for call in calls {
            let key = "\(call.toolID)|\(canonicalValue(.object(call.arguments)))"
            guard seenKeys.insert(key).inserted else { continue }
            result.append(call)
        }

        return result
    }

    private static func agentObject(from content: GeneratedContent) -> [String: AgentJSONValue] {
        guard case .structure(let properties, _) = content.kind else {
            return [:]
        }
        return properties.mapValues(agentJSONValue)
    }

    private static func agentJSONValue(from content: GeneratedContent) -> AgentJSONValue {
        switch content.kind {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .number(let value):
            return .number(value)
        case .string(let value):
            return .string(value)
        case .array(let values):
            return .array(values.map(agentJSONValue))
        case .structure(let properties, _):
            return .object(properties.mapValues(agentJSONValue))
        @unknown default:
            return .null
        }
    }

    private static func canonicalValue(_ value: AgentJSONValue) -> String {
        if let data = try? AgentToolProtocolCodec.encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return String(describing: value)
    }

    private struct PromptIndex {
        let raw: String
        let words: Set<String>
        let phrases: String

        init(_ prompt: String) {
            self.raw = prompt.lowercased()
            let normalized = FoundationModelsAgentToolBridge.normalizedPrompt(prompt)
            self.words = Set(normalized.split(separator: " ").map(String.init))
            self.phrases = " \(normalized) "
        }

        func containsPhrase(_ phrase: String) -> Bool {
            let normalized = FoundationModelsAgentToolBridge.normalizedPrompt(phrase)
            return !normalized.isEmpty && phrases.contains(" \(normalized) ")
        }

        func referencesTool(_ descriptor: AgentToolDescriptor) -> Bool {
            raw.contains(descriptor.id)
                || containsPhrase(descriptor.id.replacingOccurrences(of: "_", with: " "))
                || containsPhrase(descriptor.displayName)
        }
    }

    private static func score(
        _ descriptor: AgentToolDescriptor,
        promptIndex: PromptIndex
    ) -> Int {
        var score = 0
        let id = descriptor.id
        if promptIndex.raw.contains(id) || promptIndex.containsPhrase(id.replacingOccurrences(of: "_", with: " ")) {
            score += 120
        }
        if promptIndex.containsPhrase(descriptor.displayName) {
            score += 80
        }
        for keyword in keywords(for: id) where promptIndex.containsPhrase(keyword) {
            score += 24
        }
        for keyword in capabilityKeywords(for: descriptor.capability) where promptIndex.words.contains(keyword) {
            score += 8
        }
        if score > 0, MCPToolBridge.parseToolID(id) != nil {
            score -= 10
        }
        return max(score, 0)
    }

    private static func normalizedPrompt(_ prompt: String) -> String {
        let scalars = prompt.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars)
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func priority(for toolID: String) -> Int {
        switch toolID {
        case "read_file": return 100
        case "list_directory": return 95
        case "search_codebase": return 90
        case "grep": return 85
        case "search_files": return 80
        case "git_status": return 75
        case "git_diff": return 70
        case "read_terminal_output": return 65
        case "read_lsp_diagnostics": return 60
        case "run_command": return 55
        case "write_file": return 50
        case "apply_diff": return 45
        case "ask_user": return 40
        case "list_skills": return 35
        case "use_skill": return 30
        default: return 10
        }
    }

    private static func keywords(for toolID: String) -> [String] {
        switch toolID {
        case "read_file":
            return ["read", "read file", "file", "source", "package", "contents"]
        case "list_directory":
            return ["list", "directory", "folder", "files", "tree"]
        case "search_files":
            return ["find file", "filename", "glob", "path"]
        case "search_codebase":
            return ["search", "codebase", "symbol", "semantic", "where"]
        case "grep":
            return ["grep", "regex", "pattern", "find text", "search text"]
        case "git_status":
            return ["git status", "status", "branch", "dirty"]
        case "git_diff":
            return ["git diff", "diff", "changes", "patch"]
        case "read_terminal_output":
            return ["terminal output", "scrollback", "screen", "recent output"]
        case "read_lsp_diagnostics":
            return ["diagnostic", "diagnostics", "lsp", "warning", "errors"]
        case "run_command":
            return ["run", "runs", "command", "commands", "test", "tests", "build", "builds", "execute", "shell"]
        case "write_file":
            return ["write", "write file", "create file", "save"]
        case "apply_diff":
            return ["apply diff", "edit", "modify", "change", "fix", "update"]
        case "ask_user":
            return ["ask user", "question", "clarify", "confirm"]
        case "computer_move_mouse":
            return ["move mouse", "mouse move", "cursor", "point"]
        case "computer_click":
            return ["click", "mouse click", "press button"]
        case "computer_screenshot":
            return ["screenshot", "screen capture", "capture screen"]
        case "computer_type_text":
            return ["type text", "keyboard", "input text"]
        case "list_skills":
            return ["available skills", "local skills", "built in skills", "built-in skills", "project skills", "user skills"]
        case "use_skill":
            return ["load skill", "select skill", "apply skill", "skill id"]
        default:
            return []
        }
    }

    private static func capabilityKeywords(for capability: AgentToolCapability) -> Set<String> {
        switch capability {
        case .read:
            return ["read", "inspect", "show", "find", "search", "list", "check"]
        case .write:
            return ["write", "edit", "modify", "change", "fix", "update", "create"]
        case .command:
            return ["run", "runs", "execute", "command", "commands", "test", "tests", "build", "builds"]
        case .computerUse:
            return ["computer", "mouse", "keyboard", "screenshot", "screen", "click", "type"]
        case .external:
            return ["external", "mcp"]
        case .userInteraction:
            return ["ask", "clarify", "confirm"]
        }
    }
}

@available(macOS 26.0, *)
private struct FoundationModelsAgentTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    var includesSchemaInInstructions: Bool { true }

    init(descriptor: AgentToolDescriptor) throws {
        self.name = descriptor.id
        self.description = descriptor.description
        self.parameters = try Self.parameters(from: descriptor)
    }

    func call(arguments: GeneratedContent) async throws -> String {
        _ = arguments
        return "Tool request captured. Cocxy will review permissions before any local action runs."
    }

    private static func parameters(from descriptor: AgentToolDescriptor) throws -> GenerationSchema {
        let schemaName = "\(schemaSafeName(descriptor.id))_arguments"
        let root = DynamicGenerationSchema(
            name: schemaName,
            description: descriptor.description,
            properties: descriptor.inputSchema.properties
                .sorted { $0.key < $1.key }
                .map { name, property in
                    DynamicGenerationSchema.Property(
                        name: name,
                        description: property.description,
                        schema: dynamicSchema(for: property.type),
                        isOptional: !descriptor.inputSchema.required.contains(name)
                    )
                }
        )
        return try GenerationSchema(root: root, dependencies: [])
    }

    private static func dynamicSchema(for type: AgentToolInputProperty.ValueType) -> DynamicGenerationSchema {
        switch type {
        case .boolean:
            return DynamicGenerationSchema(type: Bool.self)
        case .number:
            return DynamicGenerationSchema(type: Double.self)
        case .string:
            return DynamicGenerationSchema(type: String.self)
        }
    }

    private static func schemaSafeName(_ rawName: String) -> String {
        let scalars = rawName.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "_" {
                return Character(scalar)
            }
            return "_"
        }
        let candidate = String(scalars)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let nonEmpty = candidate.isEmpty ? "tool" : candidate
        guard let first = nonEmpty.unicodeScalars.first,
              CharacterSet.letters.contains(first)
        else {
            return "tool_\(nonEmpty)"
        }
        return nonEmpty
    }
}

@available(macOS 26.0, *)
private enum FoundationModelsAgentRuntime {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func nextResponse(
        for messages: [AgentMessage],
        toolRegistry: AgentToolRegistry
    ) async throws -> AgentLLMResponse {
        guard SystemLanguageModel.default.isAvailable else {
            throw AgentProviderClientFactoryError.foundationModelsClientUnavailable
        }

        let prompt = FoundationModelsAgentPromptBuilder.prompt(from: messages)
        let session = LanguageModelSession(
            model: .default,
            tools: try FoundationModelsAgentToolBridge.tools(from: toolRegistry, matching: prompt),
            instructions: FoundationModelsAgentPromptBuilder.instructions(from: messages)
        )
        let response = try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: 512))
        return FoundationModelsAgentToolBridge.response(
            from: response.content,
            transcriptEntries: response.transcriptEntries
        )
    }
}
#endif

struct OpenAIAgentLLMClient: AgentLLMClient {
    let apiKey: String
    let model: String
    let transport: any AgentHTTPTransport
    let toolRegistry: AgentToolRegistry
    let endpointURL: URL

    init(
        apiKey: String,
        model: String,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        toolRegistry: AgentToolRegistry = .minimumBuiltIns(),
        endpointURL: URL = URL(string: "https://api.openai.com/v1/chat/completions")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
        self.toolRegistry = toolRegistry
        self.endpointURL = endpointURL
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        let requestMessages = try openAIMessages(from: messages)
        let request = try AgentHTTPRequest(
            url: endpointURL,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
            ],
            body: jsonData([
                "model": model,
                "messages": requestMessages,
                "tools": openAITools(from: toolRegistry.descriptors),
                "tool_choice": "auto",
            ])
        )
        let response = try await transport.send(request)
        try validate(response)
        return try parseOpenAIResponse(response.data, fallbackModel: model)
    }
}

struct AnthropicAgentLLMClient: AgentLLMClient {
    let apiKey: String
    let model: String
    let transport: any AgentHTTPTransport
    let toolRegistry: AgentToolRegistry
    let endpointURL: URL
    let maxTokens: Int

    init(
        apiKey: String,
        model: String,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        toolRegistry: AgentToolRegistry = .minimumBuiltIns(),
        endpointURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        maxTokens: Int = 4096
    ) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
        self.toolRegistry = toolRegistry
        self.endpointURL = endpointURL
        self.maxTokens = maxTokens
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        let requestMessages = try anthropicMessages(from: messages)
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": requestMessages,
            "tools": anthropicTools(from: toolRegistry.descriptors),
        ]
        let systemPrompt = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }

        let request = try AgentHTTPRequest(
            url: endpointURL,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            ],
            body: jsonData(body)
        )
        let response = try await transport.send(request)
        try validate(response)
        return try parseAnthropicResponse(response.data, fallbackModel: model)
    }
}

struct GoogleAgentLLMClient: AgentLLMClient {
    let apiKey: String
    let model: String
    let transport: any AgentHTTPTransport
    let toolRegistry: AgentToolRegistry
    let baseURL: URL

    init(
        apiKey: String,
        model: String,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        toolRegistry: AgentToolRegistry = .minimumBuiltIns(),
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    ) {
        self.apiKey = apiKey
        self.model = model
        self.transport = transport
        self.toolRegistry = toolRegistry
        self.baseURL = baseURL
    }

    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        let escapedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let requestContents = try googleContents(from: messages)
        let request = try AgentHTTPRequest(
            url: baseURL.appendingPathComponent("\(escapedModel):generateContent"),
            headers: [
                "x-goog-api-key": apiKey,
                "Content-Type": "application/json",
            ],
            body: jsonData([
                "contents": requestContents,
                "tools": googleTools(from: toolRegistry.descriptors),
            ])
        )
        let response = try await transport.send(request)
        try validate(response)
        return try parseGoogleResponse(response.data, fallbackModel: model)
    }
}

private func validate(_ response: AgentHTTPResponse) throws {
    guard (200..<300).contains(response.statusCode) else {
        throw AgentProviderClientError.httpStatus(response.statusCode, providerErrorMessage(from: response.data))
    }
}

private func providerErrorMessage(from data: Data) -> String {
    guard let object = try? jsonDictionary(from: data) else {
        return String(data: data, encoding: .utf8) ?? "HTTP request failed"
    }
    if let error = object["error"] as? [String: Any],
       let message = error["message"] as? String {
        return message
    }
    if let message = object["message"] as? String {
        return message
    }
    return "HTTP request failed"
}

private func openAIMessages(from messages: [AgentMessage]) throws -> [[String: Any]] {
    try messages.map { message in
        var result: [String: Any] = [
            "role": openAIRole(message.role),
        ]
        result["content"] = try openAIContent(from: message)
        if message.role == .assistant, !message.toolCalls.isEmpty {
            result["tool_calls"] = message.toolCalls.map(openAIToolCall)
        }
        if message.role == .tool, let toolCallID = message.toolCallID {
            result["tool_call_id"] = toolCallID
        }
        return result
    }
}

private func openAIContent(from message: AgentMessage) throws -> Any {
    guard message.role == .user, !message.imageAttachments.isEmpty else {
        return message.content
    }

    var content: [[String: Any]] = []
    if !message.content.isEmpty {
        content.append(["type": "text", "text": message.content])
    }
    content.append(contentsOf: try encodedImageAttachments(from: message).map { image in
        [
            "type": "image_url",
            "image_url": [
                "url": "data:\(image.mimeType);base64,\(image.base64Data)",
            ],
        ]
    })
    return content
}

private func openAIToolCall(_ call: AgentToolCall) -> [String: Any] {
    [
        "id": call.id,
        "type": "function",
        "function": [
            "name": call.toolID,
            "arguments": jsonString(from: call.arguments),
        ],
    ]
}

private func openAIRole(_ role: AgentMessageRole) -> String {
    switch role {
    case .system:
        return "system"
    case .user:
        return "user"
    case .assistant:
        return "assistant"
    case .tool:
        return "tool"
    }
}

private func anthropicMessages(from messages: [AgentMessage]) throws -> [[String: Any]] {
    try messages.compactMap { message in
        switch message.role {
        case .system:
            return nil
        case .user:
            return ["role": "user", "content": try anthropicUserContent(from: message)]
        case .assistant:
            guard !message.toolCalls.isEmpty else {
                return ["role": "assistant", "content": message.content]
            }
            var blocks: [[String: Any]] = []
            if !message.content.isEmpty {
                blocks.append(["type": "text", "text": message.content])
            }
            blocks.append(contentsOf: message.toolCalls.map(anthropicToolUseBlock))
            return ["role": "assistant", "content": blocks]
        case .tool:
            return [
                "role": "user",
                "content": [
                    [
                        "type": "tool_result",
                        "tool_use_id": message.toolCallID ?? message.id,
                        "content": message.content,
                    ],
                ],
            ]
        }
    }
}

private func anthropicUserContent(from message: AgentMessage) throws -> Any {
    guard !message.imageAttachments.isEmpty else {
        return message.content
    }

    var blocks: [[String: Any]] = []
    if !message.content.isEmpty {
        blocks.append(["type": "text", "text": message.content])
    }
    blocks.append(contentsOf: try encodedImageAttachments(from: message).map { image in
        [
            "type": "image",
            "source": [
                "type": "base64",
                "media_type": image.mimeType,
                "data": image.base64Data,
            ],
        ]
    })
    return blocks
}

private func anthropicToolUseBlock(_ call: AgentToolCall) -> [String: Any] {
    [
        "type": "tool_use",
        "id": call.id,
        "name": call.toolID,
        "input": agentJSONObject(from: call.arguments),
    ]
}

private func googleContents(from messages: [AgentMessage]) throws -> [[String: Any]] {
    try messages.compactMap { message in
        guard message.role != .system else { return nil }
        switch message.role {
        case .assistant:
            var parts: [[String: Any]] = []
            if !message.content.isEmpty {
                parts.append(["text": message.content])
            }
            parts.append(contentsOf: message.toolCalls.map(googleFunctionCallPart))
            return ["role": "model", "parts": parts]
        case .tool:
            return [
                "role": "user",
                "parts": [
                    [
                        "functionResponse": [
                            "name": message.toolName ?? "unknown",
                            "response": googleFunctionResponse(from: message.content),
                        ],
                    ],
                ],
            ]
        case .user:
            return ["role": "user", "parts": try googleUserParts(from: message)]
        case .system:
            return nil
        }
    }
}

private func googleUserParts(from message: AgentMessage) throws -> [[String: Any]] {
    var parts: [[String: Any]] = []
    if !message.content.isEmpty {
        parts.append(["text": message.content])
    }
    parts.append(contentsOf: try encodedImageAttachments(from: message).map { image in
        [
            "inlineData": [
                "mimeType": image.mimeType,
                "data": image.base64Data,
            ],
        ]
    })
    return parts
}

private struct EncodedAgentImageAttachment {
    let mimeType: String
    let base64Data: String
}

private func encodedImageAttachments(from message: AgentMessage) throws -> [EncodedAgentImageAttachment] {
    try message.imageAttachments.map { attachment in
        let data: Data
        do {
            data = try Data(contentsOf: attachment.fileURL)
        } catch {
            let displayName = attachment.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AgentProviderClientError.attachmentUnavailable(
                displayName.isEmpty ? "image" : displayName
            )
        }
        return EncodedAgentImageAttachment(
            mimeType: attachment.mimeType,
            base64Data: data.base64EncodedString()
        )
    }
}

private func googleFunctionCallPart(_ call: AgentToolCall) -> [String: Any] {
    [
        "functionCall": [
            "name": call.toolID,
            "args": agentJSONObject(from: call.arguments),
        ],
    ]
}

private func googleFunctionResponse(from content: String) -> [String: Any] {
    guard let data = content.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return ["content": content]
    }
    return object
}

private func openAITools(from descriptors: [AgentToolDescriptor]) -> [[String: Any]] {
    descriptors.map { descriptor in
        [
            "type": "function",
            "function": [
                "name": descriptor.id,
                "description": descriptor.description,
                "parameters": jsonSchema(from: descriptor.inputSchema),
            ],
        ]
    }
}

private func anthropicTools(from descriptors: [AgentToolDescriptor]) -> [[String: Any]] {
    descriptors.map { descriptor in
        [
            "name": descriptor.id,
            "description": descriptor.description,
            "input_schema": jsonSchema(from: descriptor.inputSchema),
        ]
    }
}

private func googleTools(from descriptors: [AgentToolDescriptor]) -> [[String: Any]] {
    [
        [
            "functionDeclarations": descriptors.map { descriptor in
                [
                    "name": descriptor.id,
                    "description": descriptor.description,
                    "parameters": googleSchema(from: descriptor.inputSchema),
                ]
            },
        ],
    ]
}

private func jsonSchema(from schema: AgentToolInputSchema) -> [String: Any] {
    var result: [String: Any] = [
        "type": "object",
        "properties": jsonSchemaProperties(from: schema.properties),
        "additionalProperties": schema.additionalProperties,
    ]
    if !schema.required.isEmpty {
        result["required"] = schema.required
    }
    return result
}

private func jsonSchemaProperties(
    from properties: [String: AgentToolInputProperty]
) -> [String: Any] {
    properties.reduce(into: [:]) { result, entry in
        var property: [String: Any] = [
            "type": jsonSchemaType(entry.value.type),
        ]
        if !entry.value.description.isEmpty {
            property["description"] = entry.value.description
        }
        result[entry.key] = property
    }
}

private func jsonSchemaType(_ type: AgentToolInputProperty.ValueType) -> String {
    switch type {
    case .boolean:
        return "boolean"
    case .number:
        return "number"
    case .string:
        return "string"
    }
}

private func googleSchema(from schema: AgentToolInputSchema) -> [String: Any] {
    var result: [String: Any] = [
        "type": "OBJECT",
        "properties": googleSchemaProperties(from: schema.properties),
    ]
    if !schema.required.isEmpty {
        result["required"] = schema.required
    }
    return result
}

private func googleSchemaProperties(
    from properties: [String: AgentToolInputProperty]
) -> [String: Any] {
    properties.reduce(into: [:]) { result, entry in
        var property: [String: Any] = [
            "type": googleSchemaType(entry.value.type),
        ]
        if !entry.value.description.isEmpty {
            property["description"] = entry.value.description
        }
        result[entry.key] = property
    }
}

private func googleSchemaType(_ type: AgentToolInputProperty.ValueType) -> String {
    switch type {
    case .boolean:
        return "BOOLEAN"
    case .number:
        return "NUMBER"
    case .string:
        return "STRING"
    }
}

private func parseOpenAIResponse(_ data: Data, fallbackModel: String) throws -> AgentLLMResponse {
    let object = try jsonDictionary(from: data)
    guard let choices = object["choices"] as? [[String: Any]],
          let first = choices.first,
          let message = first["message"] as? [String: Any]
    else {
        throw AgentProviderClientError.missingResponseChoice
    }

    let content = message["content"] as? String ?? ""
    let toolCalls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap { rawCall -> AgentToolCall? in
        guard let id = rawCall["id"] as? String,
              let function = rawCall["function"] as? [String: Any],
              let name = function["name"] as? String
        else {
            return nil
        }
        let arguments = (function["arguments"] as? String)
            .flatMap { try? agentArguments(fromJSONString: $0) } ?? [:]
        return AgentToolCall(id: id, toolID: name, arguments: arguments)
    }

    return AgentLLMResponse(
        content: content,
        toolCalls: toolCalls,
        usage: parseOpenAIUsage(from: object, fallbackModel: fallbackModel)
    )
}

private func parseAnthropicResponse(_ data: Data, fallbackModel: String) throws -> AgentLLMResponse {
    let object = try jsonDictionary(from: data)
    guard let contentBlocks = object["content"] as? [[String: Any]] else {
        throw AgentProviderClientError.missingResponseChoice
    }

    var textParts: [String] = []
    var toolCalls: [AgentToolCall] = []

    for block in contentBlocks {
        switch block["type"] as? String {
        case "text":
            if let text = block["text"] as? String {
                textParts.append(text)
            }
        case "tool_use":
            guard let id = block["id"] as? String,
                  let name = block["name"] as? String
            else {
                continue
            }
            let input = (block["input"] as? [String: Any]).map(agentArguments(fromJSONObject:)) ?? [:]
            toolCalls.append(AgentToolCall(id: id, toolID: name, arguments: input))
        default:
            continue
        }
    }

    return AgentLLMResponse(
        content: textParts.joined(separator: "\n"),
        toolCalls: toolCalls,
        usage: parseAnthropicUsage(from: object, fallbackModel: fallbackModel)
    )
}

private func parseGoogleResponse(_ data: Data, fallbackModel: String) throws -> AgentLLMResponse {
    let object = try jsonDictionary(from: data)
    guard let candidates = object["candidates"] as? [[String: Any]],
          let content = candidates.first?["content"] as? [String: Any],
          let parts = content["parts"] as? [[String: Any]]
    else {
        throw AgentProviderClientError.missingResponseChoice
    }

    var textParts: [String] = []
    var toolCalls: [AgentToolCall] = []

    for (index, part) in parts.enumerated() {
        if let text = part["text"] as? String {
            textParts.append(text)
        }
        if let functionCall = part["functionCall"] as? [String: Any],
           let name = functionCall["name"] as? String {
            let args = (functionCall["args"] as? [String: Any]).map(agentArguments(fromJSONObject:)) ?? [:]
            toolCalls.append(AgentToolCall(
                id: "google-call-\(index)-\(AgentToolDescriptor.normalizedID(name))",
                toolID: name,
                arguments: args
            ))
        }
    }

    return AgentLLMResponse(
        content: textParts.joined(separator: "\n"),
        toolCalls: toolCalls,
        usage: parseGoogleUsage(from: object, fallbackModel: fallbackModel)
    )
}

private func parseOpenAIUsage(
    from object: [String: Any],
    fallbackModel: String
) -> AgentLLMUsage? {
    guard let usage = object["usage"] as? [String: Any],
          let inputTokens = integerValue(usage["prompt_tokens"]),
          let outputTokens = integerValue(usage["completion_tokens"]) else {
        return nil
    }
    return AgentLLMUsage(
        provider: AgentProviderKind.openai.rawValue,
        model: nonEmptyString(object["model"]) ?? fallbackModel,
        inputTokens: inputTokens,
        outputTokens: outputTokens
    )
}

private func parseAnthropicUsage(
    from object: [String: Any],
    fallbackModel: String
) -> AgentLLMUsage? {
    guard let usage = object["usage"] as? [String: Any],
          let inputTokens = integerValue(usage["input_tokens"]),
          let outputTokens = integerValue(usage["output_tokens"]) else {
        return nil
    }
    return AgentLLMUsage(
        provider: AgentProviderKind.anthropic.rawValue,
        model: nonEmptyString(object["model"]) ?? fallbackModel,
        inputTokens: inputTokens,
        outputTokens: outputTokens
    )
}

private func parseGoogleUsage(
    from object: [String: Any],
    fallbackModel: String
) -> AgentLLMUsage? {
    guard let usage = object["usageMetadata"] as? [String: Any],
          let inputTokens = integerValue(usage["promptTokenCount"]) else {
        return nil
    }
    let outputTokens = integerValue(usage["candidatesTokenCount"])
        ?? integerValue(usage["totalTokenCount"]).map { max(0, $0 - inputTokens) }
    guard let outputTokens else { return nil }
    return AgentLLMUsage(
        provider: AgentProviderKind.google.rawValue,
        model: nonEmptyString(object["modelVersion"]) ?? fallbackModel,
        inputTokens: inputTokens,
        outputTokens: outputTokens
    )
}

private func integerValue(_ value: Any?) -> Int? {
    if let value = value as? Int {
        return value
    }
    if let value = value as? NSNumber {
        return value.intValue
    }
    return nil
}

private func nonEmptyString(_ value: Any?) -> String? {
    let trimmed = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let trimmed, !trimmed.isEmpty else { return nil }
    return trimmed
}

private func jsonData(_ object: [String: Any]) throws -> Data {
    guard JSONSerialization.isValidJSONObject(object) else {
        throw AgentProviderClientError.invalidRequestBody
    }
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonString(from arguments: [String: AgentJSONValue]) -> String {
    let object = agentJSONObject(from: arguments)
    guard let data = try? jsonData(object),
          let string = String(data: data, encoding: .utf8)
    else {
        return "{}"
    }
    return string
}

private func jsonDictionary(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AgentProviderClientError.invalidResponseBody
    }
    return object
}

private func agentArguments(fromJSONString json: String) throws -> [String: AgentJSONValue] {
    guard let data = json.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return [:]
    }
    return agentArguments(fromJSONObject: object)
}

private func agentArguments(fromJSONObject object: [String: Any]) -> [String: AgentJSONValue] {
    object.reduce(into: [:]) { result, entry in
        result[entry.key] = agentJSONValue(from: entry.value)
    }
}

private func agentJSONObject(from arguments: [String: AgentJSONValue]) -> [String: Any] {
    arguments.reduce(into: [:]) { result, entry in
        result[entry.key] = agentAnyValue(from: entry.value)
    }
}

private func agentAnyValue(from value: AgentJSONValue) -> Any {
    switch value {
    case .null:
        return NSNull()
    case .bool(let bool):
        return bool
    case .number(let number):
        return number
    case .string(let string):
        return string
    case .array(let array):
        return array.map(agentAnyValue(from:))
    case .object(let object):
        return agentJSONObject(from: object)
    }
}

private func agentJSONValue(from value: Any) -> AgentJSONValue {
    switch value {
    case is NSNull:
        return .null
    case let bool as Bool:
        return .bool(bool)
    case let number as NSNumber:
        return .number(number.doubleValue)
    case let string as String:
        return .string(string)
    case let array as [Any]:
        return .array(array.map(agentJSONValue(from:)))
    case let object as [String: Any]:
        return .object(agentArguments(fromJSONObject: object))
    default:
        return .string(String(describing: value))
    }
}
