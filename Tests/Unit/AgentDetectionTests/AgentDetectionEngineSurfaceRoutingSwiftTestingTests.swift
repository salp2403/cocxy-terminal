// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AgentDetectionEngine surfaceID routing")
struct AgentDetectionEngineSurfaceRoutingSwiftTestingTests {

    private func makeEngine(debounce: TimeInterval = 0.0) -> AgentDetectionEngineImpl {
        let configs = AgentConfigService.defaultAgentConfigs()
        let compiled = configs.map { AgentConfigService.compile($0) }
        return AgentDetectionEngineImpl(
            compiledConfigs: compiled,
            debounceInterval: debounce
        )
    }

    /// Deterministic signal that transitions the state machine from
    /// `.idle` to `.agentLaunched`, which is the only valid move out of
    /// idle in the transition table.
    private func launchSignal(
        agentName: String = "claude"
    ) -> DetectionSignal {
        DetectionSignal(
            event: .agentDetected(name: agentName),
            confidence: 1.0,
            source: .hook(event: "sessionStart")
        )
    }

    // MARK: - Backward compatibility

    @Test("Legacy injectSignal (no surfaceID) emits StateContext with surfaceID == nil")
    func legacyInjectEmitsNilSurfaceID() {
        let engine = makeEngine()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignal(launchSignal())

        #expect(captured.count == 1)
        #expect(captured.first?.surfaceID == nil)
        #expect(captured.first?.state == .agentLaunched)
    }

    @Test("Legacy processTerminalOutput(_:) overload does not crash when empty")
    func legacyProcessOverloadSeedsNil() {
        let engine = makeEngine()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        // Exercise the default implementation provided by the
        // AgentDetecting protocol extension. Empty data produces no
        // emission; we only assert the legacy overload reaches the
        // engine without crashing.
        let detector: AgentDetecting = engine
        detector.processTerminalOutput(Data())

        #expect(captured.isEmpty)
    }

    // MARK: - Per-surface routing

    @Test("injectSignal with explicit surfaceID propagates to StateContext")
    func explicitSurfaceIDPropagates() {
        let engine = makeEngine()
        let expected = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignal(launchSignal(), surfaceID: expected)

        #expect(captured.count == 1)
        #expect(captured.first?.surfaceID == expected)
    }

    @Test("injectSignal preserves per-call surfaceID across successive emissions")
    func surfaceIDDoesNotBleedBetweenCalls() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        // A: idle -> agentLaunched
        engine.injectSignal(
            launchSignal(agentName: "claude"),
            surfaceID: surfaceA
        )

        // B: agentLaunched -> working (outputReceived)
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surfaceB
        )

        #expect(captured.count == 2)
        #expect(captured[0].surfaceID == surfaceA)
        #expect(captured[0].state == .agentLaunched)
        #expect(captured[1].surfaceID == surfaceB)
        #expect(captured[1].state == .working)
    }

    @Test("injectSignalBatch propagates surfaceID to the resolved transition")
    func batchPropagatesSurfaceID() {
        let engine = makeEngine()
        let expected = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignalBatch(
            [
                launchSignal(agentName: "codex"),
                DetectionSignal(
                    event: .agentDetected(name: "codex"),
                    confidence: 0.7,
                    source: .pattern(name: "codex")
                )
            ],
            surfaceID: expected
        )

        #expect(captured.count == 1)
        #expect(captured.first?.surfaceID == expected)
    }

    // MARK: - Per-surface debounce buckets

    /// Deterministic signal that transitions agentLaunched -> idle so the
    /// state machine is returned to a state where another `.agentDetected`
    /// can fire. Used when building scenarios that need consecutive launch
    /// transitions on different surfaces.
    private func exitSignal() -> DetectionSignal {
        DetectionSignal(
            event: .agentExited,
            confidence: 1.0,
            source: .osc(code: 0)
        )
    }

    @Test("Before any signals, the engine tracks zero debounce buckets")
    func noBucketsInitially() {
        let engine = makeEngine()
        #expect(engine._debounceBucketCountForTesting == 0)
    }

    @Test("First signal on a surface creates an independent bucket for it")
    func firstSignalCreatesBucket() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.injectSignal(launchSignal(), surfaceID: surface)

        #expect(engine._debounceBucketCountForTesting == 1)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected")
        #expect(engine._debounceEventKeyForTesting(surfaceID: nil) == nil)
    }

    @Test("Signals from distinct surfaces produce distinct debounce buckets")
    func distinctSurfacesProduceDistinctBuckets() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        // A walks idle -> agentLaunched -> idle so the state machine is
        // ready to accept a new agentDetected on B.
        engine.injectSignal(launchSignal(), surfaceID: surfaceA)
        engine.injectSignal(exitSignal(), surfaceID: surfaceA)
        engine.injectSignal(launchSignal(), surfaceID: surfaceB)

        #expect(engine._debounceBucketCountForTesting == 2)
        // A's bucket reflects its last emission (agentExited), not the
        // initial agentDetected, since the bucket is overwritten on every
        // successful transition.
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceA) == "agentExited")
        // B's bucket carries its own event, independent of A.
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceB) == "agentDetected")
    }

    @Test("Legacy nil-surfaceID callers share one bucket, not a bucket with a real surface")
    func nilSurfaceBucketIsIsolatedFromRealSurfaces() {
        let engine = makeEngine()
        let surface = SurfaceID()

        // Legacy call (no surfaceID) seeds the nil bucket.
        engine.injectSignal(launchSignal())
        // Walk back to idle via the nil bucket.
        engine.injectSignal(exitSignal())
        // A real-surface call seeds a new bucket.
        engine.injectSignal(launchSignal(), surfaceID: surface)

        #expect(engine._debounceBucketCountForTesting == 2)
        #expect(engine._debounceEventKeyForTesting(surfaceID: nil) == "agentExited")
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected")
    }

    @Test("reset() clears every per-surface debounce bucket")
    func resetClearsAllBuckets() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        engine.injectSignal(launchSignal(), surfaceID: surfaceA)
        engine.injectSignal(exitSignal(), surfaceID: surfaceA)
        engine.injectSignal(launchSignal(), surfaceID: surfaceB)

        #expect(engine._debounceBucketCountForTesting == 2)

        engine.reset()

        #expect(engine._debounceBucketCountForTesting == 0)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceA) == nil)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceB) == nil)
        #expect(engine._debounceEventKeyForTesting(surfaceID: nil) == nil)
    }

    // MARK: - Per-surface hook session buckets

    private func hookEvent(
        type: HookEventType,
        sessionId: String
    ) -> HookEvent {
        HookEvent(type: type, sessionId: sessionId)
    }

    @Test("No hook sessions are tracked before any SessionStart event")
    func noHookSessionsInitially() {
        let engine = makeEngine()
        #expect(engine.hookActiveSurfaces.isEmpty)
        #expect(engine.hookActiveSessions.isEmpty)
    }

    @Test("SessionStart registers the session in the surface's hook bucket")
    func sessionStartRegistersInSurfaceBucket() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-1"),
            surfaceID: surface
        )

        #expect(engine._hookSessionsForTesting(surfaceID: surface) == ["sess-1"])
        #expect(engine._hookSessionsForTesting(surfaceID: nil).isEmpty)
    }

    @Test("Hook sessions from distinct surfaces live in distinct buckets")
    func hookBucketsAreIndependent() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-A"),
            surfaceID: surfaceA
        )
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-B"),
            surfaceID: surfaceB
        )

        #expect(engine._hookSessionsForTesting(surfaceID: surfaceA) == ["sess-A"])
        #expect(engine._hookSessionsForTesting(surfaceID: surfaceB) == ["sess-B"])
        #expect(engine.hookActiveSessions == ["sess-A", "sess-B"])
    }

    @Test("SessionEnd removes the session and prunes the bucket when empty")
    func sessionEndRemovesFromBucket() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-1"),
            surfaceID: surface
        )
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-2"),
            surfaceID: surface
        )
        #expect(engine._hookSessionsForTesting(surfaceID: surface) == ["sess-1", "sess-2"])

        engine.processHookEvent(
            hookEvent(type: .sessionEnd, sessionId: "sess-1"),
            surfaceID: surface
        )
        // Surface still tracked because sess-2 remains.
        #expect(engine._hookSessionsForTesting(surfaceID: surface) == ["sess-2"])
        #expect(engine.hookActiveSurfaces[surface] != nil)

        engine.processHookEvent(
            hookEvent(type: .stop, sessionId: "sess-2"),
            surfaceID: surface
        )
        // Bucket is pruned once empty.
        #expect(engine._hookSessionsForTesting(surfaceID: surface).isEmpty)
        #expect(engine.hookActiveSurfaces[surface] == nil)
    }

    @Test("Legacy nil-surfaceID callers keep sessions in their own bucket")
    func legacyNilBucketSharedAcrossLegacyCallers() {
        let engine = makeEngine()

        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "legacy-1")
        )
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "legacy-2")
        )

        #expect(engine._hookSessionsForTesting(surfaceID: nil) == ["legacy-1", "legacy-2"])
        #expect(engine._hookSessionsForTesting(surfaceID: SurfaceID()).isEmpty)
    }

    // MARK: - notifyUserInput / notifyProcessExited surfaceID threading

    @Test("notifyUserInput threads surfaceID into the emitted StateContext")
    func notifyUserInputThreadsSurfaceID() {
        let engine = makeEngine()
        let surface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        // Walk the state machine to .waitingInput so .userInput has a
        // valid transition to .working.
        engine.injectSignal(launchSignal(), surfaceID: surface)
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surface
        )
        engine.injectSignal(
            DetectionSignal(
                event: .promptDetected,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surface
        )
        // State is now .waitingInput; surfaceID threaded through every emission.

        engine.notifyUserInput(surfaceID: surface)

        // 4 transitions: idle -> agentLaunched -> working -> waitingInput -> working.
        #expect(captured.count == 4)
        #expect(captured.last?.state == .working)
        #expect(captured.last?.surfaceID == surface)
        #expect(captured.allSatisfy { $0.surfaceID == surface })
    }

    @Test("notifyProcessExited threads surfaceID into the emitted StateContext")
    func notifyProcessExitedThreadsSurfaceID() {
        let engine = makeEngine()
        let surface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignal(launchSignal(), surfaceID: surface)
        engine.notifyProcessExited(surfaceID: surface)

        #expect(captured.count == 2)
        #expect(captured.last?.state == .idle)
        #expect(captured.last?.surfaceID == surface)
    }

    @Test("Legacy notifyUserInput/notifyProcessExited default to nil surfaceID")
    func legacyNotifyHelpersSeedNilSurfaceID() {
        let engine = makeEngine()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        // Exercise the default implementations from the protocol extension
        // by calling through an AgentDetecting reference.
        let detector: AgentDetecting = engine
        engine.injectSignal(launchSignal())  // idle -> agentLaunched
        detector.notifyProcessExited()       // legacy overload -> nil

        #expect(captured.count == 2)
        #expect(captured[0].surfaceID == nil)
        #expect(captured[1].state == .idle)
        #expect(captured[1].surfaceID == nil)
    }

    // MARK: - reset

    @Test("reset() clears every per-surface hook bucket")
    func resetClearsHookBuckets() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-1"),
            surfaceID: surface
        )
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "legacy-1")
        )

        #expect(!engine.hookActiveSessions.isEmpty)

        engine.reset()

        #expect(engine.hookActiveSurfaces.isEmpty)
        #expect(engine.hookActiveSessions.isEmpty)
    }
}
