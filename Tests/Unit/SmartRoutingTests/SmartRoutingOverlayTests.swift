// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartRoutingOverlayTests.swift - Tests for the SmartRoutingOverlay (T-076).
//
// Test plan (7 tests):
// 1. Overlay ViewModel shows correct number of agents.
// 2. Keyboard selection (1-9) selects correct agent.
// 3. Filter by errors -> only errors shown.
// 4. Filter by waiting -> only waiting shown.
// 5. Empty agents -> shows "No agents need attention" message.
// 6. Filter by all -> all agents shown (resets filter).
// 7. Selected index is clamped to valid range.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Smart Routing Overlay Tests

@MainActor
final class SmartRoutingOverlayTests: XCTestCase {

    private var mockRouter: MockOverlaySmartRouter!
    private var sut: SmartRoutingOverlayViewModel!

    override func setUp() {
        super.setUp()
        mockRouter = MockOverlaySmartRouter()
        sut = SmartRoutingOverlayViewModel(router: mockRouter)
    }

    override func tearDown() {
        sut = nil
        mockRouter = nil
        super.tearDown()
    }

    // MARK: - Test 1: Shows correct number of agents

    func testOverlayShowsCorrectNumberOfAgents() {
        mockRouter.stubbedNeedingAttention = [
            makeSession(id: "s1", state: .error),
            makeSession(id: "s2", state: .blocked),
            makeSession(id: "s3", state: .waitingForInput)
        ]

        sut.refresh()

        XCTAssertEqual(sut.displayedAgents.count, 3,
                       "Overlay must show all agents needing attention")
    }

    // MARK: - Test 2: Keyboard selection selects correct agent

    func testKeyboardSelectionSelectsCorrectAgent() {
        mockRouter.stubbedNeedingAttention = [
            makeSession(id: "s1", state: .error),
            makeSession(id: "s2", state: .blocked),
            makeSession(id: "s3", state: .waitingForInput)
        ]
        sut.refresh()

        // Select agent at position 2 (0-indexed: 1).
        sut.selectAgentByNumber(2)

        XCTAssertEqual(mockRouter.lastNavigatedSessionId, "s2",
                       "Selecting number 2 must navigate to the second agent")
    }

    // MARK: - Test 3: Filter by errors -> only errors shown

    func testFilterByErrorsShowsOnlyErrors() {
        mockRouter.stubbedNeedingAttention = [
            makeSession(id: "s1", state: .error),
            makeSession(id: "s2", state: .blocked),
            makeSession(id: "s3", state: .waitingForInput)
        ]
        mockRouter.stubbedFilteredByState[.error] = [
            makeSession(id: "s1", state: .error)
        ]
        sut.refresh()

        sut.applyFilter(.errorsOnly)

        XCTAssertEqual(sut.displayedAgents.count, 1)
        XCTAssertEqual(sut.displayedAgents.first?.state, .error)
    }

    // MARK: - Test 4: Filter by waiting -> only waiting shown

    func testFilterByWaitingShowsOnlyWaiting() {
        mockRouter.stubbedNeedingAttention = [
            makeSession(id: "s1", state: .error),
            makeSession(id: "s2", state: .waitingForInput),
            makeSession(id: "s3", state: .waitingForInput)
        ]
        mockRouter.stubbedFilteredByState[.waitingForInput] = [
            makeSession(id: "s2", state: .waitingForInput),
            makeSession(id: "s3", state: .waitingForInput)
        ]
        sut.refresh()

        sut.applyFilter(.waitingOnly)

        XCTAssertEqual(sut.displayedAgents.count, 2)
        XCTAssertTrue(sut.displayedAgents.allSatisfy { $0.state == .waitingForInput })
    }

    // MARK: - Test 5: Empty agents -> message

    func testEmptyAgentsShowsNoAgentsMessage() {
        mockRouter.stubbedNeedingAttention = []

        sut.refresh()

        XCTAssertTrue(sut.displayedAgents.isEmpty)
        XCTAssertEqual(sut.emptyMessage, "No agents need attention")
    }

    // MARK: - Test 6: Filter all -> resets filter

    func testFilterAllResetsAndShowsAllAgents() {
        mockRouter.stubbedNeedingAttention = [
            makeSession(id: "s1", state: .error),
            makeSession(id: "s2", state: .waitingForInput)
        ]
        mockRouter.stubbedFilteredByState[.error] = [
            makeSession(id: "s1", state: .error)
        ]
        sut.refresh()

        // Apply error filter first.
        sut.applyFilter(.errorsOnly)
        XCTAssertEqual(sut.displayedAgents.count, 1)

        // Reset to all.
        sut.applyFilter(.all)
        XCTAssertEqual(sut.displayedAgents.count, 2,
                       "Filter .all must show all agents needing attention")
    }

    // MARK: - Test 7: Selection index clamped to valid range

    func testSelectionIndexClampedToValidRange() {
        mockRouter.stubbedNeedingAttention = [
            makeSession(id: "s1", state: .error)
        ]
        sut.refresh()

        // Select number 5 when only 1 agent exists -- should be a no-op.
        sut.selectAgentByNumber(5)

        XCTAssertNil(mockRouter.lastNavigatedSessionId,
                     "Selecting an out-of-range number must not navigate anywhere")
    }

    // MARK: - Helpers

    private func makeSession(
        id: String,
        state: AgentDashboardState,
        projectName: String = "test-project"
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: projectName,
            gitBranch: nil,
            agentName: "Claude Code",
            state: state,
            lastActivity: nil,
            lastActivityTime: nil,
            tabId: UUID(),
            subagents: [],
            priority: .standard,
            model: nil
        )
    }
}

// MARK: - Mock Smart Router

@MainActor
private final class MockOverlaySmartRouter: SmartAgentRouting {
    var stubbedNeedingAttention: [AgentSessionInfo] = []
    var stubbedFilteredByState: [AgentDashboardState: [AgentSessionInfo]] = [:]
    var lastNavigatedSessionId: String?

    func agentsNeedingAttention() -> [AgentSessionInfo] {
        stubbedNeedingAttention
    }

    func agents(withState state: AgentDashboardState) -> [AgentSessionInfo] {
        stubbedFilteredByState[state] ?? []
    }

    func mostUrgentAgent() -> AgentSessionInfo? {
        stubbedNeedingAttention.first
    }

    func navigateToAgent(_ sessionId: String) {
        lastNavigatedSessionId = sessionId
    }
}
