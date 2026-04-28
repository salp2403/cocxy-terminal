// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickSwitchModePreferencesSwiftTestingTests.swift - Preferences
// coverage for the quickswitch-mode appearance setting.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — quickSwitchMode wiring")
@MainActor
struct PreferencesViewModelQuickSwitchModeTests {

    private final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        quickSwitchMode: QuickSwitchMode
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
            rateLimitIndicatorEnabled: true,
            quickSwitchMode: quickSwitchMode
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
        let (unified, _) = makeViewModel(quickSwitchMode: .unified)
        #expect(unified.quickSwitchMode == .unified)

        let (tabsOnly, _) = makeViewModel(quickSwitchMode: .tabsOnly)
        #expect(tabsOnly.quickSwitchMode == .tabsOnly)
    }

    @Test
    func changingModeMarksUnsavedChanges() {
        let (vm, _) = makeViewModel(quickSwitchMode: .unified)
        #expect(vm.hasUnsavedChanges == false)
        vm.quickSwitchMode = .tabsOnly
        #expect(vm.hasUnsavedChanges == true)
    }

    @Test
    func discardRestoresOriginalValue() {
        let (vm, _) = makeViewModel(quickSwitchMode: .tabsOnly)
        vm.quickSwitchMode = .unified
        vm.discardChanges()
        #expect(vm.quickSwitchMode == .tabsOnly)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test
    func generatedTomlContainsCurrentValue() {
        let (vm, _) = makeViewModel(quickSwitchMode: .unified)
        vm.quickSwitchMode = .tabsOnly
        let toml = vm.generateToml()
        #expect(toml.contains("quickswitch-mode = \"tabs-only\""))
    }

    @Test
    func saveWritesValueAndResetsDirty() throws {
        let (vm, provider) = makeViewModel(quickSwitchMode: .unified)
        vm.quickSwitchMode = .tabsOnly
        try vm.save()
        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("quickswitch-mode = \"tabs-only\"") == true)
    }

    @Test
    func savedSnapshotPreservesModeAfterRoundtripWhenViewModelDoesNotChangeIt() throws {
        let (vm, provider) = makeViewModel(quickSwitchMode: .tabsOnly)
        try vm.save()
        #expect(provider.lastWrite?.contains("quickswitch-mode = \"tabs-only\"") == true)
        #expect(vm.hasUnsavedChanges == false)
    }
}
