// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RealisticAgentDetectionTests.swift - Integration tests with real-world terminal output.
//
// These tests simulate realistic agent sessions with the noise and patterns
// that appear in actual terminal output. They exercise the full detection
// pipeline: PatternMatchingDetector -> conflict resolution -> state machine.
//
// Key behavior of the PatternMatchingDetector:
// - Uses a sliding window of 5 lines (maxLineBuffer).
// - Requires 2 matching lines within the window (requiredConsecutiveMatches).
// - Launch patterns use ^ anchors, so lines must START with the agent name.
// - Lines like "$ aider" do NOT match "^aider\b" because of the leading "$".
// - The processTerminalOutput dispatches signals to main thread via async.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - State Collector

/// Reference-type wrapper for collecting state transitions from the publisher.
///
/// Swift arrays are value types. Capturing a local array in a closure and
/// mutating it does not propagate changes back to the caller. This class
/// provides a shared mutable container that the sink closure and the test
/// both reference.
private final class StateCollector {
    var states: [AgentStateMachine.State] = []
}

// MARK: - Realistic Agent Detection Tests

@MainActor
final class RealisticAgentDetectionTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs()
            .map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(
            compiledConfigs: configs,
            debounceInterval: 0.01
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Feeds multiple lines as a single terminal output chunk, newline-separated.
    private func feedLines(_ lines: [String]) {
        let text = lines.joined(separator: "\n") + "\n"
        engine.processTerminalOutput(Data(text.utf8))
    }

    /// Waits for async dispatch from processTerminalOutput to reach main thread.
    private func waitForAsyncDispatch(timeout: TimeInterval = 0.3) {
        let dispatchExpectation = expectation(description: "async dispatch")
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            dispatchExpectation.fulfill()
        }
        waitForExpectations(timeout: timeout + 1.0)
    }

    /// Creates a StateCollector subscribed to the engine's stateChanged publisher.
    /// Returns the collector so the test can inspect states after async dispatch.
    private func subscribeStateCollector() -> StateCollector {
        let collector = StateCollector()
        engine.stateChanged
            .sink { context in collector.states.append(context.state) }
            .store(in: &cancellables)
        return collector
    }

    // MARK: - REAL-001: Aider Launch with Noise

    /// Simulates a realistic Aider session launch.
    ///
    /// Aider prints its version and prompt. Both lines start with "aider",
    /// matching the launch pattern "^aider\b". The sliding window sees
    /// 2 matches within 5 lines, triggering the agentDetected signal.
    ///
    /// Lines prefixed with "$" (shell prompt) do NOT match because the
    /// pattern requires "aider" at position 0.
    func testRealisticAiderLaunchWithBannerNoise() {
        let collector = subscribeStateCollector()

        // "aider v0.82.2" matches ^aider\b (1st match in window)
        // Non-matching lines fill the buffer but do not reset the window count
        // "aider> " matches ^aider\b (2nd match in window -> signal emitted)
        feedLines([
            "aider v0.82.2",
            "Model: gpt-4 with diff edit format",
            "Git repo: .git with 42 files",
            "Repo-map: using 1024 tokens",
            "aider> ",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Aider debe detectarse como lanzado con salida realista de terminal"
        )
        XCTAssertEqual(
            engine.detectedAgentName, "aider",
            "El nombre del agente detectado debe ser 'aider'"
        )
    }

    // MARK: - REAL-002: Claude Code Launch via Pattern (No Hooks)

    /// Simulates Claude Code launched from terminal without hook integration.
    ///
    /// Two lines starting with "claude" within the sliding window satisfy
    /// the hysteresis threshold for the pattern "^claude\b".
    func testRealisticClaudeCodeLaunchViaPattern() {
        let collector = subscribeStateCollector()

        // Both lines start with "claude", matching ^claude\b
        feedLines([
            "claude v2.3.0",
            "claude: Welcome to Claude Code!",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Claude Code debe detectarse via pattern matching sin hooks"
        )
        XCTAssertEqual(engine.detectedAgentName, "claude")
    }

    // MARK: - REAL-003: Codex Launch

    /// Simulates Codex CLI startup with model selection output.
    ///
    /// Two lines starting with "codex" match the pattern "^codex\b".
    func testRealisticCodexLaunch() {
        let collector = subscribeStateCollector()

        feedLines([
            "codex v1.0.3",
            "codex: Using model o4-mini",
            "Ready for input.",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Codex debe detectarse como lanzado"
        )
        XCTAssertEqual(engine.detectedAgentName, "codex")
    }

    // MARK: - REAL-004: Gemini CLI Launch

    /// Simulates Gemini CLI startup with welcome text.
    ///
    /// Two lines starting with "gemini" match the pattern "^gemini\b".
    func testRealisticGeminiCLILaunch() {
        let collector = subscribeStateCollector()

        feedLines([
            "gemini cli v0.1.5",
            "gemini: Welcome to Gemini CLI",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Gemini CLI debe detectarse como lanzado"
        )
        XCTAssertEqual(engine.detectedAgentName, "gemini-cli")
    }

    // MARK: - REAL-005: Kiro Launch

    /// Simulates Kiro startup output.
    ///
    /// Two lines starting with "kiro" match the pattern "^kiro\b".
    func testRealisticKiroLaunch() {
        let collector = subscribeStateCollector()

        feedLines([
            "kiro v0.3.1",
            "kiro: Initializing workspace",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Kiro debe detectarse como lanzado"
        )
        XCTAssertEqual(engine.detectedAgentName, "kiro")
    }

    // MARK: - REAL-006: OpenCode Launch

    /// Simulates OpenCode startup output.
    ///
    /// Two lines starting with "opencode" match the pattern "^opencode\b".
    func testRealisticOpenCodeLaunch() {
        let collector = subscribeStateCollector()

        feedLines([
            "opencode v2.1.0",
            "opencode: Loading configuration",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "OpenCode debe detectarse como lanzado"
        )
        XCTAssertEqual(engine.detectedAgentName, "opencode")
    }

    // MARK: - REAL-007: False Positive Verification

    /// Feeds typical terminal commands that must NOT trigger agent detection.
    ///
    /// All lines are common CLI output (git, ls, npm, cargo, swift build).
    /// None start with an agent name, so no launch pattern should match.
    func testNormalTerminalOutputDoesNotTriggerDetection() {
        let collector = subscribeStateCollector()

        feedLines([
            "On branch main",
            "Your branch is up to date with 'origin/main'.",
            "Changes not staged for commit:",
            "  modified:   Sources/App/AppDelegate.swift",
        ])

        feedLines([
            "total 128",
            "drwxr-xr-x  15 user staff  480 Mar 26 10:00 .",
            "-rw-r--r--   1 user staff 2048 Mar 26 10:00 Package.swift",
        ])

        feedLines([
            "added 1024 packages in 12s",
            "42 packages are looking for funding",
        ])

        feedLines([
            "   Compiling my_crate v0.1.0",
            "    Finished release [optimized] target(s) in 45.2s",
        ])

        feedLines([
            "Building for debugging...",
            "Build complete! (12.34s)",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.isEmpty,
            "Salida normal de terminal no debe disparar deteccion de agentes. "
            + "Estados registrados: \(collector.states)"
        )
        XCTAssertEqual(engine.currentState, .idle)
        XCTAssertNil(engine.detectedAgentName)
    }

    // MARK: - REAL-008: Hook Event Full Lifecycle

    /// Exercises the complete hook event lifecycle for Claude Code.
    ///
    /// Hook events are processed synchronously on MainActor via processHookEvent.
    /// The state machine transitions are immediate, no async dispatch needed.
    ///
    /// Lifecycle: SessionStart -> PreToolUse -> PostToolUse -> TaskCompleted -> SessionEnd
    /// States:    idle -> agentLaunched -> working -> (working) -> finished -> idle
    func testHookEventFullLifecycle() {
        let collector = subscribeStateCollector()
        let sessionId = "test-session-001"

        // 1. SessionStart -> agentLaunched
        engine.processHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            data: .sessionStart(SessionStartData(
                model: "claude-sonnet-4-20250514",
                agentType: "claude-code",
                workingDirectory: "/tmp/test"
            ))
        ))

        XCTAssertEqual(engine.currentState, .agentLaunched)
        XCTAssertEqual(engine.detectedAgentName, "claude-code")
        XCTAssertTrue(engine.hookActiveSessions.contains(sessionId))

        // 2. PreToolUse -> working (outputReceived from agentLaunched)
        engine.processHookEvent(HookEvent(
            type: .preToolUse,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(
                toolName: "Bash",
                toolInput: ["command": "ls -la"]
            ))
        ))

        XCTAssertEqual(engine.currentState, .working)

        // 3. PostToolUse -> stays working
        //    outputReceived from working has no valid transition in the state table,
        //    so the state machine stays in working. No new state is emitted.
        engine.processHookEvent(HookEvent(
            type: .postToolUse,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(
                toolName: "Bash",
                toolInput: ["command": "ls -la"],
                result: "total 128"
            ))
        ))

        XCTAssertEqual(engine.currentState, .working)

        // 4. TaskCompleted -> finished (completionDetected from working)
        engine.processHookEvent(HookEvent(
            type: .taskCompleted,
            sessionId: sessionId,
            data: .taskCompleted(TaskCompletedData(
                taskDescription: "Listed directory contents"
            ))
        ))

        XCTAssertEqual(engine.currentState, .finished)

        // 5. SessionEnd -> idle (agentExited from finished)
        engine.processHookEvent(HookEvent(
            type: .sessionEnd,
            sessionId: sessionId
        ))

        XCTAssertEqual(engine.currentState, .idle)
        XCTAssertNil(engine.detectedAgentName)
        XCTAssertFalse(engine.hookActiveSessions.contains(sessionId))

        // Verify the full transition sequence captured by the collector
        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Debe registrar transicion a agentLaunched"
        )
        XCTAssertTrue(
            collector.states.contains(.working),
            "Debe registrar transicion a working"
        )
        XCTAssertTrue(
            collector.states.contains(.finished),
            "Debe registrar transicion a finished"
        )
        XCTAssertTrue(
            collector.states.contains(.idle),
            "Debe registrar transicion final a idle"
        )
    }

    // MARK: - REAL-009: Agent Switch After Reset

    /// Launches aider via pattern, resets the engine, then launches claude.
    ///
    /// Verifies that the engine correctly detects a different agent after reset
    /// without state leaking from the previous session.
    func testAgentSwitchAfterReset() {
        // Phase 1: Launch aider via pattern (2 lines matching ^aider\b)
        feedLines([
            "aider --model gpt-4",
            "aider v0.82.2",
        ])

        waitForAsyncDispatch()

        XCTAssertEqual(engine.currentState, .agentLaunched)
        XCTAssertEqual(engine.detectedAgentName, "aider")

        // Reset clears all state
        engine.reset()

        XCTAssertEqual(engine.currentState, .idle)
        XCTAssertNil(engine.detectedAgentName)

        // Phase 2: Launch claude via pattern (2 lines matching ^claude\b)
        let collector = subscribeStateCollector()

        feedLines([
            "claude v2.3.0",
            "claude: Ready",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.agentLaunched),
            "Claude debe detectarse tras resetear el engine"
        )
        XCTAssertEqual(engine.detectedAgentName, "claude")
    }

    // MARK: - REAL-010: Error Detection from Working State

    /// Launches an agent via hook, transitions to working, then feeds error
    /// output through the terminal pattern detector.
    ///
    /// The error pattern "^Error:" requires 2 matches within the sliding
    /// window to emit an errorDetected signal.
    func testErrorDetectionFromWorkingState() {
        // Set up: agent launched and working via direct injection
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .hook(event: "test")
        ))
        engine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .hook(event: "test")
        ))

        XCTAssertEqual(engine.currentState, .working)

        let collector = subscribeStateCollector()

        // Feed 2 error lines within the sliding window
        feedLines([
            "Error: API rate limit exceeded",
            "Error: Please wait 60 seconds before retrying",
        ])

        waitForAsyncDispatch()

        XCTAssertTrue(
            collector.states.contains(.error),
            "Error patterns dentro de la sliding window deben disparar transicion a error"
        )
        XCTAssertEqual(engine.currentState, .error)
    }
}

// MARK: - Hook Event Edge Cases

@MainActor
final class HookEventEdgeCaseTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs()
            .map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(
            compiledConfigs: configs,
            debounceInterval: 0.01
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - HOOK-001: PostToolUseFailure triggers error state

    /// PostToolUseFailure hook events must transition from working to error.
    func testPostToolUseFailureTriggersErrorState() {
        let sessionId = "error-session-001"

        // Set up: session start + tool use (working state)
        engine.processHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            data: .sessionStart(SessionStartData(agentType: "claude-code"))
        ))
        engine.processHookEvent(HookEvent(
            type: .preToolUse,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(toolName: "Bash"))
        ))

        XCTAssertEqual(engine.currentState, .working)

        // PostToolUseFailure -> error
        engine.processHookEvent(HookEvent(
            type: .postToolUseFailure,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(
                toolName: "Bash",
                error: "Command failed with exit code 1"
            ))
        ))

        XCTAssertEqual(
            engine.currentState, .error,
            "PostToolUseFailure debe transicionar a estado error"
        )
    }

    // MARK: - HOOK-002: TeammateIdle triggers waitingInput

    /// TeammateIdle hook event must transition from working to waitingInput.
    func testTeammateIdleTriggersWaitingInput() {
        let sessionId = "idle-session-001"

        // Set up: working state
        engine.processHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            data: .sessionStart(SessionStartData(agentType: "claude-code"))
        ))
        engine.processHookEvent(HookEvent(
            type: .preToolUse,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(toolName: "Read"))
        ))

        XCTAssertEqual(engine.currentState, .working)

        // TeammateIdle -> waitingInput (promptDetected signal)
        engine.processHookEvent(HookEvent(
            type: .teammateIdle,
            sessionId: sessionId,
            data: .teammateIdle(TeammateIdleData(
                teammateId: "teammate-1",
                reason: "Waiting for user confirmation"
            ))
        ))

        XCTAssertEqual(
            engine.currentState, .waitingInput,
            "TeammateIdle debe transicionar a waitingInput"
        )
    }

    // MARK: - HOOK-003: Informational events do not change state

    /// Notification, SubagentStart, SubagentStop, UserPromptSubmit must NOT change state.
    func testInformationalEventsDoNotChangeState() {
        let sessionId = "info-session-001"

        // Set up: working state
        engine.processHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            data: .sessionStart(SessionStartData(agentType: "claude-code"))
        ))
        engine.processHookEvent(HookEvent(
            type: .preToolUse,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(toolName: "Bash"))
        ))

        XCTAssertEqual(engine.currentState, .working)

        // Feed informational events: none should change state
        let informationalTypes: [HookEventType] = [
            .notification,
            .subagentStart,
            .subagentStop,
            .userPromptSubmit,
        ]

        for eventType in informationalTypes {
            engine.processHookEvent(HookEvent(
                type: eventType,
                sessionId: sessionId
            ))

            XCTAssertEqual(
                engine.currentState, .working,
                "\(eventType.rawValue) no debe cambiar el estado del engine"
            )
        }
    }

    // MARK: - HOOK-004: Stop event triggers completion and deregisters session

    /// The Stop hook event should transition to finished and remove the session
    /// from the active hook sessions set.
    func testStopEventTriggersCompletionAndDeregistersSession() {
        let sessionId = "stop-session-001"

        // Set up: working state
        engine.processHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            data: .sessionStart(SessionStartData(agentType: "claude-code"))
        ))
        engine.processHookEvent(HookEvent(
            type: .preToolUse,
            sessionId: sessionId,
            data: .toolUse(ToolUseData(toolName: "Bash"))
        ))

        XCTAssertTrue(engine.hookActiveSessions.contains(sessionId))

        // Stop -> finished + deregister
        engine.processHookEvent(HookEvent(
            type: .stop,
            sessionId: sessionId,
            data: .stop(StopData(reason: "User requested stop"))
        ))

        XCTAssertEqual(engine.currentState, .finished)
        XCTAssertFalse(
            engine.hookActiveSessions.contains(sessionId),
            "Stop debe eliminar la sesion de hookActiveSessions"
        )
    }
}
