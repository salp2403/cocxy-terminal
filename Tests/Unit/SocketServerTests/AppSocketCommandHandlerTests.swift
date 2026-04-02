// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandlerTests.swift - Tests for the socket command dispatcher.

import XCTest
@testable import CocxyTerminal

// MARK: - App Socket Command Handler Tests

/// Tests for `AppSocketCommandHandler` covering all command groups:
/// - Tab operations (focus, close, new, rename, move)
/// - Config operations (get, set, path)
/// - Theme operations (list, set)
/// - Acknowledged commands (async UI actions)
///
/// Each test creates the handler on @MainActor so that the closure
/// providers can safely capture TabManager state.
final class AppSocketCommandHandlerTests: XCTestCase {

    // MARK: - Existing Handler Tests (moved from PreferencesViewTests)

    func test_unknownCommand_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-1", command: "unknown-command", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
        XCTAssertNotNil(response.error)
    }

    @MainActor
    func test_statusCommand_returnsRunning() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-2", command: "status", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "running")
        XCTAssertEqual(response.data?["version"], CocxyVersion.current)
    }

    @MainActor
    func test_listTabsCommand_returnsTabInfo() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-3", command: "list-tabs", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "1")
    }

    func test_hookEventCommand_withoutReceiver_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-4", command: "hook-event", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_hookEventCommand_withMissingPayload_returnsFailure() {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: receiver)
        let request = SocketRequest(id: "test-5", command: "hook-event", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_hookEventCommand_withInvalidPayload_returnsFailure() {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: receiver)
        let request = SocketRequest(
            id: "test-6",
            command: "hook-event",
            params: ["payload": "not-valid-json"]
        )
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    // MARK: - Group 1: Tab Operations

    // MARK: focus-tab

    @MainActor
    func test_focusTab_withValidID_activatesTab() {
        let tabManager = TabManager()
        let secondTab = tabManager.addTab()
        let firstTabID = tabManager.tabs[0].id.rawValue.uuidString
        XCTAssertTrue(secondTab.isActive)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ft-1",
            command: "focus-tab",
            params: ["id": firstTabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "focused")
        XCTAssertEqual(tabManager.activeTabID, tabManager.tabs[0].id)
    }

    @MainActor
    func test_focusTab_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "ft-2", command: "focus-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor
    func test_focusTab_withInvalidUUID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ft-3",
            command: "focus-tab",
            params: ["id": "not-a-uuid"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Invalid") == true)
    }

    @MainActor
    func test_focusTab_withNonexistentID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let nonexistentUUID = UUID().uuidString
        let request = SocketRequest(
            id: "ft-4",
            command: "focus-tab",
            params: ["id": nonexistentUUID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not found") == true)
    }

    @MainActor
    func test_focusTab_withNilTabManager_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ft-5",
            command: "focus-tab",
            params: ["id": UUID().uuidString]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    // MARK: close-tab

    @MainActor
    func test_closeTab_withValidID_removesTab() {
        let tabManager = TabManager()
        let secondTab = tabManager.addTab()
        XCTAssertEqual(tabManager.tabs.count, 2)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ct-1",
            command: "close-tab",
            params: ["id": secondTab.id.rawValue.uuidString]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "closed")
        XCTAssertEqual(tabManager.tabs.count, 1)
    }

    @MainActor
    func test_closeTab_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "ct-2", command: "close-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor
    func test_closeTab_lastTab_cannotClose() {
        let tabManager = TabManager()
        XCTAssertEqual(tabManager.tabs.count, 1)
        let onlyTabID = tabManager.tabs[0].id.rawValue.uuidString

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ct-3",
            command: "close-tab",
            params: ["id": onlyTabID]
        )
        let response = handler.handleCommand(request)

        // TabManager silently refuses to close the last tab, handler reports success.
        XCTAssertTrue(response.success)
        XCTAssertEqual(tabManager.tabs.count, 1)
    }

    // MARK: new-tab

    @MainActor
    func test_newTab_withoutDir_createsTab() {
        let tabManager = TabManager()
        XCTAssertEqual(tabManager.tabs.count, 1)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "nt-1", command: "new-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["id"])
        XCTAssertNotNil(response.data?["title"])
        XCTAssertEqual(tabManager.tabs.count, 2)
    }

    @MainActor
    func test_newTab_withDir_createsTabAtDirectory() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "nt-2",
            command: "new-tab",
            params: ["dir": "/tmp"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(tabManager.tabs.count, 2)
        // The new tab should be active.
        XCTAssertTrue(tabManager.tabs.last?.isActive == true)
    }

    @MainActor
    func test_newTab_withNilTabManager_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "nt-3", command: "new-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    // MARK: tab-rename

    @MainActor
    func test_tabRename_withValidParams_renamesTab() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tr-1",
            command: "tab-rename",
            params: ["id": tabID, "name": "My Custom Name"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "renamed")
        XCTAssertEqual(tabManager.tabs[0].customTitle, "My Custom Name")
    }

    @MainActor
    func test_tabRename_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tr-2",
            command: "tab-rename",
            params: ["name": "Something"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor
    func test_tabRename_withMissingName_returnsError() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tr-3",
            command: "tab-rename",
            params: ["id": tabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    // MARK: tab-move

    @MainActor
    func test_tabMove_withValidPositions_movesTab() {
        let tabManager = TabManager()
        let firstTab = tabManager.tabs[0]
        tabManager.addTab()
        tabManager.addTab()
        XCTAssertEqual(tabManager.tabs.count, 3)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let firstTabID = firstTab.id.rawValue.uuidString
        let request = SocketRequest(
            id: "tm-1",
            command: "tab-move",
            params: ["id": firstTabID, "position": "2"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "moved")
        // The first tab should now be at index 2.
        XCTAssertEqual(tabManager.tabs[2].id, firstTab.id)
    }

    @MainActor
    func test_tabMove_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tm-2",
            command: "tab-move",
            params: ["position": "1"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
    }

    @MainActor
    func test_tabMove_withMissingPosition_returnsError() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tm-3",
            command: "tab-move",
            params: ["id": tabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
    }

    @MainActor
    func test_tabMove_withInvalidPosition_returnsError() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tm-4",
            command: "tab-move",
            params: ["id": tabID, "position": "abc"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
    }

    // MARK: - Group 2: Config Operations

    // MARK: config-path

    func test_configPath_returnsPath() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "cp-1", command: "config-path", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["path"])
        XCTAssertTrue(response.data?["path"]?.contains("config.toml") == true)
    }

    // MARK: config-get

    func test_configGet_withValidKey_returnsValue() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-1",
            command: "config-get",
            params: ["key": "appearance.theme"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["key"])
        XCTAssertNotNil(response.data?["value"])
    }

    func test_configGet_withMissingKey_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "cg-2", command: "config-get", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_configGet_withUnknownKey_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-3",
            command: "config-get",
            params: ["key": "nonexistent.key"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Unknown") == true)
    }

    func test_configGet_generalShell_returnsShellPath() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-4",
            command: "config-get",
            params: ["key": "general.shell"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "general.shell")
        // Default shell is /bin/zsh.
        XCTAssertNotNil(response.data?["value"])
    }

    // MARK: config-set

    func test_configSet_withMissingKey_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cs-1",
            command: "config-set",
            params: ["value": "something"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_configSet_withMissingValue_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cs-2",
            command: "config-set",
            params: ["key": "appearance.theme"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_configSet_withValidParams_returnsAcknowledged() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cs-3",
            command: "config-set",
            params: ["key": "appearance.theme", "value": "dracula"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "updated")
    }

    // MARK: - Group 3: Theme Operations

    // MARK: theme-list

    @MainActor func test_themeList_returnsAvailableThemes() {
        let engine = ThemeEngineImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil, themeEngineProvider: { engine })
        let request = SocketRequest(id: "tl-1", command: "theme-list", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["count"])
        // There should be at least the 6 built-in themes.
        if let countStr = response.data?["count"], let count = Int(countStr) {
            XCTAssertGreaterThanOrEqual(count, 6)
        }
    }

    @MainActor func test_themeList_includesBuiltInThemeNames() {
        let engine = ThemeEngineImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil, themeEngineProvider: { engine })
        let request = SocketRequest(id: "tl-2", command: "theme-list", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        // Built-in themes are indexed as theme_0, theme_1, etc.
        let allValues = response.data?.values.joined(separator: ",") ?? ""
        XCTAssertTrue(allValues.contains("Catppuccin Mocha"))
        XCTAssertTrue(allValues.contains("Dracula"))
    }

    // MARK: theme-set

    func test_themeSet_withMissingName_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "ts-1", command: "theme-set", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor func test_themeSet_withValidName_returnsSuccess() {
        let engine = ThemeEngineImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil, themeEngineProvider: { engine })
        let request = SocketRequest(
            id: "ts-2",
            command: "theme-set",
            params: ["name": "Dracula"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "applied")
    }

    func test_themeSet_withInvalidName_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ts-3",
            command: "theme-set",
            params: ["name": "Nonexistent Theme That Does Not Exist"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not found") == true)
    }

    // MARK: - Group 4: Acknowledged Commands

    func test_notifyCommand_dispatchesAndReturnsNotificationSent() {
        var dispatchedTitle: String?
        var dispatchedBody: String?
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            notifyDispatcher: { title, body in
                dispatchedTitle = title
                dispatchedBody = body
            }
        )
        let request = SocketRequest(
            id: "ack-1",
            command: "notify",
            params: ["message": "Build done"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "notification sent")
        XCTAssertEqual(dispatchedTitle, "Cocxy")
        XCTAssertEqual(dispatchedBody, "Build done")
    }

    func test_notifyCommand_withCustomTitle() {
        var dispatchedTitle: String?
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            notifyDispatcher: { title, _ in dispatchedTitle = title }
        )
        let request = SocketRequest(
            id: "ack-1b",
            command: "notify",
            params: ["title": "Deploy", "message": "Success"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(dispatchedTitle, "Deploy")
    }

    func test_notifyCommand_withoutMessage_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ack-1c",
            command: "notify",
            params: nil
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("message") == true)
    }

    // MARK: - V4 Commands: Without Providers Return Error

    func test_splitCommand_withoutProvider_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "v4-1", command: "split", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_splitCommand_withProvider_returnsCreated() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            splitCreateProvider: { _ in true }
        )
        let request = SocketRequest(id: "v4-2", command: "split", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "created")
    }

    func test_splitListCommand_withProvider_returnsPanes() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            splitInfoProvider: { [
                (leafID: "leaf-1", terminalID: "term-1", isFocused: true),
                (leafID: "leaf-2", terminalID: "term-2", isFocused: false)
            ] }
        )
        let request = SocketRequest(id: "v4-3", command: "split-list", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "2")
    }

    func test_dashboardToggleCommand_withProvider_returnsToggled() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            dashboardToggleProvider: { true }
        )
        let request = SocketRequest(id: "v4-4", command: "dashboard-toggle", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "toggled")
        XCTAssertEqual(response.data?["visible"], "true")
    }

    func test_dashboardStatusCommand_withProvider_returnsStatus() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            dashboardStatusProvider: { [
                "visible": "true",
                "session_count": "3",
                "active_count": "1"
            ] }
        )
        let request = SocketRequest(id: "v4-5", command: "dashboard-status", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["session_count"], "3")
    }

    func test_timelineShowCommand_withProvider_returnsShown() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            timelineToggleProvider: { }
        )
        let request = SocketRequest(id: "v4-6", command: "timeline-show", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "shown")
    }

    func test_searchCommand_withProvider_returnsToggled() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            searchToggleProvider: { }
        )
        let request = SocketRequest(id: "v4-7", command: "search", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "toggled")
    }

    func test_sendCommand_withProvider_returnsSent() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sendTextProvider: { _ in true }
        )
        let request = SocketRequest(id: "v4-8", command: "send", params: ["text": "ls"])
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "sent")
    }

    func test_sendKeyCommand_withProvider_returnsSent() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sendKeyProvider: { _ in true }
        )
        let request = SocketRequest(id: "v4-9", command: "send-key", params: ["key": "enter"])
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "sent")
    }

    func test_hooksCommand_returnsData() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "v4-10", command: "hooks", params: nil)
        let response = handler.handleCommand(request)
        // hooks reads settings.json — succeeds even without provider
        XCTAssertTrue(response.success)
    }

    func test_hookHandlerCommand_returnsReady() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "v4-11", command: "hook-handler", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ready")
    }

    func test_timelineExportCommand_withProvider_returnsExported() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            timelineExportProvider: { format in
                "[]".data(using: .utf8)
            }
        )
        let request = SocketRequest(
            id: "v4-12", command: "timeline-export",
            params: ["format": "json"]
        )
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "exported")
    }

    func test_sshCommand_withProvider_returnsConnected() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sshProvider: { destination, port, identity in
                ("tab-id", destination)
            }
        )
        let request = SocketRequest(
            id: "ssh-1", command: "ssh",
            params: ["destination": "user@host", "port": "2222"]
        )
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "connected")
        XCTAssertEqual(response.data?["destination"], "user@host")
    }

    func test_sshCommand_withoutProvider_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "ssh-2", command: "ssh", params: ["destination": "host"])
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_sshCommand_withoutDestination_returnsFailure() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sshProvider: { _, _, _ in ("id", "title") }
        )
        let request = SocketRequest(id: "ssh-3", command: "ssh", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_v4Commands_withoutProviders_returnFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let commands = [
            "split", "split-list", "split-focus", "split-close", "split-resize",
            "dashboard-show", "dashboard-hide", "dashboard-toggle", "dashboard-status",
            "timeline-show", "timeline-export", "search", "send", "send-key", "ssh"
        ]
        for command in commands {
            let request = SocketRequest(id: "nil-\(command)", command: command, params: nil)
            let response = handler.handleCommand(request)
            XCTAssertFalse(
                response.success,
                "Command '\(command)' without provider should return failure"
            )
        }
    }
}
