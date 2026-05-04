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
