// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for the engine entry points used by the per-surface
/// background dispatcher (Bug 4 phase 2). The dispatcher runs the three
/// detection layers (`OSCSequenceDetector`, `PatternMatchingDetector`,
/// `TimingHeuristicsDetector`) on a private serial queue, and then hands
/// the resulting signals back to the engine through these entry points
/// so the resolution + state-machine work stays on the main actor where
/// Combine subscribers (`@Published`, `stateChangedSubject`) expect it.
///
/// Two contracts must hold for the integration to be safe:
///   1. `detectorsForSurface(_:)` returns the same instances across
///      successive calls for a given surface — the surface lifecycle
///      caches the tuple at registration time and the detectors must
///      keep their per-chunk parser state intact between chunks.
///   2. `processBackgroundSignals(osc:pattern:surfaceID:)` resolves the
///      signals and produces a `stateChanged` emission on the main
///      thread, exactly like the legacy `processTerminalOutput(_:)`
///      does. The surfaceID flows through to the emitted StateContext.
@MainActor
@Suite("AgentDetectionEngine background-signal entry points")
struct AgentDetectionEngineBackgroundSignalsSwiftTestingTests {

    private func makeEngine(
        debounce: TimeInterval = 0.0
    ) -> AgentDetectionEngineImpl {
        let configs = AgentConfigService.defaultAgentConfigs()
        let compiled = configs.map { AgentConfigService.compile($0) }
        return AgentDetectionEngineImpl(
            compiledConfigs: compiled,
            debounceInterval: debounce
        )
    }

    private func launchSignal(
        agentName: String = "claude"
    ) -> DetectionSignal {
        DetectionSignal(
            event: .agentDetected(name: agentName),
            confidence: 1.0,
            source: .hook(event: "sessionStart")
        )
    }

    // MARK: - detectorsForSurface caching

    @Test("detectorsForSurface returns the same instances across successive calls")
    func detectorsForSurfaceCachesInstances() {
        let engine = makeEngine()
        let surface = SurfaceID()

        let first = engine.detectorsForSurface(surface)
        let second = engine.detectorsForSurface(surface)

        #expect(first.osc === second.osc)
        #expect(first.pattern === second.pattern)
        #expect(first.timing === second.timing)
    }

    @Test("detectorsForSurface returns distinct instances for distinct surfaces")
    func detectorsForSurfaceIsolatesSurfaces() {
        let engine = makeEngine()
        let surfaceA = SurfaceID()
        let surfaceB = SurfaceID()

        let bundleA = engine.detectorsForSurface(surfaceA)
        let bundleB = engine.detectorsForSurface(surfaceB)

        #expect(bundleA.osc !== bundleB.osc)
        #expect(bundleA.pattern !== bundleB.pattern)
        #expect(bundleA.timing !== bundleB.timing)
    }

    @Test("detectorsForSurface with nil returns the legacy detectors")
    func detectorsForSurfaceNilReusesLegacy() {
        let engine = makeEngine()

        let firstNil = engine.detectorsForSurface(nil)
        let secondNil = engine.detectorsForSurface(nil)

        #expect(firstNil.osc === secondNil.osc)
        #expect(firstNil.pattern === secondNil.pattern)
        #expect(firstNil.timing === secondNil.timing)
    }

    // MARK: - processBackgroundSignals

    @Test("processBackgroundSignals emits a state transition for a launch signal")
    func processBackgroundSignalsEmitsTransition() async {
        let engine = makeEngine()
        let surface = SurfaceID()

        // Drain the publisher so the assertion can wait for the first
        // emission deterministically without sleeping.
        let received = await withCheckedContinuation { (cont: CheckedContinuation<AgentStateMachine.StateContext, Never>) in
            var cancellable: AnyCancellable?
            cancellable = engine.stateChanged.sink { ctx in
                cancellable?.cancel()
                cont.resume(returning: ctx)
            }
            // Hand the engine a single-source signal as if the OSC
            // detector had produced it on the background queue.
            engine.processBackgroundSignals(
                osc: [launchSignal()],
                pattern: [],
                surfaceID: surface
            )
        }

        #expect(received.surfaceID == surface)
        #expect(received.state == .agentLaunched)
        #expect(received.agentName == "claude")
    }

    @Test("processBackgroundSignals with no signals does not emit anything")
    func processBackgroundSignalsEmptyIsNoOp() async {
        let engine = makeEngine()

        var emissions: [AgentStateMachine.StateContext] = []
        let cancellable = engine.stateChanged.sink { emissions.append($0) }
        defer { cancellable.cancel() }

        engine.processBackgroundSignals(
            osc: [],
            pattern: [],
            surfaceID: SurfaceID()
        )

        // Yield long enough for any internal `Task { @MainActor }` to
        // complete so we can prove that no late emission slipped in.
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(emissions.isEmpty)
    }

    @Test("processBackgroundSignals attributes the transition to the supplied surfaceID")
    func processBackgroundSignalsCarriesSurfaceID() async {
        let engine = makeEngine()
        let surface = SurfaceID()

        let received = await withCheckedContinuation { (cont: CheckedContinuation<AgentStateMachine.StateContext, Never>) in
            var cancellable: AnyCancellable?
            cancellable = engine.stateChanged.sink { ctx in
                cancellable?.cancel()
                cont.resume(returning: ctx)
            }
            engine.processBackgroundSignals(
                osc: [],
                pattern: [launchSignal(agentName: "codex")],
                surfaceID: surface
            )
        }

        #expect(received.surfaceID == surface)
        #expect(received.agentName == "codex")
    }
}
