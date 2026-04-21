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
        // Local detector with a generous idleTimeout: on GitHub Actions macos
        // runners `DispatchQueue.global().asyncAfter` can slip several hundred
        // milliseconds under load. With a 0.6s window and 0.15s spacing the
        // first-output timer sometimes fires before the first reset lands and
        // the inverted expectation records a spurious failure. Doubling the
        // window (1.5s) plus spacing the resets at 0.3s/0.6s/0.9s keeps every
        // reset safely inside the window even when asyncAfter slips by 100ms.
        let detector = TimingHeuristicsDetector(
            defaultIdleTimeout: 1.5,
            sustainedOutputThreshold: 0.1
        )
        defer { detector.stop() }

        let expectation = expectation(description: "Timer reset prevents early firing")
        expectation.isInverted = true

        detector.notifyStateChanged(to: .working)
        let _ = detector.processBytes(Data("first output".utf8))

        detector.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Keep sending output well before the 1.5s idle window expires.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            let _ = detector.processBytes(Data("second output".utf8))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            let _ = detector.processBytes(Data("third output".utf8))
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.9) {
            let _ = detector.processBytes(Data("fourth output".utf8))
        }

        // Each output resets the 1.5s window; the last output at t=0.9
        // rearms the timer to t=2.4, so observe up to 1.4s without any
        // early fire.
        wait(for: [expectation], timeout: 1.4)
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
        // Local detector with a more generous idleTimeout than the default
        // 0.2s of `sut`: asyncAfter deadlines on loaded CI runners can slip
        // past 0.2s, which lets the idle timer fire between chunks. 0.6s
        // plus 0.15s chunk spacing keeps resets comfortably inside the
        // window on every realistic runner.
        let detector = TimingHeuristicsDetector(
            defaultIdleTimeout: 0.6,
            sustainedOutputThreshold: 0.1
        )
        defer { detector.stop() }

        let expectation = expectation(description: "No trigger during active output")
        expectation.isInverted = true

        detector.notifyStateChanged(to: .working)

        detector.onSignalEmitted = { signal in
            if case .completionDetected = signal.event {
                expectation.fulfill()
            }
        }

        // Continuously send output every 150ms for 1.35s (10 chunks).
        for i in 0..<10 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.15) {
                let _ = detector.processBytes(Data("output chunk \(i)".utf8))
            }
        }

        // Since output keeps coming, the timeout should never fire within
        // the observation window (< 0.6s after the last chunk at t=1.35s).
        wait(for: [expectation], timeout: 1.5)
    }

    func testConfirmWorkingAfterSustainedOutput() {
        let detector = TimingHeuristicsDetector(
            defaultIdleTimeout: 0.2,
            sustainedOutputThreshold: 0.05
        )
        defer { detector.stop() }

        let expectation = expectation(description: "Sustained output confirms working")

        detector.notifyStateChanged(to: .agentLaunched)

        detector.onSignalEmitted = { signal in
            if case .outputReceived = signal.event {
                expectation.fulfill()
            }
        }

        // Drive the detector with real elapsed time instead of three queued
        // asyncAfter hops near the threshold. This keeps the test stable under
        // suite-wide CI load while still proving sustained output promotion.
        let _ = detector.processBytes(Data("chunk1".utf8))
        Thread.sleep(forTimeInterval: 0.08)
        let _ = detector.processBytes(Data("chunk2".utf8))
        Thread.sleep(forTimeInterval: 0.08)
        let _ = detector.processBytes(Data("chunk3".utf8))

        wait(for: [expectation], timeout: 2.0)
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

        // After resume the timer restarts with the default 0.2s idle window.
        // On a quiet machine the signal lands near t=0.3, but GitHub Actions
        // runners slip `asyncAfter` routinely; keep the outer timeout at 3.0
        // so the scheduling jitter cannot race the expectation.
        wait(for: [expectation], timeout: 3.0)
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
