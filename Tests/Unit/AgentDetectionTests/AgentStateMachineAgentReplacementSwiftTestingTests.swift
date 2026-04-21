// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Agent state machine agent replacement")
@MainActor
struct AgentStateMachineAgentReplacementSwiftTestingTests {

    @Test("Fresh agent launch replaces stale working agent identity")
    func freshAgentLaunchReplacesStaleWorkingAgentIdentity() {
        let machine = AgentStateMachine()

        machine.processEvent(.agentDetected(name: "codex"))
        machine.processEvent(.outputReceived)
        machine.processEvent(.agentDetected(name: "claude"))

        #expect(machine.currentState == .agentLaunched)
        #expect(machine.agentName == "claude")
        #expect(machine.transitionHistory.last?.previousState == .working)
        #expect(machine.transitionHistory.last?.agentName == "claude")
    }

    @Test("Duplicate launch for same active agent stays stable")
    func duplicateLaunchForSameActiveAgentStaysStable() {
        let machine = AgentStateMachine()

        machine.processEvent(.agentDetected(name: "claude"))
        machine.processEvent(.outputReceived)
        let historyCount = machine.transitionHistory.count
        machine.processEvent(.agentDetected(name: "claude"))

        #expect(machine.currentState == .working)
        #expect(machine.agentName == "claude")
        #expect(machine.transitionHistory.count == historyCount)
    }

    @Test("Fresh launch after finished state starts a new session")
    func freshLaunchAfterFinishedStateStartsNewSession() {
        let machine = AgentStateMachine()

        machine.processEvent(.agentDetected(name: "codex"))
        machine.processEvent(.outputReceived)
        machine.processEvent(.completionDetected)
        machine.processEvent(.agentDetected(name: "claude"))

        #expect(machine.currentState == .agentLaunched)
        #expect(machine.agentName == "claude")
        #expect(machine.transitionHistory.last?.previousState == .finished)
    }
}
