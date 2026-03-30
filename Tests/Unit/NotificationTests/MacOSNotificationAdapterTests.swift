// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacOSNotificationAdapterTests.swift - Tests for the macOS notification adapter (T-031).

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Spy Notification Center

/// Test double that records UNNotificationCenter interactions without touching
/// real system APIs. Conforms to `NotificationCenterProviding`, an abstraction
/// injected into `MacOSNotificationAdapter`.
@MainActor
final class SpyNotificationCenter: NotificationCenterProviding {
    private(set) var addedRequests: [NotificationRequestSnapshot] = []
    private(set) var authorizationRequestCount: Int = 0
    var authorizationGranted: Bool = true

    func requestAuthorization(options: NotificationAuthorizationOptions) async -> Bool {
        authorizationRequestCount += 1
        return authorizationGranted
    }

    func add(_ request: NotificationRequestSnapshot) {
        addedRequests.append(request)
    }

    func reset() {
        addedRequests.removeAll()
        authorizationRequestCount = 0
    }
}

// MARK: - Spy Tab Router

/// Test double that records tab routing requests triggered by notification click.
@MainActor
final class SpyTabRouter: NotificationTabRouting {
    private(set) var routedTabIds: [TabID] = []

    func activateTab(id: TabID) {
        routedTabIds.append(id)
    }
}

// MARK: - MacOS Notification Adapter Tests

/// Tests for `MacOSNotificationAdapter`.
///
/// Covers:
/// - Notification content mapping (title, body, categoryIdentifier, userInfo).
/// - Permission request flow.
/// - Delegate routing: notification click activates the correct tab.
/// - Foreground presentation logic (show if tab is not active).
/// - Sound configuration from CocxyConfig.
@MainActor
final class MacOSNotificationAdapterTests: XCTestCase {

    private var sut: MacOSNotificationAdapter!
    private var spyCenter: SpyNotificationCenter!
    private var spyRouter: SpyTabRouter!
    private var config: CocxyConfig!

    private let tabA = TabID()
    private let tabB = TabID()

    override func setUp() {
        super.setUp()
        spyCenter = SpyNotificationCenter()
        spyRouter = SpyTabRouter()
        config = .defaults
        sut = MacOSNotificationAdapter(
            notificationCenter: spyCenter,
            tabRouter: spyRouter,
            config: config
        )
    }

    override func tearDown() {
        sut = nil
        spyCenter = nil
        spyRouter = nil
        super.tearDown()
    }

    // MARK: - 1. emit() creates notification with correct title and body

    func testEmitCreatesNotificationWithCorrectTitleAndBody() {
        let notification = CocxyNotification(
            type: .agentNeedsAttention,
            tabId: tabA,
            title: "Claude Code needs your input",
            body: "Tab \"Terminal 1\" is waiting for input."
        )

        sut.emit(notification)

        XCTAssertEqual(spyCenter.addedRequests.count, 1)
        let request = spyCenter.addedRequests.first
        XCTAssertEqual(request?.title, "Claude Code needs your input")
        XCTAssertEqual(request?.body, "Tab \"Terminal 1\" is waiting for input.")
    }

    // MARK: - 2. emit() sets correct categoryIdentifier

    func testEmitSetsCategoryIdentifier() {
        let notification = CocxyNotification(
            type: .agentFinished,
            tabId: tabA,
            title: "Done",
            body: "Task completed"
        )

        sut.emit(notification)

        XCTAssertEqual(spyCenter.addedRequests.first?.categoryIdentifier, "COCXY_AGENT_STATE")
    }

    // MARK: - 3. emit() includes tabID in userInfo

    func testEmitIncludesTabIdInUserInfo() {
        let notification = CocxyNotification(
            type: .agentError,
            tabId: tabA,
            title: "Error",
            body: "Something went wrong"
        )

        sut.emit(notification)

        let userInfo = spyCenter.addedRequests.first?.userInfo
        XCTAssertEqual(userInfo?["tabID"], tabA.rawValue.uuidString)
    }

    // MARK: - 4. emit() includes sound when config enables it

    func testEmitIncludesSoundWhenEnabled() {
        let soundConfig = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: NotificationConfig(
                macosNotifications: true,
                sound: true,
                badgeOnTab: true,
                flashTab: true,
                showDockBadge: true,
                soundFinished: "default",
                soundAttention: "default",
                soundError: "default"
            ),
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        sut = MacOSNotificationAdapter(
            notificationCenter: spyCenter,
            tabRouter: spyRouter,
            config: soundConfig
        )

        let notification = CocxyNotification(
            type: .agentNeedsAttention,
            tabId: tabA,
            title: "Test",
            body: "Body"
        )
        sut.emit(notification)

        XCTAssertTrue(spyCenter.addedRequests.first?.hasSound ?? false)
    }

    // MARK: - 5. emit() omits sound when config disables it

    func testEmitOmitsSoundWhenDisabled() {
        let silentConfig = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: NotificationConfig(
                macosNotifications: true,
                sound: false,
                badgeOnTab: true,
                flashTab: true,
                showDockBadge: true,
                soundFinished: "default",
                soundAttention: "default",
                soundError: "default"
            ),
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        sut = MacOSNotificationAdapter(
            notificationCenter: spyCenter,
            tabRouter: spyRouter,
            config: silentConfig
        )

        let notification = CocxyNotification(
            type: .agentNeedsAttention,
            tabId: tabA,
            title: "Test",
            body: "Body"
        )
        sut.emit(notification)

        XCTAssertFalse(spyCenter.addedRequests.first?.hasSound ?? true)
    }

    // MARK: - 6. requestPermissionIfNeeded calls authorization

    func testRequestPermissionIfNeededCallsAuthorization() async {
        await sut.requestPermissionIfNeeded()

        XCTAssertEqual(spyCenter.authorizationRequestCount, 1)
    }

    // MARK: - 7. requestPermissionIfNeeded does not re-request after grant

    func testRequestPermissionIfNeededDoesNotReRequestAfterGrant() async {
        spyCenter.authorizationGranted = true
        await sut.requestPermissionIfNeeded()
        await sut.requestPermissionIfNeeded()

        // Should only request once after first grant.
        XCTAssertEqual(spyCenter.authorizationRequestCount, 1)
    }

    // MARK: - 8. requestPermissionIfNeeded does not re-request after denial

    func testRequestPermissionIfNeededDoesNotReRequestAfterDenial() async {
        spyCenter.authorizationGranted = false
        await sut.requestPermissionIfNeeded()
        await sut.requestPermissionIfNeeded()

        // Should only request once after denial too.
        XCTAssertEqual(spyCenter.authorizationRequestCount, 1)
    }

    // MARK: - 9. handleNotificationClick routes to correct tab

    func testHandleNotificationClickRoutesToCorrectTab() {
        sut.handleNotificationClick(tabIdString: tabA.rawValue.uuidString)

        XCTAssertEqual(spyRouter.routedTabIds.count, 1)
        XCTAssertEqual(spyRouter.routedTabIds.first, tabA)
    }

    // MARK: - 10. handleNotificationClick with invalid UUID is no-op

    func testHandleNotificationClickWithInvalidUUIDIsNoOp() {
        sut.handleNotificationClick(tabIdString: "not-a-uuid")

        XCTAssertTrue(spyRouter.routedTabIds.isEmpty)
    }

    // MARK: - 11. shouldShowForegroundNotification returns true when tab not active

    func testShouldShowForegroundNotificationWhenTabNotActive() {
        let result = sut.shouldShowForegroundNotification(
            forTabId: tabA,
            activeTabId: tabB
        )

        XCTAssertTrue(result)
    }

    // MARK: - 12. shouldShowForegroundNotification returns false when tab is active

    func testShouldShowForegroundNotificationWhenTabIsActive() {
        let result = sut.shouldShowForegroundNotification(
            forTabId: tabA,
            activeTabId: tabA
        )

        XCTAssertFalse(result)
    }
}
