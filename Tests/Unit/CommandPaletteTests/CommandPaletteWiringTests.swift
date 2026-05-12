// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteWiringTests.swift - Runtime command palette coverage tests.

import XCTest
@testable import CocxyTerminal

@MainActor
final class CommandPaletteWiringTests: XCTestCase {
    func testWindowCommandPaletteExposesRuntimeActionsAndDiscoverablePanels() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let engine = controller.createWiredCommandPaletteEngine()
        let actionIDs = Set(engine.allActions.map(\.id))
        let actionsByID = Dictionary(uniqueKeysWithValues: engine.allActions.map { ($0.id, $0) })

        let expectedIDs: Set<String> = [
            "window.new",
            "window.minimize",
            "window.fullscreen",
            "window.commandPalette",
            "tabs.new",
            "tabs.close",
            "tabs.configSave",
            "tabs.configOpen",
            "onboarding.show",
            "tabs.next",
            "tabs.previous",
            "tabs.moveToNewWindow",
            "tabs.goto1",
            "tabs.goto2",
            "tabs.goto3",
            "tabs.goto4",
            "tabs.goto5",
            "tabs.goto6",
            "tabs.goto7",
            "tabs.goto8",
            "tabs.goto9",
            "splits.horizontal",
            "splits.vertical",
            "splits.close",
            "splits.equalize",
            "splits.zoom",
            "navigation.splitLeft",
            "navigation.splitRight",
            "navigation.splitUp",
            "navigation.splitDown",
            "search.toggle",
            "terminal.richInput",
            "editor.zoomIn",
            "editor.zoomOut",
            "editor.resetZoom",
            "editor.openDefault",
            "preferences.show",
            "welcome.show",
            "tabbar.toggle",
            "dashboard.toggle",
            "activity.toggle",
            "agent.mode",
            "agent.review",
            "gitAssistant.commitMessage",
            "timeline.toggle",
            "notifications.toggle",
            "browser.toggle",
            "voice.input",
            "workspace.browser",
            "workspace.markdown",
            "workspace.editor",
            "workspace.notebook",
            "workspace.workflow",
            "workspace.sessionReplay",
            "workspace.aiEditHistory",
            "workspace.templates",
            "workspace.macros",
            "workspace.dbCloud",
            "remote.toggle",
            "browser.history",
            "browser.bookmarks",
            "theme.browse",
            "theme.cycle",
            "sidebar.transparency",
            "navigation.quickswitch",
            "navigation.quickterminal",
            "window.pictureInPicture",
        ]

        XCTAssertTrue(
            actionIDs.isSuperset(of: expectedIDs),
            "The runtime command palette must expose every app action and panel that has a live handler"
        )
        XCTAssertEqual(
            actionsByID["preferences.show"]?.category,
            .config,
            "The Preferences command must be grouped with settings/configuration actions, not navigation."
        )
    }

    func testPictureInPictureActionDescriptionTracksLiveConfigReload() throws {
        let provider = CommandPaletteConfigProvider(content: """
        [experimental]
        pip-enabled = false
        pty-daemon = false
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )
        let engine = controller.createWiredCommandPaletteEngine()
        controller.commandPaletteEngine = engine

        XCTAssertEqual(
            engine.allActions.first(where: { $0.id == "window.pictureInPicture" })?.description,
            "Enable [experimental].pip-enabled to use terminal Picture-in-Picture"
        )

        provider.content = """
        [experimental]
        pip-enabled = true
        pty-daemon = false
        """
        try service.reload()
        controller.refreshCommandPaletteRuntimeStateIfNeeded(service.current)

        XCTAssertEqual(
            engine.allActions.first(where: { $0.id == "window.pictureInPicture" })?.description,
            "Move the active terminal into a floating Picture-in-Picture panel"
        )
    }
}

private final class CommandPaletteConfigProvider: ConfigFileProviding, @unchecked Sendable {
    var content: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? {
        content
    }

    func writeConfigFile(_ content: String) throws {
        self.content = content
    }
}
