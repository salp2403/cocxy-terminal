// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteCodexAccountSwiftTestingTests.swift - Codex account palette action coverage.

import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Command palette Codex account actions")
struct CommandPaletteCodexAccountSwiftTestingTests {

    @Test("account actions are omitted when no accounts are discoverable")
    func accountActionsAreOmittedWhenEmpty() {
        let controller = MainWindowController(bridge: MockTerminalEngine())

        #expect(controller.commandPaletteCodexAccountActions(accounts: []).isEmpty)
    }

    @Test("account actions hide personal identity and persist the chosen account")
    func accountActionsPersistSelection() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selectionURL = root.appendingPathComponent("codex-account-selection.json")
        try CodexAccountSelectionStore.save(
            CodexAccountSelection(selectedAccountID: "acct_1"),
            to: selectionURL
        )

        let controller = MainWindowController(bridge: MockTerminalEngine())
        let actions = controller.commandPaletteCodexAccountActions(
            accounts: [
                CodexAccount(id: "acct_1", email: "one@example.com", displayName: "One"),
                CodexAccount(id: "acct_2", email: "two@example.com", displayName: nil),
            ],
            selectionURL: selectionURL
        )

        #expect(actions.map(\.id) == ["codex.account.switch.acct_1", "codex.account.switch.acct_2"])
        #expect(actions[0].name == "Switch Codex Account: Codex Account 1 (Active)")
        #expect(actions[1].name == "Switch Codex Account: Codex Account 2")
        #expect(actions[0].description == "Use this local Codex account for Cocxy integrations")
        #expect(actions[1].description == "Use this local Codex account for Cocxy integrations")
        #expect(actions.map(\.name).contains { $0.contains("example.com") || $0.contains("One") } == false)
        #expect(actions.map(\.description).contains { $0.contains("example.com") || $0.contains("One") } == false)
        #expect(actions.allSatisfy { $0.category == .agent })

        actions[1].handler()

        #expect(CodexAccountSelectionStore.load(from: selectionURL).selectedAccountID == "acct_2")
    }

    @Test("activating an account refreshes the live Codex rate-limit context without restarting")
    func activatingAccountRefreshesLiveCodexContext() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let selectionURL = root.appendingPathComponent("codex-account-selection.json")

        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tab = controller.tabManager.tabs[0]
        seedCodexAgent(controller: controller, tabID: tab.id)
        controller.refreshStatusBar()
        #expect(controller.rateLimitProbeService.currentAgent == .codex)

        controller.activateCodexAccount(accountID: "acct_2", selectionURL: selectionURL)

        #expect(CodexAccountSelectionStore.load(from: selectionURL).selectedAccountID == "acct_2")
        #expect(controller.rateLimitProbeService.currentAgent == .codex)
    }

    @discardableResult
    private func seedCodexAgent(controller: MainWindowController, tabID: TabID) -> SurfaceID {
        if controller.injectedPerSurfaceStore == nil {
            controller.injectedPerSurfaceStore = AgentStatePerSurfaceStore()
        }
        let surfaceID = SurfaceID()
        controller.tabSurfaceMap[tabID] = surfaceID
        controller.injectedPerSurfaceStore?.update(surfaceID: surfaceID) {
            $0.agentState = .working
            $0.detectedAgent = DetectedAgent(
                name: "codex-cli",
                displayName: "Codex CLI",
                launchCommand: "codex",
                startedAt: Date()
            )
        }
        return surfaceID
    }
}
