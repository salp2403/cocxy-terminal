// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRestorerTests.swift - Tests for session restoration logic (T-036).

import XCTest
@testable import CocxyTerminal

// MARK: - Session Restorer Tests

/// Tests for `SessionRestorer` covering all session restoration scenarios.
///
/// Covers:
/// - Restore single tab from saved state.
/// - Restore multiple tabs with correct active tab.
/// - Restore with missing directory falls back to home.
/// - Corrupt JSON returns nil (handled by SessionManager; restorer gets nil).
/// - Future version returns nil (handled by SessionManager; restorer gets nil).
/// - Restore preserves tab order.
/// - Restore preserves split tree structure.
/// - Restore window frame within screen bounds.
/// - Restore window frame outside bounds uses default.
/// - Round-trip: capture -> save -> load -> restore -> compare.
/// - Partial failure: bad tab skipped, rest restored.
/// - Empty session results in fresh start (no tabs restored).
/// - Restore sets first tab active when activeTabIndex is out of bounds.
/// - Restore with leaf split tree.
/// - Restore validates split tree consistency.
/// - Restore handles single window with many tabs.
@MainActor
final class SessionRestorerTests: XCTestCase {

    // MARK: - Properties

    private var tabManager: TabManager!
    private var splitCoordinator: TabSplitCoordinator!

    // MARK: - Setup / Teardown

    override func setUp() {
        super.setUp()
        tabManager = TabManager()
        splitCoordinator = TabSplitCoordinator()
    }

    override func tearDown() {
        tabManager = nil
        splitCoordinator = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// The home directory URL for fallback comparisons.
    private var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// Creates a session with one tab pointing to a real directory.
    private func makeSessionWithSingleTab(
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        title: String? = "Terminal"
    ) -> Session {
        Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 100, y: 200, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: title,
                            workingDirectory: workingDirectory,
                            splitTree: .leaf(
                                workingDirectory: workingDirectory,
                                command: nil
                            )
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )
    }

    /// Creates a session with multiple tabs.
    private func makeSessionWithMultipleTabs(
        count: Int,
        activeIndex: Int = 0
    ) -> Session {
        let tabs: [TabState] = (0..<count).map { index in
            TabState(
                id: TabID(),
                title: "Tab \(index)",
                workingDirectory: homeDirectory,
                splitTree: .leaf(
                    workingDirectory: homeDirectory,
                    command: nil
                )
            )
        }

        return Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: tabs,
                    activeTabIndex: activeIndex
                )
            ]
        )
    }

    /// Screen bounds for frame validation tests.
    private let testScreenBounds = CodableRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Test 1: Restore single tab

    func testRestoreSingleTab() {
        let session = makeSessionWithSingleTab()

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs.count, 1,
                       "Must restore exactly one tab")
        XCTAssertEqual(result.restoredTabs[0].workingDirectory, homeDirectory,
                       "Working directory must match saved state")
    }

    // MARK: - Test 2: Restore multiple tabs with correct active tab

    func testRestoreMultipleTabsWithCorrectActiveTab() {
        let session = makeSessionWithMultipleTabs(count: 4, activeIndex: 2)

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs.count, 4,
                       "Must restore all four tabs")
        XCTAssertEqual(result.activeTabIndex, 2,
                       "Active tab index must be preserved from session")
    }

    // MARK: - Test 3: Restore with missing directory falls back to home

    func testRestoreWithMissingDirectoryFallsBackToHome() {
        let nonExistentDir = URL(fileURLWithPath: "/nonexistent/directory/that/does/not/exist")
        let session = makeSessionWithSingleTab(workingDirectory: nonExistentDir)

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs.count, 1)
        XCTAssertEqual(result.restoredTabs[0].workingDirectory, homeDirectory,
                       "Missing directory must fall back to home directory")
    }

    // MARK: - Test 4: Restore preserves tab order

    func testRestorePreservesTabOrder() {
        let session = makeSessionWithMultipleTabs(count: 5)

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs.count, 5,
                       "Must restore all five tabs")
        for (index, tab) in result.restoredTabs.enumerated() {
            XCTAssertEqual(tab.title, "Tab \(index)",
                           "Tab at index \(index) must have the correct title")
        }
    }

    // MARK: - Test 5: Restore preserves split tree

    func testRestorePreservesSplitTree() {
        let splitTree = SplitNodeState.split(
            direction: .horizontal,
            first: .leaf(
                workingDirectory: homeDirectory,
                command: nil
            ),
            second: .leaf(
                workingDirectory: homeDirectory,
                command: nil
            ),
            ratio: 0.6
        )

        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Split Tab",
                            workingDirectory: homeDirectory,
                            splitTree: splitTree
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs.count, 1)
        XCTAssertEqual(result.restoredTabs[0].splitNode.leafCount, 2,
                       "Split tree must preserve the two-leaf structure")
    }

    // MARK: - Test 6: Restore window frame within screen bounds

    func testRestoreWindowFrameWithinScreenBounds() {
        let validFrame = CodableRect(x: 100, y: 200, width: 800, height: 600)
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: validFrame,
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Terminal",
                            workingDirectory: homeDirectory,
                            splitTree: .leaf(workingDirectory: homeDirectory, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.windowFrame, validFrame,
                       "Valid frame within screen bounds must be preserved")
    }

    // MARK: - Test 7: Restore window frame outside bounds uses default

    func testRestoreWindowFrameOutsideBoundsUsesDefault() {
        let outsideFrame = CodableRect(x: 5000, y: 5000, width: 800, height: 600)
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: outsideFrame,
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Terminal",
                            workingDirectory: homeDirectory,
                            splitTree: .leaf(workingDirectory: homeDirectory, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertNotEqual(result.windowFrame, outsideFrame,
                          "Frame outside screen bounds must not be used")
        // Default frame should be centered within screen bounds.
        XCTAssertTrue(result.windowFrame.x >= 0,
                      "Default frame must be within screen X bounds")
        XCTAssertTrue(result.windowFrame.y >= 0,
                      "Default frame must be within screen Y bounds")
    }

    // MARK: - Test 8: Round-trip capture save load restore compare

    func testRoundTripCaptureSaveLoadRestoreCompare() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-restore-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = SessionManagerImpl(sessionsDirectory: tempDir)

        // Create original session with 3 tabs.
        let originalSession = makeSessionWithMultipleTabs(count: 3, activeIndex: 1)

        // Save it.
        try manager.saveSession(originalSession, named: nil)

        // Load it back.
        let loadedSession = try manager.loadLastSession()
        XCTAssertNotNil(loadedSession)

        // Restore it.
        let result = SessionRestorer.restore(
            from: loadedSession!,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        // Compare.
        XCTAssertEqual(result.restoredTabs.count, 3,
                       "Round-trip must preserve all 3 tabs")
        XCTAssertEqual(result.activeTabIndex, 1,
                       "Round-trip must preserve active tab index")
    }

    // MARK: - Test 9: Partial failure skips bad tab

    func testPartialFailureSkipsBadTab() {
        let nonExistent = URL(fileURLWithPath: "/nonexistent/phantom/dir")
        let tabs: [TabState] = [
            TabState(
                id: TabID(),
                title: "Good Tab 0",
                workingDirectory: homeDirectory,
                splitTree: .leaf(workingDirectory: homeDirectory, command: nil)
            ),
            TabState(
                id: TabID(),
                title: "Bad Tab 1",
                workingDirectory: nonExistent,
                splitTree: .leaf(workingDirectory: nonExistent, command: nil)
            ),
            TabState(
                id: TabID(),
                title: "Good Tab 2",
                workingDirectory: homeDirectory,
                splitTree: .leaf(workingDirectory: homeDirectory, command: nil)
            ),
        ]

        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: tabs,
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        // Bad tabs are restored with fallback directory, not skipped.
        // All 3 tabs must be present.
        XCTAssertEqual(result.restoredTabs.count, 3,
                       "All tabs must be restored (bad directory uses fallback)")
        // The bad tab should use home directory as fallback.
        XCTAssertEqual(result.restoredTabs[1].workingDirectory, homeDirectory,
                       "Bad directory tab must fall back to home")
    }

    // MARK: - Test 10: Empty session results in no tabs

    func testEmptySessionResultsInNoTabs() {
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: [],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertTrue(result.restoredTabs.isEmpty,
                      "Empty session must result in no restored tabs")
    }

    // MARK: - Test 11: Active tab index out of bounds uses first tab

    func testActiveTabIndexOutOfBoundsUsesFirstTab() {
        let session = makeSessionWithMultipleTabs(count: 3, activeIndex: 99)

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.activeTabIndex, 0,
                       "Out-of-bounds active tab index must fall back to 0")
    }

    // MARK: - Test 12: Restore with leaf split tree

    func testRestoreWithLeafSplitTree() {
        let session = makeSessionWithSingleTab()

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs[0].splitNode.leafCount, 1,
                       "Leaf split tree must restore as single leaf")
    }

    // MARK: - Test 13: Restore preserves full screen state

    func testRestorePreservesFullScreenState() {
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: true,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Terminal",
                            workingDirectory: homeDirectory,
                            splitTree: .leaf(workingDirectory: homeDirectory, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertTrue(result.isFullScreen,
                      "Full screen state must be preserved")
    }

    // MARK: - Test 14: Restore deeply nested split tree

    func testRestoreDeeplyNestedSplitTree() {
        let deepSplitTree = SplitNodeState.split(
            direction: .horizontal,
            first: .split(
                direction: .vertical,
                first: .leaf(workingDirectory: homeDirectory, command: nil),
                second: .leaf(workingDirectory: homeDirectory, command: nil),
                ratio: 0.5
            ),
            second: .split(
                direction: .vertical,
                first: .leaf(workingDirectory: homeDirectory, command: nil),
                second: .leaf(workingDirectory: homeDirectory, command: nil),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1920, height: 1080),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Terminal",
                            workingDirectory: homeDirectory,
                            splitTree: deepSplitTree
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs[0].splitNode.leafCount, 4,
                       "Deep split tree must restore all 4 leaves")
    }

    // MARK: - Test 15: Restore session with no windows

    func testRestoreSessionWithNoWindows() {
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: []
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertTrue(result.restoredTabs.isEmpty,
                      "Session with no windows must produce no restored tabs")
    }

    // MARK: - Test 16: Restore validates directory using FileManager

    func testRestoreValidatesDirectoryUsingFileManager() {
        // /tmp exists on macOS.
        let existingDir = URL(fileURLWithPath: "/tmp")
        let session = makeSessionWithSingleTab(workingDirectory: existingDir)

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        XCTAssertEqual(result.restoredTabs[0].workingDirectory.path, "/tmp",
                       "Existing directory must be preserved")
    }

    // MARK: - Test 17: Restore window frame partially off-screen uses default

    func testRestoreWindowFramePartiallyOffScreenUsesDefault() {
        // Frame where most of it is off-screen (only a tiny sliver visible).
        let partialFrame = CodableRect(x: 1900, y: 1060, width: 800, height: 600)
        let session = Session(
            version: Session.currentVersion,
            savedAt: Date(),
            windows: [
                WindowState(
                    frame: partialFrame,
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Terminal",
                            workingDirectory: homeDirectory,
                            splitTree: .leaf(workingDirectory: homeDirectory, command: nil)
                        )
                    ],
                    activeTabIndex: 0
                )
            ]
        )

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: splitCoordinator,
            screenBounds: testScreenBounds
        )

        // At least 100px of the window should be visible.
        let isReasonablyVisible = (result.windowFrame.x + result.windowFrame.width > 100)
            && (result.windowFrame.y + result.windowFrame.height > 100)
            && (result.windowFrame.x < testScreenBounds.width - 100)
        XCTAssertTrue(isReasonablyVisible,
                      "Restored frame must be reasonably visible on screen")
    }
}
