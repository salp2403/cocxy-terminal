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
}
