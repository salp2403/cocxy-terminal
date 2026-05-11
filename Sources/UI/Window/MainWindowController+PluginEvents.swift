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

        dispatchPluginEvent(event, environment: environment)
    }

    func dispatchPluginEvent(
        _ event: PluginEvent,
        environment: [String: String]
    ) {
        if let pluginEventDispatcher {
            pluginEventDispatcher(event, environment)
            return
        }

        (NSApp.delegate as? AppDelegate)?
            .pluginManager?
            .dispatchEvent(event, environment: environment)
    }

    func dispatchRichInputSubmitEvents(
        tabID: TabID,
        text: String,
        attachmentCount: Int
    ) {
        let sessionID = sessionIDForTab(tabID)
        var environment = Self.pluginEventEnvironment(
            tabID: tabID,
            sessionID: sessionID,
            windowID: windowID
        )
        environment["COCXY_RICH_INPUT_TEXT"] = text
        environment["COCXY_RICH_INPUT_TEXT_CHARACTER_COUNT"] = "\(text.count)"
        environment["COCXY_RICH_INPUT_ATTACHMENT_COUNT"] = "\(attachmentCount)"

        dispatchPluginEvent(.richInputSubmit, environment: environment)

        let hookEvent = HookEvent(
            type: .richInputDraftSubmitted,
            sessionId: sessionID.rawValue.uuidString,
            data: .richInputDraftSubmitted(RichInputDraftSubmittedData(
                textCharacterCount: text.count,
                attachmentCount: attachmentCount
            ))
        )

        if let hookEventDispatcher {
            hookEventDispatcher(hookEvent)
            return
        }

        (NSApp.delegate as? AppDelegate)?
            .hookEventReceiver?
            .receive(hookEvent)
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
