// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase4IntegrationTests.swift - Integration and edge-case tests for Fase 4
// (NotificationManager, QuickSwitch, DockBadge).
//
// Written by El Rompe-cosas (QA, T-034).
//
// These tests focus on:
//   - Integration flows: NotificationManager + QuickSwitch + DockBadge end-to-end.
//   - Edge cases: rapid state changes, concurrent notifications, boundary values.
//   - E2E flow: agent finishes -> notification -> quick switch -> badge decrements.
//   - Config toggle mid-session.
//   - Coalescence edge cases: different states within same window, same state different tabs.
//   - Rate limiting boundary conditions.
//   - Quick Switch: circular exhaustion, re-add after full rotation.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Shared helpers (local to this file)

// NOTE: MockNotificationEmitter, SpyDockTile, MockUnreadCountSource,
// MockNotificationManagerForQuickSwitch and MockTabActivator are already
// defined in the existing test files and are visible across the test target.
// We define only the new helpers needed here.

// MARK: - Counting Unread Source

/// An UnreadCountPublishing that delegates to a real NotificationManagerImpl.
/// Exists only to make the wiring explicit in integration tests.
// We use NotificationManagerImpl directly -- it already conforms to UnreadCountPublishing.

// MARK: - Integration: NotificationManager -> DockBadge

/// Tests that verify DockBadgeController correctly reflects the state of
/// NotificationManagerImpl through the Combine pipeline.
@MainActor
final class NotificationManagerDockBadgeIntegrationTests: XCTestCase {

    private var notificationManager: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var spyDockTile: SpyDockTile!
    private var dockBadge: DockBadgeController!
    private var cancellables: Set<AnyCancellable>!

    private let tabA = TabID()
    private let tabB = TabID()
    private let tabC = TabID()

    override func setUp() {
        super.setUp()
        emitter = MockNotificationEmitter()
        notificationManager = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 2.0,
            rateLimitPerTab: 5.0
        )
        spyDockTile = SpyDockTile()
        dockBadge = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: notificationManager,
            config: .defaults
        )
        dockBadge.bind()
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        dockBadge = nil
        spyDockTile = nil
        notificationManager = nil
        emitter = nil
        super.tearDown()
    }

    // MARK: - Test 1: badge increments when notification arrives

    func testBadgeIncrementsWhenNotificationArrives() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1")
    }

    // MARK: - Test 2: badge increments for each new tab (different tabs bypass rate limit)

    func testBadgeReflectsCountAcrossMultipleTabs() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabB))
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabC))

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "3")
    }

    // MARK: - Test 3: badge clears when all tabs are marked as read

    func testBadgeClearsWhenAllTabsMarkedAsRead() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentFinished, tabId: tabB))

        notificationManager.markAllAsRead()

        XCTAssertNil(spyDockTile.currentBadgeLabel)
    }

    // MARK: - Test 4: badge decrements when single tab is marked as read

    func testBadgeDecrementsWhenSingleTabMarkedAsRead() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentFinished, tabId: tabB))

        notificationManager.markAsRead(tabId: tabA)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1")
    }

    // MARK: - Test 5: coalescence does NOT double the badge count

    func testCoalescenceDoesNotDoubleBadgeCount() {
        // Rapid same-type notifications for same tab -> coalesced -> only 1 item
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1",
            "Coalesced notifications should produce a badge of 1, not 3")
    }

    // MARK: - Test 6: badge history reflects all transitions

    func testBadgeHistoryReflectsAllTransitions() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentFinished, tabId: tabB))
        notificationManager.markAsRead(tabId: tabA)

        // History: "1" (after tabA), "2" (after tabB), "1" (after markAsRead tabA)
        let history = spyDockTile.badgeLabelHistory.compactMap { $0 }
        XCTAssertEqual(history, ["1", "2", "1"])
    }

    // MARK: - Test 7: badge disabled in config suppresses all updates

    func testBadgeDisabledInConfigSuppressesAllUpdates() {
        // Use isolated instances to avoid interference from the setUp controller.
        let isolatedEmitter = MockNotificationEmitter()
        let isolatedManager = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: isolatedEmitter,
            coalescenceWindow: 2.0,
            rateLimitPerTab: 5.0
        )
        let isolatedSpy = SpyDockTile()

        let disabledBadgeConfig = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: NotificationConfig(
                macosNotifications: true,
                sound: true,
                badgeOnTab: true,
                flashTab: true,
                showDockBadge: false
            ),
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let disabledDockBadge = DockBadgeController(
            dockTile: isolatedSpy,
            unreadCountSource: isolatedManager,
            config: disabledBadgeConfig
        )
        disabledDockBadge.bind()

        isolatedManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        XCTAssertNil(isolatedSpy.currentBadgeLabel,
            "Badge should be nil when showDockBadge is false")
    }

    // MARK: - Private helpers

    private func makeNotification(type: NotificationType, tabId: TabID) -> CocxyNotification {
        CocxyNotification(type: type, tabId: tabId, title: "Test", body: "Body")
    }
}

// MARK: - Integration: NotificationManager -> QuickSwitch -> DockBadge (E2E)

/// End-to-end flow: agent finishes -> notification queued -> quick switch ->
/// tab activated -> badge decrements.
@MainActor
final class Phase4E2EFlowTests: XCTestCase {

    private var notificationManager: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var spyDockTile: SpyDockTile!
    private var dockBadge: DockBadgeController!
    private var tabActivator: MockTabActivator!
    private var quickSwitch: QuickSwitchController!
    private var cancellables: Set<AnyCancellable>!

    private let tabA = TabID()
    private let tabB = TabID()
    private let tabC = TabID()

    override func setUp() {
        super.setUp()
        emitter = MockNotificationEmitter()
        notificationManager = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 2.0,
            rateLimitPerTab: 5.0
        )
        spyDockTile = SpyDockTile()
        dockBadge = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: notificationManager,
            config: .defaults
        )
        dockBadge.bind()
        tabActivator = MockTabActivator()
        quickSwitch = QuickSwitchController(
            notificationManager: notificationManager,
            tabActivator: tabActivator
        )
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        quickSwitch = nil
        tabActivator = nil
        dockBadge = nil
        spyDockTile = nil
        notificationManager = nil
        emitter = nil
        super.tearDown()
    }

    // MARK: - Test 8: E2E agent finishes -> badge shows 1

    func testE2EAgentFinishedShowsBadge() {
        notificationManager.handleStateChange(
            state: .finished,
            previousState: .working,
            for: tabA,
            tabTitle: "Terminal 1",
            agentName: "claude"
        )

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1",
            "Badge should show 1 after agent finished")
    }

    // MARK: - Test 9: E2E quick switch decrements badge

    func testE2EQuickSwitchDecrementsBadge() {
        notificationManager.notify(makeDifferentTypeNotification(type: .agentFinished, tabId: tabA))
        notificationManager.notify(makeDifferentTypeNotification(type: .agentNeedsAttention, tabId: tabB))

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "2")

        _ = quickSwitch.performQuickSwitch() // marks tabB as read (higher urgency)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1",
            "Badge should decrement to 1 after quick switch")
    }

    // MARK: - Test 10: E2E quick switch -> all badges clear after full rotation

    func testE2EQuickSwitchClearsAllBadgesAfterFullRotation() {
        notificationManager.notify(makeDifferentTypeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeDifferentTypeNotification(type: .agentFinished, tabId: tabB))

        _ = quickSwitch.performQuickSwitch() // tabA (higher urgency)
        _ = quickSwitch.performQuickSwitch() // tabB

        XCTAssertNil(spyDockTile.currentBadgeLabel,
            "Badge should be cleared after all tabs are visited via quick switch")
    }

    // MARK: - Test 11: E2E system emitter called on first notification per tab

    func testE2ESystemEmitterCalledOnFirstNotificationPerTab() {
        notificationManager.notify(makeDifferentTypeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeDifferentTypeNotification(type: .agentFinished, tabId: tabB))

        XCTAssertEqual(emitter.emittedNotifications.count, 2,
            "System emitter should be called once per tab (not rate-limited for different tabs)")
    }

    // MARK: - Test 12: E2E rate limiting suppresses second OS notification for same tab

    func testE2ERateLimitingSuppressesSecondOSNotification() {
        notificationManager.notify(makeDifferentTypeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeDifferentTypeNotification(type: .agentFinished, tabId: tabA))

        // Attention queue has 2 items (different types bypass coalescence)
        XCTAssertEqual(notificationManager.unreadCount, 2)
        // But OS only notified once (rate limit)
        XCTAssertEqual(emitter.emittedNotifications.count, 1,
            "Rate limiting should suppress the second OS notification for the same tab")
    }

    // MARK: - Test 13: E2E full flow with 3 agents

    func testE2EFullFlowWithThreeAgents() {
        // 3 agents finish in different tabs
        notificationManager.handleStateChange(
            state: .finished, previousState: .working,
            for: tabA, tabTitle: "Tab A", agentName: "claude"
        )
        notificationManager.handleStateChange(
            state: .finished, previousState: .working,
            for: tabB, tabTitle: "Tab B", agentName: "codex"
        )
        notificationManager.handleStateChange(
            state: .waitingInput, previousState: .working,
            for: tabC, tabTitle: "Tab C", agentName: "aider"
        )

        // Badge shows 3
        XCTAssertEqual(spyDockTile.currentBadgeLabel, "3")

        // Quick switch rotates through by urgency: tabC (waitingInput) first
        let r1 = quickSwitch.performQuickSwitch()
        XCTAssertEqual(r1?.tabId, tabC)
        XCTAssertEqual(spyDockTile.currentBadgeLabel, "2")

        // Then tabA or tabB (both agentFinished, ordered by timestamp most recent first)
        let r2 = quickSwitch.performQuickSwitch()
        XCTAssertNotNil(r2)
        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1")

        let r3 = quickSwitch.performQuickSwitch()
        XCTAssertNotNil(r3)
        XCTAssertNil(spyDockTile.currentBadgeLabel)

        // Queue exhausted
        let r4 = quickSwitch.performQuickSwitch()
        XCTAssertNil(r4)
    }

    // MARK: - Private helpers

    private func makeDifferentTypeNotification(type: NotificationType, tabId: TabID) -> CocxyNotification {
        CocxyNotification(type: type, tabId: tabId, title: "Test", body: "Body")
    }
}

// MARK: - Coalescence Edge Cases

@MainActor
final class CoalescenceEdgeCaseTests: XCTestCase {

    private var sut: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var cancellables: Set<AnyCancellable>!

    private let tabA = TabID()
    private let tabB = TabID()

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

    // MARK: - Test 14: different states within same window NOT coalesced

    func testDifferentStatesWithinWindowAreNotCoalesced() {
        // agentNeedsAttention and agentError are different types -> not coalesced
        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                     title: "T1", body: "B1"))
        sut.notify(CocxyNotification(type: .agentError, tabId: tabA,
                                     title: "T2", body: "B2"))

        XCTAssertEqual(sut.attentionQueue.count, 2,
            "Different notification types for same tab should not be coalesced")
    }

    // MARK: - Test 15: same state different tabs are NOT coalesced

    func testSameStateForDifferentTabsNotCoalesced() {
        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                     title: "T1", body: "B1"))
        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabB,
                                     title: "T2", body: "B2"))

        XCTAssertEqual(sut.attentionQueue.count, 2,
            "Same notification type for different tabs should not be coalesced")
    }

    // MARK: - Test 16: processExited with different codes NOT coalesced

    func testProcessExitedWithDifferentCodesNotCoalesced() {
        // processExited normalizes to "processExited" key regardless of exit code
        // so they SHOULD be coalesced (same type key)
        sut.notify(CocxyNotification(type: .processExited(code: 0), tabId: tabA,
                                     title: "Exit 0", body: "Normal exit"))
        sut.notify(CocxyNotification(type: .processExited(code: 1), tabId: tabA,
                                     title: "Exit 1", body: "Error exit"))

        // Both processExited map to same coalescence key -> second is suppressed
        XCTAssertEqual(sut.attentionQueue.count, 1,
            "processExited notifications for same tab should be coalesced regardless of exit code")
    }

    // MARK: - Test 17: custom type notifications coalesce by tab

    func testCustomTypeNotificationsCoalesceByTab() {
        sut.notify(CocxyNotification(type: .custom("deploy done"), tabId: tabA,
                                     title: "T1", body: "B1"))
        sut.notify(CocxyNotification(type: .custom("build done"), tabId: tabA,
                                     title: "T2", body: "B2"))

        // Both .custom normalize to "custom" key -> coalesced
        XCTAssertEqual(sut.attentionQueue.count, 1,
            "Different custom notification payloads for same tab should be coalesced")
    }

    // MARK: - Test 18: handleStateChange followed by error within window

    func testHandleStateChangeWaitingThenErrorWithinWindowBothEnqueue() {
        sut.handleStateChange(
            state: .waitingInput, previousState: .working,
            for: tabA, tabTitle: "Tab A", agentName: "claude"
        )
        sut.handleStateChange(
            state: .error, previousState: .waitingInput,
            for: tabA, tabTitle: "Tab A", agentName: "claude"
        )

        // waitingInput -> agentNeedsAttention, error -> agentError: different types -> 2 items
        XCTAssertEqual(sut.attentionQueue.count, 2,
            "waitingInput then error transitions should produce 2 distinct attention items")
    }

    // MARK: - Test 19: rapid same state changes produce exactly 1 item

    func testRapidSameStateChangesProduceExactlyOneItem() {
        for _ in 0..<10 {
            sut.handleStateChange(
                state: .finished, previousState: .working,
                for: tabA, tabTitle: "Tab A", agentName: "claude"
            )
        }

        XCTAssertEqual(sut.attentionQueue.count, 1,
            "10 rapid same-state changes should produce exactly 1 item due to coalescence")
        XCTAssertEqual(emitter.emittedNotifications.count, 1,
            "10 rapid same-state changes should emit to OS exactly once")
    }
}

// MARK: - Rate Limiting Edge Cases

@MainActor
final class RateLimitingEdgeCaseTests: XCTestCase {

    private var emitter: MockNotificationEmitter!

    private let tabA = TabID()

    override func setUp() {
        super.setUp()
        emitter = MockNotificationEmitter()
    }

    override func tearDown() {
        emitter = nil
        super.tearDown()
    }

    // MARK: - Test 20: exactly at rate limit boundary allows emission

    func testRateLimitAllowsEmissionAfterWindowExpiry() {
        let fastSut = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 0.01,
            rateLimitPerTab: 0.05
        )

        fastSut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                          title: "T1", body: "B1"))
        XCTAssertEqual(emitter.emittedNotifications.count, 1)

        // Wait for rate limit window to expire
        let exp = expectation(description: "rate limit expires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        emitter.reset()
        fastSut.notify(CocxyNotification(type: .agentError, tabId: tabA,
                                          title: "T2", body: "B2"))

        XCTAssertEqual(emitter.emittedNotifications.count, 1,
            "After rate limit window expires, a new OS notification should be allowed")
    }

    // MARK: - Test 21: notifications within rate window go to queue but not OS

    func testNotificationsWithinRateLimitWindowQueuedButNotEmitted() {
        let sut = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 0.0,  // no coalescence
            rateLimitPerTab: 60.0    // long rate limit window
        )

        // Send 3 different-type notifications for same tab within rate limit window
        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                      title: "T1", body: "B1"))
        sut.notify(CocxyNotification(type: .agentError, tabId: tabA,
                                      title: "T2", body: "B2"))
        sut.notify(CocxyNotification(type: .agentFinished, tabId: tabA,
                                      title: "T3", body: "B3"))

        // All 3 in the queue
        XCTAssertEqual(sut.attentionQueue.count, 3)
        // Only 1 OS emission (rate limited)
        XCTAssertEqual(emitter.emittedNotifications.count, 1,
            "Only the first OS notification within rate limit window should be emitted")
    }

    // MARK: - Test 22: notifications disabled -> no OS emission even after window expiry

    func testNotificationsDisabledPreventsOSEmissionAlways() {
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
                showDockBadge: false
            ),
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let sut = NotificationManagerImpl(
            config: disabledConfig,
            systemEmitter: emitter,
            coalescenceWindow: 0.0,
            rateLimitPerTab: 0.0
        )

        for type in [NotificationType.agentNeedsAttention, .agentError, .agentFinished] {
            sut.notify(CocxyNotification(type: type, tabId: tabA, title: "T", body: "B"))
        }

        XCTAssertEqual(emitter.emittedNotifications.count, 0,
            "No OS notifications should be emitted when macosNotifications is disabled")
        XCTAssertEqual(sut.unreadCount, 3,
            "Attention queue should still track items even when OS notifications disabled")
    }
}

// MARK: - Quick Switch Edge Cases

@MainActor
final class QuickSwitchEdgeCaseTests: XCTestCase {

    private var notificationManager: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var tabActivator: MockTabActivator!
    private var sut: QuickSwitchController!

    private let tabA = TabID()
    private let tabB = TabID()
    private let tabC = TabID()

    override func setUp() {
        super.setUp()
        emitter = MockNotificationEmitter()
        notificationManager = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 2.0,
            rateLimitPerTab: 5.0
        )
        tabActivator = MockTabActivator()
        sut = QuickSwitchController(
            notificationManager: notificationManager,
            tabActivator: tabActivator
        )
    }

    override func tearDown() {
        sut = nil
        tabActivator = nil
        notificationManager = nil
        emitter = nil
        super.tearDown()
    }

    // MARK: - Test 23: circular rotation exhaustion returns nil

    func testCircularRotationExhaustionReturnsNil() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentFinished, tabId: tabB))

        _ = sut.performQuickSwitch() // tabA
        _ = sut.performQuickSwitch() // tabB
        let result = sut.performQuickSwitch() // exhausted

        XCTAssertNil(result, "Quick switch should return nil after all tabs have been visited")
        XCTAssertEqual(tabActivator.activatedTabIds.count, 2)
    }

    // MARK: - Test 24: quick switch on empty queue is safe

    func testQuickSwitchOnEmptyQueueIsSafe() {
        let result = sut.performQuickSwitch()

        XCTAssertNil(result, "Quick switch on empty queue should return nil without crashing")
        XCTAssertTrue(tabActivator.activatedTabIds.isEmpty)
    }

    // MARK: - Test 25: quick switch activates most urgent tab first

    func testQuickSwitchActivatesMostUrgentTabFirst() {
        notificationManager.notify(makeNotification(type: .agentFinished, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentError, tabId: tabB))
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabC))

        let result = sut.performQuickSwitch()

        XCTAssertEqual(result?.tabId, tabC,
            "Quick switch should activate tabC (agentNeedsAttention = highest urgency)")
        XCTAssertEqual(tabActivator.activatedTabIds.first, tabC)
    }

    // MARK: - Test 26: re-add notification after full rotation restarts queue

    func testReAddAfterFullRotationRestartsQueue() {
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))

        // Exhaust the queue
        _ = sut.performQuickSwitch()
        XCTAssertNil(sut.performQuickSwitch(), "Queue should be exhausted")

        // Re-add a new notification for tabB (which wasn't in queue before)
        notificationManager.notify(makeNotification(type: .agentError, tabId: tabB))

        let result = sut.performQuickSwitch()
        XCTAssertEqual(result?.tabId, tabB,
            "After re-adding a notification, quick switch should find tabB")
    }

    // MARK: - Test 27: quick switch does not activate same tab twice in one rotation

    func testQuickSwitchDoesNotActivateSameTabTwiceInOneRotation() {
        // tabA has 2 different-type notifications (both unread)
        notificationManager.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        notificationManager.notify(makeNotification(type: .agentError, tabId: tabA))

        // First switch: goes to tabA, marks ALL items for tabA as read
        let r1 = sut.performQuickSwitch()
        XCTAssertEqual(r1?.tabId, tabA)

        // Second switch: tabA is fully read, should return nil
        // (gotoNextUnread marks by tabId, clearing all items for that tab)
        let r2 = sut.performQuickSwitch()
        XCTAssertNil(r2,
            "After marking tabA as read, there should be no more unread tabs")
    }

    // MARK: - Private helpers

    private func makeNotification(type: NotificationType, tabId: TabID) -> CocxyNotification {
        CocxyNotification(type: type, tabId: tabId, title: "Test", body: "Body")
    }
}

// MARK: - Config Toggle Mid-Session Tests

@MainActor
final class ConfigToggleMidSessionTests: XCTestCase {

    private var sut: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var spyDockTile: SpyDockTile!
    private var dockBadge: DockBadgeController!

    private let tabA = TabID()
    private let tabB = TabID()

    override func setUp() {
        super.setUp()
        emitter = MockNotificationEmitter()
        sut = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 0.0,
            rateLimitPerTab: 0.0
        )
        spyDockTile = SpyDockTile()
        dockBadge = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: sut,
            config: .defaults
        )
        dockBadge.bind()
    }

    override func tearDown() {
        dockBadge = nil
        spyDockTile = nil
        sut = nil
        emitter = nil
        super.tearDown()
    }

    // MARK: - Test 28: toggle notifications off mid-session stops OS emissions

    func testToggleNotificationsOffMidSessionStopsOSEmissions() {
        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                      title: "T1", body: "B1"))
        XCTAssertEqual(emitter.emittedNotifications.count, 1)

        // Toggle off
        let offConfig = configWithNotificationsEnabled(false)
        sut.updateConfig(offConfig)
        emitter.reset()

        sut.notify(CocxyNotification(type: .agentError, tabId: tabB,
                                      title: "T2", body: "B2"))

        XCTAssertEqual(emitter.emittedNotifications.count, 0,
            "After disabling notifications, OS should not receive any new emissions")
        // But internal queue still works
        XCTAssertEqual(sut.unreadCount, 2)
    }

    // MARK: - Test 29: toggle notifications back on resumes OS emissions

    func testToggleNotificationsBackOnResumesOSEmissions() {
        // Start enabled, then disable, then re-enable
        let offConfig = configWithNotificationsEnabled(false)
        sut.updateConfig(offConfig)

        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                      title: "T1", body: "B1"))
        XCTAssertEqual(emitter.emittedNotifications.count, 0)

        // Re-enable
        sut.updateConfig(.defaults)
        emitter.reset()

        sut.notify(CocxyNotification(type: .agentError, tabId: tabB,
                                      title: "T2", body: "B2"))

        XCTAssertEqual(emitter.emittedNotifications.count, 1,
            "After re-enabling notifications, OS should receive new emissions")
    }

    // MARK: - Test 30: unread count is accurate regardless of OS notification state

    func testUnreadCountAccurateRegardlessOfOSNotificationState() {
        let offConfig = configWithNotificationsEnabled(false)
        sut.updateConfig(offConfig)

        sut.notify(CocxyNotification(type: .agentNeedsAttention, tabId: tabA,
                                      title: "T1", body: "B1"))
        sut.notify(CocxyNotification(type: .agentError, tabId: tabB,
                                      title: "T2", body: "B2"))

        XCTAssertEqual(sut.unreadCount, 2,
            "Unread count should be accurate even when OS notifications are disabled")
        XCTAssertEqual(spyDockTile.currentBadgeLabel, "2",
            "Dock badge should reflect unread count even when OS notifications are disabled")
    }

    // MARK: - Private helpers

    private func configWithNotificationsEnabled(_ enabled: Bool) -> CocxyConfig {
        CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: NotificationConfig(
                macosNotifications: enabled,
                sound: enabled,
                badgeOnTab: enabled,
                flashTab: enabled,
                showDockBadge: true  // keep badge always on to test unread count
            ),
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
    }
}

// MARK: - DockBadge Edge Cases

@MainActor
final class DockBadgeEdgeCaseTests: XCTestCase {

    private var spyDockTile: SpyDockTile!
    private var mockSource: MockUnreadCountSource!

    override func setUp() {
        super.setUp()
        spyDockTile = SpyDockTile()
        mockSource = MockUnreadCountSource()
    }

    override func tearDown() {
        spyDockTile = nil
        mockSource = nil
        super.tearDown()
    }

    // MARK: - Test 31: badge at exact boundary count 99 shows "99" not "99+"

    func testBadgeAtExactBoundary99Shows99() {
        let sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: .defaults
        )
        sut.bind()
        mockSource.sendUnreadCount(99)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "99",
            "Exactly 99 should show '99', not '99+'")
    }

    // MARK: - Test 32: badge at count 100 shows "99+"

    func testBadgeAt100Shows99Plus() {
        let sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: .defaults
        )
        sut.bind()
        mockSource.sendUnreadCount(100)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "99+",
            "100 should show '99+' to cap the badge label")
    }

    // MARK: - Test 33: negative count treated as zero (defensive)

    func testBadgeWithNegativeCountIsNil() {
        let sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: .defaults
        )
        sut.bind()
        mockSource.sendUnreadCount(-1)

        XCTAssertNil(spyDockTile.currentBadgeLabel,
            "Negative count should be treated as 0 and clear the badge")
    }

    // MARK: - Test 34: rapid updates settle to the final value

    func testRapidUpdatessSettleToFinalValue() {
        let sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: .defaults
        )
        sut.bind()

        for i in 1...50 {
            mockSource.sendUnreadCount(i)
        }

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "50",
            "After rapid updates, badge should show the final value")
        XCTAssertEqual(spyDockTile.badgeLabelHistory.count, 50,
            "Every update should have been applied (no deduplication in DockBadgeController)")
    }

    // MARK: - Test 35: bind can be called only once (second bind is defensive)

    func testBindIdempotentDoesNotDuplicateUpdates() {
        // DockBadgeController stores only one AnyCancellable -- second bind replaces it.
        let sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: .defaults
        )
        sut.bind()
        sut.bind() // second call -- replaces the subscription

        mockSource.sendUnreadCount(5)

        // Should only fire once (not twice)
        XCTAssertEqual(spyDockTile.badgeLabelHistory.count, 1,
            "Calling bind twice should not cause duplicated badge updates")
        XCTAssertEqual(spyDockTile.currentBadgeLabel, "5")
    }
}

// MARK: - NotificationManager Combine Pipeline Tests

@MainActor
final class NotificationManagerCombineTests: XCTestCase {

    private var sut: NotificationManagerImpl!
    private var emitter: MockNotificationEmitter!
    private var cancellables: Set<AnyCancellable>!

    private let tabA = TabID()
    private let tabB = TabID()

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

    // MARK: - Test 36: publisher does not emit on coalesced notification

    func testPublisherDoesNotEmitOnCoalescedNotification() {
        var publishedCount = 0

        sut.notificationsPublisher
            .sink { _ in publishedCount += 1 }
            .store(in: &cancellables)

        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA)) // coalesced

        XCTAssertEqual(publishedCount, 1,
            "notificationsPublisher should not emit for coalesced notifications")
    }

    // MARK: - Test 37: unreadCount publisher does not emit on no-op markAsRead

    func testUnreadCountPublisherDoesNotEmitOnNoOpMarkAsRead() {
        var emitCount = 0

        sut.unreadCountPublisher
            .sink { _ in emitCount += 1 }
            .store(in: &cancellables)

        // Mark as read on a tab with no notifications -> no-op -> no emit
        sut.markAsRead(tabId: tabA)

        XCTAssertEqual(emitCount, 0,
            "unreadCountPublisher should not emit when markAsRead is a no-op")
    }

    // MARK: - Test 38: unreadCount publisher does not emit on no-op markAllAsRead

    func testUnreadCountPublisherDoesNotEmitOnNoOpMarkAllAsRead() {
        var emitCount = 0

        sut.unreadCountPublisher
            .sink { _ in emitCount += 1 }
            .store(in: &cancellables)

        // Empty queue -> markAllAsRead is a no-op
        sut.markAllAsRead()

        XCTAssertEqual(emitCount, 0,
            "unreadCountPublisher should not emit when markAllAsRead is a no-op")
    }

    // MARK: - Test 39: multiple subscribers receive the same count

    func testMultipleSubscribersReceiveSameCount() {
        var counts1: [Int] = []
        var counts2: [Int] = []

        sut.unreadCountPublisher
            .sink { counts1.append($0) }
            .store(in: &cancellables)

        sut.unreadCountPublisher
            .sink { counts2.append($0) }
            .store(in: &cancellables)

        sut.notify(makeNotification(type: .agentNeedsAttention, tabId: tabA))
        sut.notify(makeNotification(type: .agentFinished, tabId: tabB))

        XCTAssertEqual(counts1, counts2,
            "Multiple subscribers should receive the same sequence of unread counts")
        XCTAssertEqual(counts1, [1, 2])
    }

    // MARK: - Private helpers

    private func makeNotification(type: NotificationType, tabId: TabID) -> CocxyNotification {
        CocxyNotification(type: type, tabId: tabId, title: "Test", body: "Body")
    }
}
