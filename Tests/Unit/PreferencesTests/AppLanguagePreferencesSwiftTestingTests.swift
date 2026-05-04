// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLanguagePreferencesSwiftTestingTests.swift - Preferences coverage for
// the app-language appearance setting.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - appLanguage wiring")
@MainActor
struct AppLanguagePreferencesSwiftTestingTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?
        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func makeViewModel(
        appLanguage: AppLanguage
    ) -> (PreferencesViewModel, InMemoryProvider) {
        let base = CocxyConfig.defaults
        let appearance = AppearanceConfig(
            theme: base.appearance.theme,
            lightTheme: base.appearance.lightTheme,
            fontFamily: base.appearance.fontFamily,
            fontSize: base.appearance.fontSize,
            tabPosition: base.appearance.tabPosition,
            windowPadding: base.appearance.windowPadding,
            windowPaddingX: base.appearance.windowPaddingX,
            windowPaddingY: base.appearance.windowPaddingY,
            ligatures: base.appearance.ligatures,
            fontThicken: base.appearance.fontThicken,
            backgroundOpacity: base.appearance.backgroundOpacity,
            backgroundBlurRadius: base.appearance.backgroundBlurRadius,
            transparencyChromeTheme: base.appearance.transparencyChromeTheme,
            auroraEnabled: base.appearance.auroraEnabled,
            auroraSidebarDisplayMode: base.appearance.auroraSidebarDisplayMode,
            auroraSidebarPrimaryInfo: base.appearance.auroraSidebarPrimaryInfo,
            rateLimitIndicatorEnabled: base.appearance.rateLimitIndicatorEnabled,
            quickSwitchMode: base.appearance.quickSwitchMode,
            appLanguage: appLanguage
        )
        let config = CocxyConfig(
            general: base.general,
            appearance: appearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions
        )
        let provider = InMemoryProvider()
        return (
            PreferencesViewModel(
                config: config,
                fileProvider: provider,
                appLocalizationBundle: localizationBundle() ?? .main
            ),
            provider
        )
    }

    @Test
    func loadReflectsConfigValueAndAvailableLanguages() {
        let (vm, _) = makeViewModel(appLanguage: .spanish)

        #expect(vm.appLanguage == .spanish)
        #expect(vm.availableAppLanguages == [.system, .english, .spanish])
    }

    @Test
    func changingLanguageMarksUnsavedChangesAndDiscardRestores() {
        let (vm, _) = makeViewModel(appLanguage: .system)

        #expect(vm.hasUnsavedChanges == false)
        vm.appLanguage = .spanish
        #expect(vm.hasUnsavedChanges == true)

        vm.discardChanges()

        #expect(vm.appLanguage == .system)
        #expect(vm.hasUnsavedChanges == false)
    }

    @Test
    func generatedTomlContainsCurrentLanguage() {
        let (vm, _) = makeViewModel(appLanguage: .system)
        vm.appLanguage = .spanish

        let toml = vm.generateToml()

        #expect(toml.contains("app-language = \"es\""))
    }

    @Test
    func saveWritesLanguageAndResetsDirty() throws {
        let (vm, provider) = makeViewModel(appLanguage: .system)
        vm.appLanguage = .english

        try vm.save()

        #expect(vm.hasUnsavedChanges == false)
        #expect(provider.lastWrite?.contains("app-language = \"en\"") == true)
    }

    @Test
    func localizedPreferenceStringsFollowSelectedLanguage() {
        let (vm, _) = makeViewModel(appLanguage: .spanish)

        #expect(vm.localizedString(.preferencesAppearanceLanguageTitle) == "Idioma")
        #expect(vm.localizedString(.preferencesAppearanceLanguagePicker) == "Idioma de la app")
        #expect(vm.localizedString("preferences.save.button", fallback: "Save") == "Guardar")
        #expect(vm.localizedString("preferences.general.shellPath", fallback: "Shell path") == "Ruta del shell")
        #expect(vm.localizedString("preferences.appearance.activeTheme", fallback: "Active theme") == "Tema activo")
        #expect(vm.localizedString("preferences.agentDetection.enabled", fallback: "Enabled") == "Activada")
        #expect(vm.localizedString("preferences.voice.systemLocale", fallback: "System") == "Sistema")
        #expect(vm.localizedString("preferences.activity.localDirectory", fallback: "Local directory") == "Directorio local")
        #expect(vm.localizedString("preferences.sessionReplay.enable", fallback: "Enable Session Replay") == "Activar reproducción de sesiones")
        #expect(vm.localizedString("preferences.backup.defaultLocation", fallback: "Default location: %@") == "Ubicación predeterminada: %@")
        #expect(vm.localizedString("preferences.codeReview.panel.section", fallback: "Panel") == "Panel")
        #expect(vm.localizedString("preferences.notifications.visual.section", fallback: "Visual Indicators") == "Indicadores visuales")
        #expect(vm.localizedString("preferences.terminal.cursorBlink.on", fallback: "On") == "Activado")
        #expect(vm.localizedString("preferences.lsp.languages.section", fallback: "Languages") == "Lenguajes")
        #expect(vm.localizedString("preferences.editor.inlineCompletions.section", fallback: "Inline Completions") == "Completados inline")
        #expect(vm.localizedString("preferences.worktrees.randomIDLength", fallback: "Random id length: %d") == "Longitud de id aleatorio: %d")
        #expect(vm.localizedString("preferences.agentMode.provider.detail.remote", fallback: "Uses your provider API key from the macOS Keychain. Requests go directly from this Mac to the selected provider.") == "Usa la llave API del provider guardada en Keychain de macOS. Las solicitudes van directamente desde esta Mac al provider seleccionado.")
        #expect(vm.localizedString("preferences.mcp.save", fallback: "Save MCP Config") == "Guardar configuración MCP")
        #expect(vm.localizedString("preferences.iCloud.status.exported.many", fallback: "Exported %d encrypted artifacts.") == "%d artefactos cifrados exportados.")
        #expect(vm.localizedString("preferences.iCloud.conflict.versionsDiffer", fallback: "Local and remote versions differ.") == "Las versiones local y remota son diferentes.")
        #expect(vm.localizedString("preferences.github.autoRefresh", fallback: "Auto-refresh every %d s") == "Auto-refrescar cada %d s")
        #expect(vm.localizedString("preferences.about.updates", fallback: "Updates") == "Actualizaciones")
        #expect(PreferencesSection.appearance.localizedTitle(vm) == "Apariencia")
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
