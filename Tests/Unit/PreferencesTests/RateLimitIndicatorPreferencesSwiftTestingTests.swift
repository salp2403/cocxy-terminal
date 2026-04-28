// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitIndicatorPreferencesSwiftTestingTests.swift - Preferences
// coverage for the rate-limit-indicator-enabled appearance flag.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `PreferencesViewModel` wiring for the new
/// `appearance.rateLimitIndicatorEnabled` flag. Mirrors the layout of
/// `PreferencesViewModelAuroraEnabledTests` so future config flags can
/// be added against the same canonical pattern documented in
/// `feedback_config_field_pipeline`.
@Suite("PreferencesViewModel — rateLimitIndicatorEnabled wiring")
@MainActor
struct PreferencesViewModelRateLimitIndicatorTests {

    private final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        rateLimitIndicatorEnabled: Bool
    ) -> (PreferencesViewModel, InMemoryConfigFileProvider) {
        let appearance = AppearanceConfig(
            theme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            fontFamily: "JetBrainsMono Nerd Font Mono",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            ligatures: false,
            fontThicken: false,
            backgroundOpacity: 1.0,
            backgroundBlurRadius: 0,
            auroraEnabled: true,
            rateLimitIndicatorEnabled: rateLimitIndicatorEnabled
        )
        let config = CocxyConfig(
            general: .defaults,
            appearance: appearance,
            terminal: .defaults,
            agentDetection: .defaults,
            codeReview: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let provider = InMemoryConfigFileProvider()
        let vm = PreferencesViewModel(config: config, fileProvider: provider)
        return (vm, provider)
    }

    @Test
    func loadReflectsConfigValue() {
        let (off, _) = makeViewModel(rateLimitIndicatorEnabled: false)
        #expect(off.rateLimitIndicatorEnabled == false)

        let (on, _) = makeViewModel(rateLimitIndicatorEnabled: true)
        #expect(on.rateLimitIndicatorEnabled == true)
    }

    @Test
    func togglingMarksUnsavedChanges() {
        let (vm, _) = makeViewModel(rateLimitIndicatorEnabled: true)
        #expect(vm.hasUnsavedChanges == false)
        vm.rateLimitIndicatorEnabled = false
        #expect(vm.hasUnsavedChanges == true)
    }

    @Test
    func discardRestoresOriginalValue() {
        let (vm, _) = makeViewModel(rateLimitIndicatorEnabled: true)
        vm.rateLimitIndicatorEnabled = false
        vm.discardChanges()
        #expect(vm.rateLimitIndicatorEnabled == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test
    func generatedTomlContainsCurrentValue() {
        let (vm, _) = makeViewModel(rateLimitIndicatorEnabled: true)
        vm.rateLimitIndicatorEnabled = false
        let toml = vm.generateToml()
        #expect(toml.contains("rate-limit-indicator-enabled = false"))
    }

    @Test
    func saveWritesValueAndResetsDirty() throws {
        let (vm, provider) = makeViewModel(rateLimitIndicatorEnabled: true)
        vm.rateLimitIndicatorEnabled = false
        try vm.save()
        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("rate-limit-indicator-enabled = false") == true)
    }

    @Test
    func savedSnapshotPreservesFlagAfterRoundtripWhenViewModelDoesNotChangeIt() throws {
        // Regression guard for the canonical bug shipped by Aurora and
        // documented in `feedback_config_field_pipeline`: an
        // `updateSavedSnapshot` rebuild that omits a field silently
        // resets it to the default at save time. With the field wired
        // through, saving without touching it must preserve `false`.
        let (vm, provider) = makeViewModel(rateLimitIndicatorEnabled: false)
        try vm.save()
        #expect(provider.lastWrite?.contains("rate-limit-indicator-enabled = false") == true)
    }
}
