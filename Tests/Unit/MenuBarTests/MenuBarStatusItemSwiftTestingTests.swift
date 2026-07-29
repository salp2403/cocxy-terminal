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
        #expect(MenuBarStatusItem.localizedShowDashboard(using: spanish) == "Mostrar panel de agentes")
        #expect(MenuBarStatusItem.localizedQuitCocxy(using: spanish) == "Cerrar Cocxy")
        #expect(MenuBarStatusItem.localizedAgentState("waitingForInput", using: spanish) == "Esperando entrada")
        #expect(MenuBarStatusItem.localizedAgentState("launching", using: spanish) == "Iniciando")
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
        #expect(MenuBarStatusItem.symbolName(forAgentState: "error") == "exclamationmark.triangle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "finished") == "checkmark.circle.fill")
        #expect(MenuBarStatusItem.symbolName(forAgentState: "unknown") == "circle")
    }

    @Test
    func finishedSessionStaysListedWithoutContributingToBadge() {
        let summary = MenuBarAgentSummary.summarize([
            makeSession(id: "finished", state: .finished),
        ])

        #expect(summary.working == 0)
        #expect(summary.waiting == 0)
        #expect(summary.errors == 0)
        #expect(summary.badgeTitle.isEmpty)
        #expect(summary.rows.map(\.sessionID) == ["finished"])
    }

    @Test
    func reachableLaunchingAndErrorStatesCountAndStayListed() {
        let summary = MenuBarAgentSummary.summarize([
            makeSession(id: "failed", state: .error),
            makeSession(id: "starting", state: .launching),
        ])

        #expect(summary.working == 1)
        #expect(summary.waiting == 0)
        #expect(summary.errors == 1)
        #expect(summary.rows.map(\.sessionID) == ["failed", "starting"])
        #expect(summary.badgeTitle == " 1↻ 1⚠")
    }

    @Test
    func hookSessionReplacesPatternMirrorOnlyForTheSameTabAndSurface() {
        let tabID = UUID()
        let otherTabID = UUID()
        let surfaceID = SurfaceID()
        let hook = makeSession(id: "hook-session", state: .working, tabID: tabID)
        let duplicatePattern = makeSession(
            id: "pattern-\(tabID.uuidString)-\(surfaceID.rawValue.uuidString)",
            state: .working,
            tabID: tabID
        )
        let otherTabPattern = makeSession(
            id: "pattern-\(otherTabID.uuidString)-\(surfaceID.rawValue.uuidString)",
            state: .working,
            tabID: otherTabID
        )

        let summary = MenuBarAgentSummary.summarize(
            [hook, duplicatePattern, otherTabPattern],
            surfaceIDForHookSession: { sessionID in
                sessionID == hook.id ? surfaceID : nil
            }
        )

        #expect(summary.working == 2)
        #expect(summary.rows.map(\.sessionID) == [hook.id, otherTabPattern.id])
    }

    @Test
    func summaryKeepsUrgencyOrderAndReportsOverflowAfterFiveRows() {
        let sessions = (0..<6).map { index in
            makeSession(id: "session-\(index)", state: .working)
        }

        let summary = MenuBarAgentSummary.summarize(sessions)

        #expect(summary.working == 6)
        #expect(summary.rows.map(\.sessionID) == (0..<5).map { "session-\($0)" })
        #expect(summary.overflowCount == 1)
    }
}

private func makeSession(
    id: String,
    state: AgentDashboardState,
    tabID: UUID = UUID()
) -> AgentSessionInfo {
    AgentSessionInfo(
        id: id,
        projectName: id,
        gitBranch: nil,
        agentName: "Claude Code",
        state: state,
        lastActivity: nil,
        lastActivityTime: nil,
        tabId: tabID,
        subagents: [],
        priority: .standard,
        model: nil
    )
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
