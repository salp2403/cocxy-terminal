// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRestoreV2Tests.swift - Tests for multi-window session save/restore (v2).

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Session Model V2 Tests

@Suite("Session Model V2")
struct SessionModelV2Tests {

    private let screenBounds = CodableRect(x: 0, y: 0, width: 1920, height: 1080)

    // MARK: - Version

    @Test("Session current version is 3")
    func currentVersionIs3() {
        #expect(Session.currentVersion == 3)
    }

    @Test("New session defaults to version 3")
    func newSessionDefaultsToV3() {
        let session = Session(windows: [])
        #expect(session.version == 3)
    }

    // MARK: - Focused Window Index

    @Test("Session preserves focused window index")
    func preservesFocusedWindowIndex() {
        let session = Session(
            windows: [makeWindowState(), makeWindowState()],
            focusedWindowIndex: 1
        )
        #expect(session.focusedWindowIndex == 1)
    }

    @Test("Session defaults focused window index to 0")
    func defaultsFocusedWindowTo0() {
        let session = Session(windows: [makeWindowState()])
        #expect(session.focusedWindowIndex == 0)
    }

    // MARK: - WindowState V2 Fields

    @Test("WindowState preserves windowID")
    func windowStatePreservesWindowID() {
        let id = WindowID()
        let state = WindowState(
            frame: CodableRect(x: 0, y: 0, width: 800, height: 600),
            isFullScreen: false,
            tabs: [],
            activeTabIndex: 0,
            windowID: id
        )
        #expect(state.windowID == id)
    }

    @Test("WindowState preserves displayIndex")
    func windowStatePreservesDisplayIndex() {
        let state = WindowState(
            frame: CodableRect(x: 0, y: 0, width: 800, height: 600),
            isFullScreen: false,
            tabs: [],
            activeTabIndex: 0,
            displayIndex: 2
        )
        #expect(state.displayIndex == 2)
    }

    // MARK: - V1 Migration (Codable Backwards Compatibility)

    @Test("V1 session decodes with focusedWindowIndex = 0")
    func v1DecodesWithDefaultFocusedIndex() throws {
        // Simulate a v1 JSON that has no focusedWindowIndex field.
        let v1JSON = """
        {
            "version": 1,
            "savedAt": 0,
            "windows": []
        }
        """
        let data = v1JSON.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let session = try decoder.decode(Session.self, from: data)
        #expect(session.focusedWindowIndex == 0)
        #expect(session.version == 1)
    }

    @Test("V1 WindowState decodes with nil windowID and displayIndex")
    func v1WindowStateDecodesNilFields() throws {
        let v1JSON = """
        {
            "frame": {"x": 100, "y": 100, "width": 800, "height": 600},
            "isFullScreen": false,
            "tabs": [],
            "activeTabIndex": 0
        }
        """
        let data = v1JSON.data(using: .utf8)!
        let state = try JSONDecoder().decode(WindowState.self, from: data)
        #expect(state.windowID == nil)
        #expect(state.displayIndex == nil)
    }

    @Test("V2 Session round-trips through JSON correctly")
    func v2RoundTrip() throws {
        let windowID = WindowID()
        let tabID = TabID()
        let sessionID = SessionID()
        let session = Session(
            windows: [
                WindowState(
                    frame: CodableRect(x: 50, y: 50, width: 1000, height: 700),
                    isFullScreen: false,
                    tabs: [TabState(
                        id: tabID,
                        sessionID: sessionID,
                        title: "Test",
                        workingDirectory: URL(fileURLWithPath: "/tmp"),
                        splitTree: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp"), command: nil)
                    )],
                    activeTabIndex: 0,
                    windowID: windowID,
                    displayIndex: 1
                )
            ],
            focusedWindowIndex: 0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)

        #expect(decoded.version == 3)
        #expect(decoded.focusedWindowIndex == 0)
        #expect(decoded.windows.count == 1)
        #expect(decoded.windows[0].windowID == windowID)
        #expect(decoded.windows[0].displayIndex == 1)
        #expect(decoded.windows[0].tabs.count == 1)
        #expect(decoded.windows[0].tabs[0].id == tabID)
        #expect(decoded.windows[0].tabs[0].sessionID == sessionID)
    }

    @Test("legacy tab state decodes with empty pane states")
    func legacyTabStateDecodesWithEmptyPaneStates() throws {
        let json = """
        {
            "id": {"rawValue": "\(UUID().uuidString)"},
            "sessionID": {"rawValue": "\(UUID().uuidString)"},
            "title": "Terminal",
            "workingDirectory": "file:///tmp/",
            "splitTree": {
                "leaf": {
                    "workingDirectory": "file:///tmp/",
                    "command": null
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let tab = try JSONDecoder().decode(TabState.self, from: data)
        #expect(tab.paneStates.isEmpty)
    }

    @Test("tab state round-trips panel and scroll pane metadata")
    func tabStateRoundTripsPaneMetadata() throws {
        let notebook = URL(fileURLWithPath: "/tmp/notebook.cocxynb")
        let tab = TabState(
            id: TabID(),
            title: "Workspace",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            splitTree: .split(
                direction: .horizontal,
                first: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp"), command: nil),
                second: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp"), command: nil),
                ratio: 0.65
            ),
            paneStates: [
                SplitPaneState(scrollPosition: TerminalScrollPosition(visibleStartRow: 42)),
                SplitPaneState(panelInfo: .notebook(path: notebook), title: "Notebook")
            ]
        )

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(TabState.self, from: data)

        #expect(decoded.paneStates.count == 2)
        #expect(decoded.paneStates[0].panelInfo.type == .terminal)
        #expect(decoded.paneStates[0].scrollPosition?.visibleStartRow == 42)
        #expect(decoded.paneStates[1].panelInfo.type == .notebook)
        #expect(decoded.paneStates[1].panelInfo.filePath == notebook)
        #expect(decoded.paneStates[1].title == "Notebook")
    }

    @Test("SessionRestorer propagates pane metadata")
    func sessionRestorerPropagatesPaneMetadata() {
        let tab = TabState(
            id: TabID(),
            title: "Workspace",
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            splitTree: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp"), command: nil),
            paneStates: [
                SplitPaneState(
                    panelInfo: .editor(path: URL(fileURLWithPath: "/tmp/README.md")),
                    title: "README"
                )
            ]
        )
        let window = WindowState(
            frame: CodableRect(x: 100, y: 100, width: 1000, height: 700),
            isFullScreen: false,
            tabs: [tab],
            activeTabIndex: 0
        )

        let restored = SessionRestorer.restoreWindow(from: window, screenBounds: screenBounds)

        #expect(restored.restoredTabs.first?.paneStates.first?.panelInfo.type == .editor)
        #expect(restored.restoredTabs.first?.paneStates.first?.title == "README")
    }

    // MARK: - Multi-Window Restoration

    @Test("restoreAllWindows returns one result per window")
    func restoreAllWindowsCount() {
        let session = Session(
            windows: [
                makeWindowState(tabCount: 2),
                makeWindowState(tabCount: 1),
                makeWindowState(tabCount: 3)
            ]
        )

        let result = SessionRestorer.restoreAllWindows(
            from: session,
            screenBounds: screenBounds
        )

        #expect(result.windows.count == 3)
        #expect(result.windows[0].restoredTabs.count == 2)
        #expect(result.windows[1].restoredTabs.count == 1)
        #expect(result.windows[2].restoredTabs.count == 3)
    }

    @Test("restoreAllWindows preserves focused window index")
    func restoreAllWindowsFocusedIndex() {
        let session = Session(
            windows: [makeWindowState(), makeWindowState()],
            focusedWindowIndex: 1
        )

        let result = SessionRestorer.restoreAllWindows(
            from: session,
            screenBounds: screenBounds
        )

        #expect(result.focusedWindowIndex == 1)
    }

    @Test("restoreAllWindows clamps out-of-range focused index to 0")
    func restoreAllWindowsClampsInvalidFocus() {
        let session = Session(
            windows: [makeWindowState()],
            focusedWindowIndex: 99
        )

        let result = SessionRestorer.restoreAllWindows(
            from: session,
            screenBounds: screenBounds
        )

        #expect(result.focusedWindowIndex == 0)
    }

    @Test("restoreAllWindows handles empty session")
    func restoreAllWindowsEmpty() {
        let session = Session(windows: [])

        let result = SessionRestorer.restoreAllWindows(
            from: session,
            screenBounds: screenBounds
        )

        #expect(result.windows.isEmpty)
        #expect(result.focusedWindowIndex == 0)
    }

    @Test("restoreAllWindows validates each window's frame independently")
    func restoreAllWindowsValidatesFrames() {
        let offScreen = CodableRect(x: -5000, y: -5000, width: 800, height: 600)
        let onScreen = CodableRect(x: 100, y: 100, width: 800, height: 600)

        let session = Session(
            windows: [
                WindowState(frame: offScreen, isFullScreen: false,
                           tabs: [makeTabState()], activeTabIndex: 0),
                WindowState(frame: onScreen, isFullScreen: false,
                           tabs: [makeTabState()], activeTabIndex: 0)
            ]
        )

        let result = SessionRestorer.restoreAllWindows(
            from: session,
            screenBounds: screenBounds
        )

        // Off-screen window should be repositioned (not at -5000).
        #expect(result.windows[0].windowFrame.x >= 0)
        // On-screen window should keep its frame.
        #expect(result.windows[1].windowFrame.x == 100)
    }

    @Test("restoreWindow preserves active tab index per window")
    func restoreWindowActiveTabIndex() {
        let state = makeWindowState(tabCount: 3, activeIndex: 2)

        let result = SessionRestorer.restoreWindow(
            from: state,
            screenBounds: screenBounds
        )

        #expect(result.activeTabIndex == 2)
    }

    @Test("Single-window restore still works (backwards compat)")
    @MainActor
    func singleWindowRestoreCompat() {
        let session = Session(
            version: 1,
            windows: [makeWindowState(tabCount: 2)]
        )
        let tabManager = TabManager()
        let coordinator = TabSplitCoordinator()

        let result = SessionRestorer.restore(
            from: session,
            into: tabManager,
            splitCoordinator: coordinator,
            screenBounds: screenBounds
        )

        #expect(result.restoredTabs.count == 2)
    }

    // MARK: - Helpers

    private func makeTabState(
        directory: String = "/tmp"
    ) -> TabState {
        TabState(
            id: TabID(),
            title: "Terminal",
            workingDirectory: URL(fileURLWithPath: directory),
            splitTree: .leaf(workingDirectory: URL(fileURLWithPath: directory), command: nil)
        )
    }

    private func makeWindowState(
        tabCount: Int = 1,
        activeIndex: Int = 0
    ) -> WindowState {
        let tabs = (0..<tabCount).map { _ in makeTabState() }
        return WindowState(
            frame: CodableRect(x: 100, y: 100, width: 1000, height: 700),
            isFullScreen: false,
            tabs: tabs,
            activeTabIndex: min(activeIndex, tabCount - 1)
        )
    }
}
