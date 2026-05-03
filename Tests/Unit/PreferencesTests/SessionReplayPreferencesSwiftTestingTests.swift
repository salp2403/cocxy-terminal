// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayPreferencesSwiftTestingTests.swift - Preferences coverage for `[session-replay]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Session Replay round-trip")
@MainActor
struct SessionReplayPreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        init(_ content: String? = nil) { self.content = content }
        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private func makeViewModel(config: CocxyConfig = .defaults) -> (PreferencesViewModel, InMemoryProvider) {
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("init populates Session Replay fields from the saved config")
    func initPopulatesSessionReplayFieldsFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            sessionReplay: SessionReplayConfig(
                enabled: true,
                autoRecord: true,
                consentGranted: true,
                storageDirectory: "~/.cocxy/replays",
                maxRecordingBytes: 1_048_576
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.sessionReplayEnabled == true)
        #expect(vm.sessionReplayAutoRecord == true)
        #expect(vm.sessionReplayConsentGranted == true)
        #expect(vm.sessionReplayStorageDirectory == "~/.cocxy/replays")
        #expect(vm.sessionReplayMaxRecordingBytes == 1_048_576)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Session Replay fields marks Preferences dirty and discard restores")
    func changingSessionReplayFieldsMarksDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        vm.sessionReplayEnabled = true
        vm.sessionReplayAutoRecord = true
        vm.sessionReplayConsentGranted = true
        vm.sessionReplayStorageDirectory = "~/.cocxy/replays"
        vm.sessionReplayMaxRecordingBytes = 1_048_576

        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.sessionReplayEnabled == false)
        #expect(vm.sessionReplayAutoRecord == false)
        #expect(vm.sessionReplayConsentGranted == false)
        #expect(vm.sessionReplayStorageDirectory == SessionReplayConfig.defaults.storageDirectory)
        #expect(vm.sessionReplayMaxRecordingBytes == SessionReplayConfig.defaults.maxRecordingBytes)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("disabling Session Replay clears auto-record and consent in generated config")
    func disablingSessionReplayClearsAutoRecordAndConsentInGeneratedConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            sessionReplay: SessionReplayConfig(
                enabled: true,
                autoRecord: true,
                consentGranted: true
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.sessionReplayEnabled = false

        let toml = vm.generateToml()
        #expect(toml.contains("[session-replay]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("auto-record = false"))
        #expect(toml.contains("consent-granted = false"))
    }

    @Test("save then reload preserves Session Replay fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.sessionReplayEnabled = true
        vm.sessionReplayAutoRecord = true
        vm.sessionReplayConsentGranted = true
        vm.sessionReplayStorageDirectory = "~/.cocxy/replays"
        vm.sessionReplayMaxRecordingBytes = 1_048_576
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.sessionReplay.enabled == true)
        #expect(service.current.sessionReplay.autoRecord == true)
        #expect(service.current.sessionReplay.consentGranted == true)
        #expect(service.current.sessionReplay.storageDirectory == "~/.cocxy/replays")
        #expect(service.current.sessionReplay.maxRecordingBytes == 1_048_576)
        #expect(vm.hasUnsavedChanges == false)
    }
}
