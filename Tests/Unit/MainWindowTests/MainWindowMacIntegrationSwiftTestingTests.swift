// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Main window macOS integrations")
struct MainWindowMacIntegrationSwiftTestingTests {

    @Test("main window opts into Stage Manager friendly grouping and tiling")
    func mainWindowUsesStageManagerFriendlyBehaviors() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        let window = try #require(controller.window)
        let behavior = window.collectionBehavior

        #expect(behavior.contains(.primary))
        #expect(behavior.contains(.managed))
        #expect(behavior.contains(.participatesInCycle))
        #expect(behavior.contains(.fullScreenPrimary))
        #expect(behavior.contains(.fullScreenAllowsTiling))
        #expect(window.tabbingMode == .preferred)
    }

    @Test("touch bar exposes contextual local terminal actions")
    func touchBarExposesContextualTerminalActions() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        let touchBar = try #require(controller.makeTouchBar())

        #expect(touchBar.customizationIdentifier == CocxyTouchBarController.customizationIdentifier)
        #expect(touchBar.defaultItemIdentifiers == CocxyTouchBarController.defaultItemIdentifiers)
        for identifier in CocxyTouchBarController.defaultItemIdentifiers {
            #expect(touchBar.delegate?.touchBar?(touchBar, makeItemForIdentifier: identifier) != nil)
        }
    }

    @Test("touch bar buttons dispatch their configured local actions")
    func touchBarButtonsDispatchLocalActions() throws {
        var dispatchedActions: [String] = []
        let controller = CocxyTouchBarController(
            newTab: { dispatchedActions.append("new-tab") },
            commandPalette: { dispatchedActions.append("commands") },
            agentPanel: { dispatchedActions.append("agent") },
            search: { dispatchedActions.append("search") }
        )
        let touchBar = controller.makeTouchBar()

        let expectations: [(NSTouchBarItem.Identifier, String)] = [
            (CocxyTouchBarController.newTabIdentifier, "new-tab"),
            (CocxyTouchBarController.commandPaletteIdentifier, "commands"),
            (CocxyTouchBarController.agentPanelIdentifier, "agent"),
            (CocxyTouchBarController.searchIdentifier, "search")
        ]

        for (identifier, action) in expectations {
            let item = try #require(
                touchBar.delegate?.touchBar?(touchBar, makeItemForIdentifier: identifier) as? NSCustomTouchBarItem
            )
            let button = try #require(item.view as? NSButton)

            button.performClick(nil)
            #expect(dispatchedActions.last == action)
        }

        #expect(dispatchedActions == expectations.map(\.1))
    }
}
