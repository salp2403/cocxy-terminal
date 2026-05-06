// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateSessionTests.swift - Tests for AppDelegate session integration (T-036).

import XCTest
import AppKit
@testable import CocxyTerminal

// MARK: - AppDelegate Session Integration Tests

/// Tests that AppDelegate correctly initializes the session manager and
/// quick terminal view model, and that captureCurrentSession works.
@MainActor
final class AppDelegateSessionIntegrationTests: XCTestCase {

    private var tempSessionsDirectory: URL?

    override func tearDown() {
        if let tempSessionsDirectory {
            try? FileManager.default.removeItem(at: tempSessionsDirectory)
        }
        tempSessionsDirectory = nil
        super.tearDown()
    }

    // MARK: - Test 1: Session manager is nil before launch

    func testSessionManagerIsNilBeforeLaunch() {
        let delegate = AppDelegate()
        XCTAssertNil(delegate.sessionManager,
                     "SessionManager must be nil before applicationDidFinishLaunching")
    }

    // MARK: - Test 2: Quick terminal view model is nil before launch

    func testQuickTerminalViewModelIsNilBeforeLaunch() {
        let delegate = AppDelegate()
        XCTAssertNil(delegate.quickTerminalViewModel,
                     "QuickTerminalViewModel must be nil before applicationDidFinishLaunching")
    }

    // MARK: - Test 3: captureCurrentSession produces valid session without window controller

    func testCaptureCurrentSessionWithoutWindowController() {
        let delegate = AppDelegate()
        let session = delegate.captureCurrentSession()

        XCTAssertEqual(session.version, Session.currentVersion,
                       "Captured session must have current version")
        XCTAssertEqual(session.windows.count, 1,
                       "Must have exactly one window state")
        XCTAssertTrue(session.windows[0].tabs.isEmpty,
                      "No window controller means no tabs")
    }

    func testStartSessionAutoSaveIfNeededStartsTimer() {
        let delegate = AppDelegate()
        delegate.sessionManager = makeSessionManager()

        delegate.startSessionAutoSaveIfNeeded(using: makeConfig(autoSave: true, interval: 30))

        XCTAssertTrue(delegate.sessionManager?.isAutoSaveRunning == true)
    }

    func testStartSessionAutoSaveIfNeededStopsTimerWhenDisabled() {
        let delegate = AppDelegate()
        delegate.sessionManager = makeSessionManager()

        delegate.startSessionAutoSaveIfNeeded(using: makeConfig(autoSave: true, interval: 30))
        XCTAssertTrue(delegate.sessionManager?.isAutoSaveRunning == true)

        delegate.startSessionAutoSaveIfNeeded(using: makeConfig(autoSave: false, interval: 30))

        XCTAssertFalse(delegate.sessionManager?.isAutoSaveRunning == true)
    }

    func testHasRestorableSessionOnLaunchIsFalseWithoutSavedTabs() throws {
        let delegate = AppDelegate()
        let manager = makeSessionManager()
        delegate.sessionManager = manager

        let emptySession = Session(
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [],
                    activeTabIndex: 0
                ),
            ]
        )
        try manager.saveSession(emptySession, named: nil)

        XCTAssertFalse(
            delegate.hasRestorableSessionOnLaunch(),
            "Launch should not defer bootstrap surface creation when the saved session has no tabs"
        )
        XCTAssertNil(
            delegate.pendingRestorableLaunchSession,
            "Empty saved sessions must not be cached for launch restore"
        )
    }

    func testHasRestorableSessionOnLaunchIsTrueWhenSavedSessionHasTabs() throws {
        let delegate = AppDelegate()
        let manager = makeSessionManager()
        delegate.sessionManager = manager

        let session = Session(
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: "Galf",
                            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                            splitTree: .leaf(
                                workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                command: nil
                            )
                        ),
                    ],
                    activeTabIndex: 0
                ),
            ]
        )
        try manager.saveSession(session, named: nil)

        XCTAssertTrue(
            delegate.hasRestorableSessionOnLaunch(),
            "Launch should defer bootstrap surface creation when a real saved session can be restored"
        )
        XCTAssertEqual(
            delegate.pendingRestorableLaunchSession?.windows.first?.tabs.first?.title,
            "Galf",
            "The launch restore preflight should cache the decoded session for restoreSessionOnLaunch"
        )
    }

    func testRestoreSessionOnLaunchConsumesCachedSessionAndShowsOpaqueShield() throws {
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        let delegate = AppDelegate()
        delegate.installTerminalEngineForTesting(bridge)
        delegate.installWindowControllerForTesting(controller)
        let trackingWindow = LaunchTrackingRestoreWindow(
            contentRect: controller.window?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: controller.window?.styleMask ?? [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        trackingWindow.contentView = controller.window?.contentView
        trackingWindow.backgroundColor = CocxyColors.base.withAlphaComponent(0.35)
        controller.window = trackingWindow

        let manager = makeSessionManager()
        delegate.sessionManager = manager

        try manager.saveSession(makeSession(tabTitle: "Cached launch"), named: nil)
        XCTAssertTrue(delegate.hasRestorableSessionOnLaunch())

        try manager.saveSession(makeEmptySession(), named: nil)
        delegate.restoreSessionOnLaunch()

        XCTAssertNil(
            delegate.pendingRestorableLaunchSession,
            "restoreSessionOnLaunch should consume the preflight cache"
        )
        XCTAssertTrue(
            controller.tabManager.tabs.contains { $0.title == "Cached launch" },
            "restoreSessionOnLaunch should restore the cached launch snapshot instead of re-reading a changed file"
        )
        XCTAssertTrue(
            controller.window?.isVisible == true,
            "Launch restore should make an opaque shell visible before rebuilding the restored tabs"
        )
        XCTAssertTrue(
            controller.sessionRestoreShieldView?.layer?.isOpaque == true,
            "The visible restore shell must stay opaque while terminal surfaces repaint"
        )
        XCTAssertEqual(
            trackingWindow.displayIfNeededCount,
            0,
            "Launch restore should not force a synchronous display pass before restored terminal surfaces exist"
        )
        controller.window?.orderOut(nil)
    }

    private func makeSessionManager() -> SessionManagerImpl {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDelegateSessionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        tempSessionsDirectory = directory
        return SessionManagerImpl(sessionsDirectory: directory)
    }

    private func makeConfig(autoSave: Bool, interval: Int) -> CocxyConfig {
        CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: SessionsConfig(
                autoSave: autoSave,
                autoSaveInterval: interval,
                restoreOnLaunch: true
            )
        )
    }

    private func makeSession(tabTitle: String) -> Session {
        Session(
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [
                        TabState(
                            id: TabID(),
                            title: tabTitle,
                            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                            splitTree: .leaf(
                                workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
                                command: nil
                            )
                        ),
                    ],
                    activeTabIndex: 0
                ),
            ]
        )
    }

    private func makeEmptySession() -> Session {
        Session(
            windows: [
                WindowState(
                    frame: CodableRect(x: 0, y: 0, width: 1200, height: 800),
                    isFullScreen: false,
                    tabs: [],
                    activeTabIndex: 0
                ),
            ]
        )
    }

}

private final class LaunchTrackingRestoreWindow: NSWindow {
    private(set) var displayIfNeededCount = 0

    override func displayIfNeeded() {
        displayIfNeededCount += 1
        super.displayIfNeeded()
    }
}
