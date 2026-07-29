// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuBarStatusItemSwiftTestingTests.swift - Menu bar copy localization tests.

import Foundation
import AppKit
import Combine
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
        #expect(MenuBarStatusItem.localizedMoreAgents(3, using: spanish) == "+3 más")
        #expect(
            MenuBarStatusItem.localizedNoActiveAgentsMessage(using: spanish)
                == "Ejecuta un agente IA en la terminal para ver su actividad aquí."
        )
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

    @Test
    func menuRefreshKeepsTheAssignedMenuAndMakesSessionRowsNavigable() throws {
        let item = MenuBarStatusItem()
        item.install()
        defer { item.uninstall() }

        let installedMenu = try #require(item.agentMenu)
        let latestSummary = MenuBarAgentSummary.summarize([
            makeSession(id: "fresh-session", state: .finished),
        ])
        var navigatedSessionID: String?
        item.onRequestAgentSummary = { latestSummary }
        item.onNavigateToSession = { navigatedSessionID = $0 }

        item.menuNeedsUpdate(installedMenu)

        #expect(item.agentMenu === installedMenu)
        #expect(installedMenu.autoenablesItems == false)
        #expect(item.currentSummary == latestSummary)
        let row = try #require(installedMenu.items.first)
        #expect(row.isEnabled)
        #expect(row.target === item)
        #expect(row.action != nil)
        #expect(row.representedObject as? String == "fresh-session")

        installedMenu.performActionForItem(at: 0)
        #expect(navigatedSessionID == "fresh-session")
    }

    @Test
    func emptyMenuIncludesLocalizedExplanation() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let item = MenuBarStatusItem(localizer: spanish)
        item.install()
        defer { item.uninstall() }

        let menu = try #require(item.agentMenu)
        item.updateAgentCount(.empty)

        #expect(menu.items[0].title == "No hay agentes activos")
        #expect(menu.items[0].isEnabled == false)
        #expect(menu.items[1].title == "Ejecuta un agente IA en la terminal para ver su actividad aquí.")
        #expect(menu.items[1].isEnabled == false)
    }

    @Test
    func dashboardPublisherKeepsFinishedSessionVisibleWhenBadgeClears() async {
        let dashboard = AgentDashboardViewModel()
        let item = MenuBarStatusItem()
        let binding = item.bindAgentSessions(
            dashboard.sessionsPublisher,
            surfaceIDForHookSession: { _ in nil }
        )

        dashboard.processHookEvent(
            HookEvent(
                type: .sessionStart,
                sessionId: "publisher-session",
                data: .sessionStart(SessionStartData(workingDirectory: "/tmp/project"))
            )
        )
        await drainMainQueue()
        #expect(item.currentSummary.working == 1)
        #expect(item.currentSummary.rows.map(\.sessionID) == ["publisher-session"])

        dashboard.processHookEvent(
            HookEvent(
                type: .stop,
                sessionId: "publisher-session",
                data: .stop(StopData())
            )
        )
        await drainMainQueue()

        #expect(item.currentSummary.badgeTitle.isEmpty)
        #expect(item.currentSummary.rows.map(\.sessionID) == ["publisher-session"])
        #expect(item.currentSummary.rows.first?.state == .finished)
        _ = binding
    }
}

private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
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
