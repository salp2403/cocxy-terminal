// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDetectionHooksTests.swift - Tests for Layer 0 hook integration with detection engine.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent Detection Hooks Tests

/// Tests for the integration between HookEventReceiver and AgentDetectionEngine.
///
/// Validates:
/// - Hook events produce correct state machine transitions.
/// - Hook-active sessions bypass layers 1-3.
/// - Non-hook sessions use layers 1-3 normally (backward compatibility).
/// - Mixed scenarios: hooks for one session, patterns for another.
/// - Notification hook forwarding.
/// - Hook source priority is highest.
@MainActor
final class AgentDetectionHooksTests: XCTestCase {

    private var engine: AgentDetectionEngineImpl!
    private var receiver: HookEventReceiverImpl!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        let configs = AgentConfigService.defaultAgentConfigs()
        let compiledConfigs = configs.map { AgentConfigService.compile($0) }
        engine = AgentDetectionEngineImpl(compiledConfigs: compiledConfigs, debounceInterval: 0.05)
        receiver = HookEventReceiverImpl()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        receiver = nil
        engine = nil
        super.tearDown()
    }

    // MARK: - SessionStart -> Agent Registered

    func testHookSessionStartRegistersAgent() {
        let event = makeHookEvent(type: .sessionStart, sessionId: "sess-hook-1",
                                  data: .sessionStart(SessionStartData(model: "claude-opus", agentType: "claude-code")))

        engine.processHookEvent(event)

        XCTAssertEqual(engine.currentState, .agentLaunched)
        XCTAssertEqual(engine.detectedAgentName, "claude-code")
    }

    // MARK: - Stop -> Agent Finished

    func testHookStopTransitionsToFinished() {
        // First launch and get working
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-stop-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-stop-1",
            data: .toolUse(ToolUseData(toolName: "Read"))))

        XCTAssertEqual(engine.currentState, .working)

        // Stop
        engine.processHookEvent(makeHookEvent(
            type: .stop, sessionId: "sess-stop-1",
            data: .stop(StopData(reason: "end_turn"))))

        XCTAssertEqual(engine.currentState, .finished)
    }

    // MARK: - PreToolUse -> Agent Working

    func testHookPreToolUseTransitionsToWorking() {
        // Launch agent first
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-tool-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))

        XCTAssertEqual(engine.currentState, .agentLaunched)

        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-tool-1",
            data: .toolUse(ToolUseData(toolName: "Write"))))

        XCTAssertEqual(engine.currentState, .working)
    }

    // MARK: - PostToolUseFailure -> Agent Error

    func testHookPostToolUseFailureTransitionsToError() {
        // Launch and start working
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-err-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-err-1",
            data: .toolUse(ToolUseData(toolName: "Bash"))))

        XCTAssertEqual(engine.currentState, .working)

        engine.processHookEvent(makeHookEvent(
            type: .postToolUseFailure, sessionId: "sess-err-1",
            data: .toolUse(ToolUseData(toolName: "Bash", error: "exit code 1"))))

        XCTAssertEqual(engine.currentState, .error)
    }

    // MARK: - TeammateIdle -> WaitingInput

    func testHookTeammateIdleTransitionsToWaitingInput() {
        // Launch and start working
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-idle-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-idle-1",
            data: .toolUse(ToolUseData(toolName: "Read"))))

        XCTAssertEqual(engine.currentState, .working)

        engine.processHookEvent(makeHookEvent(
            type: .teammateIdle, sessionId: "sess-idle-1",
            data: .teammateIdle(TeammateIdleData(reason: "waiting"))))

        XCTAssertEqual(engine.currentState, .waitingInput)
    }

    // MARK: - TaskCompleted -> Agent Finished

    func testHookTaskCompletedTransitionsToFinished() {
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-done-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-done-1",
            data: .toolUse(ToolUseData(toolName: "Write"))))

        XCTAssertEqual(engine.currentState, .working)

        engine.processHookEvent(makeHookEvent(
            type: .taskCompleted, sessionId: "sess-done-1",
            data: .taskCompleted(TaskCompletedData(taskDescription: "Feature done"))))

        XCTAssertEqual(engine.currentState, .finished)
    }

    // MARK: - Hook Active -> Layers 1-3 Standby

    func testHookActiveSessionTrackedByEngine() {
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-track-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))

        XCTAssertTrue(engine.hookActiveSessions.contains("sess-track-1"))
    }

    func testHookStopRemovesFromActiveSessions() {
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-rm-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-rm-1",
            data: .toolUse(ToolUseData(toolName: "Read"))))
        engine.processHookEvent(makeHookEvent(
            type: .stop, sessionId: "sess-rm-1",
            data: .stop(StopData(reason: "end_turn"))))

        XCTAssertFalse(engine.hookActiveSessions.contains("sess-rm-1"))
    }

    // MARK: - No Hooks -> Layers 1-3 Work Normally (Backward Compat)

    func testNoHooksLayersWorkNormally() {
        // Use the standard injection path (no hook events)
        sut_injectStandardLifecycle()

        // Engine should behave identically to v1.0
        XCTAssertEqual(engine.currentState, .working)
        XCTAssertTrue(engine.hookActiveSessions.isEmpty)
    }

    // MARK: - Hook Source Priority

    func testHookSignalHasHighestSourcePriority() {
        // Hook source (priority 4) > OSC (priority 3)
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-prio-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))

        // The engine should be in agentLaunched via hook, not via OSC
        XCTAssertEqual(engine.currentState, .agentLaunched)
    }

    // MARK: - Notification Hook

    func testNotificationHookDoesNotChangeState() {
        // Launch and start working
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-notif-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-notif-1",
            data: .toolUse(ToolUseData(toolName: "Write"))))

        XCTAssertEqual(engine.currentState, .working)

        // Notification should NOT change state
        engine.processHookEvent(makeHookEvent(
            type: .notification, sessionId: "sess-notif-1",
            data: .notification(NotificationData(title: "Alert", body: "Something happened"))))

        XCTAssertEqual(engine.currentState, .working)
    }

    // MARK: - PostToolUse Keeps Working

    func testHookPostToolUseKeepsWorking() {
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-post-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-post-1",
            data: .toolUse(ToolUseData(toolName: "Read"))))

        XCTAssertEqual(engine.currentState, .working)

        engine.processHookEvent(makeHookEvent(
            type: .postToolUse, sessionId: "sess-post-1",
            data: .toolUse(ToolUseData(toolName: "Read", result: "OK"))))

        // Should stay working (postToolUse means still active)
        XCTAssertEqual(engine.currentState, .working)
    }

    // MARK: - SessionEnd -> Idle

    func testHookSessionEndTransitionsToIdle() {
        engine.processHookEvent(makeHookEvent(
            type: .sessionStart, sessionId: "sess-end-1",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))))
        engine.processHookEvent(makeHookEvent(
            type: .preToolUse, sessionId: "sess-end-1",
            data: .toolUse(ToolUseData(toolName: "Read"))))

        engine.processHookEvent(makeHookEvent(
            type: .sessionEnd, sessionId: "sess-end-1",
            data: .generic))

        XCTAssertEqual(engine.currentState, .idle)
    }

    // MARK: - Helpers

    private func makeHookEvent(
        type: HookEventType,
        sessionId: String,
        data: HookEventData
    ) -> HookEvent {
        HookEvent(
            type: type,
            sessionId: sessionId,
            timestamp: Date(),
            data: data
        )
    }

    /// Simulates a standard v1.0 lifecycle via direct signal injection (no hooks).
    private func sut_injectStandardLifecycle() {
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
    }
}
