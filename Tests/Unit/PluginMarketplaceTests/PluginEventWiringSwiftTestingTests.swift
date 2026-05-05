// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginEventWiringSwiftTestingTests.swift - App flow plugin event dispatch contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Plugin event wiring")
struct PluginEventWiringSwiftTestingTests {

    @Test("creating a tab dispatches tab and session plugin events without private paths")
    func creatingTabDispatchesPluginEventsWithoutPrivatePaths() throws {
        var events: [(PluginEvent, [String: String])] = []
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        controller.pluginEventDispatcher = { event, environment in
            events.append((event, environment))
        }

        let privatePath = "/tmp/cocxy-private-\(UUID().uuidString)"
        let tabID = controller.createTab(workingDirectory: URL(fileURLWithPath: privatePath))

        #expect(events.map(\.0) == [.tabCreated, .sessionStart])
        for (_, environment) in events {
            #expect(environment["COCXY_TAB_ID"] == tabID.rawValue.uuidString)
            #expect(environment["COCXY_WINDOW_ID"] == controller.windowID.rawValue.uuidString)
            #expect(environment["COCXY_SESSION_ID"]?.isEmpty == false)
            #expect(environment["COCXY_WORKING_DIRECTORY"] == nil)
            #expect(environment.values.contains { $0.contains(privatePath) } == false)
        }
    }

    @Test("closing a tab dispatches session and tab close plugin events")
    func closingTabDispatchesPluginEvents() throws {
        var events: [(PluginEvent, [String: String])] = []
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        controller.pluginEventDispatcher = { event, environment in
            events.append((event, environment))
        }
        let tabID = controller.createTab()
        events.removeAll()

        controller.performCloseTab(tabID)

        #expect(events.map(\.0) == [.sessionEnd, .tabClosed])
        #expect(events.allSatisfy { $0.1["COCXY_TAB_ID"] == tabID.rawValue.uuidString })
    }
}
