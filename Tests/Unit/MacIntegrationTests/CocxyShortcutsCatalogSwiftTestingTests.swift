// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Cocxy Shortcuts catalog")
struct CocxyShortcutsCatalogSwiftTestingTests {

    @Test("catalog exposes local only shortcuts with explicit privacy boundaries")
    func catalogExposesLocalOnlyShortcuts() {
        let descriptors = CocxyShortcutsCatalog.descriptors

        #expect(descriptors.map(\.id) == [
            "open-app",
            "run-command",
            "open-notebook",
            "list-skills",
        ])
        #expect(descriptors.allSatisfy { $0.requiresUserInitiation })
        #expect(descriptors.allSatisfy { $0.networkPolicy == .localOnly })
        #expect(descriptors.allSatisfy { !$0.title.isEmpty })
        #expect(descriptors.allSatisfy { !$0.privacySummary.isEmpty })
    }

    @Test("catalog localizes shortcut copy and local error messages")
    func catalogLocalizesShortcutCopyAndErrors() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let descriptors = CocxyShortcutsCatalog.descriptors(localizer: spanish)

        #expect(descriptors[0].title == "Abrir Cocxy")
        #expect(descriptors[0].summary == "Traer al frente la ventana local de terminal.")
        #expect(descriptors[0].privacySummary == "Solo activa la app local; ningún contenido de terminal sale de la Mac.")
        #expect(descriptors[1].title == "Ejecutar comando en Cocxy")
        #expect(descriptors[1].summary == "Enviar texto a la terminal local enfocada y opcionalmente presionar Return.")
        #expect(CocxyShortcutError.noActiveTerminal.localizedDescription(using: spanish) == "No hay una superficie de terminal activa disponible.")
    }

    @Test("Shortcuts AppIntent literals are covered by localization resources")
    func appIntentLiteralsAreCoveredByLocalizationResources() throws {
        let bundle = try #require(localizationBundle())
        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        let literals = [
            "Open Cocxy",
            "Bring the local Cocxy Terminal window forward.",
            "Run Command in Cocxy",
            "Send text to the focused Cocxy terminal and optionally press Return.",
            "Command",
            "Press Return",
            "Open Cocxy Notebook",
            "Open a local Cocxy notebook panel in the current workspace.",
            "List Cocxy Skills",
            "Return local Cocxy skill identifiers.",
            "Run Command",
            "Open Notebook",
            "List Skills",
        ]

        for literal in literals {
            #expect(english.string(literal, fallback: "") == literal)
            #expect(spanish.string(literal, fallback: literal) != literal)
        }
        #expect(spanish.string("Run Command", fallback: "Run Command") == "Ejecutar comando")
        #expect(spanish.string("Open Notebook", fallback: "Open Notebook") == "Abrir notebook")
    }

    @Test("app bundle scripts emit and verify Shortcuts metadata")
    func appBundleScriptsEmitAndVerifyShortcutsMetadata() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("appintentsmetadataprocessor"))
        #expect(buildScript.contains("SwiftConstantValues/AppIntents.json"))
        #expect(buildScript.contains("--product \"${APP_NAME}\""))
        #expect(buildScript.contains("Metadata.appintents"))
        #expect(verifyScript.contains("[Shortcuts]"))
        #expect(verifyScript.contains("Metadata.appintents"))
    }

    @Test("app bundle script rejects stale empty Shortcuts const values")
    func appBundleScriptRejectsStaleEmptyShortcutsConstValues() throws {
        let root = repositoryRoot()
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("App Intents const values did not contain AppIntent metadata"))
        #expect(buildScript.contains("\"AppIntents.AppIntent\""))
        #expect(buildScript.contains("CocxyShortcuts.*"))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let package = url.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: package.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func localizationBundle() -> Bundle? {
        Bundle(url: repositoryRoot().appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
