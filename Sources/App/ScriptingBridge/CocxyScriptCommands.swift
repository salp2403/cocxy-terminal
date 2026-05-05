// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyScriptCommands.swift - AppleScript command handlers for Cocxy Terminal.

import AppKit

private func setScriptError(on command: NSScriptCommand, message: String) {
    command.scriptErrorNumber = errOSAGeneralError
    command.scriptErrorString = message
}

enum CocxyScriptCommandErrorCopy {
    static func applicationNotReady(using localizer: AppLocalizer) -> String {
        localizer.string(
            "scripting.error.applicationNotReady",
            fallback: "Application not ready"
        )
    }

    static func noCommandTextProvided(using localizer: AppLocalizer) -> String {
        localizer.string(
            "scripting.error.noCommandTextProvided",
            fallback: "No command text provided"
        )
    }

    static func noActiveTerminal(using localizer: AppLocalizer) -> String {
        localizer.string(
            "scripting.error.noActiveTerminal",
            fallback: "No active terminal"
        )
    }

    static func tabIndexRequired(using localizer: AppLocalizer) -> String {
        localizer.string(
            "scripting.error.tabIndexRequired",
            fallback: "Tab index required"
        )
    }

    static func tabIndexOutOfRange(using localizer: AppLocalizer) -> String {
        localizer.string(
            "scripting.error.tabIndexOutOfRange",
            fallback: "Tab index out of range"
        )
    }
}

@MainActor
private func scriptCommandLocalizer() -> AppLocalizer {
    if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
        return appDelegate.appLocalizer()
    }
    return AppLocalizer(languagePreference: .system)
}

// MARK: - Make Tab Command

/// Handles: `make new tab with command "ls" at "/path"`
///
/// AppleScript commands always execute on the main thread. The bodies use
/// `MainActor.assumeIsolated` synchronously without returning non-Sendable
/// values across the isolation boundary.
@objc(CocxyMakeTabCommand)
final class CocxyMakeTabCommand: NSScriptCommand, @unchecked Sendable {

    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let commandText = arguments["command"] as? String
        let dirPath = arguments["workingDirectory"] as? String

        let outcome: (result: ScriptableTab?, errorMessage: String?) = MainActor.assumeIsolated {
            let localizer = scriptCommandLocalizer()
            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.focusedWindowController() ?? appDelegate.windowController else {
                return (nil, CocxyScriptCommandErrorCopy.applicationNotReady(using: localizer))
            }

            let workingDir: URL
            if let path = dirPath {
                workingDir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            } else {
                workingDir = FileManager.default.homeDirectoryForCurrentUser
            }

            windowController.createTab(workingDirectory: workingDir)

            // If a command was specified, send it to the new tab's terminal.
            if let cmd = commandText, !cmd.isEmpty,
               let activeID = windowController.tabManager.activeTabID,
               let surfaceID = windowController.tabSurfaceMap[activeID] {
                windowController.terminalEngine(for: surfaceID).sendText(cmd + "\r", to: surfaceID)
            }

            // Return the scriptable tab object for the new tab.
            guard let newTabID = windowController.tabManager.activeTabID else {
                return (nil, nil)
            }
            return (ScriptableTab(tabID: newTabID, tabManager: windowController.tabManager), nil)
        }

        if let message = outcome.errorMessage {
            setScriptError(on: self, message: message)
            return nil
        }
        return outcome.result
    }
}

// MARK: - Run Command

/// Handles: `run command "ls -la"`
@objc(CocxyRunCommandCommand)
final class CocxyRunCommandCommand: NSScriptCommand, @unchecked Sendable {

    override func performDefaultImplementation() -> Any? {
        let directText = directParameter as? String
        let errorMessage: String? = MainActor.assumeIsolated {
            let localizer = scriptCommandLocalizer()
            guard let text = directText, !text.isEmpty else {
                return CocxyScriptCommandErrorCopy.noCommandTextProvided(using: localizer)
            }

            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.focusedWindowController() ?? appDelegate.windowController,
                  let activeID = windowController.tabManager.activeTabID,
                  let surfaceID = windowController.tabSurfaceMap[activeID] else {
                return CocxyScriptCommandErrorCopy.noActiveTerminal(using: localizer)
            }

            windowController.terminalEngine(for: surfaceID).sendText(text + "\r", to: surfaceID)
            return nil
        }

        if let errorMessage {
            setScriptError(on: self, message: errorMessage)
        }
        return nil
    }
}

// MARK: - Split Command

/// Handles: `split terminal direction "horizontal"`
@objc(CocxySplitCommand)
final class CocxySplitCommand: NSScriptCommand, @unchecked Sendable {

    override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments ?? [:]
        let direction = (arguments["direction"] as? String)?.lowercased() ?? "vertical"

        let errorMessage: String? = MainActor.assumeIsolated {
            let localizer = scriptCommandLocalizer()
            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.focusedWindowController() ?? appDelegate.windowController else {
                return CocxyScriptCommandErrorCopy.applicationNotReady(using: localizer)
            }

            if direction == "horizontal" {
                windowController.splitHorizontalAction(nil)
            } else {
                windowController.splitVerticalAction(nil)
            }
            return nil
        }

        if let errorMessage {
            setScriptError(on: self, message: errorMessage)
        }
        return nil
    }
}

// MARK: - Focus Tab Command

/// Handles: `focus tab 2` (1-based index)
@objc(CocxyFocusTabCommand)
final class CocxyFocusTabCommand: NSScriptCommand, @unchecked Sendable {

    override func performDefaultImplementation() -> Any? {
        let directIndex = directParameter as? Int
        let errorMessage: String? = MainActor.assumeIsolated {
            let localizer = scriptCommandLocalizer()
            guard let index = directIndex else {
                return CocxyScriptCommandErrorCopy.tabIndexRequired(using: localizer)
            }

            guard let appDelegate = NSApp.delegate as? AppDelegate else {
                return CocxyScriptCommandErrorCopy.applicationNotReady(using: localizer)
            }

            let zeroBasedIndex = index - 1
            let allTabIDs = appDelegate.allWindowControllers.flatMap { controller in
                controller.tabManager.tabs.map(\.id)
            }
            guard zeroBasedIndex >= 0, zeroBasedIndex < allTabIDs.count else {
                return CocxyScriptCommandErrorCopy.tabIndexOutOfRange(using: localizer)
            }

            let targetID = allTabIDs[zeroBasedIndex]
            if let router = appDelegate.windowTabRouter {
                router.activateTab(id: targetID)
            } else {
                _ = appDelegate.controllerContainingTab(targetID)?.focusTab(id: targetID)
            }
            return nil
        }

        if let errorMessage {
            setScriptError(on: self, message: errorMessage)
        }
        return nil
    }
}
