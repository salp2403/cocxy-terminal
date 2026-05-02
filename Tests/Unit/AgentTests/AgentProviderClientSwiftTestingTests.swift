// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProviderClientSwiftTestingTests.swift - Remote provider request/response contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent provider clients")
struct AgentProviderClientSwiftTestingTests {

    @Test("OpenAI client sends chat-completions tools and parses tool calls")
    func openAIClientSendsToolsAndParsesToolCalls() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data("""
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "I will inspect the file.",
                    "tool_calls": [
                      {
                        "id": "call-openai-1",
                        "type": "function",
                        "function": {
                          "name": "read_file",
                          "arguments": "{\\"path\\":\\"Sources/App.swift\\"}"
                        }
                      }
                    ]
                  }
                }
              ]
            }
            """.utf8)
        ))
        let client = OpenAIAgentLLMClient(
            apiKey: "openai-key",
            model: "test-openai-model",
            transport: transport
        )

        let response = try await client.nextResponse(for: [
            AgentMessage(id: "m1", role: .user, content: "Read the app file"),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)

        #expect(request.url.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(request.headers["Authorization"] == "Bearer openai-key")
        #expect(body["model"] as? String == "test-openai-model")
        #expect((body["tools"] as? [[String: Any]])?.isEmpty == false)
        #expect(response.content == "I will inspect the file.")
        #expect(response.toolCalls == [
            AgentToolCall(
                id: "call-openai-1",
                toolID: "read_file",
                arguments: ["path": .string("Sources/App.swift")]
            ),
        ])
    }

    @Test("Anthropic client sends messages tools and parses tool_use blocks")
    func anthropicClientSendsToolsAndParsesToolUse() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data("""
            {
              "content": [
                {"type": "text", "text": "I will check git."},
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "git_status",
                  "input": {}
                }
              ]
            }
            """.utf8)
        ))
        let client = AnthropicAgentLLMClient(
            apiKey: "anthropic-key",
            model: "test-anthropic-model",
            transport: transport
        )

        let response = try await client.nextResponse(for: [
            AgentMessage(id: "m1", role: .system, content: "Be careful."),
            AgentMessage(id: "m2", role: .user, content: "Check status"),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)

        #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.headers["x-api-key"] == "anthropic-key")
        #expect(request.headers["anthropic-version"] == "2023-06-01")
        #expect(body["model"] as? String == "test-anthropic-model")
        #expect(body["system"] as? String == "Be careful.")
        #expect((body["tools"] as? [[String: Any]])?.isEmpty == false)
        #expect(response.content == "I will check git.")
        #expect(response.toolCalls == [
            AgentToolCall(id: "toolu_1", toolID: "git_status"),
        ])
    }

    @Test("Google client sends generateContent tools and parses function calls")
    func googleClientSendsToolsAndParsesFunctionCalls() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data("""
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      {"text": "I will search."},
                      {
                        "functionCall": {
                          "name": "grep",
                          "args": {
                            "pattern": "AgentLoop",
                            "path": "Sources"
                          }
                        }
                      }
                    ]
                  }
                }
              ]
            }
            """.utf8)
        ))
        let client = GoogleAgentLLMClient(
            apiKey: "google-key",
            model: "test-google-model",
            transport: transport
        )

        let response = try await client.nextResponse(for: [
            AgentMessage(id: "m1", role: .user, content: "Find AgentLoop"),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)

        #expect(request.url.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/test-google-model:generateContent")
        #expect(request.headers["x-goog-api-key"] == "google-key")
        #expect((body["tools"] as? [[String: Any]])?.isEmpty == false)
        #expect(response.content == "I will search.")
        #expect(response.toolCalls == [
            AgentToolCall(
                id: "google-call-1-grep",
                toolID: "grep",
                arguments: [
                    "pattern": .string("AgentLoop"),
                    "path": .string("Sources"),
                ]
            ),
        ])
    }

    @Test("provider clients surface non-success HTTP responses without leaking API keys")
    func providerClientsSurfaceHTTPFailuresWithoutLeakingKeys() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 401,
            data: Data(#"{"error":{"message":"invalid api key"}}"#.utf8)
        ))
        let client = OpenAIAgentLLMClient(
            apiKey: "secret-openai-key",
            model: "test-openai-model",
            transport: transport
        )

        await #expect(throws: AgentProviderClientError.httpStatus(401, "invalid api key")) {
            _ = try await client.nextResponse(for: [
                AgentMessage(id: "m1", role: .user, content: "hello"),
            ])
        }
    }

    private func onlyRequest(from transport: RecordingAgentHTTPTransport) async throws -> AgentHTTPRequest {
        let requests = await transport.requests
        guard requests.count == 1, let request = requests.first else {
            throw AgentProviderClientTestError.unexpectedRequestCount(requests.count)
        }
        return request
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentProviderClientTestError.invalidJSONBody
        }
        return object
    }
}

private enum AgentProviderClientTestError: Error {
    case unexpectedRequestCount(Int)
    case invalidJSONBody
}

private actor RecordingAgentHTTPTransport: AgentHTTPTransport {
    private(set) var requests: [AgentHTTPRequest] = []
    private let response: AgentHTTPResponse

    init(response: AgentHTTPResponse) {
        self.response = response
    }

    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        requests.append(request)
        return response
    }
}
