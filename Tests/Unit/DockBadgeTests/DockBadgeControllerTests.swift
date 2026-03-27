// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DockBadgeControllerTests.swift - Tests for the Dock Badge feature (T-033).

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Spy Dock Tile

/// Test double that records badge label changes without touching NSApp.dockTile.
@MainActor
final class SpyDockTile: DockTileProviding {
    private(set) var badgeLabelHistory: [String?] = []
    var currentBadgeLabel: String?

    func setBadgeLabel(_ label: String?) {
        currentBadgeLabel = label
        badgeLabelHistory.append(label)
    }
}

// MARK: - Mock Unread Count Publisher

/// Test double that provides a controllable unread count publisher for DockBadgeController.
@MainActor
final class MockUnreadCountSource: UnreadCountPublishing {
    private let subject = PassthroughSubject<Int, Never>()

    var unreadCountPublisher: AnyPublisher<Int, Never> {
        subject.eraseToAnyPublisher()
    }

    func sendUnreadCount(_ count: Int) {
        subject.send(count)
    }
}

// MARK: - Dock Badge Controller Tests

/// Tests for `DockBadgeController`.
///
/// Covers:
/// - Badge shows correct count.
/// - Badge is nil when count is 0.
/// - Badge updates on count change.
/// - Badge disabled via config.
/// - Badge caps at "99+".
/// - Badge clears when disabled mid-session.
/// - Multiple rapid updates settle to final value.
@MainActor
final class DockBadgeControllerTests: XCTestCase {

    private var sut: DockBadgeController!
    private var spyDockTile: SpyDockTile!
    private var mockSource: MockUnreadCountSource!

    override func setUp() {
        super.setUp()
        spyDockTile = SpyDockTile()
        mockSource = MockUnreadCountSource()
        sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: .defaults
        )
    }

    override func tearDown() {
        sut = nil
        spyDockTile = nil
        mockSource = nil
        super.tearDown()
    }

    // MARK: - 1. Badge shows correct count

    func testBadgeShowsCorrectCount() {
        sut.bind()
        mockSource.sendUnreadCount(3)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "3")
    }

    // MARK: - 2. Badge is nil when count is 0

    func testBadgeIsNilWhenCountIsZero() {
        sut.bind()
        mockSource.sendUnreadCount(3)
        mockSource.sendUnreadCount(0)

        XCTAssertNil(spyDockTile.currentBadgeLabel)
    }

    // MARK: - 3. Badge updates on count change

    func testBadgeUpdatesOnCountChange() {
        sut.bind()
        mockSource.sendUnreadCount(1)
        mockSource.sendUnreadCount(5)
        mockSource.sendUnreadCount(2)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "2")
        // History: "1", "5", "2"
        XCTAssertEqual(spyDockTile.badgeLabelHistory.compactMap({ $0 }), ["1", "5", "2"])
    }

    // MARK: - 4. Badge disabled via config

    func testBadgeDisabledViaConfig() {
        let disabledConfig = CocxyConfig(
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
        sut = DockBadgeController(
            dockTile: spyDockTile,
            unreadCountSource: mockSource,
            config: disabledConfig
        )

        sut.bind()
        mockSource.sendUnreadCount(5)

        XCTAssertNil(spyDockTile.currentBadgeLabel)
    }

    // MARK: - 5. Badge caps at 99+

    func testBadgeCapsAt99Plus() {
        sut.bind()
        mockSource.sendUnreadCount(150)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "99+")
    }

    // MARK: - 6. Badge shows exact count at boundary (99)

    func testBadgeShowsExactCountAt99() {
        sut.bind()
        mockSource.sendUnreadCount(99)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "99")
    }

    // MARK: - 7. Badge at count 100 shows 99+

    func testBadgeAt100Shows99Plus() {
        sut.bind()
        mockSource.sendUnreadCount(100)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "99+")
    }

    // MARK: - 8. Badge with count 1 shows "1"

    func testBadgeWithCountOneShowsOne() {
        sut.bind()
        mockSource.sendUnreadCount(1)

        XCTAssertEqual(spyDockTile.currentBadgeLabel, "1")
    }

    // MARK: - 9. Badge not bound does not receive updates

    func testBadgeNotBoundDoesNotReceiveUpdates() {
        // Do NOT call sut.bind()
        mockSource.sendUnreadCount(5)

        XCTAssertNil(spyDockTile.currentBadgeLabel)
        XCTAssertTrue(spyDockTile.badgeLabelHistory.isEmpty)
    }
}
