// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDetectionWiringTests.swift - Tests for agent detection -> tab state wiring.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Agent Detection Wiring Tests

/// Tests that agent detection engine state changes propagate to tab items in the sidebar.
///
/// These tests verify the wiring layer between:
/// - `AgentDetectionEngineImpl.stateChanged` (publisher)
/// - `TabManager.updateTab` (consumer)
/// - `TabBarViewModel.syncWithManager` (UI refresh)
///
/// The wiring is implemented in `AppDelegate.wireAgentDetectionToTabs()`.
@MainActor
final class AgentDetectionWiringTests: XCTestCase {

    // MARK: - State Machine to Tab AgentState mapping

    func testIdleStateMapsToIdleAgentState() {
        let result = AgentStateMachine.State.idle.toTabAgentState
        XCTAssertEqual(result, .idle, "idle debe mapear a AgentState.idle")
    }

    func testAgentLaunchedStateMapsToLaunchedAgentState() {
        let result = AgentStateMachine.State.agentLaunched.toTabAgentState
        XCTAssertEqual(result, .launched, "agentLaunched debe mapear a AgentState.launched")
    }

    func testWorkingStateMapsToWorkingAgentState() {
        let result = AgentStateMachine.State.working.toTabAgentState
        XCTAssertEqual(result, .working, "working debe mapear a AgentState.working")
    }

    func testWaitingInputStateMapsToWaitingInputAgentState() {
        let result = AgentStateMachine.State.waitingInput.toTabAgentState
        XCTAssertEqual(result, .waitingInput, "waitingInput debe mapear a AgentState.waitingInput")
    }

    func testFinishedStateMapsToFinishedAgentState() {
        let result = AgentStateMachine.State.finished.toTabAgentState
        XCTAssertEqual(result, .finished, "finished debe mapear a AgentState.finished")
    }

    func testErrorStateMapsToErrorAgentState() {
        let result = AgentStateMachine.State.error.toTabAgentState
        XCTAssertEqual(result, .error, "error debe mapear a AgentState.error")
    }

    // MARK: - Engine state change updates tab via TabManager (synchronous @MainActor sink)

    func testEngineStateChangeUpdatesActiveTab() {
        let tabManager = TabManager()
        let engine = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )

        // Wire engine to tab manager using synchronous sink (both are @MainActor).
        // No receive(on:) needed -- stateChanged emits on main actor.
        var cancellables = Set<AnyCancellable>()
        engine.stateChanged
            .sink { context in
                guard let activeID = tabManager.activeTabID else { return }
                let agentState = context.state.toTabAgentState
                tabManager.updateTab(id: activeID) { tab in
                    tab.agentState = agentState
                }
            }
            .store(in: &cancellables)

        // Inject an agentDetected signal to move from idle -> agentLaunched
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .hook(event: "test")
        ))

        // The active tab should now reflect the launched state.
        let activeTab = tabManager.activeTab
        XCTAssertEqual(
            activeTab?.agentState, .launched,
            "El tab activo debe reflejar el estado launched del engine"
        )

        cancellables.removeAll()
    }

    func testEngineStateChangeUpdatesTabBarViewModel() {
        let tabManager = TabManager()
        let tabBarVM = TabBarViewModel(tabManager: tabManager)
        let engine = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )

        // Wire engine to tab manager + tabBarViewModel sync (synchronous, same actor)
        var cancellables = Set<AnyCancellable>()
        engine.stateChanged
            .sink { context in
                guard let activeID = tabManager.activeTabID else { return }
                let agentState = context.state.toTabAgentState
                tabManager.updateTab(id: activeID) { tab in
                    tab.agentState = agentState
                }
                tabBarVM.syncWithManager()
            }
            .store(in: &cancellables)

        // Inject agentDetected -> working signals
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

        // TabBarViewModel should reflect the working state
        let displayItem = tabBarVM.tabItems.first
        XCTAssertEqual(
            displayItem?.agentState, .working,
            "El display item del tab bar debe reflejar el estado working"
        )

        cancellables.removeAll()
    }

    func testMultipleStateTransitionsReflectedInTab() {
        let tabManager = TabManager()
        let engine = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )

        var cancellables = Set<AnyCancellable>()
        engine.stateChanged
            .sink { context in
                guard let activeID = tabManager.activeTabID else { return }
                tabManager.updateTab(id: activeID) { tab in
                    tab.agentState = context.state.toTabAgentState
                }
            }
            .store(in: &cancellables)

        // Full lifecycle: idle -> launched -> working -> waitingInput -> working -> finished
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "claude"),
            confidence: 1.0,
            source: .hook(event: "test")
        ))
        XCTAssertEqual(tabManager.activeTab?.agentState, .launched)

        engine.injectSignal(DetectionSignal(
            event: .outputReceived,
            confidence: 1.0,
            source: .hook(event: "test")
        ))
        XCTAssertEqual(tabManager.activeTab?.agentState, .working)

        engine.injectSignal(DetectionSignal(
            event: .promptDetected,
            confidence: 1.0,
            source: .hook(event: "test")
        ))
        XCTAssertEqual(tabManager.activeTab?.agentState, .waitingInput)

        engine.injectSignal(DetectionSignal(
            event: .userInput,
            confidence: 1.0,
            source: .hook(event: "test")
        ))
        XCTAssertEqual(tabManager.activeTab?.agentState, .working)

        engine.injectSignal(DetectionSignal(
            event: .completionDetected,
            confidence: 1.0,
            source: .hook(event: "test")
        ))
        XCTAssertEqual(tabManager.activeTab?.agentState, .finished)

        cancellables.removeAll()
    }

    // MARK: - Dashboard receives engine state changes

    func testDashboardViewModelReceivesDetectionEngineSignals() {
        let engine = AgentDetectionEngineImpl(
            compiledConfigs: [],
            debounceInterval: 0.0
        )
        let dashboardVM = AgentDashboardViewModel(
            hookEventReceiver: nil,
            detectionEngine: engine
        )

        // Inject an agentDetected signal with a name
        engine.injectSignal(DetectionSignal(
            event: .agentDetected(name: "test-agent"),
            confidence: 1.0,
            source: .pattern(name: "test")
        ))

        // Give Combine a tick for the receive(on:) in dashboard subscription
        let expectation = expectation(description: "Dashboard picks up detection signal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let hasSessions = !dashboardVM.sessions.isEmpty
            if hasSessions {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Timeline store receives hook events via direct wiring

    func testTimelineStoreReceivesEventsFromHookReceiver() {
        let hookReceiver = HookEventReceiverImpl()
        let timelineStore = AgentTimelineStoreImpl()
        var cancellables = Set<AnyCancellable>()

        // Wire hook events to timeline store (same pattern as AppDelegate).
        hookReceiver.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { hookEvent in
                let timelineEvent = TimelineEvent.from(hookEvent: hookEvent)
                timelineStore.addEvent(timelineEvent)
            }
            .store(in: &cancellables)

        let json = """
        {
            "type": "SessionStart",
            "sessionId": "timeline-wiring-test",
            "timestamp": "\(ISO8601DateFormatter().string(from: Date()))",
            "data": {
                "sessionStart": {
                    "model": "claude-sonnet-4",
                    "agentType": "Claude Code",
                    "workingDirectory": "/tmp/test"
                }
            }
        }
        """.data(using: .utf8)!

        hookReceiver.receiveRawJSON(json)

        let expectation = expectation(description: "Timeline store receives event")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let events = timelineStore.events(for: "timeline-wiring-test")
            if !events.isEmpty {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
