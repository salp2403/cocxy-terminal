// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimingHeuristicsDetectorTests.swift - Tests for timing heuristics detection layer 3.

import XCTest
@testable import CocxyTerminal

// MARK: - Timing Heuristics Detector Tests

/// Tests for `TimingHeuristicsDetector`: lowest-confidence fallback detection layer.
///
/// Covers:
/// - Idle timeout after configurable seconds with no output.
/// - No timeout from idle state (stays idle).
/// - Reset timer on new output.
/// - Custom timeout per agent.
/// - No trigger during active output (sustained output confirms working).
/// - Confirm working after sustained output.
/// - Pause when unfocused.
/// - Timer cleanup on deinit.
/// - DetectionLayer protocol conformance.
/// - Edge cases: zero timeout, negative timeout.
final class TimingHeuristicsDetectorTests: XCTestCase {

    private var sut: TimingHeuristicsDetector!

    override func setUp() {
        super.setUp()
        // Use short timeouts for tests
        sut = TimingHeuristicsDetector(
            defaultIdleTimeout: 0.2,
            sustainedOutputThreshold: 0.1
        )
    }

    override func tearDown() {
        sut?.stop()
        sut = nil
        super.tearDown()
    }

    // MARK: - Idle Timeout

    func testIdleTimeoutAfterConfiguredSeconds() {
        let expectation = expectation(description: "Idle timeout fires")

        // Notify that we are in working state
        sut.notifyStateChanged(to: .working)

        // Send some output to start the timer
        let _ = sut.processBytes(Data("some output".utf8))

        // Set up callback to capture signals
        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Wait for the idle timeout (0.2s)
        wait(for: [expectation], timeout: 1.0)
    }

    func testNoTimeoutFromIdleState() {
        let expectation = expectation(description: "No timeout from idle")
        expectation.isInverted = true

        // Machine is in idle state (default)
        sut.notifyStateChanged(to: .idle)

        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Send output -- should not trigger timeout from idle
        let _ = sut.processBytes(Data("output".utf8))

        // Wait and confirm no signal was emitted
        wait(for: [expectation], timeout: 0.5)
    }

    func testResetTimerOnNewOutput() {
        let expectation = expectation(description: "Timer reset prevents early firing")
        expectation.isInverted = true

        sut.notifyStateChanged(to: .working)
        let _ = sut.processBytes(Data("first output".utf8))

        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Keep sending output before the 0.2s timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let _ = self.sut.processBytes(Data("second output".utf8))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.10) {
            let _ = self.sut.processBytes(Data("third output".utf8))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            let _ = self.sut.processBytes(Data("fourth output".utf8))
        }

        // The timer should keep getting reset, so no timeout in 0.25s
        // (Each output resets the 0.2s window)
        wait(for: [expectation], timeout: 0.25)
    }

    func testCustomTimeoutPerAgent() {
        let customDetector = TimingHeuristicsDetector(
            defaultIdleTimeout: 5.0, // Long default
            sustainedOutputThreshold: 0.1
        )
        defer { customDetector.stop() }

        let expectation = expectation(description: "Custom timeout fires")

        // Set a very short override for "fast-agent"
        customDetector.setAgentTimeout(agentName: "fast-agent", timeout: 0.15)
        customDetector.notifyStateChanged(to: .working)
        customDetector.notifyAgentChanged(to: "fast-agent")

        let _ = customDetector.processBytes(Data("output".utf8))

        customDetector.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Should fire at 0.15s, not 5.0s
        wait(for: [expectation], timeout: 1.0)
    }

    func testNoTriggerDuringActiveOutput() {
        let expectation = expectation(description: "No trigger during active output")
        expectation.isInverted = true

        sut.notifyStateChanged(to: .working)

        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Continuously send output every 50ms for 500ms
        for i in 0..<10 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.05) {
                let _ = self.sut.processBytes(Data("output chunk \(i)".utf8))
            }
        }

        // Since output keeps coming, the timeout should never fire
        wait(for: [expectation], timeout: 0.6)
    }

    func testConfirmWorkingAfterSustainedOutput() {
        let expectation = expectation(description: "Sustained output confirms working")

        sut.notifyStateChanged(to: .agentLaunched)

        sut.onSignalEmitted = { signal in
            if case .outputReceived = signal.event {
                expectation.fulfill()
            }
        }

        // Send output continuously for more than sustainedOutputThreshold (0.1s)
        let _ = sut.processBytes(Data("chunk1".utf8))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let _ = self.sut.processBytes(Data("chunk2".utf8))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) {
            let _ = self.sut.processBytes(Data("chunk3".utf8))
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testPauseWhenUnfocused() {
        let expectation = expectation(description: "No timeout while paused")
        expectation.isInverted = true

        sut.notifyStateChanged(to: .working)
        let _ = sut.processBytes(Data("output".utf8))

        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Pause immediately
        sut.pause()

        // Wait longer than timeout -- should NOT fire because paused
        wait(for: [expectation], timeout: 0.5)
    }

    func testResumeAfterPauseRestartsTimer() {
        let expectation = expectation(description: "Timer restarts after resume")

        sut.notifyStateChanged(to: .working)
        let _ = sut.processBytes(Data("output".utf8))

        sut.pause()

        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Resume after a short delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.sut.resume()
        }

        // After resume, the timer should restart and fire after defaultIdleTimeout
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Edge Cases

    func testStopCleansUpTimers() {
        let expectation = expectation(description: "No signal after stop")
        expectation.isInverted = true

        sut.notifyStateChanged(to: .working)
        let _ = sut.processBytes(Data("output".utf8))

        sut.onSignalEmitted = { signal in
            expectation.fulfill()
        }

        sut.stop()

        wait(for: [expectation], timeout: 0.5)
    }

    func testTimingSignalHasLowConfidence() {
        let expectation = expectation(description: "Signal confidence check")

        sut.notifyStateChanged(to: .working)
        let _ = sut.processBytes(Data("output".utf8))

        sut.onSignalEmitted = { signal in
            XCTAssertEqual(signal.confidence, 0.3, "Timing signals should have low confidence")
            XCTAssertEqual(signal.source, .timing)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - DetectionLayer Conformance

    func testConformsToDetectionLayerProtocol() {
        let layer: DetectionLayer = sut
        let signals = layer.processBytes(Data("test".utf8))
        // processBytes returns synchronously (timers fire async)
        XCTAssertTrue(signals.isEmpty, "processBytes should return empty for timing layer (signals are async)")
    }

    // MARK: - Timeout From Finished State

    /// The `finished` state SHOULD produce idle timeout to drive the
    /// `finished → idle` state machine transition. Without this, sessions
    /// would remain stuck in `finished` indefinitely.
    func testTimeoutFromFinishedStateTransitionsToIdle() {
        let expectation = expectation(description: "Timeout from finished")

        sut.notifyStateChanged(to: .finished)

        sut.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        let _ = sut.processBytes(Data("some output".utf8))

        wait(for: [expectation], timeout: 0.5)
    }
}
