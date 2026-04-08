// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardViewModelTests.swift - Tests for the multi-agent dashboard ViewModel.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent Dashboard ViewModel Tests

/// Tests for `AgentDashboardViewModel` covering:
///
/// **Model tests:**
/// - AgentSessionInfo creation with all fields
/// - AgentDashboardState urgency ordering
/// - AgentPriority comparison
/// - SubagentInfo model
/// - Sessions sorted correctly by priority then state
///
/// **ViewModel tests:**
/// - Initial state: empty sessions
/// - Hook SessionStart creates new session
/// - Hook PostToolUse updates lastActivity
/// - Hook Stop sets state to finished
/// - Hook PostToolUseFailure sets state to error
/// - Hook SubagentStart adds subagent
/// - Hook SessionEnd removes session
/// - Multiple sessions sorted by priority then state
/// - setPriority reorders sessions
/// - mostUrgentSession returns error > waiting > working
/// - sessions(withState:) filters correctly
/// - toggleVisibility toggles isVisible
/// - activitySummary returns truncated last activity
/// - Non-hook agent signal creates session with pattern-based data
/// - Combine publisher emits on every change
@MainActor
final class AgentDashboardViewModelTests: XCTestCase {

    private var sut: AgentDashboardViewModel!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = AgentDashboardViewModel()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Model Tests: AgentSessionInfo

    func testAgentSessionInfoCreationWithAllFields() {
        let tabId = UUID()
        let now = Date()
        let subagent = SubagentInfo(id: "sub-1", type: "research", state: .working, startTime: now)

        let session = AgentSessionInfo(
            id: "session-1",
            projectName: "my-project",
            gitBranch: "main",
            agentName: "Claude Code",
            state: .working,
            lastActivity: "Write: App.swift",
            lastActivityTime: now,
            tabId: tabId,
            subagents: [subagent],
            priority: .focus,
            model: "claude-sonnet-4"
        )

        XCTAssertEqual(session.id, "session-1")
        XCTAssertEqual(session.projectName, "my-project")
        XCTAssertEqual(session.gitBranch, "main")
        XCTAssertEqual(session.agentName, "Claude Code")
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.lastActivity, "Write: App.swift")
        XCTAssertEqual(session.lastActivityTime, now)
        XCTAssertEqual(session.tabId, tabId)
        XCTAssertEqual(session.subagents.count, 1)
        XCTAssertEqual(session.priority, .focus)
        XCTAssertEqual(session.model, "claude-sonnet-4")
    }

    // MARK: - Model Tests: AgentDashboardState Ordering

    func testAgentDashboardStateUrgencyOrdering() {
        // error is the most urgent, finished is the least urgent
        XCTAssertTrue(AgentDashboardState.error < .blocked)
        XCTAssertTrue(AgentDashboardState.blocked < .waitingForInput)
        XCTAssertTrue(AgentDashboardState.waitingForInput < .working)
        XCTAssertTrue(AgentDashboardState.working < .launching)
        XCTAssertTrue(AgentDashboardState.launching < .idle)
        XCTAssertTrue(AgentDashboardState.idle < .finished)
    }

    // MARK: - Model Tests: AgentPriority Comparison

    func testAgentPriorityComparison() {
        XCTAssertTrue(AgentPriority.focus < .priority)
        XCTAssertTrue(AgentPriority.priority < .standard)
        XCTAssertTrue(AgentPriority.focus < .standard)
        XCTAssertFalse(AgentPriority.standard < .focus)
    }

    // MARK: - Model Tests: SubagentInfo

    func testSubagentInfoCreation() {
        let now = Date()
        let subagent = SubagentInfo(id: "sub-42", type: "code-review", state: .working, startTime: now)

        XCTAssertEqual(subagent.id, "sub-42")
        XCTAssertEqual(subagent.type, "code-review")
        XCTAssertEqual(subagent.state, .working)
        XCTAssertEqual(subagent.startTime, now)
        XCTAssertNil(subagent.endTime)
        XCTAssertTrue(subagent.isActive)
        XCTAssertEqual(subagent.toolUseCount, 0)
        XCTAssertEqual(subagent.errorCount, 0)
    }

    func testSubagentInfoWithNilType() {
        let subagent = SubagentInfo(id: "sub-nil", type: nil, state: .idle, startTime: Date())

        XCTAssertEqual(subagent.id, "sub-nil")
        XCTAssertNil(subagent.type)
        XCTAssertEqual(subagent.state, .idle)
        XCTAssertFalse(subagent.isActive)
    }

    // MARK: - Model Tests: Sessions Sorted Correctly

    func testSessionsSortedByPriorityThenState() {
        // Create sessions with different priorities and states
        let sessionFocusWorking = AgentSessionInfo(
            id: "s1", projectName: "p1", gitBranch: nil, agentName: nil,
            state: .working, lastActivity: nil, lastActivityTime: nil,
            tabId: UUID(), subagents: [], priority: .focus, model: nil
        )
        let sessionStandardError = AgentSessionInfo(
            id: "s2", projectName: "p2", gitBranch: nil, agentName: nil,
            state: .error, lastActivity: nil, lastActivityTime: nil,
            tabId: UUID(), subagents: [], priority: .standard, model: nil
        )
        let sessionFocusError = AgentSessionInfo(
            id: "s3", projectName: "p3", gitBranch: nil, agentName: nil,
            state: .error, lastActivity: nil, lastActivityTime: nil,
            tabId: UUID(), subagents: [], priority: .focus, model: nil
        )

        var sessions = [sessionFocusWorking, sessionStandardError, sessionFocusError]
        sessions.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.state < rhs.state
        }

        // Focus sessions first, then standard
        // Within focus: error before working
        XCTAssertEqual(sessions[0].id, "s3") // focus + error
        XCTAssertEqual(sessions[1].id, "s1") // focus + working
        XCTAssertEqual(sessions[2].id, "s2") // standard + error
    }

    // MARK: - ViewModel Tests: Initial State

    func testInitialStateHasEmptySessions() {
        XCTAssertTrue(sut.sessions.isEmpty)
        XCTAssertFalse(sut.isVisible)
    }

    // MARK: - ViewModel Tests: Hook SessionStart

    func testSessionStartCreatesNewSession() {
        let event = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-1",
            data: .sessionStart(SessionStartData(
                model: "claude-sonnet-4",
                agentType: "claude-code",
                workingDirectory: "/Users/test/my-project"
            ))
        )

        sut.processHookEvent(event)

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, "sess-1")
        XCTAssertEqual(sut.sessions.first?.agentName, "claude-code")
        XCTAssertEqual(sut.sessions.first?.model, "claude-sonnet-4")
        XCTAssertEqual(sut.sessions.first?.projectName, "my-project")
        XCTAssertEqual(sut.sessions.first?.state, .launching)
    }

    func testSessionStartResolvesWindowMetadataFromProviders() {
        let fixedTabID = UUID()
        let fixedWindowID = WindowID()
        sut.tabIdForCwdProvider = { cwd in
            cwd == "/Users/test/my-project" ? fixedTabID : nil
        }
        sut.windowIDForTabProvider = { tabID in
            tabID == fixedTabID ? fixedWindowID : nil
        }
        sut.windowLabelProvider = { windowID in
            windowID == fixedWindowID ? "Window 2" : nil
        }

        let event = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-windowed",
            data: .sessionStart(SessionStartData(
                model: "claude-sonnet-4",
                agentType: "claude-code",
                workingDirectory: "/Users/test/my-project"
            ))
        )

        sut.processHookEvent(event)

        XCTAssertEqual(sut.sessions.first?.tabId, fixedTabID)
        XCTAssertEqual(sut.sessions.first?.windowID, fixedWindowID)
        XCTAssertEqual(sut.sessions.first?.windowLabel, "Window 2")
    }

    func testSessionStartPrefersSessionResolverOverCwdResolver() {
        let boundTabID = UUID()
        let cwdResolvedTabID = UUID()

        sut.tabIdResolver = { sessionID, cwd in
            sessionID == "sess-bound" && cwd == "/Users/test/shared-project"
                ? boundTabID
                : nil
        }
        sut.tabIdForCwdProvider = { _ in cwdResolvedTabID }

        let event = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-bound",
            data: .sessionStart(SessionStartData(
                workingDirectory: "/Users/test/shared-project"
            ))
        )

        sut.processHookEvent(event)

        XCTAssertEqual(sut.sessions.first?.tabId, boundTabID)
    }

    func testWindowMetadataRefreshesWhenSessionMovesWindows() {
        let fixedTabID = UUID()
        let firstWindowID = WindowID()
        let secondWindowID = WindowID()
        sut.tabIdForCwdProvider = { _ in fixedTabID }
        sut.windowIDForTabProvider = { _ in firstWindowID }
        sut.windowLabelProvider = { windowID in
            switch windowID {
            case firstWindowID:
                return "Window 1"
            case secondWindowID:
                return "Window 2"
            default:
                return nil
            }
        }

        let event = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-move",
            data: .sessionStart(SessionStartData(
                workingDirectory: "/Users/test/multi-window"
            ))
        )
        sut.processHookEvent(event)
        XCTAssertEqual(sut.sessions.first?.windowLabel, "Window 1")

        sut.windowIDForTabProvider = { _ in secondWindowID }
        sut.setPriority(.focus, for: "sess-move")

        XCTAssertEqual(sut.sessions.first?.windowID, secondWindowID)
        XCTAssertEqual(sut.sessions.first?.windowLabel, "Window 2")
    }

    // MARK: - ViewModel Tests: Hook PostToolUse

    func testPostToolUseUpdatesLastActivity() {
        // First create a session
        let startEvent = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-tool",
            data: .sessionStart(SessionStartData(agentType: "claude-code"))
        )
        sut.processHookEvent(startEvent)

        // Then send a tool use event
        let toolEvent = makeHookEvent(
            type: .postToolUse,
            sessionId: "sess-tool",
            data: .toolUse(ToolUseData(
                toolName: "Write",
                toolInput: ["file_path": "/Users/test/Sources/App.swift"]
            ))
        )
        sut.processHookEvent(toolEvent)

        XCTAssertEqual(sut.sessions.first?.state, .working)
        XCTAssertEqual(sut.sessions.first?.lastActivity, "Write: App.swift")
    }

    // MARK: - ViewModel Tests: Hook Stop

    func testStopEventSetsStateToFinished() {
        // Create session
        let startEvent = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-stop",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        // Stop it
        let stopEvent = makeHookEvent(
            type: .stop,
            sessionId: "sess-stop",
            data: .stop(StopData(lastMessage: "Task completed successfully", reason: "end_turn"))
        )
        sut.processHookEvent(stopEvent)

        XCTAssertEqual(sut.sessions.first?.state, .finished)
        XCTAssertEqual(sut.sessions.first?.lastActivity, "Task completed successfully")
    }

    // MARK: - ViewModel Tests: Hook PostToolUseFailure

    func testPostToolUseFailureSetsStateToError() {
        // Create session
        let startEvent = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-err",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        // Fail a tool use
        let failEvent = makeHookEvent(
            type: .postToolUseFailure,
            sessionId: "sess-err",
            data: .toolUse(ToolUseData(
                toolName: "Bash",
                error: "Permission denied"
            ))
        )
        sut.processHookEvent(failEvent)

        XCTAssertEqual(sut.sessions.first?.state, .error)
        XCTAssertEqual(sut.sessions.first?.lastActivity, "Error: Permission denied")
    }

    // MARK: - ViewModel Tests: Hook SubagentStart

    func testSubagentStartAddsSubagentToSession() {
        // Create session
        let startEvent = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-sub",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        // Start a subagent
        let subagentEvent = makeHookEvent(
            type: .subagentStart,
            sessionId: "sess-sub",
            data: .subagent(SubagentData(subagentId: "sub-1", subagentType: "research"))
        )
        sut.processHookEvent(subagentEvent)

        XCTAssertEqual(sut.sessions.first?.subagents.count, 1)
        XCTAssertEqual(sut.sessions.first?.subagents.first?.id, "sub-1")
        XCTAssertEqual(sut.sessions.first?.subagents.first?.type, "research")
        XCTAssertEqual(sut.sessions.first?.subagents.first?.state, .working)
    }

    func testSubagentStartAutoCreatesSessionWhenParentStartArrivesLate() {
        let resolvedTabId = UUID()
        sut.tabIdResolver = { sessionId, cwd in
            XCTAssertEqual(sessionId, "sess-sub-late")
            XCTAssertEqual(cwd, "/tmp/demo")
            return resolvedTabId
        }

        let subagentEvent = HookEvent(
            type: .subagentStart,
            sessionId: "sess-sub-late",
            timestamp: Date(),
            data: .subagent(SubagentData(subagentId: "sub-early", subagentType: "research")),
            cwd: "/tmp/demo"
        )
        sut.processHookEvent(subagentEvent)

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.id, "sess-sub-late")
        XCTAssertEqual(sut.sessions.first?.tabId, resolvedTabId)
        XCTAssertEqual(sut.sessions.first?.subagents.count, 1)
        XCTAssertEqual(sut.sessions.first?.subagents.first?.id, "sub-early")
        XCTAssertEqual(sut.sessions.first?.subagents.first?.type, "research")
        XCTAssertEqual(sut.sessions.first?.state, .working)
    }

    func testRepeatedSubagentStartDoesNotDuplicateTrackedSubagent() {
        let startEvent = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-sub-dup",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        let subagentEvent = makeHookEvent(
            type: .subagentStart,
            sessionId: "sess-sub-dup",
            data: .subagent(SubagentData(subagentId: "sub-1", subagentType: "research"))
        )
        sut.processHookEvent(subagentEvent)
        sut.processHookEvent(subagentEvent)

        XCTAssertEqual(sut.sessions.first?.subagents.count, 1)
        XCTAssertEqual(sut.sessions.first?.subagents.first?.id, "sub-1")
        XCTAssertEqual(sut.sessions.first?.subagents.first?.state, .working)
    }

    // MARK: - ViewModel Tests: Hook SessionEnd

    func testSessionEndRemovesSession() {
        // Create session
        let startEvent = makeHookEvent(
            type: .sessionStart,
            sessionId: "sess-remove",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)
        XCTAssertEqual(sut.sessions.count, 1)

        // End session
        let endEvent = makeHookEvent(
            type: .sessionEnd,
            sessionId: "sess-remove",
            data: .generic
        )
        sut.processHookEvent(endEvent)

        XCTAssertTrue(sut.sessions.isEmpty)
    }

    // MARK: - ViewModel Tests: Multiple Sessions Sorted

    func testMultipleSessionsSortedByPriorityThenState() {
        // Create three sessions with different states
        let start1 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-a",
            data: .sessionStart(SessionStartData())
        )
        let start2 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-b",
            data: .sessionStart(SessionStartData())
        )
        let start3 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-c",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(start1)
        sut.processHookEvent(start2)
        sut.processHookEvent(start3)

        // Make sess-b error, sess-c working, sess-a stays launching
        let failEvent = makeHookEvent(
            type: .postToolUseFailure, sessionId: "sess-b",
            data: .toolUse(ToolUseData(toolName: "Bash", error: "fail"))
        )
        let toolEvent = makeHookEvent(
            type: .postToolUse, sessionId: "sess-c",
            data: .toolUse(ToolUseData(toolName: "Read"))
        )
        sut.processHookEvent(failEvent)
        sut.processHookEvent(toolEvent)

        // Expected order: error (sess-b) > working (sess-c) > launching (sess-a)
        XCTAssertEqual(sut.sessions.count, 3)
        XCTAssertEqual(sut.sessions[0].id, "sess-b") // error
        XCTAssertEqual(sut.sessions[1].id, "sess-c") // working
        XCTAssertEqual(sut.sessions[2].id, "sess-a") // launching
    }

    // MARK: - ViewModel Tests: setPriority

    func testSetPriorityReordersSessions() {
        // Create two sessions
        let start1 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-pri-1",
            data: .sessionStart(SessionStartData())
        )
        let start2 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-pri-2",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(start1)
        sut.processHookEvent(start2)

        // Both are standard priority and launching state -- order depends on time
        // Set sess-pri-2 to focus priority
        sut.setPriority(.focus, for: "sess-pri-2")

        // sess-pri-2 should now be first
        XCTAssertEqual(sut.sessions.first?.id, "sess-pri-2")
        XCTAssertEqual(sut.sessions.first?.priority, .focus)
    }

    // MARK: - ViewModel Tests: mostUrgentSession

    func testMostUrgentSessionReturnsErrorOverWaitingOverWorking() {
        // Create sessions with different states
        let start1 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-working",
            data: .sessionStart(SessionStartData())
        )
        let start2 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-error",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(start1)
        sut.processHookEvent(start2)

        // Make one working, one error
        let toolEvent = makeHookEvent(
            type: .postToolUse, sessionId: "sess-working",
            data: .toolUse(ToolUseData(toolName: "Read"))
        )
        let failEvent = makeHookEvent(
            type: .postToolUseFailure, sessionId: "sess-error",
            data: .toolUse(ToolUseData(toolName: "Write", error: "error"))
        )
        sut.processHookEvent(toolEvent)
        sut.processHookEvent(failEvent)

        // Most urgent should be the error session
        let urgent = sut.mostUrgentSession()
        XCTAssertNotNil(urgent)
        XCTAssertEqual(urgent?.id, "sess-error")
        XCTAssertEqual(urgent?.state, .error)
    }

    func testMostUrgentSessionReturnsNilWhenEmpty() {
        XCTAssertNil(sut.mostUrgentSession())
    }

    // MARK: - ViewModel Tests: sessions(withState:)

    func testSessionsWithStateFiltersCorrectly() {
        // Create sessions with different final states
        let start1 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-f1",
            data: .sessionStart(SessionStartData())
        )
        let start2 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-f2",
            data: .sessionStart(SessionStartData())
        )
        let start3 = makeHookEvent(
            type: .sessionStart, sessionId: "sess-f3",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(start1)
        sut.processHookEvent(start2)
        sut.processHookEvent(start3)

        // Make sess-f1 finished, sess-f2 working, sess-f3 stays launching
        let stopEvent = makeHookEvent(
            type: .stop, sessionId: "sess-f1",
            data: .stop(StopData(reason: "end_turn"))
        )
        let toolEvent = makeHookEvent(
            type: .postToolUse, sessionId: "sess-f2",
            data: .toolUse(ToolUseData(toolName: "Read"))
        )
        sut.processHookEvent(stopEvent)
        sut.processHookEvent(toolEvent)

        let finishedSessions = sut.sessions(withState: .finished)
        XCTAssertEqual(finishedSessions.count, 1)
        XCTAssertEqual(finishedSessions.first?.id, "sess-f1")

        let workingSessions = sut.sessions(withState: .working)
        XCTAssertEqual(workingSessions.count, 1)
        XCTAssertEqual(workingSessions.first?.id, "sess-f2")

        let launchingSessions = sut.sessions(withState: .launching)
        XCTAssertEqual(launchingSessions.count, 1)
        XCTAssertEqual(launchingSessions.first?.id, "sess-f3")

        let idleSessions = sut.sessions(withState: .idle)
        XCTAssertTrue(idleSessions.isEmpty)
    }

    // MARK: - ViewModel Tests: toggleVisibility

    func testToggleVisibilityTogglesIsVisible() {
        XCTAssertFalse(sut.isVisible)

        sut.toggleVisibility()
        XCTAssertTrue(sut.isVisible)

        sut.toggleVisibility()
        XCTAssertFalse(sut.isVisible)
    }

    // MARK: - ViewModel Tests: activitySummary

    func testActivitySummaryReturnsTruncatedLastActivity() {
        // Create session and give it activity
        let startEvent = makeHookEvent(
            type: .sessionStart, sessionId: "sess-summary",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        let toolEvent = makeHookEvent(
            type: .postToolUse, sessionId: "sess-summary",
            data: .toolUse(ToolUseData(
                toolName: "Write",
                toolInput: ["file_path": "/Users/test/Sources/VeryLongFileName.swift"]
            ))
        )
        sut.processHookEvent(toolEvent)

        let summary = sut.activitySummary(for: "sess-summary")
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary!.contains("Write"))
    }

    func testActivitySummaryReturnsNilForUnknownSession() {
        let summary = sut.activitySummary(for: "nonexistent")
        XCTAssertNil(summary)
    }

    // MARK: - ViewModel Tests: Non-hook Agent Signal

    func testNonHookAgentSignalCreatesSessionWithPatternBasedData() {
        let tabId = UUID()

        sut.processDetectionSignal(
            agentName: "Codex",
            state: .working,
            tabId: tabId
        )

        XCTAssertEqual(sut.sessions.count, 1)
        XCTAssertEqual(sut.sessions.first?.agentName, "Codex")
        XCTAssertEqual(sut.sessions.first?.state, .working)
        XCTAssertEqual(sut.sessions.first?.id, "pattern-\(tabId.uuidString)")
    }

    // MARK: - ViewModel Tests: Combine Publisher

    func testCombinePublisherEmitsOnEveryChange() {
        var emittedValues: [[AgentSessionInfo]] = []

        sut.sessionsPublisher
            .dropFirst() // skip the initial empty value from CurrentValueSubject
            .sink { sessions in
                emittedValues.append(sessions)
            }
            .store(in: &cancellables)

        // Create a session
        let startEvent = makeHookEvent(
            type: .sessionStart, sessionId: "sess-pub",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        // Update it with a tool use
        let toolEvent = makeHookEvent(
            type: .postToolUse, sessionId: "sess-pub",
            data: .toolUse(ToolUseData(toolName: "Read"))
        )
        sut.processHookEvent(toolEvent)

        // Remove it
        let endEvent = makeHookEvent(
            type: .sessionEnd, sessionId: "sess-pub",
            data: .generic
        )
        sut.processHookEvent(endEvent)

        // Should have 3 emissions: add, update, remove
        XCTAssertEqual(emittedValues.count, 3)
        XCTAssertEqual(emittedValues[0].count, 1)  // session added
        XCTAssertEqual(emittedValues[1].count, 1)  // session updated
        XCTAssertEqual(emittedValues[2].count, 0)  // session removed
    }

    // MARK: - ViewModel Tests: TeammateIdle

    func testTeammateIdleSetsStateToIdle() {
        let startEvent = makeHookEvent(
            type: .sessionStart, sessionId: "sess-idle",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        let idleEvent = makeHookEvent(
            type: .teammateIdle, sessionId: "sess-idle",
            data: .teammateIdle(TeammateIdleData(teammateId: "tm-1", reason: "waiting_for_review"))
        )
        sut.processHookEvent(idleEvent)

        XCTAssertEqual(sut.sessions.first?.state, .idle)
    }

    // MARK: - ViewModel Tests: TaskCompleted

    func testTaskCompletedSetsStateToFinished() {
        let startEvent = makeHookEvent(
            type: .sessionStart, sessionId: "sess-task",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        let taskEvent = makeHookEvent(
            type: .taskCompleted, sessionId: "sess-task",
            data: .taskCompleted(TaskCompletedData(taskDescription: "Implemented feature X"))
        )
        sut.processHookEvent(taskEvent)

        XCTAssertEqual(sut.sessions.first?.state, .finished)
        XCTAssertEqual(sut.sessions.first?.lastActivity, "Implemented feature X")
    }

    // MARK: - ViewModel Tests: SubagentStop

    func testSubagentStopMarksFinishedInsteadOfRemoving() {
        // Create session with a subagent
        let startEvent = makeHookEvent(
            type: .sessionStart, sessionId: "sess-sub-stop",
            data: .sessionStart(SessionStartData())
        )
        sut.processHookEvent(startEvent)

        let subStart = makeHookEvent(
            type: .subagentStart, sessionId: "sess-sub-stop",
            data: .subagent(SubagentData(subagentId: "sub-remove", subagentType: "research"))
        )
        sut.processHookEvent(subStart)
        XCTAssertEqual(sut.sessions.first?.subagents.count, 1)
        XCTAssertEqual(sut.sessions.first?.subagents.first?.state, .working)

        // Stop the subagent — should mark finished, not remove
        let subStop = makeHookEvent(
            type: .subagentStop, sessionId: "sess-sub-stop",
            data: .subagent(SubagentData(subagentId: "sub-remove"))
        )
        sut.processHookEvent(subStop)
        XCTAssertEqual(sut.sessions.first?.subagents.count, 1)
        XCTAssertEqual(sut.sessions.first?.subagents.first?.state, .finished)
        XCTAssertNotNil(sut.sessions.first?.subagents.first?.endTime)
    }

    // MARK: - Helpers

    private func makeHookEvent(
        type: HookEventType,
        sessionId: String,
        data: HookEventData,
        timestamp: Date = Date()
    ) -> HookEvent {
        HookEvent(
            type: type,
            sessionId: sessionId,
            timestamp: timestamp,
            data: data
        )
    }
}
