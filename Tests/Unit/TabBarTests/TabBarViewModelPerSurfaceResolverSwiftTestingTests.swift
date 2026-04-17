// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tests for the Fase 3d sidebar-pill migration: TabBarViewModel must route
// every tab display item through the injected `agentStateResolver` so the
// sidebar pill reflects the per-surface store instead of the tab-level
// fields.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("TabBarViewModel per-surface agent resolver")
struct TabBarViewModelPerSurfaceResolverSwiftTestingTests {

    // MARK: - Test helpers

    /// Mutates the manager's bootstrap tab with the given agent-related
    /// fields so the tests can assert what the resolver overrides versus
    /// the legacy fallback without depending on any private API.
    private static func seedBootstrapTab(
        on manager: TabManager,
        agentState: AgentState,
        detectedAgent: DetectedAgent? = nil,
        agentActivity: String? = nil,
        agentToolCount: Int = 0,
        agentErrorCount: Int = 0
    ) {
        let id = manager.tabs[0].id
        manager.updateTab(id: id) { tab in
            tab.agentState = agentState
            tab.detectedAgent = detectedAgent
            tab.agentActivity = agentActivity
            tab.agentToolCount = agentToolCount
            tab.agentErrorCount = agentErrorCount
        }
    }

    // MARK: - Default resolver (no store)

    @Test("default resolver mirrors tab-level fields onto the display item")
    func defaultResolverMirrorsTabFields() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        Self.seedBootstrapTab(
            on: manager,
            agentState: .working,
            detectedAgent: DetectedAgent(
                name: "claude",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date()
            ),
            agentActivity: "Read: main.swift",
            agentToolCount: 4,
            agentErrorCount: 1
        )
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .working)
        #expect(item?.agentToolCount == 4)
        #expect(item?.agentErrorCount == 1)
        #expect(item?.agentDurationText != nil)
    }

    // MARK: - Overridden resolver drives the display item

    @Test("custom resolver overrides tab-level fields on the display item")
    func customResolverOverridesTabFields() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        // Tab looks idle, but the injected resolver reports an active
        // agent; the display item must follow the resolver.
        Self.seedBootstrapTab(on: manager, agentState: .idle)

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

        Self.seedBootstrapTab(on: manager, agentState: .idle)

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

    @Test("idle resolver produces no duration text even if the tab has a detected agent")
    func idleResolverSuppressesDuration() {
        let manager = TabManager()
        let viewModel = TabBarViewModel(tabManager: manager)

        Self.seedBootstrapTab(
            on: manager,
            agentState: .working,
            detectedAgent: DetectedAgent(
                name: "claude",
                displayName: "Claude Code",
                launchCommand: "claude",
                startedAt: Date(timeIntervalSinceNow: -300)
            )
        )

        // Resolver reports idle even though the tab still carries a
        // detected agent; the display item must suppress the duration.
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
}
