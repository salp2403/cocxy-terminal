// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AppearanceConfig — fontThicken defaults and init")
struct AppearanceConfigFontThickenTests {

    @Test func defaultsDisableFontThicken() {
        #expect(AppearanceConfig.defaults.fontThicken == false)
    }

    @Test func explicitFontThickenIsStored() {
        let config = AppearanceConfig(
            theme: "catppuccin-mocha",
            lightTheme: "catppuccin-latte",
            fontFamily: "JetBrainsMono Nerd Font Mono",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            ligatures: false,
            fontThicken: true,
            backgroundOpacity: 1.0,
            backgroundBlurRadius: 0
        )
        #expect(config.fontThicken == true)
    }

    @Test func initWithoutFontThickenDefaultsToFalse() {
        let config = AppearanceConfig(
            theme: "catppuccin-mocha",
            lightTheme: "catppuccin-latte",
            fontFamily: "JetBrainsMono Nerd Font Mono",
            fontSize: 14,
            tabPosition: .left,
            windowPadding: 8,
            windowPaddingX: nil,
            windowPaddingY: nil,
            backgroundOpacity: 1.0,
            backgroundBlurRadius: 0
        )
        #expect(config.fontThicken == false)
    }
}

@Suite("TerminalEngineConfig — fontThickenEnabled defaults and replacing")
struct TerminalEngineConfigFontThickenTests {

    private func makeConfig(fontThickenEnabled: Bool = false) -> TerminalEngineConfig {
        TerminalEngineConfig(
            fontFamily: "Menlo",
            fontSize: 14,
            themeName: "Catppuccin Mocha",
            shell: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            fontThickenEnabled: fontThickenEnabled
        )
    }

    @Test func defaultIsFalse() {
        let cfg = TerminalEngineConfig(
            fontFamily: "Menlo",
            fontSize: 14,
            themeName: "Catppuccin Mocha",
            shell: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(cfg.fontThickenEnabled == false)
    }

    @Test func explicitTrueIsStored() {
        let cfg = makeConfig(fontThickenEnabled: true)
        #expect(cfg.fontThickenEnabled == true)
    }

    @Test func replacingTogglesFlag() {
        let off = makeConfig(fontThickenEnabled: false)
        let on = off.replacing(fontThickenEnabled: true)
        #expect(on.fontThickenEnabled == true)

        let backOff = on.replacing(fontThickenEnabled: false)
        #expect(backOff.fontThickenEnabled == false)
    }

    @Test func replacingWithoutFontThickenPreservesCurrent() {
        let on = makeConfig(fontThickenEnabled: true)
        let touched = on.replacing(fontSize: 15)
        #expect(touched.fontThickenEnabled == true)
        #expect(touched.fontSize == 15)
    }
}

@Suite("PreferencesViewModel — fontThicken wiring")
@MainActor
struct PreferencesViewModelFontThickenTests {

    /// In-memory `ConfigFileProviding` used by these tests.
    ///
    /// Declared `@unchecked Sendable` because the protocol is `Sendable` but
    /// this helper owns a mutable `lastWrite` field. The tests run on the
    /// main actor and never share the instance across concurrency domains,
    /// so the `@unchecked` escape hatch is sound here. This matches the
    /// pattern used by the other in-memory providers under `Tests/Unit/…`.
    private final class InMemoryConfigFileProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        fontThicken: Bool
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
            fontThicken: fontThicken,
            backgroundOpacity: 1.0,
            backgroundBlurRadius: 0
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

    @Test func loadReflectsConfigValue() {
        let (off, _) = makeViewModel(fontThicken: false)
        #expect(off.fontThicken == false)

        let (on, _) = makeViewModel(fontThicken: true)
        #expect(on.fontThicken == true)
    }

    @Test func togglingMarksUnsavedChanges() {
        let (vm, _) = makeViewModel(fontThicken: false)
        #expect(vm.hasUnsavedChanges == false)
        vm.fontThicken = true
        #expect(vm.hasUnsavedChanges == true)
    }

    @Test func discardRestoresOriginalValue() {
        let (vm, _) = makeViewModel(fontThicken: false)
        vm.fontThicken = true
        vm.discardChanges()
        #expect(vm.fontThicken == false)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test func generatedTomlContainsFontThicken() {
        let (vm, _) = makeViewModel(fontThicken: false)
        vm.fontThicken = true
        let toml = vm.generateToml()
        #expect(toml.contains("font-thicken = true"))
    }

    @Test func saveWritesFontThickenAndResetsDirty() throws {
        let (vm, provider) = makeViewModel(fontThicken: false)
        vm.fontThicken = true
        try vm.save()
        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("font-thicken = true") == true)
    }
}
