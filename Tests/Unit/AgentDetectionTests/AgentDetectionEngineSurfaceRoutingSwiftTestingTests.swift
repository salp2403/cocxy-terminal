// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("AgentDetectionEngine surfaceID routing")
struct AgentDetectionEngineSurfaceRoutingSwiftTestingTests {

    private func makeEngine(
        debounce: TimeInterval = 0.0,
        timingSustainedOutputThreshold: TimeInterval = 2.0
    ) -> AgentDetectionEngineImpl {
        let configs = AgentConfigService.defaultAgentConfigs()
        let compiled = configs.map { AgentConfigService.compile($0) }
        return AgentDetectionEngineImpl(
            compiledConfigs: compiled,
            debounceInterval: debounce,
            timingSustainedOutputThreshold: timingSustainedOutputThreshold
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

        // B walks its own lifecycle. A's launch must not be reused as
        // B's precondition for outputReceived.
        engine.injectSignal(
            launchSignal(agentName: "codex"),
            surfaceID: surfaceB
        )
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surfaceB
        )

        #expect(captured.count == 3)
        #expect(captured[0].surfaceID == surfaceA)
        #expect(captured[0].state == .agentLaunched)
        #expect(captured[1].surfaceID == surfaceB)
        #expect(captured[1].state == .agentLaunched)
        #expect(captured[1].agentName == "codex")
        #expect(captured[2].surfaceID == surfaceB)
        #expect(captured[2].state == .working)
        #expect(captured[2].agentName == "codex")
    }

    @Test("Distinct surfaces keep independent lifecycle state and agent identity")
    func distinctSurfacesKeepIndependentLifecycleState() {
        let engine = makeEngine()
        let claudeSurface = SurfaceID()
        let codexSurface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignal(
            launchSignal(agentName: "codex"),
            surfaceID: codexSurface
        )
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: codexSurface
        )

        engine.injectSignal(
            launchSignal(agentName: "claude"),
            surfaceID: claudeSurface
        )

        #expect(captured.count == 3)
        #expect(captured[0].surfaceID == codexSurface)
        #expect(captured[0].agentName == "codex")
        #expect(captured[1].surfaceID == codexSurface)
        #expect(captured[1].agentName == "codex")
        #expect(captured[2].surfaceID == claudeSurface)
        #expect(captured[2].state == .agentLaunched)
        #expect(captured[2].agentName == "claude")
        #expect(engine._stateForTesting(surfaceID: codexSurface) == .working)
        #expect(engine._agentNameForTesting(surfaceID: codexSurface) == "codex")
        #expect(engine._stateForTesting(surfaceID: claudeSurface) == .agentLaunched)
        #expect(engine._agentNameForTesting(surfaceID: claudeSurface) == "claude")
    }

    @Test("Fresh launch on same surface replaces stale agent name")
    func freshLaunchOnSameSurfaceReplacesStaleAgentName() {
        let engine = makeEngine()
        let surface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignal(launchSignal(agentName: "codex"), surfaceID: surface)
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surface
        )
        engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surface)

        #expect(engine._stateForTesting(surfaceID: surface) == .agentLaunched)
        #expect(engine._agentNameForTesting(surfaceID: surface) == "claude")
        #expect(captured.last?.previousState == .working)
        #expect(captured.last?.state == .agentLaunched)
        #expect(captured.last?.agentName == "claude")
        #expect(captured.last?.surfaceID == surface)
    }

    @Test("Debounce suppresses duplicate launch for same agent but not another agent")
    func debounceIsScopedByAgentIdentityForLaunchEvents() {
        let engine = makeEngine(debounce: 10.0)
        let surface = SurfaceID()

        engine.injectSignal(launchSignal(agentName: "codex"), surfaceID: surface)
        engine.injectSignal(launchSignal(agentName: "codex"), surfaceID: surface)

        #expect(engine._agentNameForTesting(surfaceID: surface) == "codex")
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:codex")

        engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surface)

        #expect(engine._stateForTesting(surfaceID: surface) == .agentLaunched)
        #expect(engine._agentNameForTesting(surfaceID: surface) == "claude")
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:claude")
    }

    @Test("Process exit on one surface does not idle a sibling agent")
    func processExitDoesNotIdleSiblingSurface() {
        let engine = makeEngine()
        let claudeSurface = SurfaceID()
        let codexSurface = SurfaceID()

        engine.injectSignal(
            launchSignal(agentName: "claude"),
            surfaceID: claudeSurface
        )
        engine.injectSignal(
            launchSignal(agentName: "codex"),
            surfaceID: codexSurface
        )
        engine.notifyProcessExited(surfaceID: codexSurface)

        #expect(engine._stateForTesting(surfaceID: codexSurface) == .idle)
        #expect(engine._agentNameForTesting(surfaceID: codexSurface) == nil)
        #expect(engine._stateForTesting(surfaceID: claudeSurface) == .agentLaunched)
        #expect(engine._agentNameForTesting(surfaceID: claudeSurface) == "claude")

        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: claudeSurface
        )

        #expect(engine._stateForTesting(surfaceID: claudeSurface) == .working)
        #expect(engine._agentNameForTesting(surfaceID: claudeSurface) == "claude")
    }

    @Test("Real Codex and Claude banners route to their own surfaces")
    func realBannersRouteToTheirOwnSurfaces() async throws {
        let engine = makeEngine()
        let claudeSurface = SurfaceID()
        let codexSurface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        let codexBanner = """
        OpenAI Codex (v0.121.0)
        OpenAI Codex
        model: gpt-5.4 xhigh

        """
        engine.processTerminalOutput(Data(codexBanner.utf8), surfaceID: codexSurface)
        try await Task.sleep(nanoseconds: 100_000_000)
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: codexSurface
        )

        let claudeBanner = """
        Claude Code v2.1.14
        Opus 4.7 (1M context) with xhigh effort · Claude Max
        ~/sisocs-v3

        """
        engine.processTerminalOutput(Data(claudeBanner.utf8), surfaceID: claudeSurface)
        try await Task.sleep(nanoseconds: 100_000_000)

        let claudeLaunch = captured.last {
            $0.surfaceID == claudeSurface && $0.state == .agentLaunched
        }
        let codexWorking = captured.last {
            $0.surfaceID == codexSurface && $0.state == .working
        }

        #expect(codexWorking?.agentName == "codex")
        #expect(claudeLaunch?.agentName == "claude")
        #expect(engine._agentNameForTesting(surfaceID: codexSurface) == "codex")
        #expect(engine._agentNameForTesting(surfaceID: claudeSurface) == "claude")
    }

    @Test("Claude banner replaces stale Codex state on same surface")
    func claudeBannerReplacesStaleCodexStateOnSameSurface() async throws {
        let engine = makeEngine()
        let surface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        let codexBanner = """
        OpenAI Codex (v0.121.0)
        OpenAI Codex
        model: gpt-5.4 xhigh

        """
        engine.processTerminalOutput(Data(codexBanner.utf8), surfaceID: surface)
        try await Task.sleep(nanoseconds: 80_000_000)
        engine.injectSignal(
            DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surface
        )

        #expect(engine._stateForTesting(surfaceID: surface) == .working)
        #expect(engine._agentNameForTesting(surfaceID: surface) == "codex")

        let claudeBanner = """
        Claude Code v2.1.14
        Opus 4.7 (1M context) with xhigh effort · Claude Max
        ~/sisocs-v3

        """
        engine.processTerminalOutput(Data(claudeBanner.utf8), surfaceID: surface)
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(engine._stateForTesting(surfaceID: surface) == .agentLaunched)
        #expect(engine._agentNameForTesting(surfaceID: surface) == "claude")
        #expect(captured.last?.previousState == .working)
        #expect(captured.last?.agentName == "claude")
    }

    @Test("Pattern launch windows are isolated per surface")
    func patternLaunchWindowsAreIsolatedPerSurface() async throws {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        // Each surface sees only one Claude-specific banner line. With
        // the old shared PatternMatchingDetector these two lines
        // combined into a false launch on the second surface. Per-surface
        // detector windows must keep them separate.
        engine.processTerminalOutput(Data("Claude Code v2.1.14\n".utf8), surfaceID: surfaceA)
        engine.processTerminalOutput(Data("Claude Code v2.1.14\n".utf8), surfaceID: surfaceB)
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(captured.isEmpty)
        #expect(engine._stateForTesting(surfaceID: surfaceA) == .idle)
        #expect(engine._stateForTesting(surfaceID: surfaceB) == .idle)

        engine.processTerminalOutput(
            Data("Opus 4.7 (1M context) with xhigh effort · Claude Max\n".utf8),
            surfaceID: surfaceA
        )
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(captured.count == 1)
        #expect(captured.last?.surfaceID == surfaceA)
        #expect(captured.last?.agentName == "claude")
        #expect(engine._stateForTesting(surfaceID: surfaceA) == .agentLaunched)
        #expect(engine._stateForTesting(surfaceID: surfaceB) == .idle)
    }

    @Test("Pattern detectors can launch two different agents in sibling surfaces")
    func patternDetectorsLaunchTwoSiblingAgents() async throws {
        let engine = makeEngine()
        let claudeSurface = SurfaceID()
        let codexSurface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.processTerminalOutput(
            Data("Claude Code v2.1.14\nOpus 4.7 (1M context) with xhigh effort · Claude Max\n".utf8),
            surfaceID: claudeSurface
        )
        engine.processTerminalOutput(
            Data("OpenAI Codex (v0.121.0)\nOpenAI Codex\n".utf8),
            surfaceID: codexSurface
        )
        try await Task.sleep(nanoseconds: 120_000_000)

        let launches = captured.filter { $0.state == .agentLaunched }
        #expect(launches.count == 2)
        #expect(launches.contains { $0.surfaceID == claudeSurface && $0.agentName == "claude" })
        #expect(launches.contains { $0.surfaceID == codexSurface && $0.agentName == "codex" })
        #expect(engine._agentNameForTesting(surfaceID: claudeSurface) == "claude")
        #expect(engine._agentNameForTesting(surfaceID: codexSurface) == "codex")
    }

    @Test("Timing fallback signals keep the originating surfaceID")
    func timingFallbackSignalsKeepOriginatingSurfaceID() async throws {
        let engine = makeEngine(timingSustainedOutputThreshold: 0.05)
        let surface = SurfaceID()

        var captured: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { ctx in
            captured.append(ctx)
        }
        defer { cancellable.cancel() }

        engine.injectSignal(
            launchSignal(agentName: "claude"),
            surfaceID: surface
        )

        engine.processTerminalOutput(Data("first output chunk\n".utf8), surfaceID: surface)
        try await Task.sleep(nanoseconds: 80_000_000)
        engine.processTerminalOutput(Data("second output chunk\n".utf8), surfaceID: surface)
        try await Task.sleep(nanoseconds: 120_000_000)

        let timingTransition = captured.last {
            $0.surfaceID == surface && $0.state == .working
        }

        if case .outputReceived? = timingTransition?.transitionEvent {
            // Expected timing fallback event.
        } else {
            Issue.record("Expected timing fallback to emit outputReceived")
        }
        #expect(timingTransition?.agentName == "claude")
        #expect(engine._stateForTesting(surfaceID: surface) == .working)
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
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:claude")
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
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceB) == "agentDetected:claude")
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
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:claude")
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

    // MARK: - clearSurface lifecycle

    @Test("clearSurface on an untouched surface is a no-op")
    func clearSurfaceNoOpOnUntouchedSurface() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.clearSurface(surface)

        #expect(engine._debounceBucketCountForTesting == 0)
        #expect(engine._hookSessionsForTesting(surfaceID: surface).isEmpty)
        #expect(engine.hookActiveSurfaces.isEmpty)
    }

    @Test("clearSurface removes the debounce bucket for the given surface")
    func clearSurfaceRemovesDebounceBucket() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.injectSignal(launchSignal(), surfaceID: surface)
        #expect(engine._debounceBucketCountForTesting == 1)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:claude")

        engine.clearSurface(surface)

        #expect(engine._debounceBucketCountForTesting == 0)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == nil)
    }

    @Test("clearSurface removes the hook session bucket for the given surface")
    func clearSurfaceRemovesHookBucket() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-lifecycle"),
            surfaceID: surface
        )
        #expect(engine._hookSessionsForTesting(surfaceID: surface) == ["sess-lifecycle"])

        engine.clearSurface(surface)

        #expect(engine._hookSessionsForTesting(surfaceID: surface).isEmpty)
        #expect(engine.hookActiveSurfaces[surface] == nil)
    }

    @Test("clearSurface is idempotent across repeated calls")
    func clearSurfaceIsIdempotent() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.injectSignal(launchSignal(), surfaceID: surface)
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-idem"),
            surfaceID: surface
        )

        engine.clearSurface(surface)
        engine.clearSurface(surface)
        engine.clearSurface(surface)

        #expect(engine._debounceBucketCountForTesting == 0)
        #expect(engine._hookSessionsForTesting(surfaceID: surface).isEmpty)
    }

    @Test("clearSurface does not touch buckets of other surfaces")
    func clearSurfaceIsolatesOtherSurfaces() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        // Populate debounce buckets for both surfaces, returning the
        // state machine to idle between A's two transitions so the
        // second one (exit) can actually fire.
        engine.injectSignal(launchSignal(), surfaceID: surfaceA)
        engine.injectSignal(exitSignal(), surfaceID: surfaceA)
        engine.injectSignal(launchSignal(), surfaceID: surfaceB)

        // Populate hook bucket for B only.
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-B"),
            surfaceID: surfaceB
        )

        engine.clearSurface(surfaceA)

        #expect(engine._debounceBucketCountForTesting == 1)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceA) == nil)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surfaceB) == "agentDetected:claude-code")
        #expect(engine._hookSessionsForTesting(surfaceID: surfaceA).isEmpty)
        #expect(engine._hookSessionsForTesting(surfaceID: surfaceB) == ["sess-B"])
    }

    @Test("clearSurface(nil) clears only the legacy shared bucket")
    func clearSurfaceNilClearsLegacyBucketOnly() {
        let engine = makeEngine()
        let surface = SurfaceID()

        // Seed the legacy (nil) bucket via the untouched-caller path,
        // then return to idle so the real-surface path can fire its
        // own agentDetected transition.
        engine.injectSignal(launchSignal())
        engine.injectSignal(exitSignal())
        engine.injectSignal(launchSignal(), surfaceID: surface)

        #expect(engine._debounceEventKeyForTesting(surfaceID: nil) == "agentExited")
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:claude")

        engine.clearSurface(nil)

        #expect(engine._debounceEventKeyForTesting(surfaceID: nil) == nil)
        #expect(engine._debounceEventKeyForTesting(surfaceID: surface) == "agentDetected:claude")
    }

    @Test("clearSurface releases only the selected surface state machine")
    func clearSurfaceReleasesOnlySelectedSurfaceStateMachine() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        engine.injectSignal(launchSignal(agentName: "claude"), surfaceID: surfaceA)
        engine.injectSignal(launchSignal(agentName: "codex"), surfaceID: surfaceB)
        #expect(engine.currentState == .agentLaunched)

        engine.clearSurface(surfaceA)

        // Reading A after clear creates a fresh idle machine. B's machine
        // remains live, proving teardown of one split does not idle a
        // sibling agent.
        #expect(engine._stateForTesting(surfaceID: surfaceA) == .idle)
        #expect(engine._agentNameForTesting(surfaceID: surfaceA) == nil)
        #expect(engine._stateForTesting(surfaceID: surfaceB) == .agentLaunched)
        #expect(engine._agentNameForTesting(surfaceID: surfaceB) == "codex")
        #expect(engine.currentState == .agentLaunched)
    }

    @Test("Via AgentDetecting protocol, clearSurface reaches the engine implementation")
    func clearSurfaceReachableViaProtocol() {
        let engine = makeEngine()
        let surface = SurfaceID()

        engine.injectSignal(launchSignal(), surfaceID: surface)
        #expect(engine._debounceBucketCountForTesting == 1)

        // Exercise the method through the protocol type to confirm the
        // engine's implementation is preferred over the default no-op
        // provided by the extension.
        let detector: AgentDetecting = engine
        detector.clearSurface(surface)

        #expect(engine._debounceBucketCountForTesting == 0)
    }

    // MARK: - notifyProcessExited does NOT clear buckets on its own

    @Test("notifyProcessExited leaves per-surface buckets populated — clearSurface is the one that drops them")
    func notifyProcessExitedDoesNotClearBuckets() {
        // Regression guard for the Fase 4 process-exit handler in
        // `MainWindowController+SurfaceLifecycle`. That call site runs
        // both `notifyProcessExited` and `clearSurface` because the
        // exit transition emits a final state but does NOT release the
        // engine's debounce and hook-session buckets. If we ever drop
        // the `clearSurface` call under the assumption that
        // `notifyProcessExited` is enough, this test flags it.
        let engine = makeEngine()
        let surface = SurfaceID()

        // Seed debounce and hook-session state on the surface.
        engine.injectSignal(launchSignal(), surfaceID: surface)
        engine.processHookEvent(
            hookEvent(type: .sessionStart, sessionId: "sess-exit"),
            surfaceID: surface
        )

        #expect(engine._debounceBucketCountForTesting == 1)
        #expect(engine._hookSessionsForTesting(surfaceID: surface) == ["sess-exit"])

        // `notifyProcessExited` only fires the agentExited transition.
        engine.notifyProcessExited(surfaceID: surface)

        // Debounce bucket stays populated (a new key was just written
        // by the agentExited signal), and the hook session also
        // remains — buckets are the engine's per-surface routing
        // state, not lifecycle state.
        #expect(engine._debounceBucketCountForTesting >= 1)
        #expect(engine._hookSessionsForTesting(surfaceID: surface) == ["sess-exit"])

        // `clearSurface` is the one that actually drops the buckets.
        engine.clearSurface(surface)

        #expect(engine._debounceBucketCountForTesting == 0)
        #expect(engine._hookSessionsForTesting(surfaceID: surface).isEmpty)
    }
}
