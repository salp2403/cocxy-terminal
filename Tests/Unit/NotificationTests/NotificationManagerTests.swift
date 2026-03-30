// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotificationManagerTests.swift - Tests for the centralized notification manager.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Mock Notification Emitter

/// Spy that records every notification emitted by the manager.
/// Allows tests to verify emission behavior without touching macOS APIs.
@MainActor
final class MockNotificationEmitter: SystemNotificationEmitting {
    private(set) var emittedNotifications: [CocxyNotification] = []
    var shouldSucceed: Bool = true

    func emit(_ notification: CocxyNotification) {
        emittedNotifications.append(notification)
    }

    func reset() {
        emittedNotifications.removeAll()
    }
}

// MARK: - Notification Manager Tests

/// Tests for `NotificationManagerImpl`.
///
/// Covers:
/// - State change handling creates attention items and emits notifications.
/// - Coalescence: rapid same-state changes produce one notification.
/// - Rate limiting: multiple notifications within window emit only once.
/// - Attention queue ordering by urgency then timestamp.
/// - markAsRead by tabID / itemID / markAll.
/// - Unread counts per tab and total.
/// - nextUnreadItem returns highest urgency.
/// - States that do not generate notifications (idle, working, launched).
/// - Config disabled suppresses all notifications.
/// - Config change updates behavior dynamically.
/// - handleNotificationAction marks tab as read.
/// - Combine publishers emit correctly.
@MainActor
final class NotificationManagerTests: XCTestCase {

    private var sut: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var cancellables: Set<AnyCancellable>!

    // Stable tab IDs for tests.
    private let tabA = TabID()
    private let tabB = TabID()
    private let tabC = TabID()

    override func setUp() {
        super.setUp()
        emitter = MockNotificationEmitter()
        sut = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 2.0,
            rateLimitPerTab: 5.0
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        sut = nil
        emitter = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates a CocxyNotification of the given type for the given tab.
    private func makeNotification(
        type: NotificationType,
        tabId: TabID,
        title: String = "Test",
        body: String = "Test body"
    ) -> CocxyNotification {
        CocxyNotification(type: type, tabId: tabId, title: title, body: body)
    }

    // MARK: - 1. notify() creates attention item

    func testNotifyWithAgentNeedsAttentionCreatesAttentionItem() {
        let notification = makeNotification(type: .agentNeedsAttention, tabId: tabA)

        sut.notify(notification)

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.count, 1)
        XCTAssertEqual(sut.attentionQueue.first?.tabId, tabA)
        XCTAssertEqual(sut.attentionQueue.first?.type, .agentNeedsAttention)
        XCTAssertFalse(sut.attentionQueue.first?.isRead ?? true)
    }

    func testNotifyWithAgentFinishedCreatesAttentionItem() {
        let notification = makeNotification(type: .agentFinished, tabId: tabA)

        sut.notify(notification)

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.first?.type, .agentFinished)
    }

    func testNotifyWithAgentErrorCreatesAttentionItem() {
        let notification = makeNotification(type: .agentError, tabId: tabB)

        sut.notify(notification)

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.first?.type, .agentError)
    }

    // MARK: - 2. notify() emits to system emitter

    func testNotifyEmitsToSystemEmitter() {
        let notification = makeNotification(type: .agentNeedsAttention, tabId: tabA)

        sut.notify(notification)

        XCTAssertEqual(emitter.emittedNotifications.count, 1)
        XCTAssertEqual(emitter.emittedNotifications.first?.type, .agentNeedsAttention)
    }

    // MARK: - 3. Coalescence: rapid same-type for same tab within window

    func testCoalescenceSuppressesDuplicateWithinWindow() {
        let notification1 = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        let notification2 = makeNotification(type: .agentNeedsAttention, tabId: tabA)

        sut.notify(notification1)
        sut.notify(notification2) // within coalescence window -> suppressed

        // Only one attention item and one emission
        XCTAssertEqual(sut.attentionQueue.count, 1)
        XCTAssertEqual(emitter.emittedNotifications.count, 1)
        XCTAssertEqual(sut.unreadCount, 1)
    }

    func testCoalescenceAllowsDifferentTypesForSameTab() {
        let notificationA = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        let notificationB = makeNotification(type: .agentError, tabId: tabA)

        sut.notify(notificationA)
        sut.notify(notificationB) // different type -> not suppressed by coalescence

        // Both items are in the attention queue (coalescence did not suppress).
        XCTAssertEqual(sut.attentionQueue.count, 2)
        // Only 1 system emission because rate limiting allows max 1 per tab per window.
        XCTAssertEqual(emitter.emittedNotifications.count, 1)
    }

    func testCoalescenceAllowsSameTypeForDifferentTabs() {
        let notificationA = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        let notificationB = makeNotification(type: .agentNeedsAttention, tabId: tabB)

        sut.notify(notificationA)
        sut.notify(notificationB) // different tab -> not suppressed

        XCTAssertEqual(sut.attentionQueue.count, 2)
        XCTAssertEqual(emitter.emittedNotifications.count, 2)
    }

    func testCoalescenceAllowsSameTypeAfterWindowExpires() {
        // Use a tiny coalescence window to test expiry
        let fastSut = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 0.01,
            rateLimitPerTab: 0.01
        )

        let notification1 = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        fastSut.notify(notification1)

        // Wait for window to expire
        let expectation = expectation(description: "coalescence window expires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        emitter.reset()
        let notification2 = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        fastSut.notify(notification2)

        XCTAssertEqual(emitter.emittedNotifications.count, 1)
    }

    // MARK: - 4. Rate limiting: max 1 per tab within rate window

    func testRateLimitingSuppressesSecondNotificationWithinWindow() {
        let notification1 = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        let notification2 = makeNotification(type: .agentFinished, tabId: tabA)

        sut.notify(notification1)
        sut.notify(notification2) // same tab within rate limit -> still queued but not emitted

        // Both should be in the attention queue (they are different types)
        XCTAssertEqual(sut.attentionQueue.count, 2)
        // But only the first should be emitted to system
        XCTAssertEqual(emitter.emittedNotifications.count, 1)
    }

    func testRateLimitingDoesNotAffectDifferentTabs() {
        let notification1 = makeNotification(type: .agentNeedsAttention, tabId: tabA)
        let notification2 = makeNotification(type: .agentNeedsAttention, tabId: tabB)

        sut.notify(notification1)
        sut.notify(notification2) // different tab -> not rate-limited

        XCTAssertEqual(emitter.emittedNotifications.count, 2)
    }

    // MARK: - 5. Attention queue ordering (urgency -> timestamp)

    func testAttentionQueueOrderedByUrgencyThenTimestamp() {
        // agentFinished is lower urgency than agentNeedsAttention
        let finishedNotification = makeNotification(type: .agentFinished, tabId: tabA)
        let errorNotification = makeNotification(type: .agentError, tabId: tabB)
        let attentionNotification = makeNotification(type: .agentNeedsAttention, tabId: tabC)

        sut.notify(finishedNotification)
        sut.notify(errorNotification)
        sut.notify(attentionNotification)

        // Order should be: agentNeedsAttention (0) > agentError (1) > agentFinished (2)
        let types = sut.attentionQueue.map(\.type)
        XCTAssertEqual(types[0], .agentNeedsAttention)
        XCTAssertEqual(types[1], .agentError)
        XCTAssertEqual(types[2], .agentFinished)
    }

    func testAttentionQueueSameUrgencyOrderedByTimestamp() {
        // Two agentNeedsAttention for different tabs -- most recent first
        let notificationA = makeNotification(
            type: .agentNeedsAttention,
            tabId: tabA,
            title: "First"
        )
        let notificationB = makeNotification(
            type: .agentNeedsAttention,
            tabId: tabB,
            title: "Second"
        )

        sut.notify(notificationA)
        sut.notify(notificationB)

        // Same urgency -> most recent first
        XCTAssertEqual(sut.attentionQueue[0].tabId, tabB)
        XCTAssertEqual(sut.attentionQueue[1].tabId, tabA)
    }

    // MARK: - 6. markAsRead(tabId:)

    func testMarkAsReadByTabIdRemovesItemsForTab() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabB))

        sut.markAsRead(tabId: tabA)

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertTrue(sut.attentionQueue.allSatisfy { $0.tabId == tabB || $0.isRead })
    }

    func testMarkAsReadByTabIdDecrementsUnreadCount() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabB))

        XCTAssertEqual(sut.unreadCount, 2)

        sut.markAsRead(tabId: tabA)

        XCTAssertEqual(sut.unreadCount, 1)
    }

    func testMarkAsReadByTabIdWithNonexistentTabIsNoOp() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        let unknownTab = TabID()

        sut.markAsRead(tabId: unknownTab)

        XCTAssertEqual(sut.unreadCount, 1)
    }

    // MARK: - 7. markAllAsRead()

    func testMarkAllAsReadClearsEverything() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabB))
        sut.notify(makeNotification(type: .agentFinished, tabId: tabC))

        sut.markAllAsRead()

        XCTAssertEqual(sut.unreadCount, 0)
        XCTAssertTrue(sut.attentionQueue.allSatisfy(\.isRead))
    }

    // MARK: - 8. gotoNextUnread()

    func testGotoNextUnreadReturnsHighestUrgencyTab() {
        sut.notify(makeNotification(type: .agentFinished, tabId: tabA))
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabB))

        let nextTabId = sut.gotoNextUnread()

        XCTAssertEqual(nextTabId, tabB)
    }

    func testGotoNextUnreadMarksTabAsRead() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        _ = sut.gotoNextUnread()

        XCTAssertEqual(sut.unreadCount, 0)
    }

    func testGotoNextUnreadReturnsNilWhenNoUnread() {
        let result = sut.gotoNextUnread()

        XCTAssertNil(result)
    }

    func testGotoNextUnreadAfterMarkAsReadReturnsNext() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentFinished, tabId: tabB))

        // First call returns highest urgency (tabA = agentNeedsAttention)
        let first = sut.gotoNextUnread()
        XCTAssertEqual(first, tabA)

        // Second call returns next (tabB = agentFinished)
        let second = sut.gotoNextUnread()
        XCTAssertEqual(second, tabB)

        // Third call returns nil (all read)
        let third = sut.gotoNextUnread()
        XCTAssertNil(third)
    }

    // MARK: - 9. Unread count per tab

    func testUnreadCountPerTab() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabA))
        sut.notify(makeNotification(type: .agentFinished, tabId: tabB))

        XCTAssertEqual(sut.unreadCountForTab(tabA), 2)
        XCTAssertEqual(sut.unreadCountForTab(tabB), 1)
        XCTAssertEqual(sut.unreadCountForTab(tabC), 0)
    }

    // MARK: - 10. Total unread count

    func testTotalUnreadCountReflectsAllTabs() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabB))
        sut.notify(makeNotification(type: .agentFinished, tabId: tabC))

        XCTAssertEqual(sut.unreadCount, 3)
    }

    // MARK: - 11. States that do NOT generate notifications

    func testProcessExitedGeneratesNotification() {
        let notification = makeNotification(type: .processExited(code: 0), tabId: tabA)

        sut.notify(notification)

        XCTAssertEqual(sut.unreadCount, 1)
    }

    func testCustomTypeGeneratesNotification() {
        let notification = makeNotification(type: .custom("deploy done"), tabId: tabA)

        sut.notify(notification)

        XCTAssertEqual(sut.unreadCount, 1)
    }

    // MARK: - 12. handleStateChange convenience

    func testHandleStateChangeForWaitingInputCreatesNotification() {
        sut.handleStateChange(
            state: .waitingInput,
            previousState: .working,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.first?.type, .agentNeedsAttention)
    }

    func testHandleStateChangeForFinishedCreatesNotification() {
        sut.handleStateChange(
            state: .finished,
            previousState: .working,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.first?.type, .agentFinished)
    }

    func testHandleStateChangeForErrorCreatesNotification() {
        sut.handleStateChange(
            state: .error,
            previousState: .working,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.first?.type, .agentError)
    }

    func testHandleStateChangeForIdleDoesNotCreateNotification() {
        sut.handleStateChange(
            state: .idle,
            previousState: .finished,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: nil
        )

        XCTAssertEqual(sut.unreadCount, 0)
        XCTAssertTrue(sut.attentionQueue.isEmpty)
    }

    func testHandleStateChangeForWorkingDoesNotCreateNotification() {
        sut.handleStateChange(
            state: .working,
            previousState: .launched,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        XCTAssertEqual(sut.unreadCount, 0)
    }

    func testHandleStateChangeForLaunchedDoesNotCreateNotification() {
        sut.handleStateChange(
            state: .launched,
            previousState: .idle,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        XCTAssertEqual(sut.unreadCount, 0)
    }

    // MARK: - 13. Config disabled suppresses notifications

    func testConfigDisabledSuppressesAllNotifications() {
        let disabledConfig = NotificationConfig(
            macosNotifications: false,
            sound: false,
            badgeOnTab: false,
            flashTab: false,
            showDockBadge: false,
            soundFinished: "default",
            soundAttention: "default",
            soundError: "default"
        )
        let disabledSut = NotificationManagerImpl(
            config: CocxyConfig(
                general: .defaults,
                appearance: .defaults,
                terminal: .defaults,
                agentDetection: .defaults,
                notifications: disabledConfig,
                quickTerminal: .defaults,
                keybindings: .defaults,
                sessions: .defaults
            ),
            systemEmitter: emitter,
            coalescenceWindow: 2.0,
            rateLimitPerTab: 5.0
        )

        disabledSut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        // Attention queue still gets the item (for badge/UI)
        XCTAssertEqual(disabledSut.unreadCount, 1)
        // But system emitter is NOT called
        XCTAssertEqual(emitter.emittedNotifications.count, 0)
    }

    // MARK: - 14. Config change updates behavior

    func testUpdateConfigChangesNotificationBehavior() {
        // Start enabled
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        XCTAssertEqual(emitter.emittedNotifications.count, 1)

        // Disable notifications
        let disabledConfig = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: NotificationConfig(
                macosNotifications: false,
                sound: false,
                badgeOnTab: false,
                flashTab: false,
                showDockBadge: false,
                soundFinished: "default",
                soundAttention: "default",
                soundError: "default"
            ),
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        sut.updateConfig(disabledConfig)

        emitter.reset()
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabB))

        // System emitter should not be called
        XCTAssertEqual(emitter.emittedNotifications.count, 0)
        // But attention queue still tracks it
        XCTAssertEqual(sut.unreadCount, 2)
    }

    // MARK: - 15. handleNotificationAction marks read

    func testHandleNotificationActionMarksTabAsRead() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabB))

        sut.handleNotificationAction(tabId: tabA)

        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.unreadCountForTab(tabA), 0)
        XCTAssertEqual(sut.unreadCountForTab(tabB), 1)
    }

    // MARK: - 16. Combine publishers

    func testNotificationsPublisherEmitsOnNotify() {
        var received: [CocxyNotification] = []

        sut.notificationsPublisher
            .sink { received.append($0) }
            .store(in: &cancellables)

        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.type, .agentNeedsAttention)
    }

    func testUnreadCountPublisherEmitsOnChange() {
        var counts: [Int] = []

        sut.unreadCountPublisher
            .sink { counts.append($0) }
            .store(in: &cancellables)

        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabB))
        sut.markAsRead(tabId: tabA)

        XCTAssertEqual(counts, [1, 2, 1])
    }

    // MARK: - 17. peekNextUnread without marking as read

    func testPeekNextUnreadReturnsHighestUrgencyWithoutMarking() {
        sut.notify(makeNotification(type: .agentFinished, tabId: tabA))
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabB))

        let peeked = sut.peekNextUnread()

        XCTAssertEqual(peeked, tabB)
        XCTAssertEqual(sut.unreadCount, 2) // unchanged
    }

    func testPeekNextUnreadReturnsNilWhenEmpty() {
        XCTAssertNil(sut.peekNextUnread())
    }

    // MARK: - 18. Multiple unread for same tab

    func testMultipleNotificationsForSameTabIncrementTabCount() {
        // Different types bypass coalescence
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabA))

        XCTAssertEqual(sut.unreadCountForTab(tabA), 2)
        XCTAssertEqual(sut.unreadCount, 2)
    }

    func testMarkAsReadForTabClearsAllItemsForThatTab() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentError, tabId: tabA))
        sut.notify(makeNotification(type: .agentFinished, tabId: tabB))

        sut.markAsRead(tabId: tabA)

        XCTAssertEqual(sut.unreadCountForTab(tabA), 0)
        XCTAssertEqual(sut.unreadCountForTab(tabB), 1)
        XCTAssertEqual(sut.unreadCount, 1)
    }

    // MARK: - 19. Empty attention queue operations

    func testMarkAsReadOnEmptyQueueIsNoOp() {
        sut.markAsRead(tabId: tabA)

        XCTAssertEqual(sut.unreadCount, 0)
    }

    func testMarkAllAsReadOnEmptyQueueIsNoOp() {
        sut.markAllAsRead()

        XCTAssertEqual(sut.unreadCount, 0)
    }

    // MARK: - 20. Coalescence with handleStateChange

    func testHandleStateChangeCoalescesRapidSameState() {
        sut.handleStateChange(
            state: .waitingInput,
            previousState: .working,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )
        sut.handleStateChange(
            state: .waitingInput,
            previousState: .working,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        // Same state for same tab within coalescence window -> only one notification
        XCTAssertEqual(sut.unreadCount, 1)
        XCTAssertEqual(sut.attentionQueue.count, 1)
    }

    // MARK: - 21. Attention queue sorting stability

    func testAttentionQueueMaintainsOrderAfterMarkAsRead() {
        sut.notify(makeNotification(type: .agentFinished, tabId: tabA))
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabB))
        sut.notify(makeNotification(type: .agentError, tabId: tabC))

        sut.markAsRead(tabId: tabB) // remove the highest urgency

        // Remaining unread: error (tabC) > finished (tabA)
        let unread = sut.attentionQueue.filter { !$0.isRead }
        XCTAssertEqual(unread.count, 2)
        XCTAssertEqual(unread[0].type, .agentError)
        XCTAssertEqual(unread[1].type, .agentFinished)
    }

    // MARK: - 22. processExited notification with exit code

    func testProcessExitedWithNonZeroCodeCreatesNotification() {
        let notification = makeNotification(type: .processExited(code: 1), tabId: tabA)

        sut.notify(notification)

        XCTAssertEqual(sut.unreadCount, 1)
    }

    // MARK: - 23. Notification ID uniqueness

    func testEachNotificationHasUniqueID() {
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabB))

        let ids = sut.attentionQueue.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "All notification IDs should be unique")
    }

    // MARK: - 24. Unread count publisher accuracy

    func testUnreadCountPublisherEmitsZeroAfterMarkAllAsRead() {
        var lastCount: Int?

        sut.unreadCountPublisher
            .sink { lastCount = $0 }
            .store(in: &cancellables)

        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.markAllAsRead()

        XCTAssertEqual(lastCount, 0)
    }
}
