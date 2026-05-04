// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuBarStatusItemSwiftTestingTests.swift - Menu bar copy localization tests.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Menu bar status item")
struct MenuBarStatusItemSwiftTestingTests {

    @Test
    func spanishStringsLocalizeAgentMenuCopy() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(MenuBarStatusItem.localizedNoActiveAgents(using: spanish) == "No hay agentes activos")
        #expect(MenuBarStatusItem.localizedShowCocxy(using: spanish) == "Mostrar Cocxy")
        #expect(MenuBarStatusItem.localizedShowDashboard(using: spanish) == "Mostrar dashboard")
        #expect(MenuBarStatusItem.localizedQuitCocxy(using: spanish) == "Cerrar Cocxy")
        #expect(MenuBarStatusItem.localizedAgentState("waitingForInput", using: spanish) == "Esperando entrada")
        #expect(MenuBarStatusItem.localizedAgentState("launched", using: spanish) == "Iniciando")
        #expect(MenuBarStatusItem.localizedAgentState("finished", using: spanish) == "Finalizado")
        #expect(
            MenuBarStatusItem.localizedSessionTitle(
                name: "repo",
                state: "working",
                activity: "build",
                using: spanish
            ) == "repo — Trabajando — build"
        )
    }

    @Test
    func stateSymbolsHandleDashboardAndAgentStateTokens() {
        #expect(MenuBarStatusItem.symbolName(forAgentState: "working") == "circle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "waitingForInput") == "questionmark.circle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "waiting_input") == "questionmark.circle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "blocked") == "exclamationmark.triangle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "finished") == "checkmark.circle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "unknown") == "circle")
    }
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
