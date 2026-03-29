// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyScriptCommands.swift - AppleScript command handlers for Cocxy Terminal.

import AppKit

// MARK: - Make Tab Command

/// Handles: `make new tab with command "ls" at "/path"`
///
/// AppleScript commands always execute on the main thread. The bodies use
/// `MainActor.assumeIsolated` to satisfy strict concurrency checking
/// without introducing async overhead.
@objc(CocxyMakeTabCommand)
class CocxyMakeTabCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            let arguments = evaluatedArguments ?? [:]
            let command = arguments["command"] as? String
            let dirPath = arguments["workingDirectory"] as? String

            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.windowController else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "Application not ready"
                return nil
            }

            let workingDir: URL
            if let path = dirPath {
                workingDir = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            } else {
                workingDir = FileManager.default.homeDirectoryForCurrentUser
            }

            windowController.createTab(workingDirectory: workingDir)

            // If a command was specified, send it to the new tab's terminal.
            if let cmd = command, !cmd.isEmpty,
               let activeID = windowController.tabManager.activeTabID,
               let surfaceID = windowController.tabSurfaceMap[activeID] {
                windowController.bridge.sendText(cmd + "\r", to: surfaceID)
            }

            // Return the scriptable tab object for the new tab.
            guard let newTabID = windowController.tabManager.activeTabID else { return nil }
            return ScriptableTab(tabID: newTabID, tabManager: windowController.tabManager)
        }
    }
}

// MARK: - Run Command

/// Handles: `run command "ls -la"`
@objc(CocxyRunCommandCommand)
class CocxyRunCommandCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            guard let text = directParameter as? String, !text.isEmpty else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "No command text provided"
                return nil
            }

            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.windowController,
                  let activeID = windowController.tabManager.activeTabID,
                  let surfaceID = windowController.tabSurfaceMap[activeID] else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "No active terminal"
                return nil
            }

            windowController.bridge.sendText(text + "\r", to: surfaceID)
            return nil
        }
    }
}

// MARK: - Split Command

/// Handles: `split terminal direction "horizontal"`
@objc(CocxySplitCommand)
class CocxySplitCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            let arguments = evaluatedArguments ?? [:]
            let direction = (arguments["direction"] as? String)?.lowercased() ?? "vertical"

            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.windowController else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "Application not ready"
                return nil
            }

            if direction == "horizontal" {
                windowController.splitHorizontalAction(self)
            } else {
                windowController.splitVerticalAction(self)
            }

            return nil
        }
    }
}

// MARK: - Focus Tab Command

/// Handles: `focus tab 2` (1-based index)
@objc(CocxyFocusTabCommand)
class CocxyFocusTabCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            guard let index = directParameter as? Int else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "Tab index required"
                return nil
            }

            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let windowController = appDelegate.windowController else {
                scriptErrorNumber = errOSAGeneralError
                scriptErrorString = "Application not ready"
                return nil
            }

            // Convert from 1-based (AppleScript) to 0-based (internal).
            let zeroBasedIndex = index - 1
            windowController.tabManager.gotoTab(at: zeroBasedIndex)

            return nil
        }
    }
}
