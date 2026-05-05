// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProviderClientSwiftTestingTests.swift - Remote provider request/response contracts.

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif
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
              "model": "test-openai-model",
              "usage": {
                "prompt_tokens": 12,
                "completion_tokens": 7
              },
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
        let tools = try #require(body["tools"] as? [[String: Any]])
        let readFileTool = try #require(tools.first { tool in
            (tool["function"] as? [String: Any])?["name"] as? String == "read_file"
        })
        let function = try #require(readFileTool["function"] as? [String: Any])
        let parameters = try #require(function["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let pathProperty = try #require(properties["path"] as? [String: Any])
        #expect(parameters["additionalProperties"] as? Bool == false)
        #expect(parameters["required"] as? [String] == ["path"])
        #expect(pathProperty["type"] as? String == "string")
        #expect(response.content == "I will inspect the file.")
        #expect(response.toolCalls == [
            AgentToolCall(
                id: "call-openai-1",
                toolID: "read_file",
                arguments: ["path": .string("Sources/App.swift")]
            ),
        ])
        #expect(response.usage == AgentLLMUsage(
            provider: "openai",
            model: "test-openai-model",
            inputTokens: 12,
            outputTokens: 7
        ))
    }

    @Test("OpenAI client sends user image attachments as vision content")
    func openAIClientSendsImageAttachmentsAsVisionContent() async throws {
        let attachment = try makeTemporaryImageAttachment()
        defer { removeTemporaryAttachment(attachment) }
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"choices":[{"message":{"role":"assistant","content":"Visible."}}]}"#.utf8)
        ))
        let client = OpenAIAgentLLMClient(
            apiKey: "openai-key",
            model: "test-openai-model",
            transport: transport
        )

        _ = try await client.nextResponse(for: [
            AgentMessage(
                id: "u1",
                role: .user,
                content: "Describe this image",
                imageAttachments: [attachment]
            ),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.first)
        let content = try #require(userMessage["content"] as? [[String: Any]])
        let textBlock = try #require(content.first)
        let imageBlock = try #require(content.dropFirst().first)
        let imageURL = try #require(imageBlock["image_url"] as? [String: Any])

        #expect(textBlock["type"] as? String == "text")
        #expect(textBlock["text"] as? String == "Describe this image")
        #expect(imageBlock["type"] as? String == "image_url")
        #expect(imageURL["url"] as? String == "data:image/png;base64,\(Self.imageBytes.base64EncodedString())")
    }

    @Test("provider client rejects missing image attachment files before sending")
    func providerClientRejectsMissingImageAttachmentFilesBeforeSending() async throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-missing-agent-image-\(UUID().uuidString).png", isDirectory: false)
        let attachment = AgentImageAttachment(
            displayName: "missing.png",
            mimeType: "image/png",
            filePath: missingURL.path,
            byteCount: 0,
            pixelWidth: 1,
            pixelHeight: 1
        )
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"choices":[{"message":{"role":"assistant","content":"Visible."}}]}"#.utf8)
        ))
        let client = OpenAIAgentLLMClient(
            apiKey: "openai-key",
            model: "test-openai-model",
            transport: transport
        )

        await #expect(throws: AgentProviderClientError.attachmentUnavailable("missing.png")) {
            _ = try await client.nextResponse(for: [
                AgentMessage(
                    id: "u1",
                    role: .user,
                    content: "Describe this image",
                    imageAttachments: [attachment]
                ),
            ])
        }
        #expect(await transport.requests.isEmpty)
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
              "model": "test-anthropic-model",
              "usage": {
                "input_tokens": 22,
                "output_tokens": 9
              },
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
        let tools = try #require(body["tools"] as? [[String: Any]])
        let runCommandTool = try #require(tools.first { $0["name"] as? String == "run_command" })
        let inputSchema = try #require(runCommandTool["input_schema"] as? [String: Any])
        let properties = try #require(inputSchema["properties"] as? [String: Any])
        let commandProperty = try #require(properties["command"] as? [String: Any])
        #expect(inputSchema["additionalProperties"] as? Bool == false)
        #expect(inputSchema["required"] as? [String] == ["command"])
        #expect(commandProperty["type"] as? String == "string")
        #expect(response.content == "I will check git.")
        #expect(response.toolCalls == [
            AgentToolCall(id: "toolu_1", toolID: "git_status"),
        ])
        #expect(response.usage == AgentLLMUsage(
            provider: "anthropic",
            model: "test-anthropic-model",
            inputTokens: 22,
            outputTokens: 9
        ))
    }

    @Test("Anthropic client sends user image attachments as vision blocks")
    func anthropicClientSendsImageAttachmentsAsVisionBlocks() async throws {
        let attachment = try makeTemporaryImageAttachment()
        defer { removeTemporaryAttachment(attachment) }
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"content":[{"type":"text","text":"Visible."}]}"#.utf8)
        ))
        let client = AnthropicAgentLLMClient(
            apiKey: "anthropic-key",
            model: "test-anthropic-model",
            transport: transport
        )

        _ = try await client.nextResponse(for: [
            AgentMessage(
                id: "u1",
                role: .user,
                content: "Describe this image",
                imageAttachments: [attachment]
            ),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)
        let messages = try #require(body["messages"] as? [[String: Any]])
        let userMessage = try #require(messages.first)
        let content = try #require(userMessage["content"] as? [[String: Any]])
        let textBlock = try #require(content.first)
        let imageBlock = try #require(content.dropFirst().first)
        let source = try #require(imageBlock["source"] as? [String: Any])

        #expect(textBlock["type"] as? String == "text")
        #expect(textBlock["text"] as? String == "Describe this image")
        #expect(imageBlock["type"] as? String == "image")
        #expect(source["type"] as? String == "base64")
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == Self.imageBytes.base64EncodedString())
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
              "usageMetadata": {
                "promptTokenCount": 18,
                "candidatesTokenCount": 11
              },
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
        let tools = try #require(body["tools"] as? [[String: Any]])
        let functionDeclarations = try #require(tools.first?["functionDeclarations"] as? [[String: Any]])
        let grepDeclaration = try #require(functionDeclarations.first { $0["name"] as? String == "grep" })
        let parameters = try #require(grepDeclaration["parameters"] as? [String: Any])
        let properties = try #require(parameters["properties"] as? [String: Any])
        let patternProperty = try #require(properties["pattern"] as? [String: Any])
        #expect(parameters["type"] as? String == "OBJECT")
        #expect(parameters["required"] as? [String] == ["pattern"])
        #expect(patternProperty["type"] as? String == "STRING")
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
        #expect(response.usage == AgentLLMUsage(
            provider: "google",
            model: "test-google-model",
            inputTokens: 18,
            outputTokens: 11
        ))
    }

    @Test("Google client sends user image attachments as inline data")
    func googleClientSendsImageAttachmentsAsInlineData() async throws {
        let attachment = try makeTemporaryImageAttachment()
        defer { removeTemporaryAttachment(attachment) }
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data(#"{"candidates":[{"content":{"parts":[{"text":"Visible."}]}}]}"#.utf8)
        ))
        let client = GoogleAgentLLMClient(
            apiKey: "google-key",
            model: "test-google-model",
            transport: transport
        )

        _ = try await client.nextResponse(for: [
            AgentMessage(
                id: "u1",
                role: .user,
                content: "Describe this image",
                imageAttachments: [attachment]
            ),
        ])
        let request = try await onlyRequest(from: transport)
        let body = try jsonObject(request.body)
        let contents = try #require(body["contents"] as? [[String: Any]])
        let userMessage = try #require(contents.first)
        let parts = try #require(userMessage["parts"] as? [[String: Any]])
        let textPart = try #require(parts.first)
        let imagePart = try #require(parts.dropFirst().first)
        let inlineData = try #require(imagePart["inlineData"] as? [String: Any])

        #expect(textPart["text"] as? String == "Describe this image")
        #expect(inlineData["mimeType"] as? String == "image/png")
        #expect(inlineData["data"] as? String == Self.imageBytes.base64EncodedString())
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

    @Test("provider failure messages redact echoed secrets and stay bounded")
    func providerFailureMessagesRedactEchoedSecretsAndStayBounded() async throws {
        let transport = RecordingAgentHTTPTransport(response: AgentHTTPResponse(
            statusCode: 401,
            data: Data("""
            {"error":{"message":"invalid token sk-test-redacted-openai-key for token=abc12345678901234567890 with \(String(repeating: "context ", count: 80))"}}
            """.utf8)
        ))
        let client = OpenAIAgentLLMClient(
            apiKey: "secret-openai-key",
            model: "test-openai-model",
            transport: transport
        )

        do {
            _ = try await client.nextResponse(for: [
                AgentMessage(id: "m1", role: .user, content: "hello"),
            ])
            Issue.record("Expected provider failure")
        } catch let error as AgentProviderClientError {
            let description = error.localizedDescription
            #expect(description.contains("[redacted]"))
            #expect(!description.contains("sk-test-redacted-openai-key"))
            #expect(!description.contains("abc12345678901234567890"))
            #expect(description.count <= 360)
        }
    }

    @Test("retrying transport retries transient provider failures")
    func retryingTransportRetriesTransientProviderFailures() async throws {
        let base = SequencedAgentHTTPTransport(results: [
            .success(AgentHTTPResponse(statusCode: 500, data: Data("temporary".utf8))),
            .success(AgentHTTPResponse(statusCode: 200, data: Data("ok".utf8))),
        ])
        let transport = RetryingAgentHTTPTransport(
            base: base,
            maxAttempts: 3,
            sleep: { _ in }
        )
        let request = AgentHTTPRequest(
            url: try #require(URL(string: "https://example.com/agent")),
            headers: [:],
            body: Data()
        )

        let response = try await transport.send(request)
        let requests = await base.requests

        #expect(response.statusCode == 200)
        #expect(requests.count == 2)
    }

    @Test("retrying transport does not retry auth failures")
    func retryingTransportDoesNotRetryAuthFailures() async throws {
        let base = SequencedAgentHTTPTransport(results: [
            .success(AgentHTTPResponse(statusCode: 401, data: Data("invalid key".utf8))),
            .success(AgentHTTPResponse(statusCode: 200, data: Data("ok".utf8))),
        ])
        let transport = RetryingAgentHTTPTransport(
            base: base,
            maxAttempts: 3,
            sleep: { _ in }
        )
        let request = AgentHTTPRequest(
            url: try #require(URL(string: "https://example.com/agent")),
            headers: [:],
            body: Data()
        )

        let response = try await transport.send(request)
        let requests = await base.requests

        #expect(response.statusCode == 401)
        #expect(requests.count == 1)
    }

    @Test("factory wraps remote provider transport with retry")
    func factoryWrapsRemoteProviderTransportWithRetry() async throws {
        let secretStore = InMemoryAgentSecretStore()
        let secrets = AgentSecrets(store: secretStore)
        try secrets.saveAPIKey("user-openai-key", for: .openai)
        let transport = SequencedAgentHTTPTransport(results: [
            .success(AgentHTTPResponse(statusCode: 429, data: Data("rate limited".utf8))),
            .success(AgentHTTPResponse(
                statusCode: 200,
                data: Data(#"{"choices":[{"message":{"role":"assistant","content":"ok"}}]}"#.utf8)
            )),
        ])
        let factory = AgentProviderClientFactory(
            secrets: secrets,
            foundationModelsAvailable: false,
            transport: transport
        )

        let client = try factory.makeClient(configuration: AgentModeConfig(
            enabled: true,
            preferredProvider: .openai
        ))
        let response = try await client.nextResponse(for: [
            AgentMessage(id: "m1", role: .user, content: "hello"),
        ])
        let requests = await transport.requests

        #expect(response.content == "ok")
        #expect(requests.count == 2)
    }

    #if canImport(FoundationModels)
    @Test("Foundation Models instructions state on-device tool gating")
    func foundationModelsInstructionsStateOnDeviceToolGating() {
        let instructions = FoundationModelsAgentPromptBuilder.instructions(from: [
            AgentMessage(
                id: "s1",
                role: .system,
                content: "Prefer concise answers."
            ),
        ])

        #expect(instructions.contains("Prefer concise answers."))
        #expect(instructions.contains("Request local tools"))
        #expect(instructions.contains("local permission rules"))
        #expect(instructions.contains("Never claim you read files, ran commands, changed repositories"))
        #expect(instructions.contains("Follow direct user formatting instructions exactly"))
        #expect(instructions.count <= FoundationModelsAgentPromptBuilder.maxInstructionsCharacters)
    }

    @Test("Foundation Models prompt builder bounds long transcripts and keeps recent context")
    func foundationModelsPromptBuilderBoundsLongTranscriptsAndKeepsRecentContext() {
        let oldContent = String(repeating: "old context ", count: 4_000)
        let toolContent = String(repeating: "tool output ", count: 4_000)
        let recentPrompt = "Di exactamente COCXY_AGENT_SMOKE_OK y nada mas."

        let oldMessages = (0..<6).map {
            AgentMessage(id: "u-old-\($0)", role: .user, content: oldContent)
        }
        let prompt = FoundationModelsAgentPromptBuilder.prompt(from: oldMessages + [
            AgentMessage(
                id: "t1",
                role: .tool,
                content: toolContent,
                toolName: "terminal_output"
            ),
            AgentMessage(id: "u-recent", role: .user, content: recentPrompt),
        ])

        #expect(prompt.contains("User:\n\(recentPrompt)"))
        #expect(prompt.contains("[Earlier transcript omitted to fit the on-device context window.]"))
        #expect(prompt.count <= FoundationModelsAgentPromptBuilder.maxPromptCharacters)
    }

    @Test("Foundation Models tool bridge converts transcript calls without trusting synthetic content")
    @available(macOS 26.0, *)
    func foundationModelsToolBridgeConvertsTranscriptCallsWithoutTrustingSyntheticContent() throws {
        let entries: ArraySlice<Transcript.Entry> = [
            .toolCalls(Transcript.ToolCalls([
                Transcript.ToolCall(
                    id: "call-read",
                    toolName: "read_file",
                    arguments: GeneratedContent(properties: ["path": "Package.swift"])
                ),
                Transcript.ToolCall(
                    id: "call-read-duplicate",
                    toolName: "read_file",
                    arguments: GeneratedContent(properties: ["path": "Package.swift"])
                ),
                Transcript.ToolCall(
                    id: "call-run",
                    toolName: "run_command",
                    arguments: GeneratedContent(properties: [
                        "command": "swift test --filter AgentLoopSwiftTestingTests",
                        "timeoutSeconds": 30,
                    ])
                ),
            ])),
        ][...]

        let response = FoundationModelsAgentToolBridge.response(
            from: "Package.swift has already been read.",
            transcriptEntries: entries
        )

        #expect(response.content == "")
        #expect(response.toolCalls == [
            AgentToolCall(
                id: "call-read",
                toolID: "read_file",
                arguments: ["path": .string("Package.swift")]
            ),
            AgentToolCall(
                id: "call-run",
                toolID: "run_command",
                arguments: [
                    "command": .string("swift test --filter AgentLoopSwiftTestingTests"),
                    "timeoutSeconds": .number(30),
                ]
            ),
        ])
    }

    @Test("Foundation Models tool bridge creates no-op tools from Agent registry")
    @available(macOS 26.0, *)
    func foundationModelsToolBridgeCreatesNoOpToolsFromAgentRegistry() throws {
        let registry = try AgentToolRegistry(descriptors: [
            AgentToolDescriptor(
                id: "read_file",
                displayName: "Read File",
                description: "Read a repository file after path validation.",
                capability: .read,
                inputSchema: AgentToolInputSchema(
                    properties: [
                        "path": AgentToolInputProperty(.string, description: "Repository-relative path."),
                        "limit": AgentToolInputProperty(.number, description: "Maximum bytes."),
                        "includeHidden": AgentToolInputProperty(.boolean, description: "Include hidden files."),
                    ],
                    required: ["path"]
                )
            ),
        ])

        let tools = try FoundationModelsAgentToolBridge.tools(from: registry)

        #expect(tools.count == 1)
        #expect(tools.first?.name == "read_file")
        #expect(tools.first?.description == "Read a repository file after path validation.")
    }

    @Test("Foundation Models tool bridge selects exact tool requests without sending every schema")
    @available(macOS 26.0, *)
    func foundationModelsToolBridgeSelectsExactToolRequestsWithoutSendingEverySchema() {
        let selected = FoundationModelsAgentToolBridge.selectedDescriptors(
            from: .minimumBuiltIns(),
            matching: "Use the read_file tool with path Package.swift.",
            maxTools: 6
        )

        #expect(selected.map(\.id) == ["read_file"])
    }

    @Test("Foundation Models tool bridge bounds contextual tool selection")
    @available(macOS 26.0, *)
    func foundationModelsToolBridgeBoundsContextualToolSelection() {
        let selected = FoundationModelsAgentToolBridge.selectedDescriptors(
            from: .minimumBuiltIns(),
            matching: "Find where AgentSessionRunner runs commands and inspect recent terminal output.",
            maxTools: 3
        )

        #expect(selected.count <= 3)
        #expect(selected.map(\.id).contains("run_command"))
        #expect(selected.map(\.id).contains("read_terminal_output"))
    }

    @Test("Foundation Models tool bridge avoids skill tools for generic skill wording")
    @available(macOS 26.0, *)
    func foundationModelsToolBridgeAvoidsSkillToolsForGenericSkillWording() {
        let selected = FoundationModelsAgentToolBridge.selectedDescriptors(
            from: .minimumBuiltIns(),
            matching: "Reply exactly: skill smoke ok. Do not use tools.",
            maxTools: 6
        )

        #expect(!selected.map(\.id).contains("list_skills"))
        #expect(!selected.map(\.id).contains("use_skill"))
    }

    @Test("Foundation Models tool bridge still selects skill tools for explicit skill requests")
    @available(macOS 26.0, *)
    func foundationModelsToolBridgeStillSelectsSkillToolsForExplicitSkillRequests() {
        let listSelected = FoundationModelsAgentToolBridge.selectedDescriptors(
            from: .minimumBuiltIns(),
            matching: "Show available skills for this project.",
            maxTools: 6
        )
        let useSelected = FoundationModelsAgentToolBridge.selectedDescriptors(
            from: .minimumBuiltIns(),
            matching: "Load skill write-tests.",
            maxTools: 6
        )

        #expect(listSelected.map(\.id).contains("list_skills"))
        #expect(useSelected.map(\.id).contains("use_skill"))
    }
    #endif

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

    private func makeTemporaryImageAttachment(
        mimeType: String = "image/png",
        fileExtension: String = "png"
    ) throws -> AgentImageAttachment {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-provider-image-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("attachment.\(fileExtension)", isDirectory: false)
        try Self.imageBytes.write(to: fileURL, options: [.atomic])
        return AgentImageAttachment(
            id: "image-\(UUID().uuidString)",
            displayName: "attachment.\(fileExtension)",
            mimeType: mimeType,
            filePath: fileURL.path,
            byteCount: Self.imageBytes.count,
            pixelWidth: 1,
            pixelHeight: 1
        )
    }

    private func removeTemporaryAttachment(_ attachment: AgentImageAttachment) {
        try? FileManager.default.removeItem(at: attachment.fileURL.deletingLastPathComponent())
    }

    private static let imageBytes = Data("image-bytes".utf8)
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

private actor SequencedAgentHTTPTransport: AgentHTTPTransport {
    private(set) var requests: [AgentHTTPRequest] = []
    private var results: [Result<AgentHTTPResponse, Error>]

    init(results: [Result<AgentHTTPResponse, Error>]) {
        self.results = results
    }

    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        requests.append(request)
        guard !results.isEmpty else {
            return AgentHTTPResponse(statusCode: 599, data: Data("exhausted".utf8))
        }
        return try results.removeFirst().get()
    }
}
