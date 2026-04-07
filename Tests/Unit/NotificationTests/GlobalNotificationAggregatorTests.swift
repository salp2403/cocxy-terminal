// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GlobalNotificationAggregatorTests.swift - Tests for GlobalNotificationAggregatorImpl.

import Testing
import Foundation
import Combine
@testable import CocxyTerminal

// MARK: - Global Notification Aggregator Tests

@Suite("Global Notification Aggregator")
@MainActor
struct GlobalNotificationAggregatorTests {

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
        hasUnread: Bool = false
    ) -> SessionEntry {
        SessionEntry(
            ownerWindowID: windowID,
            tabID: TabID(),
            hasUnreadNotification: hasUnread
        )
    }

    // MARK: - Total Unread Count

    @Test("Total unread count sums all windows")
    func totalUnreadSumsAll() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowB, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowB, hasUnread: false))

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        #expect(aggregator.totalUnreadCount == 3)
    }

    @Test("Total unread count is zero when no unread sessions")
    func totalUnreadZero() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA))
        registry.registerSession(makeEntry(windowID: windowB))

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        #expect(aggregator.totalUnreadCount == 0)
    }

    // MARK: - Per-Window Count

    @Test("Unread count per window filters correctly")
    func unreadCountPerWindow() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: false))
        registry.registerSession(makeEntry(windowID: windowB, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowB, hasUnread: true))

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        #expect(aggregator.unreadCount(for: windowA) == 1)
        #expect(aggregator.unreadCount(for: windowB) == 2)
    }

    // MARK: - Remote Count

    @Test("Remote unread count excludes specified window")
    func remoteUnreadExcludes() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowB, hasUnread: true))

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        // Excluding window A should show only window B's count.
        #expect(aggregator.remoteUnreadCount(excluding: windowA) == 1)
        // Excluding window B should show only window A's count.
        #expect(aggregator.remoteUnreadCount(excluding: windowB) == 2)
    }

    @Test("Remote unread is zero when only current window has unread")
    func remoteUnreadZeroWhenOnlyLocal() {
        let registry = makeRegistry()
        registry.registerSession(makeEntry(windowID: windowA, hasUnread: true))
        registry.registerSession(makeEntry(windowID: windowB, hasUnread: false))

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        #expect(aggregator.remoteUnreadCount(excluding: windowA) == 0)
    }

    // MARK: - Publisher: Total Unread

    @Test("Total unread publisher fires on markUnread")
    func totalPublisherFiresOnMarkUnread() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA)
        registry.registerSession(entry)

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)
        var receivedCounts: [Int] = []

        let cancellable = aggregator.totalUnreadPublisher
            .dropFirst() // Skip the initial value from CurrentValueSubject.
            .sink { receivedCounts.append($0) }

        registry.markUnread(entry.sessionID)

        #expect(receivedCounts == [1])
        _ = cancellable
    }

    @Test("Total unread publisher fires on markRead")
    func totalPublisherFiresOnMarkRead() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA, hasUnread: true)
        registry.registerSession(entry)

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)
        var receivedCounts: [Int] = []

        let cancellable = aggregator.totalUnreadPublisher
            .dropFirst()
            .sink { receivedCounts.append($0) }

        registry.markRead(entry.sessionID)

        #expect(receivedCounts == [0])
        _ = cancellable
    }

    // MARK: - Publisher: Window Unread

    @Test("Window unread publisher fires with correct window ID")
    func windowPublisherFiresCorrectWindow() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowB)
        registry.registerSession(entry)

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)
        var receivedWindowID: WindowID?
        var receivedCount: Int?

        let cancellable = aggregator.windowUnreadPublisher
            .sink { (windowID, count) in
                receivedWindowID = windowID
                receivedCount = count
            }

        registry.markUnread(entry.sessionID)

        #expect(receivedWindowID == windowB)
        #expect(receivedCount == 1)
        _ = cancellable
    }

    // MARK: - Session Removal

    @Test("Removing an unread session decreases total count")
    func sessionRemovalDecreasesCount() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA, hasUnread: true)
        registry.registerSession(entry)

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)
        #expect(aggregator.totalUnreadCount == 1)

        registry.removeSession(entry.sessionID)

        #expect(aggregator.totalUnreadCount == 0)
    }

    @Test("Session removal republishes only the affected window count")
    func sessionRemovalRepublishesAffectedWindowOnly() {
        let registry = makeRegistry()
        let entryA = makeEntry(windowID: windowA, hasUnread: true)
        let entryB = makeEntry(windowID: windowB, hasUnread: true)
        registry.registerSession(entryA)
        registry.registerSession(entryB)

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)
        var received: [(WindowID, Int)] = []

        let cancellable = aggregator.windowUnreadPublisher
            .sink { received.append(($0.windowID, $0.count)) }

        registry.removeSession(entryA.sessionID)

        #expect(received.count == 1)
        #expect(received.first?.0 == windowA)
        #expect(received.first?.1 == 0)
        _ = cancellable
    }

    @Test("Owner change republishes unread counts for both windows")
    func ownerChangeRepublishesWindowCounts() {
        let registry = makeRegistry()
        let entry = makeEntry(windowID: windowA, hasUnread: true)
        registry.registerSession(entry)

        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)
        var received: [(WindowID, Int)] = []

        let cancellable = aggregator.windowUnreadPublisher
            .sink { received.append(($0.windowID, $0.count)) }

        #expect(registry.prepareTransfer(entry.sessionID, from: windowA, to: windowB) == true)
        registry.completeTransfer(entry.sessionID, newTabID: TabID())

        #expect(received.contains(where: { $0.0 == windowA && $0.1 == 0 }))
        #expect(received.contains(where: { $0.0 == windowB && $0.1 == 1 }))
        _ = cancellable
    }

    // MARK: - UnreadCountPublishing Conformance

    @Test("Conforms to UnreadCountPublishing for dock badge")
    func conformsToUnreadCountPublishing() {
        let registry = makeRegistry()
        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        // The aggregator should be usable as an UnreadCountPublishing source.
        let source: any UnreadCountPublishing = aggregator
        var received: Int?

        let cancellable = source.unreadCountPublisher.sink { received = $0 }

        // CurrentValueSubject emits the current value immediately.
        #expect(received == 0)
        _ = cancellable
    }

    // MARK: - Edge Cases

    @Test("Unknown window ID returns zero for per-window count")
    func unknownWindowReturnsZero() {
        let registry = makeRegistry()
        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        #expect(aggregator.unreadCount(for: WindowID()) == 0)
    }

    @Test("Empty registry returns zero for all counts")
    func emptyRegistryZeroCounts() {
        let registry = makeRegistry()
        let aggregator = GlobalNotificationAggregatorImpl(registry: registry)

        #expect(aggregator.totalUnreadCount == 0)
        #expect(aggregator.unreadCount(for: windowA) == 0)
        #expect(aggregator.remoteUnreadCount(excluding: windowA) == 0)
    }
}
