// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TransparencyChromeThemeTests.swift - Tests the transparency-chrome-theme
// picker wiring inside PreferencesViewModel.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel — transparency chrome theme wiring")
@MainActor
struct PreferencesViewModelTransparencyChromeThemeTests {

    /// In-memory ConfigFileProviding used by these tests.
    ///
    /// Mirrors the pattern in FontThickenSwiftTests: the provider is
    /// `Sendable` by protocol, but the mutable `lastWrite` field means we
    /// need `@unchecked Sendable`. Tests run on the main actor and don't
    /// share the instance across concurrency domains.
    private final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeConfig(
        backgroundOpacity: Double = 0.9,
        transparencyChromeTheme: TransparencyChromeTheme = .followSystem
    ) -> CocxyConfig {
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
            backgroundOpacity: backgroundOpacity,
            backgroundBlurRadius: 0,
            transparencyChromeTheme: transparencyChromeTheme
        )
        return CocxyConfig(
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
    }

    private func makeViewModel(
        backgroundOpacity: Double = 0.9,
        transparencyChromeTheme: TransparencyChromeTheme = .followSystem
    ) -> (PreferencesViewModel, InMemoryConfigFileProvider) {
        let config = makeConfig(
            backgroundOpacity: backgroundOpacity,
            transparencyChromeTheme: transparencyChromeTheme
        )
        let provider = InMemoryConfigFileProvider()
        let vm = PreferencesViewModel(config: config, fileProvider: provider)
        return (vm, provider)
    }

    // MARK: - Load

    @Test
    func loadReflectsFollowSystem() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .followSystem)
        #expect(vm.transparencyChromeTheme == .followSystem)
    }

    @Test
    func loadReflectsLight() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .light)
        #expect(vm.transparencyChromeTheme == .light)
    }

    @Test
    func loadReflectsDark() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .dark)
        #expect(vm.transparencyChromeTheme == .dark)
    }

    // MARK: - Editable flag

    @Test
    func pickerDisabledWhenBackgroundOpacityIsFullyOpaque() {
        let (vm, _) = makeViewModel(backgroundOpacity: 1.0)
        #expect(vm.isTransparencyChromeThemeEditable == false)
    }

    @Test
    func pickerEnabledWhenBackgroundOpacityBelowOne() {
        let (vm, _) = makeViewModel(backgroundOpacity: 0.85)
        #expect(vm.isTransparencyChromeThemeEditable == true)
    }

    @Test
    func pickerEnabledFlagTracksOpacityMutation() {
        let (vm, _) = makeViewModel(backgroundOpacity: 0.85)
        #expect(vm.isTransparencyChromeThemeEditable == true)
        vm.backgroundOpacity = 1.0
        #expect(vm.isTransparencyChromeThemeEditable == false)
    }

    // MARK: - Dirty tracking

    @Test
    func changingSelectionUpdatesConfig() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .followSystem)
        #expect(vm.hasUnsavedChanges == false)
        vm.transparencyChromeTheme = .dark
        #expect(vm.hasUnsavedChanges == true)
        #expect(vm.transparencyChromeTheme == .dark)
    }

    @Test
    func discardRestoresOriginalSelection() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .followSystem)
        vm.transparencyChromeTheme = .light
        vm.discardChanges()
        #expect(vm.transparencyChromeTheme == .followSystem)
        #expect(vm.hasUnsavedChanges == false)
    }

    // MARK: - Persistence

    @Test
    func changingSelectionPersistsViaConfigService() throws {
        let (vm, provider) = makeViewModel(transparencyChromeTheme: .followSystem)
        vm.transparencyChromeTheme = .dark
        try vm.save()

        let written = provider.lastWrite ?? ""
        #expect(written.contains("transparency-chrome-theme = \"dark\""))
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test
    func generatedTomlContainsCurrentSelection() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .followSystem)
        vm.transparencyChromeTheme = .light
        let toml = vm.generateToml()
        #expect(toml.contains("transparency-chrome-theme = \"light\""))
    }

    @Test
    func generatedTomlContainsFollowSystemAfterRevert() {
        let (vm, _) = makeViewModel(transparencyChromeTheme: .dark)
        vm.transparencyChromeTheme = .followSystem
        let toml = vm.generateToml()
        #expect(toml.contains("transparency-chrome-theme = \"follow-system\""))
    }
}

@Suite("TransparencyChromeTheme — NSAppearance resolution")
struct TransparencyChromeThemeVibrancyAppearanceTests {

    @Test
    func followSystemResolvesToNil() {
        #expect(TransparencyChromeTheme.followSystem.vibrancyAppearance == nil)
    }

    @Test
    func lightResolvesToAqua() {
        let appearance = TransparencyChromeTheme.light.vibrancyAppearance
        #expect(appearance?.name == .aqua)
    }

    @Test
    func darkResolvesToDarkAqua() {
        let appearance = TransparencyChromeTheme.dark.vibrancyAppearance
        #expect(appearance?.name == .darkAqua)
    }

    @Test
    func allCasesEnumerated() {
        // Guards against accidentally adding a case without updating the
        // vibrancyAppearance resolver. If a new case ships without a
        // switch arm, this test forces a compile error; if it ships with
        // the wrong arm, the other tests catch it.
        let cases = TransparencyChromeTheme.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.followSystem))
        #expect(cases.contains(.light))
        #expect(cases.contains(.dark))
    }
}
