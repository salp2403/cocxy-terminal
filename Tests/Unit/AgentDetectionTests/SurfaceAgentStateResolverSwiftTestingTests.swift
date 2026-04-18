// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tests for SurfaceAgentStateResolver — pure priority chain used by the
// tab-scoped UI indicators. After Fase 4 the resolver only consults the
// per-surface store; the safety-net fallback is plain `.idle`.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("SurfaceAgentStateResolver")
struct SurfaceAgentStateResolverSwiftTestingTests {

    // MARK: - Test helpers

    private static func makeAgent(name: String = "claude") -> DetectedAgent {
        DetectedAgent(
            name: name,
            displayName: "Claude Code",
            launchCommand: name,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - Priority 4: `.idle` fallback

    @Test("falls back to idle when no store is provided")
    func fallsBackToIdleWithoutStore() {
        let resolved = SurfaceAgentStateResolver.resolve(
            focusedSurfaceID: SurfaceID(),
            primarySurfaceID: SurfaceID(),
            allSurfaceIDs: [SurfaceID()],
            store: nil
        )

        #expect(resolved == .idle)
    }

    @Test("falls back to idle when every surface in the store is idle")
    func fallsBackToIdleWhenStoreEmpty() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()

        let resolved = SurfaceAgentStateResolver.resolve(
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused],
            store: store
        )

        #expect(resolved == .idle)
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
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary],
            store: store
        )

        #expect(resolved.detectedAgent?.name == "claude")
        #expect(resolved.agentToolCount == 42)
        #expect(resolved.agentState == .finished)
    }

    // MARK: - resolveFull returns both state and chosen surface

    @Test("resolveFull returns the focused surface ID when it wins")
    func resolveFullReturnsFocusedSurfaceID() {
        let store = AgentStatePerSurfaceStore()
        let focused = SurfaceID()
        let primary = SurfaceID()

        store.update(surfaceID: focused) { $0.agentState = .working }

        let resolution = SurfaceAgentStateResolver.resolveFull(
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, focused],
            store: store
        )

        #expect(resolution.chosenSurfaceID == focused)
        #expect(resolution.state.agentState == .working)
    }

    @Test("resolveFull reports nil when the idle fallback is used")
    func resolveFullNilOnIdleFallback() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()

        let resolution = SurfaceAgentStateResolver.resolveFull(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary],
            store: store
        )

        #expect(resolution.chosenSurfaceID == nil)
        #expect(resolution.state == .idle)
    }

    @Test("resolveFull without store returns idle and nil surface")
    func resolveFullWithoutStoreReturnsIdle() {
        let resolution = SurfaceAgentStateResolver.resolveFull(
            focusedSurfaceID: SurfaceID(),
            primarySurfaceID: SurfaceID(),
            allSurfaceIDs: [],
            store: nil
        )

        #expect(resolution.state == .idle)
        #expect(resolution.chosenSurfaceID == nil)
    }

    // MARK: - additionalActiveStates for multi-agent pills

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
        // When the primary resolver falls back to `.idle`, the
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

    // MARK: - additionalActiveSnapshots (identity-aware)

    @Test("additionalActiveSnapshots returns empty without store")
    func additionalActiveSnapshotsEmptyWithoutStore() {
        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: SurfaceID(),
            primarySurfaceID: SurfaceID(),
            primaryChosenSurfaceID: nil,
            allSurfaceIDs: [SurfaceID(), SurfaceID()],
            store: nil
        )
        #expect(result.isEmpty)
    }

    @Test("additionalActiveSnapshots preserves surface IDs")
    func additionalActiveSnapshotsPreservesSurfaceIDs() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: other) { $0.agentState = .working }

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, other],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.surfaceID == other)
    }

    @Test("additionalActiveSnapshots marks isFocused correctly")
    func additionalActiveSnapshotsMarksFocused() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let focused = SurfaceID()
        let another = SurfaceID()

        store.update(surfaceID: focused) { $0.agentState = .working }
        store.update(surfaceID: another) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: focused,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, focused, another],
            store: store
        )

        let focusedSnapshot = result.first(where: { $0.surfaceID == focused })
        let anotherSnapshot = result.first(where: { $0.surfaceID == another })
        #expect(focusedSnapshot?.isFocused == true)
        #expect(anotherSnapshot?.isFocused == false)
    }

    @Test("additionalActiveSnapshots marks isPrimary correctly")
    func additionalActiveSnapshotsMarksPrimary() {
        // primary surface is active and the resolver picked a different
        // chosen surface. The primary flag reflects `primarySurfaceID`
        // independent of the chosen filter.
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: primary) { $0.agentState = .working }
        store.update(surfaceID: other) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: other,
            allSurfaceIDs: [primary, other],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.surfaceID == primary)
        #expect(result.first?.isPrimary == true)
    }

    @Test("additionalActiveSnapshots sorted by UUID")
    func additionalActiveSnapshotsSortedByUUID() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let surfaces = (0..<4).map { _ -> SurfaceID in
            let id = SurfaceID()
            store.update(surfaceID: id) { $0.agentState = .working }
            return id
        }

        let first = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary] + surfaces.shuffled(),
            store: store
        )
        let second = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary] + surfaces.shuffled(),
            store: store
        )

        #expect(first.count == 4)
        #expect(first.map(\.surfaceID) == second.map(\.surfaceID))
    }

    @Test("additionalActiveSnapshots excludes primaryChosenSurfaceID")
    func additionalActiveSnapshotsExcludesPrimaryChosen() {
        let store = AgentStatePerSurfaceStore()
        let chosen = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: chosen) { $0.agentState = .working }
        store.update(surfaceID: other) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: chosen,
            primaryChosenSurfaceID: chosen,
            allSurfaceIDs: [chosen, other],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.surfaceID == other)
    }

    @Test("additionalActiveSnapshots filters idle surfaces without agent")
    func additionalActiveSnapshotsFiltersIdle() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let idleSurface = SurfaceID()
        let activeSurface = SurfaceID()

        store.update(surfaceID: activeSurface) { $0.agentState = .working }
        // idleSurface has no entry — the store returns .idle

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, idleSurface, activeSurface],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.surfaceID == activeSurface)
    }

    @Test("additionalActiveSnapshots keeps finished surfaces that carry a detected agent")
    func additionalActiveSnapshotsKeepsFinishedWithAgent() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let finished = SurfaceID()

        store.update(surfaceID: finished) { state in
            state.agentState = .finished
            state.detectedAgent = Self.makeAgent()
        }

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: primary,
            allSurfaceIDs: [primary, finished],
            store: store
        )

        #expect(result.count == 1)
        #expect(result.first?.state.detectedAgent != nil)
    }

    @Test("additionalActiveSnapshots keeps all active surfaces when primaryChosenSurfaceID is nil")
    func additionalActiveSnapshotsFallbackKeepsAll() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: primary) { $0.agentState = .working }
        store.update(surfaceID: other) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.additionalActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            primaryChosenSurfaceID: nil,
            allSurfaceIDs: [primary, other],
            store: store
        )

        #expect(result.count == 2)
        let ids = Set(result.map(\.surfaceID))
        #expect(ids.contains(primary))
        #expect(ids.contains(other))
    }

    // MARK: - allActiveSnapshots (includes primary)

    @Test("allActiveSnapshots returns empty without store")
    func allActiveSnapshotsEmptyWithoutStore() {
        let result = SurfaceAgentStateResolver.allActiveSnapshots(
            focusedSurfaceID: SurfaceID(),
            primarySurfaceID: SurfaceID(),
            allSurfaceIDs: [SurfaceID()],
            store: nil
        )
        #expect(result.isEmpty)
    }

    @Test("allActiveSnapshots includes the primary surface when active")
    func allActiveSnapshotsIncludesPrimary() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        let other = SurfaceID()

        store.update(surfaceID: primary) { $0.agentState = .working }
        store.update(surfaceID: other) { $0.agentState = .waitingInput }

        let result = SurfaceAgentStateResolver.allActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary, other],
            store: store
        )

        #expect(result.count == 2)
        let primarySnapshot = result.first(where: { $0.surfaceID == primary })
        #expect(primarySnapshot?.isPrimary == true)
        #expect(primarySnapshot?.state.agentState == .working)
    }

    @Test("allActiveSnapshots sorts deterministically by UUID")
    func allActiveSnapshotsSortedByUUID() {
        let store = AgentStatePerSurfaceStore()
        let primary = SurfaceID()
        store.update(surfaceID: primary) { $0.agentState = .working }

        let surfaces = (0..<3).map { _ -> SurfaceID in
            let id = SurfaceID()
            store.update(surfaceID: id) { $0.agentState = .working }
            return id
        }

        let first = SurfaceAgentStateResolver.allActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: [primary] + surfaces.shuffled(),
            store: store
        )
        let second = SurfaceAgentStateResolver.allActiveSnapshots(
            focusedSurfaceID: nil,
            primarySurfaceID: primary,
            allSurfaceIDs: (surfaces + [primary]).shuffled(),
            store: store
        )

        #expect(first.count == 4)
        #expect(first.map(\.surfaceID) == second.map(\.surfaceID))
    }

    // MARK: - SurfaceAgentSnapshot equatability

    @Test("SurfaceAgentSnapshot equality includes identity + role flags")
    func surfaceAgentSnapshotEquality() {
        let surfaceID = SurfaceID()
        let a = SurfaceAgentSnapshot(
            surfaceID: surfaceID,
            state: SurfaceAgentState(agentState: .working),
            isFocused: true,
            isPrimary: false
        )
        let b = SurfaceAgentSnapshot(
            surfaceID: surfaceID,
            state: SurfaceAgentState(agentState: .working),
            isFocused: true,
            isPrimary: false
        )
        let c = SurfaceAgentSnapshot(
            surfaceID: surfaceID,
            state: SurfaceAgentState(agentState: .working),
            isFocused: false,
            isPrimary: false
        )

        #expect(a == b)
        #expect(a != c)
    }
}
