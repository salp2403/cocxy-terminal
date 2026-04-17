// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tests for SurfaceAgentStateResolver — the pure priority chain used by
// Fase 3 UI consumers to pick per-surface state with a Tab fallback.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("SurfaceAgentStateResolver")
struct SurfaceAgentStateResolverSwiftTestingTests {

    // MARK: - Test helpers

    private static func makeTab(
        agentState: AgentState = .idle,
        detectedAgent: DetectedAgent? = nil,
        agentActivity: String? = nil,
        agentToolCount: Int = 0,
        agentErrorCount: Int = 0
    ) -> Tab {
        var tab = Tab(
            agentState: agentState,
            detectedAgent: detectedAgent
        )
        tab.agentActivity = agentActivity
        tab.agentToolCount = agentToolCount
        tab.agentErrorCount = agentErrorCount
        return tab
    }

    private static func makeAgent(name: String = "claude") -> DetectedAgent {
        DetectedAgent(
            name: name,
            displayName: "Claude Code",
            launchCommand: name,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Priority 4: no store / pure Tab fallback

    @Test("falls back to Tab when no store is provided")
    func fallsBackToTabWithoutStore() {
        let tab = Self.makeTab(
            agentState: .working,
            detectedAgent: Self.makeAgent(),
            agentActivity: "Read: main.swift",
            agentToolCount: 3,
            agentErrorCount: 1
        )

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: tab,
            focusedSurfaceID: nil,
            primarySurfaceID: nil,
            allSurfaceIDs: [],
            store: nil
        )

        #expect(resolved.agentState == .working)
        #expect(resolved.detectedAgent?.name == "claude")
        #expect(resolved.agentActivity == "Read: main.swift")
        #expect(resolved.agentToolCount == 3)
        #expect(resolved.agentErrorCount == 1)
    }

    @Test("falls back to Tab when every surface in the store is idle")
    func fallsBackToTabWhenStoreEmpty() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()
        let tab = Self.makeTab(agentState: .working, agentToolCount: 99)

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: tab,
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused],
            store: store
        )

        #expect(resolved.agentState == .working)
        #expect(resolved.agentToolCount == 99)
    }

    // MARK: - Priority 1: focused split

    @Test("prefers the focused surface when it is active")
    func prefersFocusedWhenActive() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()

        store.update(surfaceID: focused) { state in
            state.agentState = .working
            state.agentToolCount = 5
        }
        store.update(surfaceID: primary) { state in
            state.agentState = .working
            state.agentToolCount = 1
        }

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Self.makeTab(),
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused],
            store: store
        )

        #expect(resolved.agentToolCount == 5)
    }

    // MARK: - Priority 2: primary surface

    @Test("falls through to primary when focused is idle")
    func fallsThroughToPrimary() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()

        // focused has no entry (idle).
        store.update(surfaceID: primary) { state in
            state.agentState = .working
            state.agentToolCount = 7
        }

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Self.makeTab(),
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused],
            store: store
        )

        #expect(resolved.agentToolCount == 7)
    }

    @Test("does not reuse primary when it equals focused and focused is idle")
    func skipsPrimaryWhenSameAsFocused() {
        let store = AgentStatePerSurfaceStore()
        let shared = SurfaceID()
        let otherActive = SurfaceID()

        // shared (focused + primary collapsed) is idle.
        store.update(surfaceID: otherActive) { state in
            state.agentState = .working
            state.agentToolCount = 42
        }

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Self.makeTab(),
            focusedSurfaceID: shared,
            primarySurfaceID: shared,
            allSurfaceIDs: [shared, otherActive],
            store: store
        )

        #expect(resolved.agentToolCount == 42)
    }

    // MARK: - Priority 3: any surface with activity

    @Test("falls through to other surfaces when focused and primary are idle")
    func fallsThroughToOtherSurfaces() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: other) { state in
            state.agentState = .waitingInput
            state.agentToolCount = 11
        }

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Self.makeTab(),
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused, other],
            store: store
        )

        #expect(resolved.agentState == .waitingInput)
        #expect(resolved.agentToolCount == 11)
    }

    @Test("iteration preserves caller ordering and skips focused + primary")
    func iterationPreservesOrderAndSkipsSelected() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()
        let a = SurfaceID()
        let b = SurfaceID()

        // Two candidates are active; the first one in the iteration order wins.
        store.update(surfaceID: a) { state in
            state.agentState = .working
            state.agentToolCount = 1
        }
        store.update(surfaceID: b) { state in
            state.agentState = .working
            state.agentToolCount = 2
        }

        // Order `[focused, primary, b, a]` must still produce `b` first since
        // focused + primary are skipped in the iteration pass.
        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Self.makeTab(),
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [focused, primary, b, a],
            store: store
        )

        #expect(resolved.agentToolCount == 2)
    }

    // MARK: - hasAgent keeps the indicator visible

    @Test("considers a surface active when it has a detected agent even if finished")
    func detectedAgentCountsAsActivity() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()

        store.update(surfaceID: primary) { state in
            state.agentState = .finished
            state.detectedAgent = Self.makeAgent()
            state.agentToolCount = 42
        }

        let resolved = SurfaceAgentStateResolver.resolve(
            tab: Self.makeTab(),
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary],
            store: store
        )

        #expect(resolved.detectedAgent?.name == "claude")
        #expect(resolved.agentToolCount == 42)
        #expect(resolved.agentState == .finished)
    }

    // MARK: - SurfaceAgentState init from Tab

    @Test("SurfaceAgentState init from Tab mirrors all five fields")
    func surfaceStateInitFromTabMirrorsFields() {
        let agent = Self.makeAgent()
        let tab = Self.makeTab(
            agentState: .working,
            detectedAgent: agent,
            agentActivity: "Read: main.swift",
            agentToolCount: 7,
            agentErrorCount: 1
        )

        let state = SurfaceAgentState(from: tab)

        #expect(state.agentState == .working)
        #expect(state.detectedAgent?.name == agent.name)
        #expect(state.detectedAgent?.displayName == agent.displayName)
        #expect(state.agentActivity == "Read: main.swift")
        #expect(state.agentToolCount == 7)
        #expect(state.agentErrorCount == 1)
    }

    @Test("SurfaceAgentState init from idle Tab produces the canonical idle state")
    func surfaceStateInitFromIdleTabIsIdle() {
        let tab = Self.makeTab()

        let state = SurfaceAgentState(from: tab)

        #expect(state == .idle)
    }

    // MARK: - resolveFull returns both state and chosen surface (Fase 3e)

    @Test("resolveFull returns the focused surface ID when it wins")
    func resolveFullReturnsFocusedSurfaceID() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()

        store.update(surfaceID: focused) { $0.agentState = .working }

        let resolution = SurfaceAgentStateResolver.resolveFull(
            tab: Self.makeTab(),
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused],
            store: store
        )

        #expect(resolution.chosenSurfaceID == focused)
        #expect(resolution.state.agentState == .working)
    }

    @Test("resolveFull reports nil when the Tab fallback is used")
    func resolveFullNilOnFallback() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let tab = Self.makeTab(agentState: .working)

        let resolution = SurfaceAgentStateResolver.resolveFull(
            tab: tab,
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary],
            store: store
        )

        #expect(resolution.chosenSurfaceID == nil)
        #expect(resolution.state.agentState == .working)
    }

    // MARK: - additionalActiveStates for Fase 3e multi-agent pills

    @Test("additionalActiveStates returns empty when no store is provided")
    func additionalActiveStatesEmptyWithoutStore() {
        let result = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: nil,
            allSurfaceIDs: [SurfaceID(), SurfaceID()],
            store: nil
        )
        #expect(result.isEmpty)
    }

    @Test("additionalActiveStates excludes the primary surface")
    func additionalActiveStatesExcludesPrimary() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: primary) { $0.agentState = .working }
        store.update(surfaceID: other) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, other],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.agentState == .waitingInput)
    }

    @Test("additionalActiveStates filters out idle surfaces without a detected agent")
    func additionalActiveStatesFiltersIdle() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let idleSurface = SurfaceID()
        let activeSurface = SurfaceID()

        store.update(surfaceID: activeSurface) { $0.agentState = .working }
        // idleSurface has no entry — the store returns .idle

        let result = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, idleSurface, activeSurface],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.agentState == .working)
    }

    @Test("additionalActiveStates keeps finished surfaces that still carry a detected agent")
    func additionalActiveStatesKeepsFinishedWithAgent() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let finished = SurfaceID()

        store.update(surfaceID: finished) { state in
            state.agentState = .finished
            state.detectedAgent = Self.makeAgent()
        }

        let result = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, finished],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.detectedAgent != nil)
    }

    @Test("additionalActiveStates is sorted deterministically by surface UUID")
    func additionalActiveStatesSortedByUUID() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        // Create several active surfaces; the result must be UUID-sorted
        // regardless of caller-provided ordering.
        let surfaces = (0..<5).map { _ -> SurfaceID in
            let id = SurfaceID()
            store.update(surfaceID: id) { $0.agentState = .working }
            return id
        }

        let first = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary] + surfaces.shuffled(),
            store: store
        )
        let second = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary] + surfaces.shuffled(),
            store: store
        )

        #expect(first.count == 5)
        #expect(first == second)
    }

    @Test("additionalActiveStates keeps the primary surface when primaryChosenSurfaceID is nil")
    func additionalActiveStatesFallbackKeepsAll() {
        // When the primary resolver falls back to the Tab snapshot, the
        // chosenSurfaceID is nil; no surface must be excluded.
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: primary) { $0.agentState = .working }
        store.update(surfaceID: other) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.additionalActiveStates(
            primaryChosenSurfaceID: nil,
            allSurfaceIDs: [primary, other],
            store: store
        )

        #expect(result.count == 2)
        let states = result.map(\.agentState)
        #expect(states.contains(.working))
        #expect(states.contains(.waitingInput))
    }
}
