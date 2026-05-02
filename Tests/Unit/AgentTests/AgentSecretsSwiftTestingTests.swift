// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSecretsSwiftTestingTests.swift - Keychain-backed Agent secret contracts.

import Testing
@testable import CocxyTerminal

@Suite("AgentSecrets")
struct AgentSecretsSwiftTestingTests {

    @Test("API keys save load and delete through injected store")
    func apiKeysSaveLoadAndDelete() throws {
        let store = InMemoryAgentSecretStore()
        let secrets = AgentSecrets(store: store)

        try secrets.saveAPIKey("sk-ant-test", for: .anthropic)

        #expect(try secrets.apiKey(for: .anthropic) == "sk-ant-test")
        #expect(try secrets.hasAPIKey(for: .anthropic))

        try secrets.deleteAPIKey(for: .anthropic)
        #expect(try secrets.apiKey(for: .anthropic) == nil)
        #expect(try !secrets.hasAPIKey(for: .anthropic))
    }

    @Test("API keys are trimmed and empty values rejected")
    func apiKeysTrimmedAndEmptyRejected() throws {
        let secrets = AgentSecrets(store: InMemoryAgentSecretStore())

        try secrets.saveAPIKey("  sk-openai-test\n", for: .openai)
        #expect(try secrets.apiKey(for: .openai) == "sk-openai-test")

        #expect(throws: AgentSecretError.emptyAPIKey) {
            try secrets.saveAPIKey(" \n\t ", for: .openai)
        }
    }

    @Test("Foundation Models never accepts API key storage")
    func foundationModelsRejectsAPIKeyStorage() throws {
        let secrets = AgentSecrets(store: InMemoryAgentSecretStore())

        #expect(AgentProviderKind.foundationModelsOnDevice.requiresAPIKey == false)
        #expect(throws: AgentSecretError.providerDoesNotUseAPIKey(.foundationModelsOnDevice)) {
            try secrets.saveAPIKey("local-provider-has-no-key", for: .foundationModelsOnDevice)
        }
        #expect(try secrets.apiKey(for: .foundationModelsOnDevice) == nil)
    }

    @Test("provider keys are isolated by keychain account")
    func providerKeysAreIsolated() throws {
        let secrets = AgentSecrets(store: InMemoryAgentSecretStore())

        try secrets.saveAPIKey("sk-ant", for: .anthropic)
        try secrets.saveAPIKey("sk-openai", for: .openai)
        try secrets.saveAPIKey("sk-google", for: .google)

        #expect(try secrets.apiKey(for: .anthropic) == "sk-ant")
        #expect(try secrets.apiKey(for: .openai) == "sk-openai")
        #expect(try secrets.apiKey(for: .google) == "sk-google")
        #expect(AgentProviderKind.anthropic.keychainAccount == "anthropic")
        #expect(AgentProviderKind.openai.keychainAccount == "openai")
        #expect(AgentProviderKind.google.keychainAccount == "google")
    }
}
