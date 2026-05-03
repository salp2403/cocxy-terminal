// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraEnabledPreferencesSwiftTestingTests.swift - Preferences coverage for
// the aurora-enabled appearance flag.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — auroraEnabled wiring")
@MainActor
struct PreferencesViewModelAuroraEnabledTests {

    private final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        auroraEnabled: Bool,
        displayMode: AuroraSidebarDisplayMode = .detailed,
        primaryInfo: AuroraSidebarPrimaryInfo = .state
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
            auroraEnabled: auroraEnabled,
            auroraSidebarDisplayMode: displayMode,
            auroraSidebarPrimaryInfo: primaryInfo
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
        let (off, _) = makeViewModel(auroraEnabled: false)
        #expect(off.auroraEnabled == false)

        let (on, _) = makeViewModel(auroraEnabled: true)
        #expect(on.auroraEnabled == true)
    }

    @Test
    func loadReflectsSidebarDisplayChoices() {
        let (vm, _) = makeViewModel(
            auroraEnabled: true,
            displayMode: .compact,
            primaryInfo: .command
        )

        #expect(vm.auroraSidebarDisplayMode == .compact)
        #expect(vm.auroraSidebarPrimaryInfo == .command)
    }

    @Test
    func togglingMarksUnsavedChanges() {
        let (vm, _) = makeViewModel(auroraEnabled: false)
        #expect(vm.hasUnsavedChanges == false)
        vm.auroraEnabled = true
        #expect(vm.hasUnsavedChanges == true)
    }

    @Test
    func discardRestoresOriginalValue() {
        let (vm, _) = makeViewModel(auroraEnabled: true)
        vm.auroraEnabled = false
        vm.discardChanges()
        #expect(vm.auroraEnabled == true)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test
    func generatedTomlContainsCurrentValue() {
        let (vm, _) = makeViewModel(auroraEnabled: false)
        vm.auroraEnabled = true
        vm.auroraSidebarDisplayMode = .summary
        vm.auroraSidebarPrimaryInfo = .process
        let toml = vm.generateToml()
        #expect(toml.contains("aurora-enabled = true"))
        #expect(toml.contains("aurora-sidebar-display-mode = \"summary\""))
        #expect(toml.contains("aurora-sidebar-primary-info = \"process\""))
    }

    @Test
    func classicTabPositionPickerIsDisabledOnlyWhileAuroraIsEnabled() {
        let (vm, _) = makeViewModel(auroraEnabled: false)
        #expect(vm.isClassicTabPositionEditable == true)

        vm.auroraEnabled = true
        #expect(vm.isClassicTabPositionEditable == false)

        vm.auroraEnabled = false
        #expect(vm.isClassicTabPositionEditable == true)
    }

    @Test
    func saveWritesAuroraEnabledAndResetsDirty() throws {
        let (vm, provider) = makeViewModel(auroraEnabled: false)
        vm.auroraEnabled = true
        vm.auroraSidebarDisplayMode = .compact
        vm.auroraSidebarPrimaryInfo = .directory
        try vm.save()
        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("aurora-enabled = true") == true)
        #expect(provider.lastWrite?.contains("aurora-sidebar-display-mode = \"compact\"") == true)
        #expect(provider.lastWrite?.contains("aurora-sidebar-primary-info = \"directory\"") == true)
    }
}
