// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentProviderFactorySwiftTestingTests.swift - Provider selection from config and secrets.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentProviderClientFactory")
struct AgentProviderFactorySwiftTestingTests {

    @Test("default model catalog uses current provider model IDs")
    func defaultModelCatalogUsesProviderModelIDs() {
        let catalog = AgentProviderModelCatalog.defaults

        #expect(catalog.openAI == "gpt-5.1")
        #expect(catalog.anthropic == "claude-sonnet-4-20250514")
        #expect(catalog.google == "gemini-2.5-flash")
    }

    @Test("factory errors expose user-readable descriptions")
    func factoryErrorsExposeUserReadableDescriptions() {
        #expect(
            AgentProviderClientFactoryError.explicitProviderChoiceRequired.localizedDescription
                == "Choose an Agent Mode provider in Settings."
        )
        #expect(
            AgentProviderClientFactoryError.missingAPIKey(.openai).localizedDescription
                == "Add an API key for OpenAI in Settings."
        )
    }

    @Test("factory refuses to create clients when Agent Mode is disabled")
    func factoryRefusesWhenDisabled() async throws {
        let factory = AgentProviderClientFactory(
            secrets: AgentSecrets(store: InMemoryAgentSecretStore()),
            foundationModelsAvailable: false,
            transport: RecordingFactoryHTTPTransport()
        )

        #expect(throws: AgentProviderClientFactoryError.agentModeDisabled) {
            _ = try factory.makeClient(configuration: AgentModeConfig(enabled: false))
        }
    }

    @Test("factory requires explicit provider choice when Foundation Models is unavailable")
    func factoryRequiresExplicitChoiceWhenFoundationModelsUnavailable() async throws {
        let factory = AgentProviderClientFactory(
            secrets: AgentSecrets(store: InMemoryAgentSecretStore()),
            foundationModelsAvailable: false,
            transport: RecordingFactoryHTTPTransport()
        )

        #expect(throws: AgentProviderClientFactoryError.explicitProviderChoiceRequired) {
            _ = try factory.makeClient(configuration: AgentModeConfig(enabled: true))
        }
    }

    @Test("factory creates on-device client when Foundation Models are available")
    func factoryCreatesOnDeviceClientWhenFoundationModelsAreAvailable() throws {
        let factory = AgentProviderClientFactory(
            secrets: AgentSecrets(store: InMemoryAgentSecretStore()),
            foundationModelsAvailable: true,
            transport: RecordingFactoryHTTPTransport()
        )

        let client = try factory.makeClient(configuration: AgentModeConfig(enabled: true))

        #expect(client is FoundationModelsAgentLLMClient)
    }

    @Test("factory refuses remote providers without a saved user API key")
    func factoryRequiresUserAPIKeyForRemoteProviders() async throws {
        let factory = AgentProviderClientFactory(
            secrets: AgentSecrets(store: InMemoryAgentSecretStore()),
            foundationModelsAvailable: false,
            transport: RecordingFactoryHTTPTransport()
        )

        #expect(throws: AgentProviderClientFactoryError.missingAPIKey(.openai)) {
            _ = try factory.makeClient(configuration: AgentModeConfig(
                enabled: true,
                preferredProvider: .openai
            ))
        }
    }

    @Test("factory creates remote client with stored user key and model catalog")
    func factoryCreatesRemoteClientWithStoredKeyAndModelCatalog() async throws {
        let secretStore = InMemoryAgentSecretStore()
        let secrets = AgentSecrets(store: secretStore)
        try secrets.saveAPIKey("user-openai-key", for: .openai)
        let transport = RecordingFactoryHTTPTransport(response: AgentHTTPResponse(
            statusCode: 200,
            data: Data("""
            {"choices":[{"message":{"role":"assistant","content":"ok","tool_calls":null}}]}
            """.utf8)
        ))
        let factory = AgentProviderClientFactory(
            secrets: secrets,
            foundationModelsAvailable: false,
            transport: transport,
            modelCatalog: AgentProviderModelCatalog(
                openAI: "custom-openai-model",
                anthropic: "custom-anthropic-model",
                google: "custom-google-model"
            )
        )

        let client = try factory.makeClient(configuration: AgentModeConfig(
            enabled: true,
            preferredProvider: .openai
        ))
        let response = try await client.nextResponse(for: [
            AgentMessage(id: "m1", role: .user, content: "hello"),
        ])
        let requests = await transport.requests
        let body = try #require(try JSONSerialization.jsonObject(with: requests[0].body) as? [String: Any])

        #expect(response.content == "ok")
        #expect(requests[0].headers["Authorization"] == "Bearer user-openai-key")
        #expect(body["model"] as? String == "custom-openai-model")
    }
}

private actor RecordingFactoryHTTPTransport: AgentHTTPTransport {
    private(set) var requests: [AgentHTTPRequest] = []
    private let response: AgentHTTPResponse

    init(response: AgentHTTPResponse = AgentHTTPResponse(statusCode: 200, data: Data())) {
        self.response = response
    }

    func send(_ request: AgentHTTPRequest) async throws -> AgentHTTPResponse {
        requests.append(request)
        return response
    }
}
