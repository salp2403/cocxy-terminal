// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

/// Tests the end-to-end contract of the Fase 4 agent-state wiring:
///
/// - Detection engine transitions routed through a sink that mirrors
///   the same mutation onto `AgentStatePerSurfaceStore` (the sole
///   source of truth after Fase 4).
/// - Teardown (surface destroy) releases both the engine's debounce
///   and hook buckets AND the store entry.
///
/// The sink replicates the inline logic that
/// `AppDelegate+AgentWiring.wireAgentDetectionToTabs` wires in
/// production. Instantiating the full AppDelegate is prohibitively
/// expensive and orthogonal to the contract tested here; keeping the
/// wiring inline makes any divergence between production and tests
/// obvious in diff review.
@MainActor
@Suite("Agent wiring writes to the per-surface store", .serialized)
struct AgentWiringStoreOnlySwiftTestingTests {

    // MARK: - Helpers

    private struct StoreWiringFixture {
        let tabManager: TabManager
        let store: AgentStatePerSurfaceStore
        let engine: AgentDetectionEngineImpl
        let primarySurfaceID: SurfaceID
        var cancellables: Set<AnyCancellable>
    }

    /// Builds a minimal wiring: a tab manager with exactly one tab, an
    /// engine with patterns disabled (`compiledConfigs: []`) and zero
    /// debounce, and a per-surface store. A subscription mirrors the
    /// production `wireAgentDetectionToTabs` closure for state changes
    /// — now store-only, since Fase 4 retired the tab-level agent fields.
    ///
    /// - Parameter displayNameResolver: Optional override for display
    ///   name resolution. Defaults to identity (the raw agent name).
    private func makeFixture(
        displayNameResolver: @escaping (String) -> String = { $0 }
    ) -> StoreWiringFixture {
        let tabManager = TabManager()
        let store = AgentStatePerSurfaceStore()
        let engine = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )
        let primarySurfaceID = SurfaceID()
        var cancellables = Set<AnyCancellable>()

        // Ensure the manager has the expected active tab; activity
        // timestamps still belong on the tab so we bump them from the
        // sink below.
        guard let activeTabID = tabManager.activeTabID else {
            Issue.record("TabManager did not initialize with an active tab")
            return StoreWiringFixture(
                tabManager: tabManager,
                store: store,
                engine: engine,
                primarySurfaceID: primarySurfaceID,
                cancellables: cancellables
            )
        }

        engine.stateChanged
            .sink { [primarySurfaceID] context in
                let agentState = context.state.toTabAgentState
                let displayName: String? = context.agentName.map(displayNameResolver)

                // Non-agent tab metadata: only the last-activity
                // timestamp moves with every transition now.
                tabManager.updateTab(id: activeTabID) { tab in
                    tab.lastActivityAt = Date()
                }

                let targetSurfaceID = context.surfaceID ?? primarySurfaceID
                store.update(surfaceID: targetSurfaceID) { state in
                    state.agentState = agentState

                    if agentState == .idle {
                        state.agentToolCount = 0
                        state.agentErrorCount = 0
                        state.agentActivity = nil
                        state.detectedAgent = nil
                    } else if let agentName = context.agentName?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                        !agentName.isEmpty {
                        if let existing = state.detectedAgent,
                           existing.name == agentName {
                            state.detectedAgent = existing
                        } else {
                            state.detectedAgent = DetectedAgent(
                                name: agentName,
                                displayName: displayName,
                                launchCommand: agentName,
                                startedAt: Date()
                            )
                        }
                    }

                    if agentState == .finished, state.agentActivity == nil {
                        state.agentActivity = "Task completed"
                    } else if agentState == .error, state.agentActivity == nil {
                        state.agentActivity = "Error occurred"
                    } else if agentState == .waitingInput, state.agentActivity == nil {
                        state.agentActivity = "Waiting for input"
                    }
                }
            }
            .store(in: &cancellables)

        return StoreWiringFixture(
            tabManager: tabManager,
            store: store,
            engine: engine,
            primarySurfaceID: primarySurfaceID,
            cancellables: cancellables
        )
    }

    private func launchSignal(agentName: String = "claude") -> DetectionSignal {
        DetectionSignal(
            event: .agentDetected(name: agentName),
            confidence: 1.0,
            source: .hook(event: "sessionStart")
        )
    }

    private func outputSignal() -> DetectionSignal {
        DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 0)
        )
    }

    private func exitSignal() -> DetectionSignal {
        DetectionSignal(
            event: .agentExited,
            confidence: 1.0,
            source: .osc(code: 0)
        )
    }

    // MARK: - Pattern-based detection with explicit surfaceID

    @Test("Transition with context.surfaceID writes the store entry for that surface")
    func contextSurfaceIDWritesToStore() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let splitSurfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(), surfaceID: splitSurfaceID)

        let splitState = fixture.store.state(for: splitSurfaceID)
        #expect(splitState.agentState == .launched)
        #expect(splitState.detectedAgent?.name == "claude")

        // The primary surface remains at .idle because the transition
        // was explicitly scoped to the split.
        #expect(fixture.store.state(for: fixture.primarySurfaceID) == .idle)
    }

    @Test("Transition without context.surfaceID falls back to the tab primary surface")
    func fallbackToPrimarySurfaceID() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        // injectSignal without surfaceID leaves context.surfaceID == nil;
        // the sink picks the primary surface as fallback.
        fixture.engine.injectSignal(launchSignal())

        let primaryState = fixture.store.state(for: fixture.primarySurfaceID)
        #expect(primaryState.agentState == .launched)
        #expect(primaryState.detectedAgent?.name == "claude")
    }

    @Test("Idle transition resets counters and detectedAgent on the store")
    func idleTransitionResetsStoreState() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let splitSurfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(), surfaceID: splitSurfaceID)

        // Simulate tool activity accumulating before idle.
        fixture.store.update(surfaceID: splitSurfaceID) { state in
            state.agentToolCount = 5
            state.agentErrorCount = 1
            state.agentActivity = "Edit: main.swift"
        }

        // Exit -> idle.
        fixture.engine.injectSignal(exitSignal(), surfaceID: splitSurfaceID)

        let splitState = fixture.store.state(for: splitSurfaceID)
        #expect(splitState.agentState == .idle)
        #expect(splitState.agentToolCount == 0)
        #expect(splitState.agentErrorCount == 0)
        #expect(splitState.agentActivity == nil)
        #expect(splitState.detectedAgent == nil)
    }

    // MARK: - Per-surface independence

    @Test("Concurrent transitions on sibling surfaces leave per-surface state independent")
    func siblingSurfaceStatesRemainIndependent() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        // Surface A: idle -> launched.
        fixture.engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surfaceA)
        // Surface A: launched -> working -> finished so the state machine
        // can fire another agentDetected on surface B.
        fixture.engine.injectSignal(outputSignal(), surfaceID: surfaceA)
        fixture.engine.injectSignal(
            DetectionSignal(event: .completionDetected, confidence: 1.0, source: .osc(code: 0)),
            surfaceID: surfaceA
        )
        fixture.engine.injectSignal(exitSignal(), surfaceID: surfaceA)

        // Surface B starts its own agent.
        fixture.engine.injectSignal(launchSignal(agentName: "codex"), surfaceID: surfaceB)

        let stateA = fixture.store.state(for: surfaceA)
        let stateB = fixture.store.state(for: surfaceB)

        #expect(stateA.agentState == .idle)
        #expect(stateA.detectedAgent == nil)
        #expect(stateB.agentState == .launched)
        #expect(stateB.detectedAgent?.name == "codex")
    }

    // MARK: - detectedAgent lifecycle

    @Test("detectedAgent preserves startedAt when the same agent name reappears")
    func detectedAgentPreservesStartedAt() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let surfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surfaceID)
        let originalStartedAt = try? #require(
            fixture.store.state(for: surfaceID).detectedAgent?.startedAt
        )

        fixture.engine.injectSignal(outputSignal(), surfaceID: surfaceID)

        let updated = fixture.store.state(for: surfaceID)
        #expect(updated.agentState == .working)
        #expect(updated.detectedAgent?.name == "claude")
        #expect(updated.detectedAgent?.startedAt == originalStartedAt)
    }

    @Test("Different display name resolution is reflected in the per-surface store")
    func detectedAgentDisplayName() {
        var fixture = makeFixture(displayNameResolver: { rawName in
            rawName == "claude" ? "Claude Code" : rawName
        })
        defer { fixture.cancellables.removeAll() }

        let surfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surfaceID)

        let state = fixture.store.state(for: surfaceID)
        #expect(state.detectedAgent?.displayName == "Claude Code")
    }

    // MARK: - Teardown contract

    @Test("reset(surfaceID:) drops the store entry while other surfaces remain untouched")
    func resetDropsOnlyTargetSurfaceEntry() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        fixture.engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surfaceA)
        // Walk surface A back to idle so B can fire agentDetected.
        fixture.engine.injectSignal(exitSignal(), surfaceID: surfaceA)
        fixture.engine.injectSignal(launchSignal(agentName: "codex"), surfaceID: surfaceB)

        fixture.store.reset(surfaceID: surfaceA)

        #expect(fixture.store.state(for: surfaceA) == .idle)
        #expect(fixture.store.states[surfaceA] == nil)
        #expect(fixture.store.state(for: surfaceB).agentState == .launched)
        #expect(fixture.store.state(for: surfaceB).detectedAgent?.name == "codex")
    }

    @Test("Engine clearSurface paired with store reset leaves zero per-surface state")
    func engineClearPairedWithStoreReset() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let surfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(), surfaceID: surfaceID)

        // Production teardown calls both methods in the same block.
        fixture.engine.clearSurface(surfaceID)
        fixture.store.reset(surfaceID: surfaceID)

        #expect(fixture.engine._debounceBucketCountForTesting == 0)
        #expect(fixture.engine._hookSessionsForTesting(surfaceID: surfaceID).isEmpty)
        #expect(fixture.store.state(for: surfaceID) == .idle)
        #expect(fixture.store.states[surfaceID] == nil)
    }

    // MARK: - Activity fallbacks on lifecycle endpoints

    @Test("finished transition without custom activity fills the default message on the store")
    func finishedDefaultsToTaskCompleted() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let surfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(), surfaceID: surfaceID)
        fixture.engine.injectSignal(outputSignal(), surfaceID: surfaceID)
        fixture.engine.injectSignal(
            DetectionSignal(event: .completionDetected, confidence: 1.0, source: .osc(code: 0)),
            surfaceID: surfaceID
        )

        let state = fixture.store.state(for: surfaceID)
        #expect(state.agentState == .finished)
        #expect(state.agentActivity == "Task completed")
    }

    @Test("waitingInput transition without custom activity fills the default message on the store")
    func waitingInputDefaultsToWaitingForInput() {
        var fixture = makeFixture()
        defer { fixture.cancellables.removeAll() }

        let surfaceID = SurfaceID()
        fixture.engine.injectSignal(launchSignal(), surfaceID: surfaceID)
        fixture.engine.injectSignal(outputSignal(), surfaceID: surfaceID)
        fixture.engine.injectSignal(
            DetectionSignal(event: .promptDetected, confidence: 1.0, source: .osc(code: 0)),
            surfaceID: surfaceID
        )

        let state = fixture.store.state(for: surfaceID)
        #expect(state.agentState == .waitingInput)
        #expect(state.agentActivity == "Waiting for input")
    }
}
