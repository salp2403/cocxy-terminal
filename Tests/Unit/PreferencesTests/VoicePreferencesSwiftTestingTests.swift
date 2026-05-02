// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VoicePreferencesSwiftTestingTests.swift - Preferences coverage for `[voice]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Voice round-trip")
@MainActor
struct VoicePreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func makeViewModel(config: CocxyConfig = .defaults) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        let vm = PreferencesViewModel(
            config: config,
            fileProvider: provider,
            voiceLocaleResolver: VoiceLocaleResolver(
                supportedLocales: [
                    Locale(identifier: "en_US"),
                    Locale(identifier: "es_ES"),
                ],
                systemLocale: Locale(identifier: "es_HN")
            )
        )
        return (vm, provider)
    }

    @Test("init populates Voice fields from the saved config")
    func initPopulatesVoiceFieldsFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            voice: VoiceConfig(enabled: true, localeIdentifier: "es-ES"),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.voiceEnabled == true)
        #expect(vm.voiceLocaleIdentifier == "es-ES")
        #expect(vm.availableVoiceLocales.map(\.identifier) == ["en-US", "es-ES"])
        #expect(vm.resolvedVoiceLocale == VoiceLocaleResolution(
            localeIdentifier: "es-ES",
            source: .manualOverride
        ))
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Voice fields marks Preferences dirty and discard restores")
    func changingVoiceFieldsMarksDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        vm.voiceEnabled = true
        vm.voiceLocaleIdentifier = "en-US"

        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.voiceEnabled == false)
        #expect(vm.voiceLocaleIdentifier == VoiceConfig.systemLocaleIdentifier)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("save then reload preserves Voice fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.voiceEnabled = true
        vm.voiceLocaleIdentifier = "es-ES"
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.voice.enabled == true)
        #expect(service.current.voice.localeIdentifier == "es-ES")
        #expect(vm.hasUnsavedChanges == false)
    }
}
