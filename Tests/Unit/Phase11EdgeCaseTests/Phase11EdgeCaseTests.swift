// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase11EdgeCaseTests.swift - Smart Agent Router edge cases for Phase 11 (T-079).
//
// Edge cases covered (6 tests in CocxyTerminalTests target):
// EC-01  Zero agents -> agentsNeedingAttention returns empty, no crash.
// EC-02  All agents working/idle/finished/launching -> none need attention.
// EC-03  20 agents with mixed states -> correct ordering and count.
// EC-04  navigateToAgent with non-existent session ID -> no crash, no navigation.
// EC-05  Idle and finished states excluded from needing-attention list.
// EC-06  Same-state agents sorted by oldest activity time first.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Phase 11: Smart Agent Router Edge Cases

@MainActor
final class Phase11SmartRouterEdgeCaseTests: XCTestCase {

    private var mockDashboard: MockPhase11Dashboard!
    private var mockNavigator: MockPhase11Navigator!
    private var sut: SmartAgentRouterImpl!

    override func setUp() {
        super.setUp()
        mockDashboard = MockPhase11Dashboard()
        mockNavigator = MockPhase11Navigator()
        sut = SmartAgentRouterImpl(
            dashboard: mockDashboard,
            tabNavigator: mockNavigator
        )
    }

    override func tearDown() {
        sut = nil
        mockNavigator = nil
        mockDashboard = nil
        super.tearDown()
    }

    // MARK: - EC-01: Zero agents -> empty list, no crash

    func testEC01_ZeroAgentsReturnsEmptyListWithoutCrash() {
        // Given
        mockDashboard.stubbedSessions = []

        // When / Then (must not crash)
        let attention = sut.agentsNeedingAttention()
        let urgent = sut.mostUrgentAgent()

        XCTAssertTrue(attention.isEmpty,
                      "EC-01: agentsNeedingAttention must return empty when there are no agents")
        XCTAssertNil(urgent,
                     "EC-01: mostUrgentAgent must return nil when there are no agents")
    }

    // MARK: - EC-02: All agents working/idle/finished/launching -> none need attention

    func testEC02_NonAttentionStatesNeverNeedAttention() {
        // Given: all four non-attention states represented
        mockDashboard.stubbedSessions = [
            makeSession(id: "w1", state: .working),
            makeSession(id: "w2", state: .working),
            makeSession(id: "i1", state: .idle),
            makeSession(id: "f1", state: .finished),
            makeSession(id: "l1", state: .launching)
        ]

        // When
        let attention = sut.agentsNeedingAttention()

        // Then
        XCTAssertTrue(attention.isEmpty,
                      "EC-02: working/idle/finished/launching agents must not appear in attention list")
    }

    // MARK: - EC-03: 20 agents with mixed states -> correct ordering and count

    func testEC03_TwentyMixedAgentsCorrectOrderAndCount() {
        // Given: 20 sessions total, 11 needing attention
        var sessions: [AgentSessionInfo] = []

        // 5 x error (highest urgency -- should appear first)
        for i in 1...5 {
            sessions.append(makeSession(
                id: "err-\(i)",
                state: .error,
                lastActivityTime: Date(timeIntervalSince1970: Double(i * 100))
            ))
        }
        // 3 x blocked (medium urgency)
        for i in 1...3 {
            sessions.append(makeSession(
                id: "blk-\(i)",
                state: .blocked,
                lastActivityTime: Date(timeIntervalSince1970: Double(i * 200))
            ))
        }
        // 6 x working (should NOT appear in attention list)
        for i in 1...6 {
            sessions.append(makeSession(id: "work-\(i)", state: .working))
        }
        // 3 x waitingForInput (lowest urgency -- should appear last)
        for i in 1...3 {
            sessions.append(makeSession(
                id: "wait-\(i)",
                state: .waitingForInput,
                lastActivityTime: Date(timeIntervalSince1970: Double(i * 300))
            ))
        }
        // 3 x non-attention states
        sessions.append(makeSession(id: "idle-1", state: .idle))
        sessions.append(makeSession(id: "fin-1", state: .finished))
        sessions.append(makeSession(id: "launch-1", state: .launching))

        mockDashboard.stubbedSessions = sessions

        // When
        let attention = sut.agentsNeedingAttention()

        // Then: exactly 11 needing attention
        XCTAssertEqual(attention.count, 11,
                       "EC-03: must identify exactly 11 sessions needing attention from 20 mixed agents")

        let errorSessions  = attention.filter { $0.state == .error }
        let blockedSessions = attention.filter { $0.state == .blocked }
        let waitingSessions = attention.filter { $0.state == .waitingForInput }

        XCTAssertEqual(errorSessions.count, 5,  "EC-03: must find 5 error sessions")
        XCTAssertEqual(blockedSessions.count, 3, "EC-03: must find 3 blocked sessions")
        XCTAssertEqual(waitingSessions.count, 3, "EC-03: must find 3 waiting sessions")

        // Verify ordering: first 5 are errors
        let firstFive = Array(attention.prefix(5)).map { $0.state }
        XCTAssertTrue(firstFive.allSatisfy { $0 == .error },
                      "EC-03: first 5 results must all be .error")

        // Next 3 are blocked
        let nextThree = Array(attention.dropFirst(5).prefix(3)).map { $0.state }
        XCTAssertTrue(nextThree.allSatisfy { $0 == .blocked },
                      "EC-03: positions 6-8 must all be .blocked")
    }

    // MARK: - EC-04: Navigate to non-existent session -> no crash, no navigation

    func testEC04_NavigateToNonExistentSessionNoCrash() {
        // Given: one real session exists
        mockDashboard.stubbedSessions = [
            makeSession(id: "real-session", state: .error)
        ]

        // When: navigate to a session ID that does not exist
        sut.navigateToAgent("session-that-does-not-exist-12345")

        // Then: navigator must NOT be called
        XCTAssertEqual(mockNavigator.focusCallCount, 0,
                       "EC-04: navigating to a non-existent session must not call the tab navigator")
    }

    // MARK: - EC-05: Idle, finished, launching never need attention

    func testEC05_IdleFinishedLaunchingNeverNeedAttention() {
        // Given
        mockDashboard.stubbedSessions = [
            makeSession(id: "idle", state: .idle),
            makeSession(id: "finished", state: .finished),
            makeSession(id: "launching", state: .launching)
        ]

        // When
        let attention = sut.agentsNeedingAttention()
        let urgent = sut.mostUrgentAgent()

        // Then
        XCTAssertTrue(attention.isEmpty,
                      "EC-05: idle/finished/launching must never appear in needing-attention list")
        XCTAssertNil(urgent,
                     "EC-05: mostUrgentAgent must be nil when no urgent agents exist")
    }

    // MARK: - EC-06: Same-state agents sorted oldest activity time first

    func testEC06_SameStateAgentsSortedByOldestActivityTimeFirst() {
        // Given: 3 error agents with distinct activity times
        let old     = Date(timeIntervalSince1970: 1_000)
        let mid     = Date(timeIntervalSince1970: 2_000)
        let newest  = Date(timeIntervalSince1970: 3_000)

        // Intentionally in reverse order to verify sorting
        mockDashboard.stubbedSessions = [
            makeSession(id: "newest", state: .error, lastActivityTime: newest),
            makeSession(id: "oldest", state: .error, lastActivityTime: old),
            makeSession(id: "middle", state: .error, lastActivityTime: mid)
        ]

        // When
        let attention = sut.agentsNeedingAttention()

        // Then: oldest first
        XCTAssertEqual(attention.count, 3, "EC-06: all 3 error agents must appear")
        XCTAssertEqual(attention[0].id, "oldest",
                       "EC-06: agent with oldest activity time must be first")
        XCTAssertEqual(attention[1].id, "middle",
                       "EC-06: agent with middle activity time must be second")
        XCTAssertEqual(attention[2].id, "newest",
                       "EC-06: agent with newest activity time must be last")
    }

    // MARK: - Helpers

    private func makeSession(
        id: String,
        state: AgentDashboardState,
        tabId: UUID = UUID(),
        lastActivityTime: Date? = nil
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: "test-project",
            gitBranch: nil,
            agentName: "Claude Code",
            state: state,
            lastActivity: nil,
            lastActivityTime: lastActivityTime,
            tabId: tabId,
            subagents: [],
            priority: .standard,
            model: nil
        )
    }
}

// MARK: - Mocks

@MainActor
private final class MockPhase11Dashboard: AgentDashboardProviding {
    var stubbedSessions: [AgentSessionInfo] = []

    var sessions: [AgentSessionInfo] { stubbedSessions }

    var sessionsPublisher: AnyPublisher<[AgentSessionInfo], Never> {
        Just(stubbedSessions).eraseToAnyPublisher()
    }

    var isVisible: Bool = false

    func toggleVisibility() { isVisible.toggle() }

    func setPriority(_ priority: AgentPriority, for sessionId: String) {}

    func mostUrgentSession() -> AgentSessionInfo? { stubbedSessions.first }

    func sessions(withState state: AgentDashboardState) -> [AgentSessionInfo] {
        stubbedSessions.filter { $0.state == state }
    }

    func activitySummary(for sessionId: String) -> String? {
        stubbedSessions.first(where: { $0.id == sessionId })?.lastActivity
    }
}

@MainActor
private final class MockPhase11Navigator: DashboardTabNavigating {
    private(set) var focusCallCount = 0

    func focusTab(id: TabID) -> Bool {
        focusCallCount += 1
        return true
    }
}
