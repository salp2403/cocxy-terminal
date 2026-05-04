// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLocalizationSwiftTestingTests.swift - Local app-language resolver tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("App localization")
struct AppLocalizationSwiftTestingTests {

    @Test
    func normalizesLanguageIdentifiers() {
        #expect(AppLanguage.normalized("system") == .system)
        #expect(AppLanguage.normalized("en-US") == .english)
        #expect(AppLanguage.normalized("es_HN") == .spanish)
        #expect(AppLanguage.normalized("fr") == nil)
    }

    @Test
    func systemPreferenceResolvesFirstSupportedLocale() {
        let spanish = AppLocalizationResolver(preferredLanguageIdentifiers: ["fr-FR", "es-HN"])
        let fallback = AppLocalizationResolver(preferredLanguageIdentifiers: ["fr-FR"])

        #expect(spanish.resolve(.system) == .spanish)
        #expect(fallback.resolve(.system) == .english)
        #expect(fallback.resolve(.spanish) == .spanish)
    }

    @Test
    func localizerLoadsEnglishAndSpanishResources() throws {
        let bundle = try #require(localizationBundle())

        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(english.string(.preferencesAppearanceLanguageTitle) == "Language")
        #expect(spanish.string(.preferencesAppearanceLanguageTitle) == "Idioma")
        #expect(spanish.string(.preferencesAppearanceLanguagePicker) == "Idioma de la app")
        #expect(spanish.string("preferences.section.appearance", fallback: "Appearance") == "Apariencia")
        #expect(spanish.string("preferences.save.button", fallback: "Save") == "Guardar")
        #expect(spanish.string("preferences.general.shellPath", fallback: "Shell path") == "Ruta del shell")
        #expect(spanish.string("preferences.appearance.fontSize", fallback: "Font size") == "Tamaño de fuente")
        #expect(spanish.string("preferences.appearance.glassChromeTint.dark", fallback: "Dark") == "Oscuro")
        #expect(spanish.string("preferences.appearance.fontResolution.included", fallback: "Included with Cocxy: %@") == "Incluida con Cocxy: %@")
        #expect(spanish.string("preferences.appearance.sidebarDensity.detailed", fallback: "Detailed") == "Detallada")
        #expect(spanish.string("preferences.appearance.sidebarRowDetail.state", fallback: "State") == "Estado")
        #expect(spanish.string("preferences.agentDetection.idleTimeout", fallback: "Idle timeout: %d s") == "Timeout de inactividad: %d s")
        #expect(spanish.string("preferences.voice.recognitionLocale", fallback: "Recognition locale") == "Idioma de reconocimiento")
        #expect(spanish.string("preferences.activity.trackCosts", fallback: "Track token usage and estimated costs") == "Registrar uso de tokens y costos estimados")
        #expect(spanish.string("preferences.sessionReplay.storageDirectory", fallback: "Storage directory") == "Directorio de almacenamiento")
        #expect(spanish.string("preferences.backup.enable", fallback: "Enable local automatic backups") == "Activar copias automáticas locales")
        #expect(spanish.string("preferences.backup.artifact.aiConversations", fallback: "AI conversations") == "Conversaciones IA")
        #expect(spanish.string("preferences.codeReview.autoShow", fallback: "Auto-show review panel when an agent session ends") == "Mostrar panel de revisión automáticamente cuando termina una sesión de agente")
        #expect(spanish.string("preferences.notifications.dockBadge", fallback: "Dock badge") == "Badge en el Dock")
        #expect(spanish.string("preferences.terminal.imageMemoryBudget", fallback: "Image memory budget: %d MiB") == "Memoria para imágenes: %d MiB")
        #expect(spanish.string("preferences.lsp.enable", fallback: "Enable language servers") == "Activar servidores de lenguaje")
        #expect(spanish.string("preferences.editor.enableVimMode", fallback: "Enable Vim mode") == "Activar modo Vim")
        #expect(spanish.string("preferences.editor.contextWindow", fallback: "Context window: %d UTF-16") == "Ventana de contexto: %d UTF-16")
        #expect(spanish.string("preferences.worktrees.enable", fallback: "Enable worktrees") == "Activar worktrees")
        #expect(spanish.string("preferences.worktrees.onClose.remove", fallback: "Remove if clean") == "Eliminar si está limpio")
        #expect(spanish.string("preferences.agentMode.enable", fallback: "Enable Agent Mode") == "Activar modo agente")
        #expect(spanish.string("preferences.agentMode.apiKey.saved", fallback: "A key is saved in the macOS Keychain for this provider.") == "Hay una llave guardada en Keychain de macOS para este provider.")
        #expect(spanish.string("preferences.mcp.configFile.section", fallback: "Config File") == "Archivo de configuración")
        #expect(spanish.string("preferences.mcp.noServers", fallback: "No MCP servers configured.") == "No hay servidores MCP configurados.")
        #expect(spanish.string("preferences.iCloud.enable", fallback: "Enable iCloud Drive sync") == "Activar sincronización con iCloud Drive")
        #expect(spanish.string("preferences.iCloud.artifact.settings", fallback: "Settings") == "Ajustes")
        #expect(spanish.string("preferences.iCloud.export", fallback: "Export Encrypted Artifacts") == "Exportar artefactos cifrados")
        #expect(spanish.string("preferences.iCloud.conflict.useRemote", fallback: "Use Remote") == "Usar remoto")
        #expect(spanish.string("preferences.github.enable", fallback: "Enable GitHub pane") == "Activar panel de GitHub")
        #expect(spanish.string("preferences.github.defaultState.merged", fallback: "Merged (PRs only)") == "Fusionados (solo PRs)")
        #expect(spanish.string("preferences.about.subtitle", fallback: "Agent-aware terminal for macOS") == "Terminal para macOS con conciencia de agentes")
        #expect(spanish.string("preferences.about.checkForUpdates", fallback: "Check for Updates") == "Buscar actualizaciones")
        #expect(spanish.string("app.crashRecovery.restore.button", fallback: "Restore") == "Restaurar")
        #expect(spanish.string("app.quit.message", fallback: "All terminal sessions will be closed.") == "Todas las sesiones de terminal se cerrarán.")
        #expect(spanish.string("common.cancel", fallback: "Cancel") == "Cancelar")
    }

    @Test
    func localizerLoadsCommandPaletteResources() throws {
        let bundle = try #require(localizationBundle())

        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(english.string("command.tabs.new.name", fallback: "New Tab") == "New Tab")
        #expect(spanish.string("command.tabs.new.name", fallback: "New Tab") == "Nueva pestaña")
        #expect(spanish.string("command.category.tabs", fallback: "Tabs") == "Pestañas")
        #expect(spanish.string("commandPalette.empty", fallback: "No commands found") == "No se encontraron comandos")
        #expect(spanish.string("commandPalette.footer.navigate", fallback: "Navigate") == "Navegar")
        #expect(spanish.string("commandPalette.footer.action.plural", fallback: "actions") == "acciones")
    }

    @Test
    func auroraCommandPaletteStringsLocalizeChrome() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        let strings = Design.AuroraPaletteStrings(localizer: spanish)

        #expect(strings.accessibilityLabel == "Paleta de comandos")
        #expect(strings.searchPlaceholder == "Escribe un comando...")
        #expect(strings.searchAccessibilityLabel == "Buscar en la paleta de comandos")
        #expect(strings.emptyMessage == "No se encontraron comandos")
        #expect(strings.navigateHint == "Navegar")
        #expect(strings.selectHint == "Seleccionar")
        #expect(strings.closeHint == "Cerrar")
        #expect(strings.actionCountLabel(for: 1) == "1 acción")
        #expect(strings.actionCountLabel(for: 2) == "2 acciones")
    }

    @Test
    func localizerLoadsWelcomeAndOnboardingResources() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("welcome.subtitle", fallback: "Agent-aware terminal for macOS") == "Terminal para macOS con conciencia de agentes")
        #expect(spanish.string("welcome.getStarted", fallback: "Get Started") == "Comenzar")
        #expect(spanish.string("welcome.shortcut.commandPalette", fallback: "Command Palette") == "Paleta de comandos")
        #expect(spanish.string("onboarding.title", fallback: "Cocxy Setup") == "Configuración de Cocxy")
        #expect(spanish.string("onboarding.subtitle", fallback: "Choose local defaults for this Mac") == "Elige valores predeterminados locales para esta Mac")
        #expect(spanish.string("onboarding.enableLanguageServers", fallback: "Enable language servers") == "Activar servidores de lenguaje")
        #expect(spanish.string("onboarding.apply", fallback: "Apply") == "Aplicar")
        #expect(spanish.string("onboarding.error.apply", fallback: "Unable to apply onboarding settings.") == "No se pudieron aplicar los ajustes de onboarding.")
    }

    @MainActor
    @Test
    func commandPaletteViewModelLocalizesActionsAndSearchesSpanish() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = CommandPaletteViewModel(
            engine: CommandPaletteEngineImpl(),
            localizer: localizer
        )

        let newTab = try #require(viewModel.filteredActions.first { $0.id == "tabs.new" })
        #expect(newTab.name == "Nueva pestaña")
        #expect(newTab.description == "Abrir una nueva pestaña de terminal")
        #expect(viewModel.localizedCategoryTitle(.tabs) == "Pestañas")

        viewModel.query = "pesta"

        #expect(viewModel.filteredActions.contains { $0.id == "tabs.new" })
    }

    @MainActor
    @Test
    func commandActionLocalizationPreservesDynamicPictureInPictureState() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let disabled = CommandAction(
            id: "window.pictureInPicture",
            name: "Float Active Terminal",
            description: "Enable [experimental].pip-enabled to use terminal Picture-in-Picture",
            shortcut: nil,
            category: .navigation,
            handler: {}
        ).localized(using: localizer)
        let enabled = CommandAction(
            id: "window.pictureInPicture",
            name: "Float Active Terminal",
            description: "Move the active terminal into a floating Picture-in-Picture panel",
            shortcut: nil,
            category: .navigation,
            handler: {}
        ).localized(using: localizer)

        #expect(disabled.description == "Activa [experimental].pip-enabled para usar Picture-in-Picture del terminal")
        #expect(enabled.description == "Mover el terminal activo a un panel flotante Picture-in-Picture")
    }

    @Test
    func buildAndVerifyScriptsIncludeLocalizationResources() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("Resources/Localization"))
        #expect(verifyScript.contains("en.lproj/Localizable.strings"))
        #expect(verifyScript.contains("es.lproj/Localizable.strings"))
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
