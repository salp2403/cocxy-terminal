// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateMachineTests.swift - Tests for the agent state machine.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent State Machine Tests

/// Tests for `AgentStateMachine` state transitions, history, and publishers.
///
/// Covers:
/// - Initial state is idle.
/// - All valid transitions from ADR-004 (18 transitions).
/// - Invalid transitions are silently ignored.
/// - StateContext correctness (timestamps, events, metadata).
/// - Reset from any state.
/// - Transition history (capped at 50).
/// - Combine publisher emissions.
/// - Agent name propagation through transitions.
/// - Error metadata propagation.
/// - Tab.AgentState mapping.
@MainActor
final class AgentStateMachineTests: XCTestCase {

    private var sut: AgentStateMachine!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AgentStateMachine()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        XCTAssertEqual(sut.currentState, .idle)
    }

    func testInitialHistoryIsEmpty() {
        XCTAssertTrue(sut.transitionHistory.isEmpty)
    }

    func testInitialAgentNameIsNil() {
        XCTAssertNil(sut.agentName)
    }

    // MARK: - Valid Transitions: idle ->

    func testIdleToAgentLaunchedOnAgentDetected() {
        sut.processEvent(.agentDetected(name: "claude"))

        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    // MARK: - Valid Transitions: agentLaunched ->

    func testAgentLaunchedToWorkingOnOutputReceived() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)

        XCTAssertEqual(sut.currentState, .working)
    }

    func testAgentLaunchedToErrorOnErrorDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.errorDetected(message: "segfault"))

        XCTAssertEqual(sut.currentState, .error)
    }

    func testAgentLaunchedToIdleOnAgentExited() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.agentExited)

        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - Valid Transitions: working ->

    func testWorkingToWaitingInputOnPromptDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)

        XCTAssertEqual(sut.currentState, .waitingInput)
    }

    func testWorkingToFinishedOnCompletionDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)

        XCTAssertEqual(sut.currentState, .finished)
    }

    func testWorkingToErrorOnErrorDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "timeout"))

        XCTAssertEqual(sut.currentState, .error)
    }

    func testWorkingToIdleOnAgentExited() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.agentExited)

        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - Valid Transitions: waitingInput ->

    func testWaitingInputToWorkingOnUserInput() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)
        sut.processEvent(.userInput)

        XCTAssertEqual(sut.currentState, .working)
    }

    func testWaitingInputToFinishedOnCompletionDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)
        sut.processEvent(.completionDetected)

        XCTAssertEqual(sut.currentState, .finished)
    }

    func testWaitingInputToErrorOnErrorDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)
        sut.processEvent(.errorDetected(message: "crash"))

        XCTAssertEqual(sut.currentState, .error)
    }

    func testWaitingInputToIdleOnAgentExited() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)
        sut.processEvent(.agentExited)

        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - Valid Transitions: finished ->

    func testFinishedToWorkingOnOutputReceived() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)
        sut.processEvent(.outputReceived)

        XCTAssertEqual(sut.currentState, .working)
    }

    func testFinishedToIdleOnIdleTimeout() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)
        sut.processEvent(.idleTimeout)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testFinishedToIdleOnAgentExited() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)
        sut.processEvent(.agentExited)

        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - Valid Transitions: error ->

    func testErrorToWorkingOnOutputReceived() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "oops"))
        sut.processEvent(.outputReceived)

        XCTAssertEqual(sut.currentState, .working)
    }

    func testErrorToIdleOnAgentExited() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "oops"))
        sut.processEvent(.agentExited)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testErrorToIdleOnIdleTimeout() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "oops"))
        sut.processEvent(.idleTimeout)

        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - Invalid Transitions

    func testIdleIgnoresOutputReceived() {
        sut.processEvent(.outputReceived)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testIdleIgnoresPromptDetected() {
        sut.processEvent(.promptDetected)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testIdleIgnoresCompletionDetected() {
        sut.processEvent(.completionDetected)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testIdleIgnoresUserInput() {
        sut.processEvent(.userInput)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testIdleIgnoresIdleTimeout() {
        sut.processEvent(.idleTimeout)

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testAgentLaunchedIgnoresPromptDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.promptDetected)

        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    func testAgentLaunchedIgnoresCompletionDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.completionDetected)

        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    func testWorkingIgnoresAgentDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.agentDetected(name: "codex"))

        XCTAssertEqual(sut.currentState, .working)
    }

    func testFinishedIgnoresPromptDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)
        sut.processEvent(.promptDetected)

        XCTAssertEqual(sut.currentState, .finished)
    }

    func testErrorIgnoresPromptDetected() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "fail"))
        sut.processEvent(.promptDetected)

        XCTAssertEqual(sut.currentState, .error)
    }

    // MARK: - Invalid Transition Does Not Record History

    func testInvalidTransitionDoesNotAddToHistory() {
        sut.processEvent(.outputReceived) // invalid from idle

        XCTAssertTrue(sut.transitionHistory.isEmpty)
    }

    // MARK: - Full Lifecycle (Happy Path)

    func testFullHappyPathLifecycle() {
        sut.processEvent(.agentDetected(name: "claude"))
        XCTAssertEqual(sut.currentState, .agentLaunched)

        sut.processEvent(.outputReceived)
        XCTAssertEqual(sut.currentState, .working)

        sut.processEvent(.promptDetected)
        XCTAssertEqual(sut.currentState, .waitingInput)

        sut.processEvent(.userInput)
        XCTAssertEqual(sut.currentState, .working)

        sut.processEvent(.completionDetected)
        XCTAssertEqual(sut.currentState, .finished)

        sut.processEvent(.idleTimeout)
        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - StateContext

    func testStateContextHasCorrectTimestamp() {
        let beforeTransition = Date()
        sut.processEvent(.agentDetected(name: "claude"))

        let context = sut.transitionHistory.last
        XCTAssertNotNil(context)
        XCTAssertGreaterThanOrEqual(context!.timestamp, beforeTransition)
        XCTAssertLessThanOrEqual(context!.timestamp, Date())
    }

    func testStateContextHasCorrectStates() {
        sut.processEvent(.agentDetected(name: "claude"))

        let context = sut.transitionHistory.last!
        XCTAssertEqual(context.state, .agentLaunched)
        XCTAssertEqual(context.previousState, .idle)
    }

    func testStateContextRecordsAgentName() {
        sut.processEvent(.agentDetected(name: "codex"))

        let context = sut.transitionHistory.last!
        XCTAssertEqual(context.agentName, "codex")
    }

    func testStateContextRecordsErrorMessage() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.errorDetected(message: "connection lost"))

        let context = sut.transitionHistory.last!
        XCTAssertEqual(context.metadata["errorMessage"], "connection lost")
    }

    // MARK: - Agent Name

    func testAgentNameIsSetOnAgentDetected() {
        sut.processEvent(.agentDetected(name: "aider"))

        XCTAssertEqual(sut.agentName, "aider")
    }

    func testAgentNameIsPreservedThroughTransitions() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)

        XCTAssertEqual(sut.agentName, "claude")
    }

    func testAgentNameIsClearedOnResetToIdle() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.agentExited)

        XCTAssertNil(sut.agentName)
    }

    // MARK: - Reset

    func testResetFromIdleRemainsIdle() {
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testResetFromAgentLaunched() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertNil(sut.agentName)
    }

    func testResetFromWorking() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testResetFromWaitingInput() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testResetFromFinished() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testResetFromError() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "fail"))
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
    }

    func testResetClearsHistory() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        XCTAssertFalse(sut.transitionHistory.isEmpty)

        sut.reset()

        XCTAssertTrue(sut.transitionHistory.isEmpty)
    }

    // MARK: - History

    func testHistoryRecordsTransitions() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)

        XCTAssertEqual(sut.transitionHistory.count, 3)
    }

    func testHistoryIsCappedAt50() {
        // Generate 60 transitions by cycling through valid states.
        for i in 0..<60 {
            if i % 3 == 0 {
                sut.processEvent(.agentDetected(name: "claude"))
            } else if i % 3 == 1 {
                sut.processEvent(.outputReceived)
            } else {
                sut.processEvent(.agentExited)
            }
        }

        XCTAssertLessThanOrEqual(sut.transitionHistory.count, 50)
    }

    func testHistoryMaintainsChronologicalOrder() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.completionDetected)

        let timestamps = sut.transitionHistory.map(\.timestamp)
        XCTAssertEqual(timestamps, timestamps.sorted())
    }

    // MARK: - Combine Publisher

    func testPublisherEmitsOnStateChange() {
        var receivedStates: [AgentStateMachine.State] = []

        sut.stateChanged
            .sink { context in
                receivedStates.append(context.state)
            }
            .store(in: &cancellables)

        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)

        XCTAssertEqual(receivedStates, [.agentLaunched, .working])
    }

    func testPublisherDoesNotEmitOnInvalidTransition() {
        var emissionCount = 0

        sut.stateChanged
            .sink { _ in
                emissionCount += 1
            }
            .store(in: &cancellables)

        sut.processEvent(.outputReceived) // invalid from idle

        XCTAssertEqual(emissionCount, 0)
    }

    func testPublisherContextIncludesPreviousState() {
        var receivedContext: AgentStateMachine.StateContext?

        sut.processEvent(.agentDetected(name: "claude"))

        sut.stateChanged
            .sink { context in
                receivedContext = context
            }
            .store(in: &cancellables)

        sut.processEvent(.outputReceived)

        XCTAssertEqual(receivedContext?.previousState, .agentLaunched)
        XCTAssertEqual(receivedContext?.state, .working)
    }

    // MARK: - Tab.AgentState Mapping

    func testMapIdleToTabAgentState() {
        XCTAssertEqual(AgentStateMachine.State.idle.toTabAgentState, .idle)
    }

    func testMapAgentLaunchedToTabAgentStateLaunched() {
        XCTAssertEqual(AgentStateMachine.State.agentLaunched.toTabAgentState, .launched)
    }

    func testMapWorkingToTabAgentState() {
        XCTAssertEqual(AgentStateMachine.State.working.toTabAgentState, .working)
    }

    func testMapWaitingInputToTabAgentState() {
        XCTAssertEqual(AgentStateMachine.State.waitingInput.toTabAgentState, .waitingInput)
    }

    func testMapFinishedToTabAgentState() {
        XCTAssertEqual(AgentStateMachine.State.finished.toTabAgentState, .finished)
    }

    func testMapErrorToTabAgentState() {
        XCTAssertEqual(AgentStateMachine.State.error.toTabAgentState, .error)
    }

    // MARK: - Error Metadata

    func testErrorMetadataIsStoredInContext() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.errorDetected(message: "SIGKILL received"))

        let errorContext = sut.transitionHistory.last!
        XCTAssertEqual(errorContext.state, .error)
        XCTAssertEqual(errorContext.metadata["errorMessage"], "SIGKILL received")
    }

    func testNonErrorTransitionHasEmptyMetadata() {
        sut.processEvent(.agentDetected(name: "claude"))

        let context = sut.transitionHistory.last!
        XCTAssertTrue(context.metadata.isEmpty || context.metadata["errorMessage"] == nil)
    }

    // MARK: - Edge Cases

    func testMultipleAgentDetectedFromIdleUpdatesName() {
        // First detection
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.agentExited)

        // Second detection with different name
        sut.processEvent(.agentDetected(name: "codex"))

        XCTAssertEqual(sut.agentName, "codex")
        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    func testRapidTransitionsAreAllRecorded() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.promptDetected)
        sut.processEvent(.userInput)
        sut.processEvent(.promptDetected)
        sut.processEvent(.userInput)
        sut.processEvent(.completionDetected)

        XCTAssertEqual(sut.transitionHistory.count, 7)
        XCTAssertEqual(sut.currentState, .finished)
    }

    func testErrorRecoveryToWorkingPreservesAgentName() {
        sut.processEvent(.agentDetected(name: "aider"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "temporary"))
        sut.processEvent(.outputReceived)

        XCTAssertEqual(sut.currentState, .working)
        XCTAssertEqual(sut.agentName, "aider")
    }
}
