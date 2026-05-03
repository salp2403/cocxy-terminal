// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityPreferencesSwiftTestingTests.swift - Preferences coverage for `[activity]`.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - Activity round-trip")
@MainActor
struct ActivityPreferencesSwiftTestingTests {
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

    @Test("init populates Activity fields from the saved config")
    func initPopulatesActivityFieldsFromConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            activity: ActivityConfig(
                enabled: true,
                costTrackingEnabled: true,
                inputCostMicrosPerMillionTokens: 1_250_000,
                outputCostMicrosPerMillionTokens: 10_000_000
            ),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )

        let (vm, _) = makeViewModel(config: config)

        #expect(vm.activityTrackingEnabled == true)
        #expect(vm.activityCostTrackingEnabled == true)
        #expect(vm.activityInputCostMicrosPerMillionTokens == 1_250_000)
        #expect(vm.activityOutputCostMicrosPerMillionTokens == 10_000_000)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("changing Activity fields marks Preferences dirty and discard restores")
    func changingActivityFieldsMarksPreferencesDirtyAndDiscardRestores() {
        let (vm, _) = makeViewModel()

        vm.activityTrackingEnabled = true
        vm.activityCostTrackingEnabled = true
        vm.activityInputCostMicrosPerMillionTokens = 1_250_000
        vm.activityOutputCostMicrosPerMillionTokens = 10_000_000

        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.activityTrackingEnabled == false)
        #expect(vm.activityCostTrackingEnabled == false)
        #expect(vm.activityInputCostMicrosPerMillionTokens == 0)
        #expect(vm.activityOutputCostMicrosPerMillionTokens == 0)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test("disabling Activity also disables cost tracking in generated config")
    func disablingActivityAlsoDisablesCostTrackingInGeneratedConfig() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            activity: ActivityConfig(enabled: true, costTrackingEnabled: true),
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let (vm, _) = makeViewModel(config: config)

        vm.activityTrackingEnabled = false

        let toml = vm.generateToml()
        #expect(toml.contains("[activity]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("cost-tracking = false"))
    }

    @Test("save then reload preserves Activity fields")
    func saveReloadRoundTrip() throws {
        let (vm, provider) = makeViewModel()

        vm.activityTrackingEnabled = true
        vm.activityCostTrackingEnabled = true
        vm.activityInputCostMicrosPerMillionTokens = 1_250_000
        vm.activityOutputCostMicrosPerMillionTokens = 10_000_000
        try vm.save()

        let written = try #require(provider.content)
        let service = ConfigService(fileProvider: InMemoryProvider(written))
        try service.reload()

        #expect(service.current.activity.enabled == true)
        #expect(service.current.activity.costTrackingEnabled == true)
        #expect(service.current.activity.inputCostMicrosPerMillionTokens == 1_250_000)
        #expect(service.current.activity.outputCostMicrosPerMillionTokens == 10_000_000)
        #expect(vm.hasUnsavedChanges == false)
    }
}
