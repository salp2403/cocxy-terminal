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
    case missingResponseChoice
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
            return FoundationModelsAgentLLMClient()
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
            return try await FoundationModelsAgentRuntime.nextResponse(for: messages)
        }
        #endif
        throw AgentProviderClientFactoryError.foundationModelsClientUnavailable
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
private enum FoundationModelsAgentRuntime {
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        guard SystemLanguageModel.default.isAvailable else {
            throw AgentProviderClientFactoryError.foundationModelsClientUnavailable
        }

        let session = LanguageModelSession(
            model: .default,
            instructions: foundationModelsInstructions(from: messages)
        )
        let response = try await session.respond(to: foundationModelsPrompt(from: messages))
        return AgentLLMResponse(content: response.content, toolCalls: [])
    }

    private static func foundationModelsInstructions(from messages: [AgentMessage]) -> String {
        let systemMessages = messages
            .filter { $0.role == .system }
            .map(\.content)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return (systemMessages + [
            "You are Cocxy Agent Mode running fully on this Mac.",
            "Use the conversation and local tool results already provided in the prompt.",
            "When a repository change or command is needed, explain the next local action clearly instead of inventing unavailable tool output.",
        ]).joined(separator: "\n\n")
    }

    private static func foundationModelsPrompt(from messages: [AgentMessage]) -> String {
        let transcript = messages
            .filter { $0.role != .system }
            .map { message -> String in
                switch message.role {
                case .user:
                    return "User:\n\(message.content)"
                case .assistant:
                    return "Assistant:\n\(message.content)"
                case .tool:
                    let name = message.toolName ?? "tool"
                    return "Local tool result (\(name)):\n\(message.content)"
                case .system:
                    return ""
                }
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        return transcript.isEmpty ? "User:\nHello" : transcript
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
        let request = try AgentHTTPRequest(
            url: endpointURL,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
            ],
            body: jsonData([
                "model": model,
                "messages": openAIMessages(from: messages),
                "tools": openAITools(from: toolRegistry.descriptors),
                "tool_choice": "auto",
            ])
        )
        let response = try await transport.send(request)
        try validate(response)
        return try parseOpenAIResponse(response.data)
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
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": anthropicMessages(from: messages),
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
        return try parseAnthropicResponse(response.data)
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
        let request = try AgentHTTPRequest(
            url: baseURL.appendingPathComponent("\(escapedModel):generateContent"),
            headers: [
                "x-goog-api-key": apiKey,
                "Content-Type": "application/json",
            ],
            body: jsonData([
                "contents": googleContents(from: messages),
                "tools": googleTools(from: toolRegistry.descriptors),
            ])
        )
        let response = try await transport.send(request)
        try validate(response)
        return try parseGoogleResponse(response.data)
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

private func openAIMessages(from messages: [AgentMessage]) -> [[String: Any]] {
    messages.map { message in
        var result: [String: Any] = [
            "role": openAIRole(message.role),
            "content": message.content,
        ]
        if message.role == .assistant, !message.toolCalls.isEmpty {
            result["tool_calls"] = message.toolCalls.map(openAIToolCall)
        }
        if message.role == .tool, let toolCallID = message.toolCallID {
            result["tool_call_id"] = toolCallID
        }
        return result
    }
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

private func anthropicMessages(from messages: [AgentMessage]) -> [[String: Any]] {
    messages.compactMap { message in
        switch message.role {
        case .system:
            return nil
        case .user:
            return ["role": "user", "content": message.content]
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

private func anthropicToolUseBlock(_ call: AgentToolCall) -> [String: Any] {
    [
        "type": "tool_use",
        "id": call.id,
        "name": call.toolID,
        "input": agentJSONObject(from: call.arguments),
    ]
}

private func googleContents(from messages: [AgentMessage]) -> [[String: Any]] {
    messages.compactMap { message in
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
            return ["role": "user", "parts": [["text": message.content]]]
        case .system:
            return nil
        }
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

private func parseOpenAIResponse(_ data: Data) throws -> AgentLLMResponse {
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

    return AgentLLMResponse(content: content, toolCalls: toolCalls)
}

private func parseAnthropicResponse(_ data: Data) throws -> AgentLLMResponse {
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

    return AgentLLMResponse(content: textParts.joined(separator: "\n"), toolCalls: toolCalls)
}

private func parseGoogleResponse(_ data: Data) throws -> AgentLLMResponse {
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

    return AgentLLMResponse(content: textParts.joined(separator: "\n"), toolCalls: toolCalls)
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
