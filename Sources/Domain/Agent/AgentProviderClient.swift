// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProviderClient.swift - User-keyed Agent LLM provider clients.

import Foundation

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

struct AgentProviderClientFactory: Sendable {
    let secrets: AgentSecrets
    let foundationModelsAvailable: Bool
    let transport: any AgentHTTPTransport
    let modelCatalog: AgentProviderModelCatalog

    init(
        secrets: AgentSecrets = AgentSecrets(),
        foundationModelsAvailable: Bool,
        transport: any AgentHTTPTransport = URLSessionAgentHTTPTransport(),
        modelCatalog: AgentProviderModelCatalog = .defaults
    ) {
        self.secrets = secrets
        self.foundationModelsAvailable = foundationModelsAvailable
        self.transport = transport
        self.modelCatalog = modelCatalog
    }

    func makeClient(configuration: AgentModeConfig) throws -> any AgentLLMClient {
        guard configuration.enabled else {
            throw AgentProviderClientFactoryError.agentModeDisabled
        }

        switch configuration.effectiveProvider(foundationModelsAvailable: foundationModelsAvailable) {
        case .explicitChoiceRequired:
            throw AgentProviderClientFactoryError.explicitProviderChoiceRequired
        case .provider(let provider):
            return try makeClient(provider: provider)
        }
    }

    private func makeClient(provider: AgentProviderKind) throws -> any AgentLLMClient {
        switch provider {
        case .foundationModelsOnDevice:
            return FoundationModelsAgentLLMClient()
        case .openai:
            return OpenAIAgentLLMClient(
                apiKey: try requiredAPIKey(for: provider),
                model: modelCatalog.openAI,
                transport: transport
            )
        case .anthropic:
            return AnthropicAgentLLMClient(
                apiKey: try requiredAPIKey(for: provider),
                model: modelCatalog.anthropic,
                transport: transport
            )
        case .google:
            return GoogleAgentLLMClient(
                apiKey: try requiredAPIKey(for: provider),
                model: modelCatalog.google,
                transport: transport
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
    func nextResponse(for messages: [AgentMessage]) async throws -> AgentLLMResponse {
        throw AgentProviderClientFactoryError.foundationModelsClientUnavailable
    }
}

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
        if message.role == .tool, let toolCallID = message.toolCallID {
            result["tool_call_id"] = toolCallID
        }
        return result
    }
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
            return ["role": "assistant", "content": message.content]
        case .tool:
            return [
                "role": "user",
                "content": "Tool \(message.toolName ?? "unknown") result:\n\(message.content)",
            ]
        }
    }
}

private func googleContents(from messages: [AgentMessage]) -> [[String: Any]] {
    messages.compactMap { message in
        guard message.role != .system else { return nil }
        return [
            "role": message.role == .assistant ? "model" : "user",
            "parts": [["text": message.content]],
        ]
    }
}

private func openAITools(from descriptors: [AgentToolDescriptor]) -> [[String: Any]] {
    descriptors.map { descriptor in
        [
            "type": "function",
            "function": [
                "name": descriptor.id,
                "description": descriptor.description,
                "parameters": genericJSONSchema(),
            ],
        ]
    }
}

private func anthropicTools(from descriptors: [AgentToolDescriptor]) -> [[String: Any]] {
    descriptors.map { descriptor in
        [
            "name": descriptor.id,
            "description": descriptor.description,
            "input_schema": genericJSONSchema(),
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
                    "parameters": genericGoogleSchema(),
                ]
            },
        ],
    ]
}

private func genericJSONSchema() -> [String: Any] {
    [
        "type": "object",
        "additionalProperties": true,
    ]
}

private func genericGoogleSchema() -> [String: Any] {
    [
        "type": "OBJECT",
        "properties": [:],
    ]
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
