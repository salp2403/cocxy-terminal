// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickSwitchControllerTests.swift - Tests for the Quick Switch feature (T-032).

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Mock Notification Manager for Quick Switch

/// Test double for NotificationManaging that provides controlled unread tab behavior.
@MainActor
final class MockNotificationManagerForQuickSwitch: NotificationManaging {
    /// The tab IDs that will be returned by successive gotoNextUnread calls.
    var nextUnreadTabIds: [TabID?] = []
    private var nextUnreadIndex: Int = 0
    private(set) var gotoNextUnreadCallCount: Int = 0
    private(set) var markAsReadTabIds: [TabID] = []

    var unreadCount: Int = 0

    var notificationsPublisher: AnyPublisher<CocxyNotification, Never> {
        Empty().eraseToAnyPublisher()
    }

    var unreadCountPublisher: AnyPublisher<Int, Never> {
        Empty().eraseToAnyPublisher()
    }

    func notify(_ notification: CocxyNotification) {}

    func markAsRead(tabId: TabID) {
        markAsReadTabIds.append(tabId)
    }

    func markAllAsRead() {}

    func gotoNextUnread() -> TabID? {
        gotoNextUnreadCallCount += 1
        guard nextUnreadIndex < nextUnreadTabIds.count else { return nil }
        let result = nextUnreadTabIds[nextUnreadIndex]
        nextUnreadIndex += 1
        return result
    }
}

// MARK: - Mock Tab Manager for Quick Switch

/// Test double for tab activation tracking.
@MainActor
final class MockTabActivator: TabActivating {
    private(set) var activatedTabIds: [TabID] = []
    var activeTabID: TabID?

    func setActive(id: TabID) {
        activatedTabIds.append(id)
        activeTabID = id
    }
}

// MARK: - Quick Switch Controller Tests

/// Tests for `QuickSwitchController`.
///
/// Covers:
/// - Quick switch activates the correct tab.
/// - Quick switch returns nil when no pending attention.
/// - Circular rotation through multiple pending tabs.
/// - Mark as read after switch.
/// - Integration with NotificationManager.gotoNextUnread.
/// - Result reporting (which tab was activated, description).
@MainActor
final class QuickSwitchControllerTests: XCTestCase {

    private var sut: QuickSwitchController!
    private var mockNotificationManager: MockNotificationManagerForQuickSwitch!
    private var mockTabActivator: MockTabActivator!

    private let tabA = TabID()
    private let tabB = TabID()
    private let tabC = TabID()

    override func setUp() {
        super.setUp()
        mockNotificationManager = MockNotificationManagerForQuickSwitch()
        mockTabActivator = MockTabActivator()
        sut = QuickSwitchController(
            notificationManager: mockNotificationManager,
            tabActivator: mockTabActivator
        )
    }

    override func tearDown() {
        sut = nil
        mockNotificationManager = nil
        mockTabActivator = nil
        super.tearDown()
    }

    // MARK: - 1. Quick switch activates correct tab

    func testQuickSwitchActivatesCorrectTab() {
        mockNotificationManager.nextUnreadTabIds = [tabA]

        let result = sut.performQuickSwitch()

        XCTAssertEqual(mockTabActivator.activatedTabIds.count, 1)
        XCTAssertEqual(mockTabActivator.activatedTabIds.first, tabA)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tabId, tabA)
    }

    // MARK: - 2. Quick switch returns nil when no pending

    func testQuickSwitchReturnsNilWhenNoPending() {
        mockNotificationManager.nextUnreadTabIds = []

        let result = sut.performQuickSwitch()

        XCTAssertNil(result)
        XCTAssertTrue(mockTabActivator.activatedTabIds.isEmpty)
    }

    // MARK: - 3. Rotation through 3 pending tabs

    func testQuickSwitchRotatesThroughMultiplePendingTabs() {
        mockNotificationManager.nextUnreadTabIds = [tabA, tabB, tabC]

        let result1 = sut.performQuickSwitch()
        let result2 = sut.performQuickSwitch()
        let result3 = sut.performQuickSwitch()

        XCTAssertEqual(result1?.tabId, tabA)
        XCTAssertEqual(result2?.tabId, tabB)
        XCTAssertEqual(result3?.tabId, tabC)
        XCTAssertEqual(mockTabActivator.activatedTabIds, [tabA, tabB, tabC])
    }

    // MARK: - 4. After rotation exhausted, returns nil

    func testQuickSwitchReturnsNilAfterRotationExhausted() {
        mockNotificationManager.nextUnreadTabIds = [tabA]

        _ = sut.performQuickSwitch()
        let result = sut.performQuickSwitch()

        XCTAssertNil(result)
    }

    // MARK: - 5. gotoNextUnread is called on NotificationManager

    func testQuickSwitchCallsGotoNextUnread() {
        mockNotificationManager.nextUnreadTabIds = [tabA]

        _ = sut.performQuickSwitch()

        XCTAssertEqual(mockNotificationManager.gotoNextUnreadCallCount, 1)
    }

    // MARK: - 6. QuickSwitchResult contains description

    func testQuickSwitchResultContainsDescription() {
        mockNotificationManager.nextUnreadTabIds = [tabA]

        let result = sut.performQuickSwitch()

        XCTAssertNotNil(result)
        XCTAssertFalse(result!.description.isEmpty)
    }

    // MARK: - 7. Quick switch does not activate when manager returns nil

    func testQuickSwitchDoesNotActivateWhenManagerReturnsNil() {
        mockNotificationManager.nextUnreadTabIds = [nil]

        let result = sut.performQuickSwitch()

        XCTAssertNil(result)
        XCTAssertTrue(mockTabActivator.activatedTabIds.isEmpty)
    }

    // MARK: - 8. Multiple switches call gotoNextUnread each time

    func testMultipleSwitchesCallGotoNextUnreadEachTime() {
        mockNotificationManager.nextUnreadTabIds = [tabA, tabB]

        _ = sut.performQuickSwitch()
        _ = sut.performQuickSwitch()

        XCTAssertEqual(mockNotificationManager.gotoNextUnreadCallCount, 2)
    }

    // MARK: - 9. QuickSwitchResult tabId matches activated tab

    func testQuickSwitchResultTabIdMatchesActivatedTab() {
        mockNotificationManager.nextUnreadTabIds = [tabB]

        let result = sut.performQuickSwitch()

        XCTAssertEqual(result?.tabId, tabB)
        XCTAssertEqual(mockTabActivator.activatedTabIds.first, tabB)
    }
}
