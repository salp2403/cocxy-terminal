// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Command palette task handoff")
struct CommandPaletteTaskHandoffSwiftTestingTests {
    @Test("global palette exposes one task handoff entry")
    func globalPaletteContainsHandoff() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let engine = controller.createWiredCommandPaletteEngine()
        let actions = engine.allActions.filter { $0.id == "handoff.passTask" }

        let action = try #require(actions.first)
        #expect(actions.count == 1)
        #expect(action.name == "Pass This Task To...")
        #expect(action.category == .agent)
    }

    @Test("destination picker excludes the current provider and prioritizes its counterpart")
    func destinationPickerOrdersProviders() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let sourceTabID = controller.tabManager.tabs[0].id
        let actions = controller.taskHandoffProviderActions(
            sourceTabID: sourceTabID,
            currentProvider: .claudeCode,
            availableProviders: [.gemini, .claudeCode, .codex, .codex]
        )

        #expect(actions.map(\.id) == [
            "handoff.destination.codex",
            "handoff.destination.gemini",
        ])
        #expect(actions.map(\.name) == ["Codex CLI", "Gemini CLI"])
        #expect(actions.allSatisfy { $0.category == .agent })
    }

    @Test("detected agent aliases exclude only an unambiguous current provider")
    func currentProviderUsesPerSurfaceDetection() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tabID = try #require(controller.tabManager.activeTabID)
        let surfaceID = SurfaceID()
        let store = AgentStatePerSurfaceStore()
        controller.tabSurfaceMap[tabID] = surfaceID
        controller.injectedPerSurfaceStore = store
        store.update(surfaceID: surfaceID) {
            $0.agentState = .working
            $0.detectedAgent = DetectedAgent(
                name: "codex-cli",
                displayName: "Codex CLI",
                launchCommand: "codex",
                startedAt: Date(timeIntervalSince1970: 1_000)
            )
        }

        #expect(controller.currentTaskHandoffProvider(sourceTabID: tabID) == .codex)

        store.update(surfaceID: surfaceID) {
            $0.detectedAgent = DetectedAgent(
                name: "custom-wrapper",
                displayName: "Unknown Agent",
                launchCommand: "custom-wrapper",
                startedAt: Date(timeIntervalSince1970: 1_001)
            )
        }
        #expect(controller.currentTaskHandoffProvider(sourceTabID: tabID) == nil)
    }

    @Test("provider availability follows the same executable candidates as launch preflight")
    func providerAvailabilityUsesLaunchCandidates() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let available = controller.availableTaskHandoffProviders { executable in
            switch executable {
            case "claude", "codex", "gemini":
                return "/mock/bin/\(executable)"
            default:
                return nil
            }
        }

        #expect(available == [.claudeCode, .codex, .gemini])
    }
}
