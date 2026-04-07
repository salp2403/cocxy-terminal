// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartAgentRouterTests.swift - Tests for the SmartAgentRouter (T-075).
//
// Test plan (12 tests):
// 1.  No agents -> agentsNeedingAttention returns empty list.
// 2.  Only working agents -> not in needing attention list.
// 3.  Error agent -> appears in needing attention list.
// 4.  Blocked agent -> appears in needing attention list.
// 5.  Waiting agent -> appears in needing attention list.
// 6.  Multiple agents: error sorts before waiting.
// 7.  Multiple agents: blocked sorts before waiting.
// 8.  Most urgent -> returns highest priority agent.
// 9.  Most urgent with no urgent agents -> returns nil.
// 10. Filter by state -> returns correct subset.
// 11. Filter by state with no matches -> returns empty.
// 12. Navigate calls tab navigator with correct tab ID.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - SmartAgentRouter Tests

@MainActor
final class SmartAgentRouterTests: XCTestCase {

    private var mockDashboard: MockSmartRoutingDashboard!
    private var navigator: MockSmartRoutingNavigator!
    private var sut: SmartAgentRouterImpl!

    override func setUp() {
        super.setUp()
        mockDashboard = MockSmartRoutingDashboard()
        navigator = MockSmartRoutingNavigator()
        sut = SmartAgentRouterImpl(
            dashboard: mockDashboard,
            tabNavigator: navigator
        )
    }

    override func tearDown() {
        sut = nil
        navigator = nil
        mockDashboard = nil
        super.tearDown()
    }

    // MARK: - Test 1: No agents -> empty list

    func testAgentsNeedingAttentionReturnsEmptyWhenNoAgents() {
        mockDashboard.stubbedSessions = []

        let result = sut.agentsNeedingAttention()

        XCTAssertTrue(result.isEmpty,
                      "agentsNeedingAttention must return empty list when no agents exist")
    }

    // MARK: - Test 2: Only working agents -> not needing attention

    func testOnlyWorkingAgentsNotInNeedingAttentionList() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-w1", state: .working),
            makeSession(id: "sess-w2", state: .working)
        ]

        let result = sut.agentsNeedingAttention()

        XCTAssertTrue(result.isEmpty,
                      "Working agents should not appear in needing attention list")
    }

    // MARK: - Test 3: Error agent -> in needing attention list

    func testErrorAgentAppearsInNeedingAttentionList() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-err", state: .error)
        ]

        let result = sut.agentsNeedingAttention()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "sess-err")
        XCTAssertEqual(result.first?.state, .error)
    }

    // MARK: - Test 4: Blocked agent -> in needing attention list

    func testBlockedAgentAppearsInNeedingAttentionList() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-blk", state: .blocked)
        ]

        let result = sut.agentsNeedingAttention()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "sess-blk")
        XCTAssertEqual(result.first?.state, .blocked)
    }

    // MARK: - Test 5: Waiting agent -> in needing attention list

    func testWaitingAgentAppearsInNeedingAttentionList() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-wait", state: .waitingForInput)
        ]

        let result = sut.agentsNeedingAttention()

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "sess-wait")
        XCTAssertEqual(result.first?.state, .waitingForInput)
    }

    // MARK: - Test 6: Multiple agents: error sorts before waiting

    func testMultipleAgentsErrorSortsBeforeWaiting() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-wait", state: .waitingForInput),
            makeSession(id: "sess-err", state: .error)
        ]

        let result = sut.agentsNeedingAttention()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "sess-err",
                       "Error agent must appear before waiting agent")
        XCTAssertEqual(result[1].id, "sess-wait")
    }

    // MARK: - Test 7: Multiple agents: blocked sorts before waiting

    func testMultipleAgentsBlockedSortsBeforeWaiting() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-wait", state: .waitingForInput),
            makeSession(id: "sess-blk", state: .blocked)
        ]

        let result = sut.agentsNeedingAttention()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "sess-blk",
                       "Blocked agent must appear before waiting agent")
        XCTAssertEqual(result[1].id, "sess-wait")
    }

    // MARK: - Test 8: Most urgent -> returns highest priority

    func testMostUrgentAgentReturnsHighestPriority() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-work", state: .working),
            makeSession(id: "sess-err", state: .error),
            makeSession(id: "sess-wait", state: .waitingForInput)
        ]

        let urgent = sut.mostUrgentAgent()

        XCTAssertNotNil(urgent)
        XCTAssertEqual(urgent?.id, "sess-err",
                       "Most urgent agent should be the one with error state")
    }

    // MARK: - Test 9: Most urgent with no urgent agents -> nil

    func testMostUrgentAgentReturnsNilWhenNoUrgentAgents() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-work", state: .working),
            makeSession(id: "sess-idle", state: .idle)
        ]

        let urgent = sut.mostUrgentAgent()

        XCTAssertNil(urgent,
                     "mostUrgentAgent should return nil when no agents need attention")
    }

    // MARK: - Test 10: Filter by state -> correct subset

    func testAgentsFilteredByStateReturnsCorrectSubset() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-err-1", state: .error),
            makeSession(id: "sess-err-2", state: .error),
            makeSession(id: "sess-work", state: .working),
            makeSession(id: "sess-wait", state: .waitingForInput)
        ]

        let errorAgents = sut.agents(withState: .error)

        XCTAssertEqual(errorAgents.count, 2)
        let errorIds = Set(errorAgents.map { $0.id })
        XCTAssertTrue(errorIds.contains("sess-err-1"))
        XCTAssertTrue(errorIds.contains("sess-err-2"))
    }

    // MARK: - Test 11: Filter by state with no matches -> empty

    func testAgentsFilteredByStateWithNoMatchesReturnsEmpty() {
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-work", state: .working)
        ]

        let blockedAgents = sut.agents(withState: .blocked)

        XCTAssertTrue(blockedAgents.isEmpty,
                      "Filter by blocked should return empty when no blocked agents exist")
    }

    // MARK: - Test 12: Navigate calls tab navigator

    func testNavigateToAgentCallsTabNavigatorWithCorrectTabId() {
        let tabId = UUID()
        mockDashboard.stubbedSessions = [
            makeSession(id: "sess-nav", state: .error, tabId: tabId)
        ]

        sut.navigateToAgent("sess-nav")

        XCTAssertEqual(navigator.focusTabCallCount, 1,
                       "navigateToAgent must call focusTab exactly once")
        XCTAssertEqual(navigator.focusedTabIds.first, TabID(rawValue: tabId),
                       "navigateToAgent must pass the correct tab ID to the navigator")
    }

    // MARK: - Helpers

    private func makeSession(
        id: String,
        state: AgentDashboardState,
        tabId: UUID = UUID(),
        projectName: String = "test-project",
        lastActivity: String? = nil,
        lastActivityTime: Date? = nil
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: projectName,
            gitBranch: nil,
            agentName: "Claude Code",
            state: state,
            lastActivity: lastActivity,
            lastActivityTime: lastActivityTime,
            tabId: tabId,
            subagents: [],
            priority: .standard,
            model: nil
        )
    }
}

// MARK: - Mock Dashboard

@MainActor
final class MockSmartRoutingDashboard: AgentDashboardProviding {
    var stubbedSessions: [AgentSessionInfo] = []

    var sessions: [AgentSessionInfo] { stubbedSessions }

    var sessionsPublisher: AnyPublisher<[AgentSessionInfo], Never> {
        Just(stubbedSessions).eraseToAnyPublisher()
    }

    var isVisible: Bool = false

    func toggleVisibility() {
        isVisible.toggle()
    }

    func setPriority(_ priority: AgentPriority, for sessionId: String) {
        // No-op for tests.
    }

    func mostUrgentSession() -> AgentSessionInfo? {
        stubbedSessions.first
    }

    func sessions(withState state: AgentDashboardState) -> [AgentSessionInfo] {
        stubbedSessions.filter { $0.state == state }
    }

    func activitySummary(for sessionId: String) -> String? {
        stubbedSessions.first(where: { $0.id == sessionId })?.lastActivity
    }
}

// MARK: - Mock Tab Navigator

@MainActor
private final class MockSmartRoutingNavigator: DashboardTabNavigating {
    private(set) var focusedTabIds: [TabID] = []
    var focusTabCallCount: Int { focusedTabIds.count }

    func focusTab(id: TabID) -> Bool {
        focusedTabIds.append(id)
        return true
    }
}
