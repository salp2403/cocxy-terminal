// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateAggregatorTests.swift - Tests for AgentStateAggregatorImpl.

import Testing
import Foundation
import Combine
@testable import CocxyTerminal

// MARK: - Agent State Aggregator Tests

@Suite("Agent State Aggregator")
@MainActor
struct AgentStateAggregatorTests {

    // MARK: - Helpers

    private let windowA = WindowID()
    private let windowB = WindowID()

    private func makeRegistry() -> SessionRegistryImpl {
        let registry = SessionRegistryImpl()
        registry.registerWindow(windowA)
        registry.registerWindow(windowB)
        return registry
    }

    private func makeEntry(
        windowID: WindowID,
        agentState: AgentState = .idle,
        agentName: String? = nil
    ) -> SessionEntry {
        SessionEntry(
            ownerWindowID: windowID,
            tabID: TabID(),
            agentState: agentState,
            detectedAgentName: agentName
        )
    }

    // MARK: - Active Agent Sessions

    @Test("Active agent sessions excludes idle sessions")
    func activeExcludesIdle() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, agentState: .idle))
        registry.registerSession(makeEntry(windowID: windowA, agentState: .working))
        registry.registerSession(makeEntry(windowID: windowB, agentState: .finished))

        let aggregator = AgentStateAggregatorImpl(registry: registry)

        #expect(aggregator.activeAgentSessions.count == 2)
    }

    @Test("Active agent sessions is empty when all idle")
    func activeEmptyWhenAllIdle() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA))
        registry.registerSession(makeEntry(windowID: windowB))

        let aggregator = AgentStateAggregatorImpl(registry: registry)

        #expect(aggregator.activeAgentSessions.isEmpty)
    }

    @Test("Active sessions span multiple windows")
    func activeSpansWindows() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, agentState: .working))
        registry.registerSession(makeEntry(windowID: windowB, agentState: .waitingInput))

        let aggregator = AgentStateAggregatorImpl(registry: registry)
        let active = aggregator.activeAgentSessions

        #expect(active.count == 2)
        let windows = Set(active.map(\.ownerWindowID))
        #expect(windows.contains(windowA))
        #expect(windows.contains(windowB))
    }

    // MARK: - Filter by State

    @Test("Filter by agent state returns matching sessions")
    func filterByState() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, agentState: .working))
        registry.registerSession(makeEntry(windowID: windowA, agentState: .working))
        registry.registerSession(makeEntry(windowID: windowB, agentState: .error))

        let aggregator = AgentStateAggregatorImpl(registry: registry)

        #expect(aggregator.sessions(withAgentState: .working).count == 2)
        #expect(aggregator.sessions(withAgentState: .error).count == 1)
        #expect(aggregator.sessions(withAgentState: .idle).isEmpty)
    }

    // MARK: - Publisher

    @Test("Publisher fires on agent state change")
    func publisherFiresOnChange() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA, agentState: .idle)
        registry.registerSession(entry)

        let aggregator = AgentStateAggregatorImpl(registry: registry)
        var receivedEvent: AgentStateEvent?

        let cancellable = aggregator.agentStateChanged.sink { receivedEvent = $0 }

        registry.updateAgentState(entry.sessionID, state: .working, agentName: "Claude Code")

        #expect(receivedEvent != nil)
        #expect(receivedEvent?.sessionID == entry.sessionID)
        #expect(receivedEvent?.windowID == windowA)
        #expect(receivedEvent?.previousState == .idle)
        #expect(receivedEvent?.newState == .working)
        #expect(receivedEvent?.agentName == "Claude Code")
        _ = cancellable
    }

    @Test("Publisher does not fire for non-agent-state changes")
    func publisherSilentForOtherChanges() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)

        let aggregator = AgentStateAggregatorImpl(registry: registry)
        var eventFired = false

        let cancellable = aggregator.agentStateChanged.sink { _ in eventFired = true }

        // Title change should NOT trigger agentStateChanged.
        registry.updateTitle(entry.sessionID, title: "New Title")

        #expect(!eventFired)
        _ = cancellable
    }

    @Test("Publisher fires correct sequence for state transitions")
    func publisherSequence() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA, agentState: .idle)
        registry.registerSession(entry)

        let aggregator = AgentStateAggregatorImpl(registry: registry)
        var events: [AgentStateEvent] = []

        let cancellable = aggregator.agentStateChanged.sink { events.append($0) }

        registry.updateAgentState(entry.sessionID, state: .working, agentName: "Claude")
        registry.updateAgentState(entry.sessionID, state: .waitingInput, agentName: "Claude")
        registry.updateAgentState(entry.sessionID, state: .finished, agentName: "Claude")

        #expect(events.count == 3)
        #expect(events[0].previousState == .idle)
        #expect(events[0].newState == .working)
        #expect(events[1].previousState == .working)
        #expect(events[1].newState == .waitingInput)
        #expect(events[2].previousState == .waitingInput)
        #expect(events[2].newState == .finished)
        _ = cancellable
    }

    // MARK: - Edge Cases

    @Test("Empty registry returns empty active sessions")
    func emptyRegistryEmpty() {
        let registry = makeRegistry()
        let aggregator = AgentStateAggregatorImpl(registry: registry)

        #expect(aggregator.activeAgentSessions.isEmpty)
    }

    @Test("Removed session disappears from active list")
    func removedSessionDisappears() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA, agentState: .working)
        registry.registerSession(entry)

        let aggregator = AgentStateAggregatorImpl(registry: registry)
        #expect(aggregator.activeAgentSessions.count == 1)

        registry.removeSession(entry.sessionID)

        #expect(aggregator.activeAgentSessions.isEmpty)
    }
}
