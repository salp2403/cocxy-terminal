// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// End-to-end Fase 3 checks: wire the real AgentStatePerSurfaceStore, the
// real SurfaceAgentStateResolver, and the real TabBarViewModel (no mocks,
// no AppKit), then verify the display items, notification-ring decisions,
// and status-bar formatting all follow the store instead of Tab.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Per-surface store end-to-end (Fase 3)")
struct PerSurfaceStoreE2ESwiftTestingTests {

    // MARK: - Helpers

    /// Wires a `TabBarViewModel` to the real resolver + store, mimicking
    /// the controller's `buildSidebar` setup but without booting AppKit.
    private static func wireViewModel(
        _ viewModel: TabBarViewModel,
        store: AgentStatePerSurfaceStore,
        primarySurfaceIDsByTab: [TabID: SurfaceID],
        allSurfaceIDsByTab: [TabID: [SurfaceID]]
    ) {
        viewModel.agentStateResolver = { tab in
            SurfaceAgentStateResolver.resolve(
                tab: tab,
                focusedSurfaceID: nil,
                primarySurfaceID: primarySurfaceIDsByTab[tab.id],
                allSurfaceIDs: allSurfaceIDsByTab[tab.id] ?? [],
                store: store
            )
        }
        viewModel.additionalActiveAgentStatesProvider = { tab in
            let resolution = SurfaceAgentStateResolver.resolveFull(
                tab: tab,
                focusedSurfaceID: nil,
                primarySurfaceID: primarySurfaceIDsByTab[tab.id],
                allSurfaceIDs: allSurfaceIDsByTab[tab.id] ?? [],
                store: store
            )
            return SurfaceAgentStateResolver.additionalActiveStates(
                primaryChosenSurfaceID: resolution.chosenSurfaceID,
                allSurfaceIDs: allSurfaceIDsByTab[tab.id] ?? [],
                store: store
            )
        }
    }

    private static func makeAgent(name: String) -> DetectedAgent {
        DetectedAgent(
            name: name,
            displayName: name.capitalized,
            launchCommand: name,
            startedAt: Date()
        )
    }

    // MARK: - Sidebar pill reflects the store, not Tab

    @Test("display item mirrors the per-surface store while Tab remains idle")
    func displayItemMirrorsStore() {
        let manager = TabManager()
        let tabID = manager.tabs[0].id
        let primary = SurfaceID()

        let store = AgentStatePerSurfaceStore()
        store.update(surfaceID: primary) { state in
            state.agentState = .working
            state.detectedAgent = Self.makeAgent(name: "claude")
            state.agentActivity = "Read: main.swift"
            state.agentToolCount = 3
            state.agentErrorCount = 0
        }

        let viewModel = TabBarViewModel(tabManager: manager)
        Self.wireViewModel(
            viewModel,
            store: store,
            primarySurfaceIDsByTab: [tabID: primary],
            allSurfaceIDsByTab: [tabID: [primary]]
        )
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .working)
        #expect(item?.agentToolCount == 3)
        #expect(item?.agentDurationText != nil)
        #expect(item?.agentStatusText.contains("Read: main.swift") == true)

        // Tab itself is still idle — the store shadowed it.
        let tabSnapshot = manager.tab(for: tabID)
        #expect(tabSnapshot?.agentState == .idle)
        #expect(tabSnapshot?.agentToolCount == 0)
    }

    // MARK: - Multi-split routing

    @Test("multi-split tab surfaces extra active splits as mini-pill states")
    func multiSplitExposesAdditionalStates() {
        let manager = TabManager()
        let tabID = manager.tabs[0].id
        let primary = SurfaceID()
        let splitA = SurfaceID()
        let splitB = SurfaceID()

        let store = AgentStatePerSurfaceStore()
        store.update(surfaceID: primary) { $0.agentState = .working }
        store.update(surfaceID: splitA) { $0.agentState = .waitingInput }
        // Mirror production: when an agent errors, `AgentWiring` leaves
        // `detectedAgent` attached until an explicit `.idle` transition.
        // Without that attachment the surface is not considered "with
        // activity" because `.error` alone is not `isActive`.
        store.update(surfaceID: splitB) { state in
            state.agentState = .error
            state.detectedAgent = Self.makeAgent(name: "aider")
        }

        let viewModel = TabBarViewModel(tabManager: manager)
        Self.wireViewModel(
            viewModel,
            store: store,
            primarySurfaceIDsByTab: [tabID: primary],
            allSurfaceIDsByTab: [tabID: [primary, splitA, splitB]]
        )
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .working)  // primary
        #expect(item?.additionalActiveAgentStates.count == 2)
        #expect(item?.additionalActiveAgentStates.contains(.waitingInput) == true)
        #expect(item?.additionalActiveAgentStates.contains(.error) == true)
        // Primary state is not duplicated in the additional list.
        #expect(item?.additionalActiveAgentStates.contains(.working) == false)
    }

    // MARK: - Store reset flows through to the display item

    @Test("resetting a surface clears the primary indicator on the next sync")
    func resettingSurfaceClearsIndicator() {
        let manager = TabManager()
        let tabID = manager.tabs[0].id
        let primary = SurfaceID()

        let store = AgentStatePerSurfaceStore()
        store.update(surfaceID: primary) { state in
            state.agentState = .working
            state.agentToolCount = 4
        }

        let viewModel = TabBarViewModel(tabManager: manager)
        Self.wireViewModel(
            viewModel,
            store: store,
            primarySurfaceIDsByTab: [tabID: primary],
            allSurfaceIDsByTab: [tabID: [primary]]
        )
        viewModel.syncWithManager()
        #expect(viewModel.tabItems.first?.agentState == .working)

        // Simulate surface teardown — the per-surface store resets its
        // entry to idle and the display item must follow.
        store.reset(surfaceID: primary)
        viewModel.syncWithManager()
        #expect(viewModel.tabItems.first?.agentState == .idle)
        #expect(viewModel.tabItems.first?.additionalActiveAgentStates.isEmpty == true)
    }

    // MARK: - Notification ring decisions follow the store per surface

    @Test("ring decisions pulse only for splits waiting on input")
    func ringDecisionsPerSurface() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()
        let splitWaiting = SurfaceID()

        store.update(surfaceID: focused) { $0.agentState = .working }
        store.update(surfaceID: primary) { $0.agentState = .waitingInput }
        store.update(surfaceID: splitWaiting) { $0.agentState = .waitingInput }

        // Tab is visible; the focused pane never pulses, but the
        // background splits do even though they belong to the displayed
        // tab.
        let focusedDecision = NotificationRingDecision.decide(
            agentState: store.state(for: focused).agentState,
            isTabVisible: true,
            isSurfaceFocused: true
        )
        #expect(focusedDecision == .hide)

        let primaryDecision = NotificationRingDecision.decide(
            agentState: store.state(for: primary).agentState,
            isTabVisible: true,
            isSurfaceFocused: false
        )
        #expect(primaryDecision == .show)

        let splitDecision = NotificationRingDecision.decide(
            agentState: store.state(for: splitWaiting).agentState,
            isTabVisible: true,
            isSurfaceFocused: false
        )
        #expect(splitDecision == .show)
    }

    // MARK: - Status bar text follows the store

    @Test("status bar active label follows the store-resolved activity")
    func statusBarLabelFollowsStore() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()

        store.update(surfaceID: primary) { state in
            state.agentState = .working
            state.detectedAgent = Self.makeAgent(name: "codex")
            state.agentActivity = "Edit: server.ts"
        }

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Tab(),
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary],
            store: store
        )

        let label = AgentStatusTextFormatter.activeAgentStatusText(
            state: resolved.agentState,
            agentName: resolved.detectedAgent?.displayName ?? "Agent",
            agentActivity: resolved.agentActivity
        )
        #expect(label == "Edit: server.ts")
    }

    // MARK: - No store wiring = legacy behavior (Tab fallback)

    @Test("display item falls back to Tab snapshot when no resolver is wired")
    func displayItemFallsBackToTabWithoutResolver() {
        let manager = TabManager()
        let tabID = manager.tabs[0].id

        // Seed the tab so the fallback can prove itself.
        manager.updateTab(id: tabID) { tab in
            tab.agentState = .working
            tab.agentToolCount = 9
        }

        // No resolver / provider is wired — default closures keep the
        // legacy tab-level behavior and never touch a store.
        let viewModel = TabBarViewModel(tabManager: manager)
        viewModel.syncWithManager()

        let item = viewModel.tabItems.first
        #expect(item?.agentState == .working)
        #expect(item?.agentToolCount == 9)
        #expect(item?.additionalActiveAgentStates.isEmpty == true)
    }
}
