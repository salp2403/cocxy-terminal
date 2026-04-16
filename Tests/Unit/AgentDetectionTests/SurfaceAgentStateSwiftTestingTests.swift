// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SurfaceAgentState")
struct SurfaceAgentStateSwiftTestingTests {

    @Test("Default init yields canonical idle state")
    func defaultInitIsIdle() {
        let state = SurfaceAgentState()
        #expect(state.agentState == .idle)
        #expect(state.detectedAgent == nil)
        #expect(state.agentActivity == nil)
        #expect(state.agentToolCount == 0)
        #expect(state.agentErrorCount == 0)
    }

    @Test("Static .idle equals default-initialized instance")
    func staticIdleEqualsDefault() {
        #expect(SurfaceAgentState.idle == SurfaceAgentState())
    }

    @Test("Explicit init preserves all fields")
    func explicitInitPreservesFields() {
        let agent = DetectedAgent(
            name: "claude",
            displayName: "Claude Code",
            launchCommand: "claude",
            startedAt: Date(timeIntervalSince1970: 1_734_000_000)
        )
        let state = SurfaceAgentState(
            agentState: .working,
            detectedAgent: agent,
            agentActivity: "Read: main.swift",
            agentToolCount: 5,
            agentErrorCount: 1
        )

        #expect(state.agentState == .working)
        #expect(state.detectedAgent == agent)
        #expect(state.agentActivity == "Read: main.swift")
        #expect(state.agentToolCount == 5)
        #expect(state.agentErrorCount == 1)
    }

    @Test("isActive is true only for launched, working, waitingInput")
    func isActiveLiveStates() {
        var state = SurfaceAgentState()

        state.agentState = .idle
        #expect(!state.isActive)

        state.agentState = .launched
        #expect(state.isActive)

        state.agentState = .working
        #expect(state.isActive)

        state.agentState = .waitingInput
        #expect(state.isActive)

        state.agentState = .finished
        #expect(!state.isActive)

        state.agentState = .error
        #expect(!state.isActive)
    }

    @Test("hasAgent mirrors detectedAgent presence")
    func hasAgentMirrorsDetectedAgent() {
        var state = SurfaceAgentState()
        #expect(!state.hasAgent)

        state.detectedAgent = DetectedAgent(
            name: "codex",
            launchCommand: "codex",
            startedAt: Date()
        )
        #expect(state.hasAgent)

        state.detectedAgent = nil
        #expect(!state.hasAgent)
    }

    @Test("Codable round trip preserves every field")
    func codableRoundTrip() throws {
        let original = SurfaceAgentState(
            agentState: .working,
            detectedAgent: DetectedAgent(
                name: "codex",
                displayName: "Codex CLI",
                launchCommand: "codex --model gpt-5",
                startedAt: Date(timeIntervalSince1970: 1_734_000_000)
            ),
            agentActivity: "Read: Package.swift",
            agentToolCount: 7,
            agentErrorCount: 1
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SurfaceAgentState.self, from: data)

        #expect(decoded == original)
    }

    @Test("Equatable distinguishes state differences")
    func equatableDistinguishesDifferences() {
        let working = SurfaceAgentState(agentState: .working)
        let waiting = SurfaceAgentState(agentState: .waitingInput)
        let workingCopy = SurfaceAgentState(agentState: .working)

        #expect(working != waiting)
        #expect(working == workingCopy)
    }
}
