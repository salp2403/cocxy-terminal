// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDetectionEngineTests.swift - Tests for the agent detection engine orchestrator.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent Detection Engine Tests

/// Tests for `AgentDetectionEngineImpl` covering:
/// - Signal priority: OSC > pattern > timing.
/// - Debounce: rapid signals produce only 1 transition.
/// - Full lifecycle: launch -> working -> waiting -> working -> finished -> idle.
/// - Output distribution to all 3 layers.
/// - User input resets timing detector.
/// - Process exit -> idle.
/// - Reset clears everything.
/// - Concurrent output processing (thread safety).
/// - State published on main thread.
/// - Conflict resolution between layers.
@MainActor
final class AgentDetectionEngineTests: XCTestCase {

    private var sut: AgentDetectionEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs()
        let compiledConfigs = configs.map { AgentConfigService.compile($0) }
        sut = AgentDetectionEngineImpl(compiledConfigs: compiledConfigs, debounceInterval: 0.05)
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

    func testInitialDetectedAgentNameIsNil() {
        XCTAssertNil(sut.detectedAgentName)
    }

    // MARK: - OSC Signal Overrides Pattern Signal

    func testOSCSignalOverridesPatternSignal() {
        // Simulate an OSC 133;A (completionDetected, confidence 1.0)
        // and a pattern signal (confidence 0.7) arriving in the same window.
        // The engine should use the OSC signal.

        // First, get into working state via direct events
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        let expectation = expectation(description: "State should reach finished via OSC")
        var receivedState: AgentStateMachine.State?

        sut.stateChanged
            .filter { $0.state == .finished }
            .first()
            .sink { context in
                receivedState = context.state
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Inject competing signals: pattern says prompt, OSC says completion
        // OSC (confidence 1.0) should win over pattern (confidence 0.7)
        sut.injectSignal(DetectionSignal(
            event: .promptDetected,
            confidence: 0.7,
            source: .pattern(name: "claude")
        ))
        sut.injectSignal(DetectionSignal(
            event: .completionDetected,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedState, .finished)
    }

    // MARK: - Pattern Signal Overrides Timing Signal

    func testPatternSignalOverridesTimingSignal() {
        // Get into agentLaunched state
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 0.7,
            source: .pattern(name: "claude")
        ))

        let expectation = expectation(description: "State should reach working via pattern")
        var receivedState: AgentStateMachine.State?

        sut.stateChanged
            .filter { $0.state == .working }
            .first()
            .sink { context in
                receivedState = context.state
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Pattern signal (0.7) should win over timing signal (0.3)
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 0.3,
            source: .timing
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 0.7,
            source: .pattern(name: "claude")
        ))

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(receivedState, .working)
    }

    // MARK: - Debounce

    func testDebounceRapidSignalsProduceOnlyOneTransition() {
        var transitionCount = 0

        sut.stateChanged
            .sink { _ in
                transitionCount += 1
            }
            .store(in: &cancellables)

        // Send multiple identical signals rapidly
        for _ in 0..<5 {
            sut.injectSignal(DetectionSignal(
                event: .agentDetected(name: "claude"),
                confidence: 1.0,
                source: .osc(code: 99)
            ))
        }

        let expectation = expectation(description: "Wait for debounce window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        // Only 1 transition should happen (idle -> agentLaunched)
        // Additional signals are identical and get debounced
        XCTAssertEqual(transitionCount, 1)
        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    // MARK: - Full Lifecycle

    func testFullLifecycleLaunchWorkWaitWorkFinishIdle() {
        var states: [AgentStateMachine.State] = []

        sut.stateChanged
            .sink { context in
                states.append(context.state)
            }
            .store(in: &cancellables)

        // Launch
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        // Working
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        // Waiting
        sut.injectSignal(DetectionSignal(
            event: .promptDetected,
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        // Back to working via user input
        sut.notifyUserInput()

        // Finished
        sut.injectSignal(DetectionSignal(
            event: .completionDetected,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        // Idle via process exit
        sut.notifyProcessExited()

        let expectation = expectation(description: "Wait for all transitions")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(states, [
            .agentLaunched,
            .working,
            .waitingInput,
            .working,
            .finished,
            .idle
        ])
    }

    // MARK: - Process Terminal Output Distributes to All Layers

    func testProcessTerminalOutputDistributesToAllLayers() {
        // Create an OSC sequence that the OSC layer will recognize
        // ESC ] 133 ; A BEL -> completionDetected
        let oscBytes: [UInt8] = [0x1B, 0x5D] // ESC ]
            + Array("133".utf8)
            + [0x3B] // ;
            + Array("B".utf8) // outputReceived
            + [0x07] // BEL

        // First get into agentLaunched state
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        let expectation = expectation(description: "Process terminal output triggers transition")

        sut.stateChanged
            .filter { $0.state == .working }
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.processTerminalOutput(Data(oscBytes))

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(sut.currentState, .working)
    }

    // MARK: - User Input Notification

    func testUserInputTransitionsFromWaitingToWorking() {
        // Get into waitingInput state
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))
        sut.injectSignal(DetectionSignal(
            event: .promptDetected,
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        XCTAssertEqual(sut.currentState, .waitingInput)

        let expectation = expectation(description: "User input transitions to working")

        sut.stateChanged
            .filter { $0.state == .working }
            .first()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.notifyUserInput()

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(sut.currentState, .working)
    }

    // MARK: - Process Exit

    func testProcessExitTransitionsToIdle() {
        // Get into working state
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        XCTAssertEqual(sut.currentState, .working)

        sut.notifyProcessExited()

        let expectation = expectation(description: "Process exit transitions to idle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertEqual(sut.currentState, .idle)
    }

    // MARK: - Reset

    func testResetClearsEverything() {
        // Get into working state with agent name
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        XCTAssertEqual(sut.currentState, .working)
        XCTAssertEqual(sut.detectedAgentName, "claude")

        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertNil(sut.detectedAgentName)
    }

    // MARK: - Concurrent Output Processing (Thread Safety)

    func testConcurrentOutputProcessingDoesNotCrash() {
        // Send output from multiple threads concurrently
        let iterations = 100
        let group = DispatchGroup()
        let engineRef = WeakReference(sut)

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let data = "output line \(i)\n".data(using: .utf8)!
                engineRef.value?.processTerminalOutput(data)
                group.leave()
            }
        }

        let expectation = expectation(description: "All concurrent operations complete")
        group.notify(queue: .main) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 5.0)
        // No crash = pass
    }

    // MARK: - State Published on Main Thread

    func testStateChangedPublishesOnMainThread() {
        let expectation = expectation(description: "Publisher emits on main thread")

        sut.stateChanged
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread,
                              "State changes must be published on the main thread")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - Confidence-Based Conflict Resolution

    func testHigherConfidenceSignalWinsInSameBatch() {
        // Get to working state
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        // Inject two competing signals as a batch (simulates same output chunk)
        // Low confidence: error (timing heuristic)
        // High confidence: completion (OSC)
        // The batch resolver should pick the OSC signal (higher confidence)
        sut.injectSignalBatch([
            DetectionSignal(
                event: .errorDetected(message: "timing heuristic error"),
                confidence: 0.3,
                source: .timing
            ),
            DetectionSignal(
                event: .completionDetected,
                confidence: 1.0,
                source: .osc(code: 133)
            )
        ])

        // The OSC completionDetected (confidence 1.0) should have won
        XCTAssertEqual(sut.currentState, .finished)
    }

    // MARK: - Same Confidence Uses Source Priority

    func testSameConfidenceUsesSourcePriorityOSCOverPattern() {
        // Get to agentLaunched
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        // Both at 0.9 confidence, OSC should win
        sut.injectSignal(DetectionSignal(
            event: .errorDetected(message: "pattern error"),
            confidence: 0.9,
            source: .pattern(name: "claude")
        ))
        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 0.9,
            source: .osc(code: 133)
        ))

        let expectation = expectation(description: "OSC wins at same confidence")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        // OSC outputReceived should win -> working state
        XCTAssertEqual(sut.currentState, .working)
    }

    // MARK: - Agent Name Propagation

    func testAgentNameUpdatesOnDetection() {
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "aider"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        XCTAssertEqual(sut.detectedAgentName, "aider")
    }

    func testAgentNameClearsOnIdle() {
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        sut.notifyProcessExited()

        let expectation = expectation(description: "Agent name cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertNil(sut.detectedAgentName)
    }

    // MARK: - Multiple Resets Are Safe

    func testMultipleResetsAreSafe() {
        sut.reset()
        sut.reset()
        sut.reset()

        XCTAssertEqual(sut.currentState, .idle)
        XCTAssertNil(sut.detectedAgentName)
    }

    // MARK: - Debounce Does Not Swallow Distinct Transitions

    func testDebounceAllowsDistinctTransitions() {
        var states: [AgentStateMachine.State] = []

        sut.stateChanged
            .sink { context in
                states.append(context.state)
            }
            .store(in: &cancellables)

        // These are distinct valid transitions, not duplicates
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        sut.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        let expectation = expectation(description: "Distinct transitions pass through")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(states.contains(.agentLaunched))
        XCTAssertTrue(states.contains(.working))
    }

    // MARK: - Timing Detector Focus Control (Fix A)

    func testPauseTimingDetectorDelegatesToTimingLayer() {
        // Pause should not crash and the engine should still be functional.
        sut.pauseTimingDetector()

        // After pause, inject signals and verify the engine still works.
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    func testResumeTimingDetectorDelegatesToTimingLayer() {
        // Pause then resume should not crash and the engine should still work.
        sut.pauseTimingDetector()
        sut.resumeTimingDetector()

        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        XCTAssertEqual(sut.currentState, .agentLaunched)
    }

    func testPauseTimingDetectorSuppressesTimingSignals() {
        let expectation = expectation(description: "No timing signal while paused")
        expectation.isInverted = true

        // Use a detector with very short timeout to keep the test fast.
        let shortTimeoutConfigs = AgentConfigService.defaultAgentConfigs()
            .map { AgentConfigService.compile($0) }
        let shortEngine = AgentDetectionEngineImpl(
            compiledConfigs: shortTimeoutConfigs,
            debounceInterval: 0.0
        )

        // Move to working state so timing detector is active.
        shortEngine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        shortEngine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        // Pause the timing detector.
        shortEngine.pauseTimingDetector()

        // Listen for any state change that timing would cause.
        shortEngine.stateChanged
            .sink { context in
                if context.state == .finished {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Wait longer than the default idle timeout. No signal should fire.
        wait(for: [expectation], timeout: 6.0)
    }

    // MARK: - Per-Agent Idle Timeout Forwarding (Fix B)

    func testSetAgentTimeoutForwardsToTimingDetector() {
        // Setting a per-agent timeout should not crash.
        sut.setAgentTimeout(agentName: "aider", timeout: 10.0)
        sut.setAgentTimeout(agentName: "gemini-cli", timeout: 8.0)

        // Engine should still function normally after setting timeouts.
        sut.injectSignal(DetectionSignal(
            event: .agentDetected(name: "aider"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        XCTAssertEqual(sut.currentState, .agentLaunched)
        XCTAssertEqual(sut.detectedAgentName, "aider")
    }
}
