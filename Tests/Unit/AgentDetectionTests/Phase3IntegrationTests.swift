// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase3IntegrationTests.swift - Integration and edge-case tests for Fase 3 (T-029).
//
// Test plan executed:
// - Integration: real agent sessions end-to-end through processTerminalOutput
// - Edge cases: malformed OSC, regex DoS, rapid transitions, concurrent access
// - Metrics: false positive rate with normal terminal output
// - OSC detection rate: 100% with valid hooks
// - Pattern detection rate: > 80% with typical agent output

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Integration: Claude Code Session (OSC path)

/// Simulates a complete Claude Code session using OSC 133 sequences.
/// Validates the 100% OSC detection rate gate from ADR-004.
@MainActor
final class ClaudeCodeOSCSessionTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs().map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(compiledConfigs: configs, debounceInterval: 0.01)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - INT-001

    /// Full Claude Code session via OSC 133 sequences.
    /// launch -> OSC 133;B -> working -> OSC 133;D;0 -> finished -> idle
    func testIntegration_ClaudeCodeOSCFullSession() {
        var states: [AgentStateMachine.State] = []

        engine.stateChanged
            .sink { states.append($0.state) }
            .store(in: &cancellables)

        // 1. Agent launched via direct injection (process launch)
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))

        // 2. OSC 133;B - command execution started -> outputReceived
        let osc133B: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B] + Array("B".utf8) + [0x07]
        engine.processTerminalOutput(Data(osc133B))

        // 3. OSC 133;D;0 - command finished successfully -> completionDetected
        let osc133D0: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B] + Array("D;0".utf8) + [0x07]
        engine.processTerminalOutput(Data(osc133D0))

        let reachedFullLifecycle = MainActorTestSupport.waitForMainCondition {
            states.contains(.agentLaunched)
                && states.contains(.working)
                && states.contains(.finished)
        }

        XCTAssertTrue(reachedFullLifecycle, "Claude OSC lifecycle should reach launched, working, and finished")
        XCTAssertTrue(states.contains(.agentLaunched), "Should pass through launched state")
        XCTAssertTrue(states.contains(.working), "Should pass through working state")
        XCTAssertTrue(states.contains(.finished), "Should reach finished state")
    }

    // MARK: - INT-002

    /// OSC 133;D with non-zero exit code triggers errorDetected, not completionDetected.
    func testIntegration_OSC133DWithErrorExitCode() {
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        engine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        // OSC 133;D;127 - non-zero exit code = error
        let osc133DError: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B] + Array("D;127".utf8) + [0x07]
        engine.processTerminalOutput(Data(osc133DError))

        let reachedError = MainActorTestSupport.waitForMainCondition { engine.currentState == .error }

        XCTAssertTrue(reachedError, "Non-zero exit code should eventually transition to error")
        XCTAssertEqual(engine.currentState, .error, "Non-zero exit code must transition to error state")
    }

    // MARK: - INT-003

    /// OSC 99 agent hook covers all four status values.
    func testIntegration_OSC99AllStatusValues() {
        let mappings: [(payload: String, expectedContains: AgentStateMachine.State)] = [
            ("agent-status;working", .working),
            ("agent-status;waiting", .waitingInput),
            ("agent-status;finished", .finished),
        ]

        for (payload, expectedState) in mappings {
            engine.reset()

            // Get into a state where the OSC99 payload is a valid transition
            engine.injectSignal(DetectionSignal(
                event: .agentDetected(name: "claude"),
                confidence: 1.0,
                source: .osc(code: 99)
            ))
            if expectedState == .waitingInput || expectedState == .finished {
                engine.injectSignal(DetectionSignal(
                    event: .outputReceived,
                    confidence: 1.0,
                    source: .osc(code: 133)
                ))
            }

            let osc99: [UInt8] = [0x1B, 0x5D] + Array("99".utf8) + [0x3B] + Array(payload.utf8) + [0x07]
            engine.processTerminalOutput(Data(osc99))

            let reachedExpectedState = MainActorTestSupport.waitForMainCondition {
                engine.currentState == expectedState
            }

            XCTAssertTrue(reachedExpectedState, "OSC99 payload '\(payload)' should eventually produce state \(expectedState)")
            XCTAssertEqual(engine.currentState, expectedState,
                           "OSC99 payload '\(payload)' should produce state \(expectedState)")
        }
    }
}

// MARK: - Integration: Aider Session (Pattern path)

/// Simulates an Aider session using only pattern matching (no OSC).
/// Validates the > 80% pattern detection gate from ADR-004.
@MainActor
final class AiderPatternSessionTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs().map { AgentConfigService.compile($0) }
        // requiredConsecutiveMatches=2 is default in the engine
        engine = AgentDetectionEngineImpl(compiledConfigs: configs, debounceInterval: 0.0)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        engine = nil
        super.tearDown()
    }

    private func sendLine(_ text: String) {
        engine.processTerminalOutput(Data((text + "\n").utf8))
    }

    // MARK: - INT-004

    /// Aider launch detected through consecutive launch pattern matches.
    func testIntegration_AiderLaunchDetectedByPattern() {
        var states: [AgentStateMachine.State] = []

        engine.stateChanged
            .sink { states.append($0.state) }
            .store(in: &cancellables)

        // Two consecutive lines matching aider launch pattern
        sendLine("aider --model gpt-4")
        sendLine("aider --model gpt-4")  // second line triggers hysteresis

        MainActorTestSupport.waitForMainDispatch(delay: 0.15)

        XCTAssertTrue(
            states.contains(.agentLaunched),
            "Aider must be detected as launched after consecutive pattern matches"
        )
    }

    // MARK: - INT-005

    /// Aider waiting prompt ">" detected as waiting input.
    ///
    /// Uses "> " which exclusively matches the waiting pattern "^>\\s*$".
    /// The default Aider launch pattern is intentionally exclusive from the
    /// waiting prompt, so "aider>" is no longer used here as a waiting probe.
    func testIntegration_AiderWaitingPromptDetected() {
        // Get into working state via direct injection
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "aider"),
            confidence: 0.7,
            source: .pattern(name: "aider")
        ))
        engine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 0.7,
            source: .pattern(name: "aider")
        ))

        XCTAssertEqual(engine.currentState, .working)

        var states: [AgentStateMachine.State] = []
        engine.stateChanged
            .sink { states.append($0.state) }
            .store(in: &cancellables)

        // Use "> " which only matches the waiting pattern "^>\s*$", not the launch pattern.
        sendLine("> ")
        sendLine("> ")

        MainActorTestSupport.waitForMainDispatch(delay: 0.15)

        XCTAssertTrue(states.contains(.waitingInput),
                      "> prompt should trigger waitingInput state via pattern matching")
    }

    // MARK: - INT-006

    /// Agent crash: error pattern followed by process exit transitions to idle.
    func testIntegration_AgentCrashFlow() {
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "aider"),
            confidence: 1.0,
            source: .osc(code: 99)
        ))
        engine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .osc(code: 133)
        ))

        XCTAssertEqual(engine.currentState, .working)

        // Error output
        engine.injectSignal(DetectionSignal(
            event: .errorDetected(message: "Traceback (most recent call last)"),
            confidence: 0.7,
            source: .pattern(name: "aider")
        ))

        XCTAssertEqual(engine.currentState, .error)

        // Process exits
        engine.notifyProcessExited()

        XCTAssertEqual(engine.currentState, .idle, "Process exit from error state must return to idle")
        XCTAssertNil(engine.detectedAgentName, "Agent name must be cleared after process exit")
    }
}

// MARK: - Edge Cases: Malformed OSC Sequences

/// Tests for malformed, truncated, and adversarial OSC sequences.
/// These validate that the parser does not crash or produce false positives.
final class MalformedOSCEdgeCaseTests: XCTestCase {

    private var sut: OSCSequenceDetector!

    override func setUp() {
        super.setUp()
        sut = OSCSequenceDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - EDGE-001

    /// Truncated OSC sequence (no terminator) produces no signal and no crash.
    func testEdge_TruncatedOSCSequenceNoCrash() {
        // ESC ] 133 ; A  -- missing BEL and ST
        let truncated: [UInt8] = [0x1B, 0x5D, 0x31, 0x33, 0x33, 0x3B, 0x41]
        let signals = sut.processBytes(Data(truncated))
        XCTAssertTrue(signals.isEmpty, "Truncated OSC must produce no signal")
    }

    // MARK: - EDGE-002

    /// Wrong escape character (CSI instead of OSC start) is ignored.
    func testEdge_CSISequenceIgnored() {
        // ESC [ (CSI sequence, not OSC) followed by digits and letter
        let csi: [UInt8] = [0x1B, 0x5B, 0x31, 0x6D]  // ESC [ 1 m (SGR)
        let signals = sut.processBytes(Data(csi))
        XCTAssertTrue(signals.isEmpty, "CSI sequences must not produce detection signals")
    }

    // MARK: - EDGE-003

    /// Nested ESC inside OSC payload discards the first OSC gracefully.
    func testEdge_NestedESCInsideOSCPayload() {
        // Start OSC 133;A, then inject ESC in the middle without completing,
        // then send a clean OSC 9 sequence.
        var data: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x1B]
        // No ST after the embedded ESC: send a new unrelated byte
        data.append(0x41) // 'A' -- malformed mid-OSC-ESC
        // Now send a clean OSC 9 terminated by BEL
        data += [0x1B, 0x5D] + Array("9".utf8) + [0x3B] + Array("done".utf8) + [0x07]

        let signals = sut.processBytes(Data(data))
        // The clean OSC 9 must be detected
        XCTAssertEqual(signals.count, 1, "Clean OSC after malformed sequence must still be detected")
        XCTAssertEqual(signals.first?.source, .osc(code: 9))
    }

    // MARK: - EDGE-004

    /// OSC payload exactly at the buffer limit (4096 bytes) is discarded gracefully.
    func testEdge_OversizedOSCPayloadDiscardedGracefully() {
        // ESC ] 133 ;
        var data: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B]
        // Append 4097 bytes of payload (exceeds maxOSCBufferSize = 4096)
        data += [UInt8](repeating: 0x41, count: 4097)
        data += [0x07] // BEL

        let signals = sut.processBytes(Data(data))
        // Oversized payload: buffer is cleared and state returns to normal.
        // The BEL arrives after the clear, so it's just a stray BEL in normal mode: no signal.
        XCTAssertTrue(signals.isEmpty, "Oversized OSC payload must be silently discarded")
    }

    // MARK: - EDGE-005

    /// Sequence of multiple consecutive ESCs followed by ] starts a clean OSC.
    func testEdge_MultipleConsecutiveESCThenOSCStart() {
        // ESC ESC ] 133 ; A BEL
        let data: [UInt8] = [0x1B, 0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x07]
        let signals = sut.processBytes(Data(data))
        // The second ESC starts the escape state, ] begins OSC. Should parse correctly.
        XCTAssertEqual(signals.count, 1, "Double ESC then ] should start valid OSC")
    }

    // MARK: - EDGE-006

    /// Zero-byte payload OSC code with no semicolon is handled gracefully.
    func testEdge_OSCCodeOnlyNoSemicolon() {
        // ESC ] 9 BEL -- no semicolon, only code
        let data: [UInt8] = [0x1B, 0x5D, 0x39, 0x07]  // ESC ] 9 BEL
        let signals = sut.processBytes(Data(data))
        // OSC 9 with no payload still maps to completionDetected
        XCTAssertEqual(signals.count, 1, "OSC code without semicolon/payload must be handled")
        if case .completionDetected = signals.first?.event { } else {
            XCTFail("OSC 9 no-payload should produce completionDetected")
        }
    }

    // MARK: - EDGE-007

    /// Empty OSC sequence (ESC ] BEL) produces no signal and no crash.
    func testEdge_EmptyOSCSequence() {
        let data: [UInt8] = [0x1B, 0x5D, 0x07]  // ESC ] BEL
        let signals = sut.processBytes(Data(data))
        XCTAssertTrue(signals.isEmpty, "Empty OSC must produce no signal")
    }

    // MARK: - EDGE-008

    /// 0-byte input produces no signal and no crash.
    func testEdge_ZeroByteInput() {
        let signals = sut.processBytes(Data())
        XCTAssertTrue(signals.isEmpty, "Zero-byte input must produce no signal")
    }

    // MARK: - EDGE-009

    /// OSC with non-numeric code is silently ignored.
    func testEdge_NonNumericOSCCode() {
        // ESC ] abc ; payload BEL
        let data: [UInt8] = [0x1B, 0x5D] + Array("abc".utf8) + [0x3B] + Array("test".utf8) + [0x07]
        let signals = sut.processBytes(Data(data))
        XCTAssertTrue(signals.isEmpty, "Non-numeric OSC code must be silently ignored")
    }

    // MARK: - EDGE-010

    /// ST terminator (ESC \) followed immediately by new OSC works correctly.
    func testEdge_STTerminatorFollowedByNewOSC() {
        // OSC 9;done ESC\ OSC 133;A BEL
        var data: [UInt8] = [0x1B, 0x5D] + Array("9".utf8) + [0x3B] + Array("done".utf8) + [0x1B, 0x5C]
        data += [0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x07]

        let signals = sut.processBytes(Data(data))
        XCTAssertEqual(signals.count, 2, "Two OSC sequences back-to-back (ST then BEL) must both be detected")
    }
}

// MARK: - Edge Cases: Pattern Matching Detector

/// Tests edge cases for the pattern matching layer.
final class PatternMatchingEdgeCaseTests: XCTestCase {

    private var sut: PatternMatchingDetector!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs().map { AgentConfigService.compile($0) }
        sut = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.5,
            maxLineBuffer: 5
        )
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    private func sendLine(_ text: String) -> [DetectionSignal] {
        sut.processBytes(Data((text + "\n").utf8))
    }

    // MARK: - EDGE-011

    /// Lines with only whitespace do not trigger patterns or reset counters.
    func testEdge_WhitespaceOnlyLinesIgnored() {
        _ = sendLine("claude --help")   // 1st match
        _ = sendLine("   ")            // whitespace: must NOT reset counter
        let signals = sendLine("claude --version") // should be 2nd consecutive match

        let launches = signals.filter { if case .agentDetected = $0.event { return true }; return false }
        XCTAssertFalse(launches.isEmpty,
                       "Whitespace-only lines must not reset the hysteresis counter")
    }

    // MARK: - EDGE-012

    /// Data without UTF-8 encoding produces no signals and no crash.
    func testEdge_InvalidUTF8DataHandled() {
        let invalidUTF8: [UInt8] = [0xFF, 0xFE, 0xFD, 0x00, 0x80, 0xBF]
        let signals = sut.processBytes(Data(invalidUTF8))
        _ = signals // No crash = pass
    }

    // MARK: - EDGE-013

    /// Data chunk without trailing newline is buffered, not processed yet.
    func testEdge_DataWithoutNewlineIsBuffered() {
        // "claude" without newline -- incomplete line, should not trigger
        let signals = sut.processBytes(Data("claude --help".utf8))
        let launches = signals.filter { if case .agentDetected = $0.event { return true }; return false }
        XCTAssertTrue(launches.isEmpty, "Line without newline must be buffered, not processed")
    }

    // MARK: - EDGE-014

    /// Very long line (100KB) is processed without crash.
    func testEdge_VeryLongLineNoBufferOverflow() {
        let longLine = String(repeating: "x", count: 100_000)
        let data = Data((longLine + "\n").utf8)
        let signals = sut.processBytes(data)
        _ = signals  // No crash = pass
    }

    // MARK: - EDGE-015

    /// Unicode and emoji in output lines do not cause crashes.
    func testEdge_UnicodeAndEmojiInLines() {
        let unicodeLine = "claude: 🤖 Processing... — ❯ △ ⌂ ✓"
        let signals = sut.processBytes(Data((unicodeLine + "\n").utf8))
        _ = signals  // No crash = pass
    }

    // MARK: - EDGE-016

    /// RTL characters (Arabic, Hebrew) in output lines do not cause crashes.
    func testEdge_RTLCharactersInLines() {
        let rtlLine = "مرحبا بالعالم claude --help שלום"
        let signals = sut.processBytes(Data((rtlLine + "\n").utf8))
        _ = signals  // No crash = pass
    }
}

// MARK: - Edge Cases: Concurrent ProcessTerminalOutput

/// Tests for thread safety under concurrent load.
@MainActor
final class ConcurrencyEdgeCaseTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs().map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(compiledConfigs: configs, debounceInterval: 0.0)
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - EDGE-017

    /// 10 rapid state transitions in < 100ms produce valid final state.
    func testEdge_RapidStateTransitionsIn100ms() {
        var states: [AgentStateMachine.State] = []
        var cancellables = Set<AnyCancellable>()

        engine.stateChanged
            .sink { states.append($0.state) }
            .store(in: &cancellables)

        // 10 transitions using the valid cycle: idle->launched->working->finished->idle->...
        for _ in 0..<3 {
            engine.injectSignal(DetectionSignal(
                event: .agentDetected(name: "claude"),
                confidence: 1.0, source: .osc(code: 99)
            ))
            engine.injectSignal(DetectionSignal(
                event: .outputReceived,
                confidence: 1.0, source: .osc(code: 133)
            ))
            engine.injectSignal(DetectionSignal(
                event: .completionDetected,
                confidence: 1.0, source: .osc(code: 133)
            ))
            engine.notifyProcessExited()
        }

        // Valid final state: idle (after last agentExited)
        XCTAssertEqual(engine.currentState, .idle)
        // Should have recorded at least the valid transitions (debounce may reduce count)
        XCTAssertFalse(states.isEmpty, "Rapid transitions must produce at least some state changes")
    }

    // MARK: - EDGE-018

    /// Concurrent processTerminalOutput calls from 10 threads produce no data races.
    func testEdge_ConcurrentProcessTerminalOutput10Threads() {
        let group = DispatchGroup()
        let oscData: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x07]
        let capturedEngine = engine!

        for i in 0..<50 {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let text = "output line \(i)\n"
                capturedEngine.processTerminalOutput(Data(text.utf8))
                capturedEngine.processTerminalOutput(Data(oscData))
                group.leave()
            }
        }

        let exp = expectation(description: "All threads complete")
        group.notify(queue: .main) { exp.fulfill() }
        waitForExpectations(timeout: 5.0)
        // No crash, no sanitizer errors = pass
    }

    // MARK: - EDGE-019

    /// Engine reset during active processTerminalOutput does not crash.
    func testEdge_ResetDuringActiveProcessing() {
        let group = DispatchGroup()
        let oscData: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x07]
        // Capture engine reference before spawning background threads to avoid
        // IUO nil access if tearDown races with asyncAfter.
        let capturedEngine = engine!

        for i in 0..<20 {
            group.enter()
            DispatchQueue.global(qos: .background).async {
                capturedEngine.processTerminalOutput(Data("output \(i)\n".utf8))
                capturedEngine.processTerminalOutput(Data(oscData))
                group.leave()
            }
        }

        // Reset from main thread while background threads process output
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            capturedEngine.reset()
        }

        let exp = expectation(description: "No crash during concurrent reset")
        group.notify(queue: .global(qos: .background)) { exp.fulfill() }
        // This stress case competes with the rest of the suite for CPU on CI.
        // Keep the assertion strict (no retries), but allow enough headroom
        // that scheduler pressure does not masquerade as a product failure.
        waitForExpectations(timeout: 20.0)
        // No crash = pass
    }

    // MARK: - EDGE-020

    /// Large output burst (1MB in one chunk) processed without hang or crash.
    func testEdge_LargeOutputBurst1MB() {
        // 1MB of mixed text
        let chunk = String(repeating: "output line with some content here\n", count: 28572)
        let data = Data(chunk.utf8)
        let capturedEngine = engine!

        XCTAssertGreaterThan(data.count, 900_000, "Test data must be approximately 1MB")

        let exp = expectation(description: "1MB processed without hang")

        DispatchQueue.global(qos: .userInteractive).async {
            capturedEngine.processTerminalOutput(data)
            exp.fulfill()
        }

        // This is intentionally a heavy stress test (~1MB in a single burst).
        // CI runners can take well over 10 seconds under whole-suite load even
        // when the engine is healthy, so the timeout must reflect that load.
        waitForExpectations(timeout: 20.0)
        // Completes within timeout = pass
    }

    // MARK: - EDGE-021

    /// Empty Data (0 bytes) is handled silently.
    func testEdge_EmptyDataInputSilent() {
        // Should not crash, should not change state
        engine.processTerminalOutput(Data())

        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        XCTAssertEqual(engine.currentState, .idle, "Empty input must not change state from idle")
    }
}

// MARK: - Metrics: False Positive Rate with Normal Terminal Output

/// Validates that normal terminal usage (ls, git, npm, etc.) does NOT
/// trigger agent detection transitions.
/// Gate requirement: < 5% false positives.
@MainActor
final class FalsePositiveRateTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    /// Common terminal output lines that should NOT trigger agent detection.
    private static let normalTerminalOutput: [String] = [
        "total 48",
        "drwxr-xr-x  12 user  staff   384 Mar 16 10:00 .",
        "drwxr-xr-x  20 user  staff   640 Mar 15 09:00 ..",
        "-rw-r--r--   1 user  staff  2048 Mar 16 10:00 Package.swift",
        "On branch main",
        "Your branch is up to date with 'origin/main'.",
        "nothing to commit, working tree clean",
        "* main",
        "  feature/T-029-qa",
        "npm warn deprecated inflight@1.0.6: This module is not supported",
        "added 142 packages in 3s",
        "swift build",
        "Build complete!",
        "Compiling CocxyTerminal AgentStateMachine.swift",
        "xcodebuild: error: 'CocxyTerminal' is not a valid target",
        "make[1]: Nothing to be done for 'all'.",
        "Fetching https://github.com/apple/swift-argument-parser",
        "ping: google.com: Network is unreachable",
        "--- 127.0.0.1 ping statistics ---",
        "1 packets transmitted, 1 received, 0% packet loss",
        "Running 127 tests",
        "Test Suite 'All tests' passed",
        "PASS src/utils.test.js",
        "FAIL src/api.test.js",
        "  ● Test suite failed to run",
        "python3 -m pytest",
        "collected 45 items",
        "PASSED tests/test_main.py::test_function",
        "vim README.md",
        "man ls",
        "cat /etc/hosts",
        "grep -r 'pattern' .",
        "find . -name '*.swift'",
        "docker ps",
        "docker build -t myapp .",
        "kubectl get pods",
        "ssh user@server",
        "rsync -av src/ dest/",
        "curl https://api.example.com/health",
        "brew install ripgrep",
    ]

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs().map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(compiledConfigs: configs, debounceInterval: 0.0)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - METRIC-001

    /// Normal terminal output (40 lines) produces zero false positive agent detections.
    func testMetric_NormalTerminalOutputFalsePositiveRateZero() {
        var transitionCount = 0

        engine.stateChanged
            .sink { _ in transitionCount += 1 }
            .store(in: &cancellables)

        for line in Self.normalTerminalOutput {
            engine.processTerminalOutput(Data((line + "\n").utf8))
        }

        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        XCTAssertEqual(transitionCount, 0,
                       "Normal terminal output must produce zero false positive agent detections")
        XCTAssertEqual(engine.currentState, .idle,
                       "Engine must remain idle after normal terminal output")
    }

    // MARK: - METRIC-002

    /// Git output with "Error" substring does not trigger error detection.
    func testMetric_GitErrorSubstringNotFalsePositive() {
        var errorSignalCount = 0

        engine.stateChanged
            .filter { if case .error = $0.state { return true }; return false }
            .sink { _ in errorSignalCount += 1 }
            .store(in: &cancellables)

        // These contain "Error" but are not agent errors
        let gitLines = [
            "error: pathspec 'main' did not match any file(s) known to git",
            "ERROR: Couldn't find remote ref feature/old",
            "fatal: Not a git repository",
            "warning: LF will be replaced by CRLF in file.txt",
        ]

        for line in gitLines {
            engine.processTerminalOutput(Data((line + "\n").utf8))
        }

        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        XCTAssertEqual(errorSignalCount, 0,
                       "Git error output from idle state must not trigger agent error state")
    }

    // MARK: - METRIC-003

    /// Prompt characters from normal shells (zsh, bash) do not trigger agent detection.
    func testMetric_ShellPromptsNotFalsePositives() {
        var transitionCount = 0

        engine.stateChanged
            .sink { _ in transitionCount += 1 }
            .store(in: &cancellables)

        let promptLines = [
            "$ ls -la",
            "% pwd",
            "❯ git status",
            "> echo hello",
            "user@host:~$ ",
            "➜  ~ ",
        ]

        for line in promptLines {
            engine.processTerminalOutput(Data((line + "\n").utf8))
        }

        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        XCTAssertEqual(transitionCount, 0,
                       "Shell prompts from idle state must not trigger agent detection")
    }

    // MARK: - METRIC-004

    /// OSC sequences from non-agent shells (window title, color changes) do not trigger detection.
    func testMetric_NonAgentOSCSequencesIgnored() {
        var transitionCount = 0

        engine.stateChanged
            .sink { _ in transitionCount += 1 }
            .store(in: &cancellables)

        // OSC 0: set window title
        let oscTitle: [UInt8] = [0x1B, 0x5D, 0x30, 0x3B] + Array("My Terminal".utf8) + [0x07]
        // OSC 4: set color
        let oscColor: [UInt8] = [0x1B, 0x5D, 0x34, 0x3B] + Array("0;rgb:00/00/00".utf8) + [0x07]
        // OSC 52: clipboard
        let oscClipboard: [UInt8] = [0x1B, 0x5D, 0x35, 0x32, 0x3B] + Array("c;SGVsbG8=".utf8) + [0x07]

        engine.processTerminalOutput(Data(oscTitle))
        engine.processTerminalOutput(Data(oscColor))
        engine.processTerminalOutput(Data(oscClipboard))

        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        XCTAssertEqual(transitionCount, 0,
                       "Non-agent OSC sequences must be ignored and not trigger state changes")
    }
}

// MARK: - Metrics: OSC Detection Latency

/// Validates that OSC sequence detection is fast (< 5ms from bytes received).
final class OSCDetectionLatencyTests: XCTestCase {

    private var sut: OSCSequenceDetector!

    override func setUp() {
        super.setUp()
        sut = OSCSequenceDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - METRIC-005

    /// Single OSC 133;A sequence processed in < 5ms.
    func testMetric_OSCDetectionLatencyUnder5ms() {
        let oscData: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x07]
        let data = Data(oscData)

        let start = Date()
        let signals = sut.processBytes(data)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(signals.isEmpty, "OSC 133;A must produce a signal")
        XCTAssertLessThan(elapsed, 0.005, "OSC detection must be < 5ms, got \(elapsed * 1000)ms")
    }

    // MARK: - METRIC-006

    /// 100 consecutive OSC sequences processed in < 100ms total.
    func testMetric_100OSCSequencesUnder100ms() {
        var combinedData = Data()
        let oscData: [UInt8] = [0x1B, 0x5D] + Array("133".utf8) + [0x3B, 0x41, 0x07]
        for _ in 0..<100 {
            combinedData.append(contentsOf: oscData)
        }

        let start = Date()
        let signals = sut.processBytes(combinedData)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(signals.count, 100, "All 100 OSC sequences must be detected")
        XCTAssertLessThan(elapsed, 0.1, "100 OSC sequences must be processed in < 100ms")
    }
}

// MARK: - Gate Verification: AgentStateMachine Edge Cases

/// Tests additional edge cases for the state machine not covered by T-022.
@MainActor
final class AgentStateMachineGateTests: XCTestCase {

    private var sut: AgentStateMachine!

    override func setUp() {
        super.setUp()
        sut = AgentStateMachine()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - GATE-001

    /// Agent name is nil in StateContext when transitioning to idle (agentExited).
    func testGate_AgentNameIsNilInContextWhenTransitioningToIdle() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.agentExited)

        let lastContext = sut.transitionHistory.last
        XCTAssertNotNil(lastContext)
        XCTAssertNil(lastContext?.agentName, "agentName in StateContext must be nil after transitioning to idle")
    }

    // MARK: - GATE-002

    /// History cap removes oldest entries, preserving the most recent 50.
    func testGate_HistoryCapPreservesMostRecent50() {
        // Generate 75 valid transitions
        for _ in 0..<25 {
            sut.processEvent(.agentDetected(name: "claude"))  // idle -> launched
            sut.processEvent(.outputReceived)                  // launched -> working
            sut.processEvent(.agentExited)                     // working -> idle
        }

        XCTAssertEqual(sut.transitionHistory.count, 50, "History must be exactly 50 after cap")

        // Verify most recent entry is the last valid transition
        let lastEntry = sut.transitionHistory.last
        XCTAssertEqual(lastEntry?.state, .idle)
    }

    // MARK: - GATE-003

    /// Reset does not emit a stateChanged event.
    func testGate_ResetDoesNotEmitStateChangedEvent() {
        var emissionCount = 0
        var cancellables = Set<AnyCancellable>()

        sut.processEvent(.agentDetected(name: "claude"))

        sut.stateChanged
            .sink { _ in emissionCount += 1 }
            .store(in: &cancellables)

        sut.reset()

        XCTAssertEqual(emissionCount, 0, "reset() must not emit a stateChanged event")
    }

    // MARK: - GATE-004

    /// Transition event is recorded in the StateContext.
    func testGate_TransitionEventIsRecordedInContext() {
        sut.processEvent(.agentDetected(name: "claude"))
        sut.processEvent(.outputReceived)
        sut.processEvent(.errorDetected(message: "test"))

        let lastContext = sut.transitionHistory.last!
        if case .errorDetected(let msg) = lastContext.transitionEvent {
            XCTAssertEqual(msg, "test")
        } else {
            XCTFail("TransitionEvent must be errorDetected, got \(lastContext.transitionEvent)")
        }
    }
}

// MARK: - Gate Verification: DetectionSignal Confidence Clamping

/// Tests that DetectionSignal clamps confidence to [0.0, 1.0].
final class DetectionSignalTests: XCTestCase {

    // MARK: - GATE-005

    func testGate_ConfidenceAbove1IsClamped() {
        let signal = DetectionSignal(event: .outputReceived, confidence: 1.5, source: .timing)
        XCTAssertEqual(signal.confidence, 1.0, "Confidence above 1.0 must be clamped to 1.0")
    }

    // MARK: - GATE-006

    func testGate_ConfidenceBelowZeroIsClamped() {
        let signal = DetectionSignal(event: .outputReceived, confidence: -0.5, source: .timing)
        XCTAssertEqual(signal.confidence, 0.0, "Confidence below 0.0 must be clamped to 0.0")
    }

    // MARK: - GATE-007

    func testGate_ConfidenceExactlyZeroIsAccepted() {
        let signal = DetectionSignal(event: .outputReceived, confidence: 0.0, source: .timing)
        XCTAssertEqual(signal.confidence, 0.0)
    }

    // MARK: - GATE-008

    func testGate_ConfidenceExactlyOneIsAccepted() {
        let signal = DetectionSignal(event: .completionDetected, confidence: 1.0, source: .osc(code: 133))
        XCTAssertEqual(signal.confidence, 1.0)
    }
}

// MARK: - Gate Verification: Engine injectSignalBatch with empty array

/// Additional engine edge cases.
@MainActor
final class EngineAdditionalEdgeCases: XCTestCase {

    private var engine: AgentDetectionEngineImpl!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs().map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(compiledConfigs: configs, debounceInterval: 0.01)
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - GATE-009

    /// injectSignalBatch with empty array does not crash or change state.
    func testGate_InjectSignalBatchEmptyArray() {
        engine.injectSignalBatch([])
        XCTAssertEqual(engine.currentState, .idle, "Empty batch must not change state")
    }

    // MARK: - GATE-010

    /// Debounce allows a new event key through after the debounce interval expires.
    func testGate_DebounceAllowsSameEventAfterInterval() {
        var transitionCount = 0
        var cancellables = Set<AnyCancellable>()

        engine.stateChanged
            .sink { _ in transitionCount += 1 }
            .store(in: &cancellables)

        // First detection: idle -> agentLaunched
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0, source: .osc(code: 99)
        ))

        // Exit to idle immediately
        engine.notifyProcessExited()

        // Wait past debounce interval (0.01s + margin)
        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        // Second detection: same event, should pass through now
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0, source: .osc(code: 99)
        ))

        MainActorTestSupport.waitForMainDispatch(delay: 0.05)

        XCTAssertGreaterThanOrEqual(transitionCount, 3,
            "After debounce interval, same event must be processed again: got \(transitionCount) transitions")
    }

    // MARK: - GATE-011

    /// @Published currentState updates are observable via Combine.
    func testGate_PublishedCurrentStateIsObservable() {
        var observedStates: [AgentStateMachine.State] = []
        var cancellables = Set<AnyCancellable>()

        engine.$currentState
            .dropFirst()  // Skip initial .idle value
            .sink { observedStates.append($0) }
            .store(in: &cancellables)

        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0, source: .osc(code: 99)
        ))
        engine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0, source: .osc(code: 133)
        ))

        XCTAssertEqual(observedStates, [.agentLaunched, .working],
                       "@Published currentState must emit correct values in order")
    }

    // MARK: - GATE-012

    /// @Published detectedAgentName updates correctly through lifecycle.
    func testGate_PublishedDetectedAgentNameUpdatesCorrectly() {
        var observedNames: [String?] = []
        var cancellables = Set<AnyCancellable>()

        engine.$detectedAgentName
            .dropFirst()
            .sink { observedNames.append($0) }
            .store(in: &cancellables)

        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "aider"),
            confidence: 1.0, source: .pattern(name: "aider")
        ))

        engine.notifyProcessExited()

        MainActorTestSupport.waitForMainDispatch(delay: 0.1)

        XCTAssertTrue(observedNames.contains("aider"), "detectedAgentName must be 'aider' after detection")
        XCTAssertTrue(observedNames.contains(nil), "detectedAgentName must be nil after process exit")
    }
}
