// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+PluginEvents.swift - App flow plugin event dispatch.

import AppKit

extension MainWindowController {
    func dispatchPluginEvent(
        _ event: PluginEvent,
        tabID: TabID,
        sessionID: SessionID
    ) {
        let environment = Self.pluginEventEnvironment(
            tabID: tabID,
            sessionID: sessionID,
            windowID: windowID
        )

        if let pluginEventDispatcher {
            pluginEventDispatcher(event, environment)
            return
        }

        (NSApp.delegate as? AppDelegate)?
            .pluginManager?
            .dispatchEvent(event, environment: environment)
    }

    static func pluginEventEnvironment(
        tabID: TabID,
        sessionID: SessionID,
        windowID: WindowID
    ) -> [String: String] {
        [
            "COCXY_SESSION_ID": sessionID.rawValue.uuidString,
            "COCXY_TAB_ID": tabID.rawValue.uuidString,
            "COCXY_WINDOW_ID": windowID.rawValue.uuidString,
        ]
    }
}
