// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PatternMatchingDetectorTests.swift - Tests for pattern matching detection layer 2.

import XCTest
@testable import CocxyTerminal

// MARK: - Pattern Matching Detector Tests

/// Tests for `PatternMatchingDetector`: medium-confidence detection layer.
///
/// Covers:
/// - Agent launch detection via launch patterns.
/// - Waiting input detection via waiting patterns.
/// - Error detection via error patterns.
/// - Finished detection via finished indicators.
/// - Hysteresis: single match does not trigger transition.
/// - Hysteresis: N consecutive matches trigger transition.
/// - Cooldown: no re-trigger within cooldown window.
/// - Multiple agents: correct one is detected.
/// - Circular buffer retains last N lines.
/// - Empty line handling.
/// - Special regex characters in patterns.
/// - No match produces no signals.
/// - DetectionLayer protocol conformance.
final class PatternMatchingDetectorTests: XCTestCase {

    private var sut: PatternMatchingDetector!
    private var configs: [CompiledAgentConfig]!

    override func setUp() {
        super.setUp()
        configs = createTestConfigs()
        sut = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 1.0,
            maxLineBuffer: 5
        )
    }

    override func tearDown() {
        sut = nil
        configs = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func createTestConfigs() -> [CompiledAgentConfig] {
        let claude = AgentConfig(
            name: "claude",
            displayName: "Claude Code",
            launchPatterns: ["^claude\\b", "^claude-code\\b"],
            waitingPatterns: ["^\\? ", "\\(Y/n\\)"],
            errorPatterns: ["^Error:", "APIError"],
            finishedIndicators: ["^\\$\\s*$", "^>\\s*$"],
            oscSupported: true,
            idleTimeoutOverride: nil
        )

        let codex = AgentConfig(
            name: "codex",
            displayName: "Codex CLI",
            launchPatterns: ["^codex\\b"],
            waitingPatterns: ["Enter to confirm"],
            errorPatterns: ["Failed"],
            finishedIndicators: ["^\\$\\s*$"],
            oscSupported: false,
            idleTimeoutOverride: nil
        )

        return [
            AgentConfigService.compile(claude),
            AgentConfigService.compile(codex),
        ]
    }

    private func lineData(_ text: String) -> Data {
        Data((text + "\n").utf8)
    }

    // MARK: - Agent Launch Detection

    func testDetectClaudeAsAgentLaunch() {
        // First match
        let signals1 = sut.processBytes(lineData("claude --help"))
        // Hysteresis: need 2 matches but launch is special -- single match should trigger
        // because launch patterns have high confidence and we don't want to miss the launch.
        // Actually per spec, hysteresis applies. Let's check:
        // First invocation sets up the match counter.

        // Second match to trigger hysteresis
        let signals2 = sut.processBytes(lineData("claude --version"))

        let allSignals = signals1 + signals2
        let launchSignals = allSignals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(launchSignals.isEmpty, "Claude launch should be detected after consecutive matches")
    }

    func testDetectCodexAsAgentLaunch() {
        let _ = sut.processBytes(lineData("codex run tests"))
        let signals = sut.processBytes(lineData("codex run tests"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(launchSignals.isEmpty, "Codex launch should be detected")
    }

    // MARK: - Waiting Input Detection

    func testDetectWaitingInputPattern() {
        // Set up: detect agent first
        let _ = sut.processBytes(lineData("claude chat"))
        let _ = sut.processBytes(lineData("claude chat"))

        // Now send waiting patterns
        let _ = sut.processBytes(lineData("? Do you want to continue?"))
        let signals = sut.processBytes(lineData("? Choose an option"))

        let waitingSignals = signals.filter {
            if case .promptDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(waitingSignals.isEmpty, "Waiting input pattern should be detected")
    }

    func testDetectYesNoPrompt() {
        let _ = sut.processBytes(lineData("claude chat"))
        let _ = sut.processBytes(lineData("claude chat"))

        let _ = sut.processBytes(lineData("Apply changes? (Y/n)"))
        let signals = sut.processBytes(lineData("Save file? (Y/n)"))

        let waitingSignals = signals.filter {
            if case .promptDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(waitingSignals.isEmpty, "(Y/n) pattern should detect waiting input")
    }

    // MARK: - Error Detection

    func testDetectErrorPattern() {
        let _ = sut.processBytes(lineData("claude chat"))
        let _ = sut.processBytes(lineData("claude chat"))

        let _ = sut.processBytes(lineData("Error: connection refused"))
        let signals = sut.processBytes(lineData("Error: timeout"))

        let errorSignals = signals.filter {
            if case .errorDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(errorSignals.isEmpty, "Error pattern should be detected")
    }

    func testDetectAPIErrorPattern() {
        let _ = sut.processBytes(lineData("claude chat"))
        let _ = sut.processBytes(lineData("claude chat"))

        let _ = sut.processBytes(lineData("APIError: rate limited"))
        let signals = sut.processBytes(lineData("APIError: server error"))

        let errorSignals = signals.filter {
            if case .errorDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(errorSignals.isEmpty, "APIError pattern should be detected")
    }

    // MARK: - Finished Detection

    func testDetectShellPromptAsFinished() {
        let _ = sut.processBytes(lineData("claude chat"))
        let _ = sut.processBytes(lineData("claude chat"))

        let _ = sut.processBytes(lineData("$ "))
        let signals = sut.processBytes(lineData("$ "))

        let finishedSignals = signals.filter {
            if case .completionDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(finishedSignals.isEmpty, "Shell prompt '$' should indicate finished")
    }

    // MARK: - Hysteresis

    func testSingleMatchDoesNotTriggerTransition() {
        // With requiredConsecutiveMatches = 2, a single match should not trigger
        let singleMatchDetector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0, // No cooldown for this test
            maxLineBuffer: 5
        )

        let signals = singleMatchDetector.processBytes(lineData("claude --help"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertTrue(launchSignals.isEmpty, "Single match should not trigger with requiredConsecutiveMatches=2")
    }

    func testTwoConsecutiveMatchesTriggerTransition() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )

        let _ = detector.processBytes(lineData("claude --help"))
        let signals = detector.processBytes(lineData("claude --version"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(launchSignals.isEmpty, "Two consecutive matches should trigger transition")
    }

    func testNoiseWithinWindowDoesNotPreventDetection() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )

        let _ = detector.processBytes(lineData("claude --help"))
        let _ = detector.processBytes(lineData("some other output"))
        let signals = detector.processBytes(lineData("claude --version"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertFalse(launchSignals.isEmpty,
            "Noise within window should not prevent detection (sliding window hysteresis)")
    }

    // MARK: - Cooldown

    func testCooldownPreventsRetriggerWithinWindow() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 10.0, // Long cooldown for test
            maxLineBuffer: 5
        )

        // First detection
        let signals1 = detector.processBytes(lineData("claude --help"))
        XCTAssertFalse(signals1.isEmpty, "First detection should succeed")

        // Immediate second detection should be suppressed by cooldown
        let signals2 = detector.processBytes(lineData("claude --version"))

        let launchSignals2 = signals2.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertTrue(launchSignals2.isEmpty, "Cooldown should prevent re-trigger within window")
    }

    // MARK: - Multiple Agents

    func testCorrectAgentDetectedWhenMultipleConfigured() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )

        let signals = detector.processBytes(lineData("codex run all-tests"))

        let launchSignals = signals.filter {
            if case .agentDetected(let name) = $0.event {
                return name == "codex"
            }
            return false
        }

        XCTAssertFalse(launchSignals.isEmpty, "Codex should be correctly identified, not claude")
    }

    // MARK: - Circular Buffer

    func testCircularBufferRetainsLastNLines() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 0.0,
            maxLineBuffer: 3
        )

        // Fill buffer with 5 lines (exceeds max of 3)
        let _ = detector.processBytes(lineData("line 1"))
        let _ = detector.processBytes(lineData("line 2"))
        let _ = detector.processBytes(lineData("line 3"))
        let _ = detector.processBytes(lineData("line 4"))
        let _ = detector.processBytes(lineData("line 5"))

        // Buffer should only have the last 3 lines
        XCTAssertEqual(detector.recentLineCount, 3, "Buffer should cap at maxLineBuffer")
    }

    // MARK: - Empty Lines

    func testEmptyLineDoesNotCrash() {
        let signals = sut.processBytes(lineData(""))
        // Should not crash, and empty lines should not match any pattern
        XCTAssertTrue(signals.isEmpty, "Empty line should produce no signals")
    }

    func testWhitespaceOnlyLineDoesNotCrash() {
        let signals = sut.processBytes(lineData("   "))
        // Not a crash test, just verifying stability
        _ = signals // Avoid unused variable warning
    }

    // MARK: - Special Regex Characters

    func testPatternWithSpecialRegexChars() {
        // The waiting pattern "(Y/n)" contains regex special chars ()
        // It should still work because the patterns are pre-compiled
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )

        let signals = detector.processBytes(lineData("Do you want to continue? (Y/n)"))

        let waitingSignals = signals.filter {
            if case .promptDetected = $0.event { return true }
            return false
        }

        // The pattern \(Y/n\) should match literal "(Y/n)"
        XCTAssertFalse(waitingSignals.isEmpty, "Pattern with special regex chars should match")
    }

    // MARK: - No Match

    func testNoMatchProducesNoSignals() {
        let signals = sut.processBytes(lineData("Just some regular terminal output"))
        XCTAssertTrue(signals.isEmpty, "Unmatched text should produce no signals")
    }

    func testRandomBinaryDataDoesNotCrash() {
        var randomBytes = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { randomBytes[i] = UInt8(i) }
        let data = Data(randomBytes)

        let signals = sut.processBytes(data)
        _ = signals
        // No crash = pass
    }

    // MARK: - DetectionLayer Conformance

    func testConformsToDetectionLayerProtocol() {
        let layer: DetectionLayer = sut
        let signals = layer.processBytes(lineData("claude test"))
        _ = signals
        // Compiles and runs = pass
    }

    // MARK: - Per-Agent Cooldown

    func testCooldown_differentAgentsNotSuppressed() {
        let aider = AgentConfig(
            name: "aider",
            displayName: "Aider",
            launchPatterns: ["^aider\\b"],
            waitingPatterns: [],
            errorPatterns: [],
            finishedIndicators: [],
            oscSupported: false,
            idleTimeoutOverride: nil
        )
        let configsWithAider = configs + [AgentConfigService.compile(aider)]

        let detector = PatternMatchingDetector(
            configs: configsWithAider,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 1.0,
            maxLineBuffer: 5
        )

        let aiderSignals = detector.processBytes(lineData("aider --model gpt-4"))
        XCTAssertEqual(aiderSignals.count, 1, "Should detect aider launch")

        let claudeSignals = detector.processBytes(lineData("claude --model opus"))
        XCTAssertEqual(claudeSignals.count, 1,
            "Should detect claude launch even within cooldown — different agent")
    }

    // MARK: - Confidence Levels

    func testLaunchSignalHasMediumConfidence() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 1,
            cooldownInterval: 0.0,
            maxLineBuffer: 5
        )

        let signals = detector.processBytes(lineData("claude --help"))
        let launchSignal = signals.first {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertNotNil(launchSignal)
        XCTAssertEqual(launchSignal?.confidence, 0.7, "Pattern-based detection should have 0.7 confidence")
        XCTAssertEqual(launchSignal?.source, .pattern(name: "claude"))
    }

    // MARK: - Sliding Window Hysteresis

    func testSlidingWindow_matchesSeparatedByNoiseDetectsAgent() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        // First matching line
        let _ = detector.processBytes(lineData("claude --model opus"))
        // Noise lines between matches
        let _ = detector.processBytes(lineData("Loading..."))
        let _ = detector.processBytes(lineData("Connecting..."))
        // Second matching line within window
        let signals = detector.processBytes(lineData("claude initialized"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertEqual(launchSignals.count, 1,
            "Should detect agent when 2 matches occur within sliding window despite noise")
    }

    func testSlidingWindow_matchOutsideWindowDoesNotCount() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 3
        )

        // First matching line
        let _ = detector.processBytes(lineData("claude --help"))
        // Push the first match out of the window (buffer size 3)
        let _ = detector.processBytes(lineData("noise 1"))
        let _ = detector.processBytes(lineData("noise 2"))
        let _ = detector.processBytes(lineData("noise 3"))
        // Second match, but first match has scrolled out of window
        let signals = detector.processBytes(lineData("claude --version"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertTrue(launchSignals.isEmpty,
            "Match that scrolled out of window should not count toward threshold")
    }

    func testSlidingWindow_waitingMatchesSeparatedByNoise() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        let _ = detector.processBytes(lineData("? First question"))
        let _ = detector.processBytes(lineData("some output text"))
        let signals = detector.processBytes(lineData("? Second question"))

        let waitingSignals = signals.filter {
            if case .promptDetected = $0.event { return true }
            return false
        }

        XCTAssertEqual(waitingSignals.count, 1,
            "Should detect waiting when 2 matches occur within sliding window despite noise")
    }

    func testSlidingWindow_errorMatchesSeparatedByNoise() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        let _ = detector.processBytes(lineData("Error: connection refused"))
        let _ = detector.processBytes(lineData("retrying..."))
        let signals = detector.processBytes(lineData("Error: timeout"))

        let errorSignals = signals.filter {
            if case .errorDetected = $0.event { return true }
            return false
        }

        XCTAssertEqual(errorSignals.count, 1,
            "Should detect error when 2 matches occur within sliding window despite noise")
    }

    func testSlidingWindow_finishedMatchesSeparatedByNoise() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        let _ = detector.processBytes(lineData("$ "))
        let _ = detector.processBytes(lineData("some cleanup output"))
        let signals = detector.processBytes(lineData("$ "))

        let finishedSignals = signals.filter {
            if case .completionDetected = $0.event { return true }
            return false
        }

        XCTAssertEqual(finishedSignals.count, 1,
            "Should detect finished when 2 matches occur within sliding window despite noise")
    }

    func testSlidingWindow_emissionResetsWindowCounters() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        // First emission
        let _ = detector.processBytes(lineData("claude --help"))
        let _ = detector.processBytes(lineData("noise"))
        let signals1 = detector.processBytes(lineData("claude --version"))

        let launch1 = signals1.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }
        XCTAssertEqual(launch1.count, 1, "First emission should fire")

        // After emission, need 2 fresh matches again
        let signals2 = detector.processBytes(lineData("claude --chat"))

        let launch2 = signals2.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }
        XCTAssertTrue(launch2.isEmpty,
            "Single match after emission should not re-trigger (need 2 fresh matches)")
    }

    func testSlidingWindow_emptyLinesDoNotCountAsMatches() {
        let detector = PatternMatchingDetector(
            configs: configs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 0.0,
            maxLineBuffer: 10
        )

        let _ = detector.processBytes(lineData("claude --help"))
        let _ = detector.processBytes(lineData(""))
        let _ = detector.processBytes(lineData("  "))
        let signals = detector.processBytes(lineData("claude --version"))

        let launchSignals = signals.filter {
            if case .agentDetected = $0.event { return true }
            return false
        }

        XCTAssertEqual(launchSignals.count, 1,
            "Empty lines should be false flags in window, not block detection")
    }
}
