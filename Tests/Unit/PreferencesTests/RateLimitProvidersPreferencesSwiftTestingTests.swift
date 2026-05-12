// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - rate-limit providers wiring")
@MainActor
struct RateLimitProvidersPreferencesSwiftTestingTests {

    private final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        rateLimit: RateLimitConfig
    ) -> (PreferencesViewModel, InMemoryConfigFileProvider) {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            codeReview: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            rateLimit: rateLimit
        )
        let provider = InMemoryConfigFileProvider()
        let vm = PreferencesViewModel(config: config, fileProvider: provider)
        return (vm, provider)
    }

    @Test("load reflects enabled providers and auto-detect")
    func loadReflectsConfig() {
        let (vm, _) = makeViewModel(rateLimit: RateLimitConfig(
            enabledProviders: [.cursor, .copilot],
            autoDetect: false,
            oauthRefreshIntervalMinutes: 15
        ))

        #expect(vm.rateLimitProviderEnabled(.cursor))
        #expect(vm.rateLimitProviderEnabled(.copilot))
        #expect(!vm.rateLimitProviderEnabled(.codex))
        #expect(vm.rateLimitAutoDetect == false)
        #expect(vm.rateLimitOAuthRefreshIntervalMinutes == 15)
    }

    @Test("provider toggle marks the model dirty and discard restores it")
    func providerToggleDirtyAndDiscard() {
        let (vm, _) = makeViewModel(rateLimit: RateLimitConfig(
            enabledProviders: [.cursor],
            autoDetect: true,
            oauthRefreshIntervalMinutes: 50
        ))

        vm.setRateLimitProvider(.copilot, enabled: true)
        #expect(vm.hasUnsavedChanges)
        vm.discardChanges()

        #expect(vm.rateLimitProviderEnabled(.cursor))
        #expect(!vm.rateLimitProviderEnabled(.copilot))
        #expect(!vm.hasUnsavedChanges)
    }

    @Test("save writes the provider section and resets dirty state")
    func saveWritesProviderSection() throws {
        let (vm, provider) = makeViewModel(rateLimit: .defaults)

        vm.setRateLimitProvider(.cursor, enabled: false)
        vm.rateLimitAutoDetect = false
        vm.rateLimitOAuthRefreshIntervalMinutes = 12
        try vm.save()

        #expect(!vm.hasUnsavedChanges)
        #expect(provider.lastWrite?.contains("[rate-limit]") == true)
        #expect(provider.lastWrite?.contains("auto-detect = false") == true)
        #expect(provider.lastWrite?.contains("oauth-refresh-interval-minutes = 12") == true)
        #expect(provider.lastWrite?.contains("\"cursor\"") == false)
    }
}
