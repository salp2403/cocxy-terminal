// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRegistryTests.swift - Tests for SessionRegistryImpl.

import Testing
import Foundation
import Combine
@testable import CocxyTerminal

// MARK: - Session Registry Tests

/// Comprehensive tests for the central session registry.
///
/// Tests cover:
/// - Session registration and removal.
/// - Window-scoped queries.
/// - Title, directory, agent state, and notification updates.
/// - Transfer lifecycle (prepare, complete, cancel).
/// - Concurrent transfer rejection.
/// - Cascade deletion on window removal.
/// - Publisher verification for all events.
/// - Edge cases (duplicate registration, unknown IDs, self-transfer).
@Suite("Session Registry")
@MainActor
struct SessionRegistryTests {

    // MARK: - Helpers

    private let windowA = WindowID()
    private let windowB = WindowID()

    private func makeRegistry() -> SessionRegistryImpl {
        SessionRegistryImpl()
    }

    private func makeEntry(
        sessionID: SessionID = SessionID(),
        windowID: WindowID? = nil,
        tabID: TabID = TabID(),
        title: String = "Terminal",
        directory: String = "/Users/dev/project",
        agentState: AgentState = .idle
    ) -> SessionEntry {
        SessionEntry(
            sessionID: sessionID,
            ownerWindowID: windowID ?? windowA,
            tabID: tabID,
            title: title,
            workingDirectory: URL(fileURLWithPath: directory),
            agentState: agentState
        )
    }

    // MARK: - Registration

    @Test("Register session stores entry and increments count")
    func registerSession() {
        let registry = makeRegistry()
        let entry = makeEntry()

        registry.registerSession(entry)

        #expect(registry.sessionCount == 1)
        #expect(registry.session(for: entry.sessionID) != nil)
    }

    @Test("Register session publishes sessionAdded event")
    func registerSessionPublishesEvent() async {
        let registry = makeRegistry()
        let entry = makeEntry()
        var received: SessionEntry?

        let cancellable = registry.sessionAdded.sink { received = $0 }
        registry.registerSession(entry)

        #expect(received?.sessionID == entry.sessionID)
        _ = cancellable
    }

    @Test("Duplicate registration is silently ignored")
    func duplicateRegistration() {
        let registry = makeRegistry()
        let sessionID = SessionID()
        let entry1 = makeEntry(sessionID: sessionID, title: "First")
        let entry2 = makeEntry(sessionID: sessionID, title: "Second")

        registry.registerSession(entry1)
        registry.registerSession(entry2)

        #expect(registry.sessionCount == 1)
        #expect(registry.session(for: sessionID)?.title == "First")
    }

    @Test("Register multiple sessions from different windows")
    func registerMultipleSessions() {
        let registry = makeRegistry()
        registry.registerWindow(windowA)
        registry.registerWindow(windowB)

        let entryA = makeEntry(windowID: windowA)
        let entryB = makeEntry(windowID: windowB)

        registry.registerSession(entryA)
        registry.registerSession(entryB)

        #expect(registry.sessionCount == 2)
        #expect(registry.sessions(in: windowA).count == 1)
        #expect(registry.sessions(in: windowB).count == 1)
    }

    // MARK: - Removal

    @Test("Remove session decrements count and publishes event")
    func removeSession() {
        let registry = makeRegistry()
        let entry = makeEntry()
        var removedEvent: SessionRemovalEvent?

        registry.registerSession(entry)
        let cancellable = registry.sessionRemoved.sink { removedEvent = $0 }
        registry.removeSession(entry.sessionID)

        #expect(registry.sessionCount == 0)
        #expect(registry.session(for: entry.sessionID) == nil)
        #expect(removedEvent?.sessionID == entry.sessionID)
        #expect(removedEvent?.windowID == entry.ownerWindowID)
        _ = cancellable
    }

    @Test("Remove non-existent session is a no-op")
    func removeNonExistentSession() {
        let registry = makeRegistry()
        var eventFired = false

        let cancellable = registry.sessionRemoved.sink { _ in eventFired = true }
        registry.removeSession(SessionID())

        #expect(!eventFired)
        _ = cancellable
    }

    // MARK: - Window Queries

    @Test("Sessions filtered by window ID")
    func sessionsFilteredByWindow() {
        let registry = makeRegistry()
        let e1 = makeEntry(windowID: windowA, title: "Tab 1")
        let e2 = makeEntry(windowID: windowA, title: "Tab 2")
        let e3 = makeEntry(windowID: windowB, title: "Tab 3")

        registry.registerSession(e1)
        registry.registerSession(e2)
        registry.registerSession(e3)

        let windowASessions = registry.sessions(in: windowA)
        let windowBSessions = registry.sessions(in: windowB)

        #expect(windowASessions.count == 2)
        #expect(windowBSessions.count == 1)
        #expect(windowBSessions.first?.title == "Tab 3")
    }

    @Test("Sessions for unknown window returns empty array")
    func sessionsForUnknownWindow() {
        let registry = makeRegistry()
        let unknownWindow = WindowID()

        #expect(registry.sessions(in: unknownWindow).isEmpty)
    }

    @Test("allSessions returns every registered session")
    func allSessionsReturnsAll() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA))
        registry.registerSession(makeEntry(windowID: windowB))

        #expect(registry.allSessions.count == 2)
    }

    // MARK: - Title Updates

    @Test("Update title changes entry and publishes event")
    func updateTitle() {
        let registry = makeRegistry()
        let entry = makeEntry(title: "Old")
        registry.registerSession(entry)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }
        registry.updateTitle(entry.sessionID, title: "New")

        #expect(registry.session(for: entry.sessionID)?.title == "New")
        if case .titleChanged(let old, let new) = change?.change {
            #expect(old == "Old")
            #expect(new == "New")
        } else {
            Issue.record("Expected titleChanged event")
        }
        _ = cancellable
    }

    @Test("Update title with same value is a no-op")
    func updateTitleSameValue() {
        let registry = makeRegistry()
        let entry = makeEntry(title: "Same")
        registry.registerSession(entry)
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.updateTitle(entry.sessionID, title: "Same")

        #expect(!eventFired)
        _ = cancellable
    }

    @Test("Update title for unknown session is a no-op")
    func updateTitleUnknownSession() {
        let registry = makeRegistry()
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.updateTitle(SessionID(), title: "Anything")

        #expect(!eventFired)
        _ = cancellable
    }

    // MARK: - Working Directory Updates

    @Test("Update working directory changes entry and publishes event")
    func updateWorkingDirectory() {
        let registry = makeRegistry()
        let entry = makeEntry(directory: "/old")
        registry.registerSession(entry)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }
        let newDir = URL(fileURLWithPath: "/new")
        registry.updateWorkingDirectory(entry.sessionID, directory: newDir)

        #expect(registry.session(for: entry.sessionID)?.workingDirectory == newDir)
        if case .workingDirectoryChanged(let old, let new) = change?.change {
            #expect(old.path.hasSuffix("/old"))
            #expect(new == newDir)
        } else {
            Issue.record("Expected workingDirectoryChanged event")
        }
        _ = cancellable
    }

    @Test("Update working directory with same value is a no-op")
    func updateWorkingDirectorySameValue() {
        let registry = makeRegistry()
        let dir = URL(fileURLWithPath: "/same")
        let entry = SessionEntry(
            ownerWindowID: windowA,
            tabID: TabID(),
            workingDirectory: dir
        )
        registry.registerSession(entry)
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.updateWorkingDirectory(entry.sessionID, directory: dir)

        #expect(!eventFired)
        _ = cancellable
    }

    // MARK: - Agent State Updates

    @Test("Update agent state changes entry and publishes event")
    func updateAgentState() {
        let registry = makeRegistry()
        let entry = makeEntry(agentState: .idle)
        registry.registerSession(entry)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }
        registry.updateAgentState(entry.sessionID, state: .working, agentName: "Claude Code")

        let updated = registry.session(for: entry.sessionID)
        #expect(updated?.agentState == .working)
        #expect(updated?.detectedAgentName == "Claude Code")
        if case .agentStateChanged(let old, let new) = change?.change {
            #expect(old == .idle)
            #expect(new == .working)
        } else {
            Issue.record("Expected agentStateChanged event")
        }
        _ = cancellable
    }

    @Test("Update agent state with same values is a no-op")
    func updateAgentStateSameValues() {
        let registry = makeRegistry()
        let entry = makeEntry(agentState: .working)
        var modified = entry
        modified.detectedAgentName = "Claude"
        // We need to register with the agent name already set.
        let entryWithAgent = SessionEntry(
            sessionID: entry.sessionID,
            ownerWindowID: windowA,
            tabID: entry.tabID,
            agentState: .working,
            detectedAgentName: "Claude"
        )
        registry.registerSession(entryWithAgent)
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.updateAgentState(entry.sessionID, state: .working, agentName: "Claude")

        #expect(!eventFired)
        _ = cancellable
    }

    // MARK: - Notification State

    @Test("Mark unread sets flag and publishes event")
    func markUnread() {
        let registry = makeRegistry()
        let entry = makeEntry()
        registry.registerSession(entry)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }
        registry.markUnread(entry.sessionID)

        #expect(registry.session(for: entry.sessionID)?.hasUnreadNotification == true)
        if case .notificationStateChanged(let hasUnread) = change?.change {
            #expect(hasUnread == true)
        } else {
            Issue.record("Expected notificationStateChanged event")
        }
        _ = cancellable
    }

    @Test("Mark unread on already-unread session is a no-op")
    func markUnreadAlreadyUnread() {
        let registry = makeRegistry()
        let entry = SessionEntry(
            ownerWindowID: windowA,
            tabID: TabID(),
            hasUnreadNotification: true
        )
        registry.registerSession(entry)
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.markUnread(entry.sessionID)

        #expect(!eventFired)
        _ = cancellable
    }

    @Test("Mark read clears flag and publishes event")
    func markRead() {
        let registry = makeRegistry()
        let entry = SessionEntry(
            ownerWindowID: windowA,
            tabID: TabID(),
            hasUnreadNotification: true
        )
        registry.registerSession(entry)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }
        registry.markRead(entry.sessionID)

        #expect(registry.session(for: entry.sessionID)?.hasUnreadNotification == false)
        if case .notificationStateChanged(let hasUnread) = change?.change {
            #expect(hasUnread == false)
        } else {
            Issue.record("Expected notificationStateChanged event")
        }
        _ = cancellable
    }

    @Test("Mark read on already-read session is a no-op")
    func markReadAlreadyRead() {
        let registry = makeRegistry()
        let entry = makeEntry()
        registry.registerSession(entry)
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.markRead(entry.sessionID)

        #expect(!eventFired)
        _ = cancellable
    }

    // MARK: - Transfer Lifecycle

    @Test("Prepare transfer marks session as inTransfer")
    func prepareTransfer() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }

        let result = registry.prepareTransfer(entry.sessionID, from: windowA, to: windowB)

        #expect(result == true)
        let updated = registry.session(for: entry.sessionID)
        #expect(updated?.transferState == .inTransfer(from: windowA, to: windowB))
        if case .transferStateChanged(let old, let new) = change?.change {
            #expect(old == .stable)
            #expect(new == .inTransfer(from: windowA, to: windowB))
        } else {
            Issue.record("Expected transferStateChanged event")
        }
        _ = cancellable
    }

    @Test("Complete transfer updates owner and resets state")
    func completeTransfer() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        registry.prepareTransfer(entry.sessionID, from: windowA, to: windowB)
        var change: SessionChangeEvent?
        let newTabID = TabID()

        let cancellable = registry.sessionUpdated.sink { change = $0 }
        registry.completeTransfer(entry.sessionID, newTabID: newTabID)

        let updated = registry.session(for: entry.sessionID)
        #expect(updated?.ownerWindowID == windowB)
        #expect(updated?.tabID == newTabID)
        #expect(updated?.transferState == .stable)
        if case .ownerChanged(let oldWindow, let newWindow) = change?.change {
            #expect(oldWindow == windowA)
            #expect(newWindow == windowB)
        } else {
            Issue.record("Expected ownerChanged event")
        }
        _ = cancellable
    }

    @Test("Cancel transfer resets state without changing owner")
    func cancelTransfer() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        registry.prepareTransfer(entry.sessionID, from: windowA, to: windowB)
        var change: SessionChangeEvent?

        let cancellable = registry.sessionUpdated.sink { change = $0 }

        registry.cancelTransfer(entry.sessionID)

        let updated = registry.session(for: entry.sessionID)
        #expect(updated?.ownerWindowID == windowA)
        #expect(updated?.transferState == .stable)
        if case .transferStateChanged(let old, let new) = change?.change {
            #expect(old == .inTransfer(from: windowA, to: windowB))
            #expect(new == .stable)
        } else {
            Issue.record("Expected transferStateChanged event")
        }
        _ = cancellable
    }

    @Test("Concurrent transfer is rejected")
    func concurrentTransferRejected() {
        let registry = makeRegistry()
        let windowC = WindowID()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        registry.prepareTransfer(entry.sessionID, from: windowA, to: windowB)

        let secondResult = registry.prepareTransfer(entry.sessionID, from: windowA, to: windowC)

        #expect(secondResult == false)
        // Original transfer is still active.
        let updated = registry.session(for: entry.sessionID)
        #expect(updated?.transferState == .inTransfer(from: windowA, to: windowB))
    }

    @Test("Transfer from wrong source window is rejected")
    func transferFromWrongSource() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)

        let result = registry.prepareTransfer(entry.sessionID, from: windowB, to: windowA)

        #expect(result == false)
    }

    @Test("Self-transfer (same source and destination) is rejected")
    func selfTransferRejected() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)

        let result = registry.prepareTransfer(entry.sessionID, from: windowA, to: windowA)

        #expect(result == false)
    }

    @Test("Transfer for non-existent session returns false")
    func transferNonExistentSession() {
        let registry = makeRegistry()

        let result = registry.prepareTransfer(SessionID(), from: windowA, to: windowB)

        #expect(result == false)
    }

    @Test("Complete transfer without prepare is a no-op")
    func completeWithoutPrepare() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        var eventFired = false

        let cancellable = registry.sessionUpdated.sink { _ in eventFired = true }
        registry.completeTransfer(entry.sessionID, newTabID: TabID())

        #expect(!eventFired)
        #expect(registry.session(for: entry.sessionID)?.ownerWindowID == windowA)
        _ = cancellable
    }

    @Test("Cancel transfer without prepare is a no-op")
    func cancelWithoutPrepare() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)

        // Should not crash or change anything.
        registry.cancelTransfer(entry.sessionID)

        #expect(registry.session(for: entry.sessionID)?.transferState == .stable)
    }

    // MARK: - Window Management

    @Test("Register window adds to window set")
    func registerWindow() {
        let registry = makeRegistry()

        registry.registerWindow(windowA)
        registry.registerWindow(windowB)

        #expect(registry.windowIDs.contains(windowA))
        #expect(registry.windowIDs.contains(windowB))
        #expect(registry.windowCount == 2)
    }

    @Test("Remove window cascades session removal")
    func removeWindowCascadesSessions() {
        let registry = makeRegistry()
        registry.registerWindow(windowA)
        registry.registerWindow(windowB)

        let e1 = makeEntry(windowID: windowA, title: "Tab A1")
        let e2 = makeEntry(windowID: windowA, title: "Tab A2")
        let e3 = makeEntry(windowID: windowB, title: "Tab B1")
        registry.registerSession(e1)
        registry.registerSession(e2)
        registry.registerSession(e3)

        var removedEvents: [SessionRemovalEvent] = []
        let cancellable = registry.sessionRemoved.sink { removedEvents.append($0) }

        registry.removeWindow(windowA)

        #expect(registry.windowCount == 1)
        #expect(!registry.windowIDs.contains(windowA))
        #expect(registry.sessionCount == 1)
        #expect(registry.session(for: e3.sessionID) != nil)
        #expect(removedEvents.count == 2)
        #expect(removedEvents.map(\.sessionID).contains(e1.sessionID))
        #expect(removedEvents.map(\.sessionID).contains(e2.sessionID))
        #expect(removedEvents.allSatisfy { $0.windowID == windowA })
        _ = cancellable
    }

    @Test("Remove window cancels transfers targeting the removed destination")
    func removeWindowCancelsTransfersToRemovedDestination() {
        let registry = makeRegistry()
        registry.registerWindow(windowA)
        registry.registerWindow(windowB)
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        #expect(registry.prepareTransfer(entry.sessionID, from: windowA, to: windowB))

        var changes: [SessionChangeEvent] = []
        let cancellable = registry.sessionUpdated.sink { changes.append($0) }

        registry.removeWindow(windowB)

        let updated = registry.session(for: entry.sessionID)
        #expect(updated?.ownerWindowID == windowA)
        #expect(updated?.transferState == .stable)
        #expect(changes.contains(where: { change in
            guard case .transferStateChanged(let old, let new) = change.change else { return false }
            return old == .inTransfer(from: windowA, to: windowB) && new == .stable
        }))
        _ = cancellable
    }

    @Test("Remove non-existent window is a no-op")
    func removeNonExistentWindow() {
        let registry = makeRegistry()
        var eventFired = false

        let cancellable = registry.sessionRemoved.sink { _ in eventFired = true }
        registry.removeWindow(WindowID())

        #expect(!eventFired)
        _ = cancellable
    }

    @Test("Remove window with no sessions does not emit removal events")
    func removeEmptyWindow() {
        let registry = makeRegistry()
        registry.registerWindow(windowA)
        var eventFired = false

        let cancellable = registry.sessionRemoved.sink { _ in eventFired = true }
        registry.removeWindow(windowA)

        #expect(!eventFired)
        #expect(registry.windowCount == 0)
        _ = cancellable
    }

    // MARK: - Edge Cases

    @Test("Session entry preserves creation timestamp")
    func sessionPreservesTimestamp() {
        let registry = makeRegistry()
        let now = Date()
        let entry = SessionEntry(
            createdAt: now,
            ownerWindowID: windowA,
            tabID: TabID()
        )
        registry.registerSession(entry)

        #expect(registry.session(for: entry.sessionID)?.createdAt == now)
    }

    @Test("Multiple updates publish correct sequence of events")
    func multipleUpdatesSequence() {
        let registry = makeRegistry()
        let entry = makeEntry(title: "Start", agentState: .idle)
        registry.registerSession(entry)
        var events: [SessionChangeEvent] = []

        let cancellable = registry.sessionUpdated.sink { events.append($0) }

        registry.updateTitle(entry.sessionID, title: "Working")
        registry.updateAgentState(entry.sessionID, state: .working, agentName: "Claude")
        registry.markUnread(entry.sessionID)
        registry.markRead(entry.sessionID)

        #expect(events.count == 4)
        if case .titleChanged = events[0].change {} else { Issue.record("Event 0 should be titleChanged") }
        if case .agentStateChanged = events[1].change {} else { Issue.record("Event 1 should be agentStateChanged") }
        if case .notificationStateChanged(true) = events[2].change {} else { Issue.record("Event 2 should be unread") }
        if case .notificationStateChanged(false) = events[3].change {} else { Issue.record("Event 3 should be read") }
        _ = cancellable
    }

    @Test("Register session auto-registers owner window when missing")
    func registerSessionAutoRegistersOwnerWindow() {
        let registry = SessionRegistryImpl()
        let orphanWindow = WindowID()
        let entry = makeEntry(windowID: orphanWindow)

        registry.registerSession(entry)

        #expect(registry.windowIDs.contains(orphanWindow))
        #expect(registry.session(for: entry.sessionID)?.ownerWindowID == orphanWindow)
    }

    @Test("Session change events include correct window ID")
    func changeEventsIncludeWindowID() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)
        var receivedWindowID: WindowID?

        let cancellable = registry.sessionUpdated.sink { receivedWindowID = $0.windowID }
        registry.updateTitle(entry.sessionID, title: "Updated")

        #expect(receivedWindowID == windowA)
        _ = cancellable
    }
}
