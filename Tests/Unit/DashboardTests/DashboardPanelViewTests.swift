// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardPanelViewTests.swift - Tests for Dashboard UI, ordering, navigation, and hooks integration.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Mock: Dashboard Tab Navigator

/// Test double that records navigation calls.
@MainActor
final class MockDashboardTabNavigator: DashboardTabNavigating {
    /// Tab IDs that were requested to focus, in order.
    private(set) var focusedTabIds: [TabID] = []

    var shouldSucceed = true

    /// Number of times focusTab was called.
    var focusTabCallCount: Int { focusedTabIds.count }

    func focusTab(id: TabID) -> Bool {
        focusedTabIds.append(id)
        return shouldSucceed
    }
}

// MARK: - Dashboard Panel View Tests

/// Tests for T-064 (DashboardPanelView), T-065 (ordering, navigation),
/// and T-066 (hooks->dashboard integration).
///
/// Organized in 4 sections:
/// 1. UI/View tests (via ViewModel -- SwiftUI views tested through presentation layer)
/// 2. Ordering tests
/// 3. Navigation tests
/// 4. Integration tests (hooks -> dashboard)
@MainActor
final class DashboardPanelViewTests: XCTestCase {

    private var sut: AgentDashboardViewModel!
    private var navigator: MockDashboardTabNavigator!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        navigator = MockDashboardTabNavigator()
        sut = AgentDashboardViewModel()
        sut.tabNavigator = navigator
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        navigator = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - UI/View Tests (5+)

    func testDashboardPanelRenderEmptySessionsShowsEmptyState() {
        // An empty dashboard should have zero sessions.
        XCTAssertTrue(sut.sessions.isEmpty,
                       "Dashboard with no events should have no sessions")
        XCTAssertFalse(sut.isVisible,
                        "Dashboard should start hidden")
    }

    func testDashboardPanelRendersFiveSessions() {
        // Create 5 sessions via hook events
        for index in 0..<5 {
            let event = makeSessionStartEvent(
                sessionId: "sess-\(index)",
                projectDir: "/Users/test/project-\(index)"
            )
            sut.processHookEvent(event)
        }

        XCTAssertEqual(sut.sessions.count, 5,
                        "Dashboard should display all 5 sessions")
    }

    func testDashboardSessionRowShowsCorrectStateIndicatorColor() {
        // Verify DashboardStateIndicator mapping for each state
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .working), "systemGreen",
                        "Working state should map to green")
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .waitingForInput), "systemOrange",
                        "WaitingForInput state should map to orange")
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .error), "systemRed",
                        "Error state should map to red")
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .blocked), "systemRed",
                        "Blocked state should map to red")
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .idle), "tertiaryLabel",
                        "Idle state should map to gray")
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .finished), "tertiaryLabel",
                        "Finished state should map to gray")
        XCTAssertEqual(DashboardStateIndicator.colorName(for: .launching), "systemBlue",
                        "Launching state should map to blue")
    }

    func testDashboardSessionRowTruncatesLongProjectNames() {
        let longProjectName = String(repeating: "a", count: 60)
        let event = makeSessionStartEvent(
            sessionId: "sess-long",
            projectDir: "/Users/test/\(longProjectName)"
        )
        sut.processHookEvent(event)

        let session = sut.sessions.first
        XCTAssertNotNil(session)
        // The projectName should be the full directory name (truncation is a view concern,
        // but the ViewModel should provide the raw data)
        XCTAssertEqual(session?.projectName, longProjectName,
                        "ViewModel should store full project name for view to truncate")
    }

    func testDashboardStateIndicatorMapsAllStatesToColors() {
        // Every state in AgentDashboardState should produce a non-empty color name
        for state in AgentDashboardState.allCases {
            let colorName = DashboardStateIndicator.colorName(for: state)
            XCTAssertFalse(colorName.isEmpty,
                           "State \(state) must have a non-empty color name")
        }
    }

    func testDashboardStateIndicatorMapsStateToCorrectSymbol() {
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .working), "circle.fill")
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .waitingForInput), "circle.badge.questionmark.fill")
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .error), "exclamationmark.circle.fill")
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .blocked), "exclamationmark.circle.fill")
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .idle), "circle")
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .finished), "circle")
        XCTAssertEqual(DashboardStateIndicator.symbol(for: .launching), "circle.fill")
    }

    // MARK: - Ordering Tests (5+)

    func testErrorsSortBeforeWaiting() {
        // Use detection signals with fixed UUIDs for predictable IDs
        let waitTabId = UUID()
        sut.processDetectionSignal(agentName: "agent-wait", state: .waitingInput, tabId: waitTabId)
        let waitSessionId = "pattern-\(waitTabId.uuidString)"

        createSessionWithState("sess-err", state: .error)

        XCTAssertEqual(sut.sessions[0].id, "sess-err",
                        "Error sessions should appear before waiting sessions")
        XCTAssertEqual(sut.sessions[1].id, waitSessionId)
    }

    func testWaitingSortsBeforeWorking() {
        createSessionWithState("sess-work", state: .working)

        let waitTabId = UUID()
        sut.processDetectionSignal(agentName: "agent-wait", state: .waitingInput, tabId: waitTabId)
        let waitSessionId = "pattern-\(waitTabId.uuidString)"

        XCTAssertEqual(sut.sessions[0].id, waitSessionId,
                        "Waiting sessions should appear before working sessions")
        XCTAssertEqual(sut.sessions[1].id, "sess-work")
    }

    func testWorkingSortsBeforeFinished() {
        createSessionWithState("sess-fin", state: .finished)
        createSessionWithState("sess-work", state: .working)

        XCTAssertEqual(sut.sessions[0].id, "sess-work",
                        "Working sessions should appear before finished sessions")
        XCTAssertEqual(sut.sessions[1].id, "sess-fin")
    }

    func testFocusPriorityOverridesStateOrdering() {
        // Create a finished session with focus priority and an error session with standard
        createSessionWithState("sess-err", state: .error)
        createSessionWithState("sess-focus-fin", state: .finished)
        sut.setPriority(.focus, for: "sess-focus-fin")

        // Focus priority should put the finished session above the error session
        XCTAssertEqual(sut.sessions[0].id, "sess-focus-fin",
                        "Focus priority session should appear first regardless of state")
        XCTAssertEqual(sut.sessions[1].id, "sess-err")
    }

    func testWithinSameStateOldestFirst() {
        let oldDate = Date(timeIntervalSinceNow: -120)
        let recentDate = Date(timeIntervalSinceNow: -10)

        // Create two sessions both in working state, with different times
        let startOld = makeSessionStartEvent(sessionId: "sess-old")
        sut.processHookEvent(startOld)

        let startRecent = makeSessionStartEvent(sessionId: "sess-recent")
        sut.processHookEvent(startRecent)

        // Make both working with different activity timestamps
        let toolOld = makeToolUseEvent(sessionId: "sess-old", timestamp: oldDate)
        let toolRecent = makeToolUseEvent(sessionId: "sess-recent", timestamp: recentDate)
        sut.processHookEvent(toolOld)
        sut.processHookEvent(toolRecent)

        // Both are working; oldest (earlier timestamp) should come first
        let workingSessions = sut.sessions.filter { $0.state == .working }
        XCTAssertEqual(workingSessions.count, 2)
        XCTAssertEqual(workingSessions[0].id, "sess-old",
                        "Within same state, oldest activity should sort first")
        XCTAssertEqual(workingSessions[1].id, "sess-recent")
    }

    // MARK: - Navigation Tests (3+)

    func testNavigateToSessionCallsFocusTabOnNavigator() {
        // Create a session with a known tabId
        let startEvent = makeSessionStartEvent(sessionId: "sess-nav")
        sut.processHookEvent(startEvent)

        let session = sut.sessions.first!

        sut.navigateToSession(session.id)

        XCTAssertEqual(navigator.focusTabCallCount, 1,
                        "navigateToSession should call focusTab exactly once")
        XCTAssertEqual(navigator.focusedTabIds.first, TabID(rawValue: session.tabId),
                        "Should navigate to the session's tabId")
    }

    func testNavigateToSessionWithInvalidIdDoesNotCrash() {
        // Should not crash -- no-op for invalid ID
        sut.navigateToSession("nonexistent-id")

        XCTAssertEqual(navigator.focusTabCallCount, 0,
                        "Should not call focusTab for nonexistent session")
    }

    func testNavigateToSessionWithoutNavigatorDoesNotCrash() {
        // ViewModel without navigator set should not crash
        let viewModelWithoutNav = AgentDashboardViewModel()
        let event = makeSessionStartEvent(sessionId: "sess-no-nav")
        viewModelWithoutNav.processHookEvent(event)

        // Should not crash
        viewModelWithoutNav.navigateToSession("sess-no-nav")
    }

    func testNavigateToSessionSkipsCrossWindowCallbackWhenLocalNavigationSucceeds() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-local")
        sut.processHookEvent(startEvent)

        var crossWindowCallCount = 0
        sut.onCrossWindowNavigate = { _ in
            crossWindowCallCount += 1
        }

        navigator.shouldSucceed = true
        sut.navigateToSession("sess-local")

        XCTAssertEqual(crossWindowCallCount, 0,
                       "Cross-window callback should not fire when local navigation succeeds")
    }

    func testNavigateToSessionFallsBackToCrossWindowCallbackWhenLocalNavigationFails() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-remote")
        sut.processHookEvent(startEvent)

        var broadcastedTabID: UUID?
        sut.onCrossWindowNavigate = { tabID in
            broadcastedTabID = tabID
        }

        navigator.shouldSucceed = false
        sut.navigateToSession("sess-remote")

        XCTAssertEqual(broadcastedTabID, sut.sessions.first?.tabId,
                       "Cross-window callback should receive the session tab UUID when local navigation fails")
    }

    // MARK: - Integration Tests (7+)

    func testHookSessionStartCreatesNewRowInDashboard() {
        let event = makeSessionStartEvent(
            sessionId: "sess-int-1",
            projectDir: "/Users/test/my-api",
            agentType: "claude-code",
            model: "claude-sonnet-4"
        )

        sut.processHookEvent(event)

        XCTAssertEqual(sut.sessions.count, 1)
        let session = sut.sessions.first!
        XCTAssertEqual(session.id, "sess-int-1")
        XCTAssertEqual(session.projectName, "my-api")
        XCTAssertEqual(session.agentName, "claude-code")
        XCTAssertEqual(session.model, "claude-sonnet-4")
        XCTAssertEqual(session.state, .launching)
    }

    func testHookPostToolUseUpdatesLastActivityInRealTime() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-int-tool")
        sut.processHookEvent(startEvent)

        let toolEvent = HookEvent(
            type: .postToolUse,
            sessionId: "sess-int-tool",
            timestamp: Date(),
            data: .toolUse(ToolUseData(
                toolName: "Write",
                toolInput: ["file_path": "/Users/test/Sources/App.swift"]
            ))
        )
        sut.processHookEvent(toolEvent)

        XCTAssertEqual(sut.sessions.first?.state, .working,
                        "PostToolUse should transition to working state")
        XCTAssertEqual(sut.sessions.first?.lastActivity, "Write: App.swift",
                        "LastActivity should show tool name and file")
    }

    func testHookStopChangesStateToFinished() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-int-stop")
        sut.processHookEvent(startEvent)

        let stopEvent = HookEvent(
            type: .stop,
            sessionId: "sess-int-stop",
            timestamp: Date(),
            data: .stop(StopData(lastMessage: "All tasks completed", reason: "end_turn"))
        )
        sut.processHookEvent(stopEvent)

        XCTAssertEqual(sut.sessions.first?.state, .finished)
        XCTAssertEqual(sut.sessions.first?.lastActivity, "All tasks completed")
    }

    func testPatternDetectedAgentAppearsInDashboardWithBasicInfo() {
        let tabId = UUID()

        sut.processDetectionSignal(
            agentName: "Aider",
            state: .working,
            tabId: tabId
        )

        XCTAssertEqual(sut.sessions.count, 1,
                        "Pattern-detected agent should create a session")
        let session = sut.sessions.first!
        XCTAssertEqual(session.agentName, "Aider")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.tabId, tabId)
        XCTAssertEqual(session.id, "pattern-\(tabId.uuidString)")
    }

    func testMultipleAgentsAllVisibleCorrectlyOrdered() {
        // Create 3 agents in different states
        createSessionWithState("sess-multi-err", state: .error)
        createSessionWithState("sess-multi-work", state: .working)
        createSessionWithState("sess-multi-fin", state: .finished)

        XCTAssertEqual(sut.sessions.count, 3)
        XCTAssertEqual(sut.sessions[0].id, "sess-multi-err",
                        "Error first")
        XCTAssertEqual(sut.sessions[1].id, "sess-multi-work",
                        "Working second")
        XCTAssertEqual(sut.sessions[2].id, "sess-multi-fin",
                        "Finished last")
    }

    func testSessionEndRemovesRowFromDashboard() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-remove")
        sut.processHookEvent(startEvent)
        XCTAssertEqual(sut.sessions.count, 1)

        let endEvent = HookEvent(
            type: .sessionEnd,
            sessionId: "sess-remove",
            timestamp: Date(),
            data: .generic
        )
        sut.processHookEvent(endEvent)

        XCTAssertTrue(sut.sessions.isEmpty,
                       "SessionEnd should remove the session from dashboard")
    }

    func testDashboardToggleShowsAndHidesPanel() {
        XCTAssertFalse(sut.isVisible, "Should start hidden")

        sut.toggleVisibility()
        XCTAssertTrue(sut.isVisible, "Toggle should show panel")

        sut.toggleVisibility()
        XCTAssertFalse(sut.isVisible, "Toggle again should hide panel")
    }

    func testHookPostToolUseFailureSetsErrorState() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-int-fail")
        sut.processHookEvent(startEvent)

        let failEvent = HookEvent(
            type: .postToolUseFailure,
            sessionId: "sess-int-fail",
            timestamp: Date(),
            data: .toolUse(ToolUseData(
                toolName: "Bash",
                error: "npm ERR! missing script: build"
            ))
        )
        sut.processHookEvent(failEvent)

        XCTAssertEqual(sut.sessions.first?.state, .error,
                        "PostToolUseFailure should set error state")
        XCTAssertTrue(sut.sessions.first?.lastActivity?.contains("npm ERR!") ?? false,
                       "Error message should be in lastActivity")
    }

    func testHookSubagentStartUpdatesSubagents() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-int-sub")
        sut.processHookEvent(startEvent)

        let subagentEvent = HookEvent(
            type: .subagentStart,
            sessionId: "sess-int-sub",
            timestamp: Date(),
            data: .subagent(SubagentData(subagentId: "sub-research", subagentType: "research"))
        )
        sut.processHookEvent(subagentEvent)

        XCTAssertEqual(sut.sessions.first?.subagents.count, 1)
        XCTAssertEqual(sut.sessions.first?.subagents.first?.id, "sub-research")
    }

    func testHookTeammateIdleSetsIdleState() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-int-idle")
        sut.processHookEvent(startEvent)

        let idleEvent = HookEvent(
            type: .teammateIdle,
            sessionId: "sess-int-idle",
            timestamp: Date(),
            data: .teammateIdle(TeammateIdleData(
                teammateId: "tm-1",
                reason: "waiting_for_review"
            ))
        )
        sut.processHookEvent(idleEvent)

        XCTAssertEqual(sut.sessions.first?.state, .idle)
    }

    func testHookTaskCompletedSetsFinishedWithDescription() {
        let startEvent = makeSessionStartEvent(sessionId: "sess-int-task")
        sut.processHookEvent(startEvent)

        let taskEvent = HookEvent(
            type: .taskCompleted,
            sessionId: "sess-int-task",
            timestamp: Date(),
            data: .taskCompleted(TaskCompletedData(
                taskDescription: "Implemented login feature"
            ))
        )
        sut.processHookEvent(taskEvent)

        XCTAssertEqual(sut.sessions.first?.state, .finished)
        XCTAssertEqual(sut.sessions.first?.lastActivity, "Implemented login feature")
    }

    // MARK: - Helpers

    /// Creates a SessionStart hook event.
    private func makeSessionStartEvent(
        sessionId: String,
        projectDir: String = "/Users/test/project",
        agentType: String = "claude-code",
        model: String = "claude-sonnet-4"
    ) -> HookEvent {
        HookEvent(
            type: .sessionStart,
            sessionId: sessionId,
            timestamp: Date(),
            data: .sessionStart(SessionStartData(
                model: model,
                agentType: agentType,
                workingDirectory: projectDir
            ))
        )
    }

    /// Creates a PostToolUse hook event.
    private func makeToolUseEvent(
        sessionId: String,
        toolName: String = "Read",
        timestamp: Date = Date()
    ) -> HookEvent {
        HookEvent(
            type: .postToolUse,
            sessionId: sessionId,
            timestamp: timestamp,
            data: .toolUse(ToolUseData(toolName: toolName))
        )
    }

    /// Creates a session and moves it to the specified state.
    private func createSessionWithState(_ sessionId: String, state: AgentDashboardState) {
        let startEvent = makeSessionStartEvent(sessionId: sessionId)
        sut.processHookEvent(startEvent)

        switch state {
        case .working:
            let toolEvent = makeToolUseEvent(sessionId: sessionId)
            sut.processHookEvent(toolEvent)
        case .error:
            let failEvent = HookEvent(
                type: .postToolUseFailure,
                sessionId: sessionId,
                timestamp: Date(),
                data: .toolUse(ToolUseData(toolName: "Bash", error: "fail"))
            )
            sut.processHookEvent(failEvent)
        case .finished:
            let stopEvent = HookEvent(
                type: .stop,
                sessionId: sessionId,
                timestamp: Date(),
                data: .stop(StopData(lastMessage: "Done", reason: "end_turn"))
            )
            sut.processHookEvent(stopEvent)
        case .idle:
            let idleEvent = HookEvent(
                type: .teammateIdle,
                sessionId: sessionId,
                timestamp: Date(),
                data: .teammateIdle(TeammateIdleData())
            )
            sut.processHookEvent(idleEvent)
        case .waitingForInput:
            // waitingForInput has no direct hook event mapping.
            // Use processDetectionSignal for this state -- tests that need
            // waitingForInput ordering do so directly via processDetectionSignal.
            break
        case .blocked, .launching:
            // launching is the default state after sessionStart
            break
        }
    }
}
