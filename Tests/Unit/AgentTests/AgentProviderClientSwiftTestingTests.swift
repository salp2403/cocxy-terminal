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

    @Test("OpenAI transcript preserves assistant tool calls before tool results")
    func openAITranscriptPreservesAssistantToolCalls() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"choices":[{"message":{"role":"assistant","content":"Done."}}]}"#.utf8)
        ))
        let call = AgentToolCall(
            id: "call-openai-1",
            toolID: "read_file",
            arguments: ["path": .string("Sources/App.swift")]
        )
        let client = OpenAIAgentLLMClient(
            apiKey: "openai-key",
            model: "test-openai-model",
            transport: transport
        )

        _ = try await client.nextResponse(for: [
            AgentMessage(id: "u1", role: .user, content: "Read the app file"),
            AgentMessage(id: "a1", role: .assistant, content: "I will inspect it.", toolCalls: [call]),
            AgentMessage(
                id: "t1",
                role: .tool,
                content: #"{"status":"success"}"#,
                toolName: "read_file",
                toolCallID: "call-openai-1"
            ),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        let toolMessage = try #require(messages.first { $0["role"] as? String == "tool" })
        let toolCalls = try #require(assistant["tool_calls"] as? [[String: Any]])
        let function = try #require(toolCalls.first?["function"] as? [String: Any])
        let argumentString = try #require(function["arguments"] as? String)
        let arguments = try jsonObject(Data(argumentString.utf8))

        #expect(toolCalls.first?["id"] as? String == "call-openai-1")
        #expect(function["name"] as? String == "read_file")
        #expect(arguments["path"] as? String == "Sources/App.swift")
        #expect(toolMessage["tool_call_id"] as? String == "call-openai-1")
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

    @Test("Anthropic transcript preserves tool_use and tool_result blocks")
    func anthropicTranscriptPreservesToolUseAndToolResultBlocks() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"content":[{"type":"text","text":"Done."}]}"#.utf8)
        ))
        let call = AgentToolCall(
            id: "toolu_1",
            toolID: "git_status",
            arguments: [:]
        )
        let client = AnthropicAgentLLMClient(
            apiKey: "anthropic-key",
            model: "test-anthropic-model",
            transport: transport
        )

        _ = try await client.nextResponse(for: [
            AgentMessage(id: "u1", role: .user, content: "Check status"),
            AgentMessage(id: "a1", role: .assistant, content: "I will check git.", toolCalls: [call]),
            AgentMessage(
                id: "t1",
                role: .tool,
                content: #"{"status":"success"}"#,
                toolName: "git_status",
                toolCallID: "toolu_1"
            ),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let assistant = try #require(messages.first { $0["role"] as? String == "assistant" })
        let toolResult = try #require(messages.last)
        let assistantBlocks = try #require(assistant["content"] as? [[String: Any]])
        let toolUse = try #require(assistantBlocks.first { $0["type"] as? String == "tool_use" })
        let toolResultBlocks = try #require(toolResult["content"] as? [[String: Any]])
        let toolResultBlock = try #require(toolResultBlocks.first)

        #expect(toolUse["id"] as? String == "toolu_1")
        #expect(toolUse["name"] as? String == "git_status")
        #expect(toolResultBlock["type"] as? String == "tool_result")
        #expect(toolResultBlock["tool_use_id"] as? String == "toolu_1")
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

    @Test("Google transcript preserves functionCall and functionResponse parts")
    func googleTranscriptPreservesFunctionCallAndFunctionResponseParts() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"candidates":[{"content":{"parts":[{"text":"Done."}]}}]}"#.utf8)
        ))
        let call = AgentToolCall(
            id: "google-call-1-grep",
            toolID: "grep",
            arguments: [
                "pattern": .string("AgentLoop"),
                "path": .string("Sources"),
            ]
        )
        let client = GoogleAgentLLMClient(
            apiKey: "google-key",
            model: "test-google-model",
            transport: transport
        )

        _ = try await client.nextResponse(for: [
            AgentMessage(id: "u1", role: .user, content: "Find AgentLoop"),
            AgentMessage(id: "a1", role: .assistant, content: "I will search.", toolCalls: [call]),
            AgentMessage(
                id: "t1",
                role: .tool,
                content: #"{"status":"success","matches":2}"#,
                toolName: "grep",
                toolCallID: "google-call-1-grep"
            ),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)
        let contents = try #require(body["contents"] as? [[String: Any]])
        let modelMessage = try #require(contents.first { $0["role"] as? String == "model" })
        let toolMessage = try #require(contents.last)
        let modelParts = try #require(modelMessage["parts"] as? [[String: Any]])
        let functionCallPart = try #require(modelParts.first { $0["functionCall"] != nil })
        let functionCall = try #require(functionCallPart["functionCall"] as? [String: Any])
        let args = try #require(functionCall["args"] as? [String: Any])
        let toolParts = try #require(toolMessage["parts"] as? [[String: Any]])
        let functionResponsePart = try #require(toolParts.first)
        let functionResponse = try #require(functionResponsePart["functionResponse"] as? [String: Any])
        let response = try #require(functionResponse["response"] as? [String: Any])

        #expect(functionCall["name"] as? String == "grep")
        #expect(args["pattern"] as? String == "AgentLoop")
        #expect(functionResponse["name"] as? String == "grep")
        #expect(response["status"] as? String == "success")
        #expect((response["matches"] as? NSNumber)?.intValue == 2)
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
