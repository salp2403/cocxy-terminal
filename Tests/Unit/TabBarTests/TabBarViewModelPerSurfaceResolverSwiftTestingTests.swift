// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tests for the sidebar-pill per-surface wiring: TabBarViewModel must
// route every tab display item through the injected `agentStateResolver`
// so the pill reflects the per-surface store. After Fase 4 the default
// resolver is `.idle` (no Tab fallback); tests wire explicit resolvers
// to exercise each state.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("TabBarViewModel per-surface agent resolver")
struct TabBarViewModelPerSurfaceResolverSwiftTestingTests {

    // MARK: - Default resolver returns idle

    @Test("default resolver reports idle when no closure is wired")
    func defaultResolverReportsIdle() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .idle)
        #expect(item?.agentToolCount == 0)
        #expect(item?.agentErrorCount == 0)
        #expect(item?.agentDurationText == nil)
        #expect(item?.additionalActiveAgentStates.isEmpty == true)
    }

    // MARK: - Overridden resolver drives the display item

    @Test("custom resolver drives the display item fields")
    func customResolverDrivesDisplayItem() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        let resolvedAgent = DetectedAgent(
            name: "codex",
            displayName: "Codex CLI",
            launchCommand: "codex",
            startedAt: Date()
        )
        viewModel.agentStateResolver = { _ in
            SurfaceAgentState(
                agentState: .waitingInput,
                detectedAgent: resolvedAgent,
                agentActivity: "Waiting for input",
                agentToolCount: 9,
                agentErrorCount: 2
            )
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .waitingInput)
        #expect(item?.agentToolCount == 9)
        #expect(item?.agentErrorCount == 2)
        #expect(item?.agentStatusText.contains("Codex CLI") == true)
    }

    @Test("resolver-driven duration follows the resolved detected agent")
    func resolverDrivenDuration() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        let startedAt = Date(timeIntervalSinceNow: -125)  // ~2 minutes ago
        viewModel.agentStateResolver = { _ in
            SurfaceAgentState(
                agentState: .working,
                detectedAgent: DetectedAgent(
                    name: "aider",
                    displayName: "Aider",
                    launchCommand: "aider",
                    startedAt: startedAt
                )
            )
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentDurationText == "2m")
    }

    @Test("idle resolver produces no duration text even if the resolver carries a detected agent")
    func idleResolverSuppressesDuration() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        // Resolver reports idle; the display item must suppress the
        // duration even though a detected agent would otherwise be
        // available.
        viewModel.agentStateResolver = { _ in
            SurfaceAgentState(agentState: .idle)
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .idle)
        #expect(item?.agentDurationText == nil)
    }

    // MARK: - Resolver is called per tab

    @Test("resolver is called once per tab and routed with that tab's ID")
    func resolverCalledPerTab() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        // Bootstrap tab + two more, so we cover the full `map` loop.
        let second = manager.addTab()
        let third = manager.addTab()
        let expectedIDs = manager.tabs.map(\.id)

        var seenTabIDs: [TabID] = []
        viewModel.agentStateResolver = { tab in
            seenTabIDs.append(tab.id)
            return SurfaceAgentState(agentState: .working)
        }
        viewModel.syncWithManager()

        #expect(seenTabIDs == expectedIDs)
        #expect(seenTabIDs.contains(second.id))
        #expect(seenTabIDs.contains(third.id))
        #expect(viewModel.tabItems.allSatisfy { $0.agentState == .working })
    }

    // MARK: - Additional pills (multi-agent)

    @Test("additional agent states are exposed as [AgentState] on the display item")
    func additionalAgentStatesExposedOnDisplayItem() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        viewModel.additionalActiveAgentStatesProvider = { _ in
            [
                SurfaceAgentState(agentState: .waitingInput),
                SurfaceAgentState(agentState: .error),
                SurfaceAgentState(agentState: .working)
            ]
        }
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.additionalActiveAgentStates == [.waitingInput, .error, .working])
    }

    @Test("display item has empty additional states when provider returns nothing")
    func additionalAgentStatesEmptyByDefault() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.additionalActiveAgentStates.isEmpty == true)
    }
}
