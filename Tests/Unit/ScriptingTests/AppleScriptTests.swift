// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppleScriptTests.swift - Tests for the AppleScript scripting bridge.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("AppleScript Scripting")
struct AppleScriptTests {

    @Test("ScriptableTab exposes tab properties via KVC keys")
    @MainActor
    func scriptableTabProperties() {
        let tabManager = TabManager()
        let tab = tabManager.tabs.first!
        let scriptable = ScriptableTab(tabID: tab.id, tabManager: tabManager)

        #expect(scriptable.uniqueID == tab.id.rawValue.uuidString)
        #expect(scriptable.name == tab.displayTitle)
        #expect(scriptable.agentState == "idle")
        #expect(scriptable.isActiveTab == true)
    }

    @Test("ScriptableTab name setter renames tab")
    @MainActor
    func scriptableTabRename() {
        let tabManager = TabManager()
        let tab = tabManager.tabs.first!
        let scriptable = ScriptableTab(tabID: tab.id, tabManager: tabManager)

        scriptable.name = "My Custom Tab"
        let updated = tabManager.tab(for: tab.id)
        #expect(updated?.customTitle == "My Custom Tab")
    }

    @Test("ScriptableTab empty name clears custom title")
    @MainActor
    func scriptableTabClearName() {
        let tabManager = TabManager()
        let tab = tabManager.tabs.first!
        let scriptable = ScriptableTab(tabID: tab.id, tabManager: tabManager)

        scriptable.name = "Temp"
        scriptable.name = ""
        let updated = tabManager.tab(for: tab.id)
        #expect(updated?.customTitle == nil)
    }

    @Test("ScriptableTab returns process name from tab")
    @MainActor
    func scriptableTabProcessName() {
        let tabManager = TabManager()
        let tab = tabManager.tabs.first!
        tabManager.updateTab(id: tab.id) { t in
            t.processName = "zsh"
        }
        let scriptable = ScriptableTab(tabID: tab.id, tabManager: tabManager)

        #expect(scriptable.processName == "zsh")
    }

    @Test("ScriptableTab returns working directory path")
    @MainActor
    func scriptableTabWorkingDirectory() {
        let tabManager = TabManager()
        let tab = tabManager.tabs.first!
        let scriptable = ScriptableTab(tabID: tab.id, tabManager: tabManager)

        // Default working directory should be a valid path.
        #expect(!scriptable.workingDirectory.isEmpty)
        #expect(scriptable.workingDirectory != "~")
    }

    @Test("ScriptableTab with nil tab manager returns defaults")
    @MainActor
    func scriptableTabNilManager() {
        let tabID = TabID()
        let scriptable = ScriptableTab(tabID: tabID, tabManager: nil)

        #expect(scriptable.name == "Terminal")
        #expect(scriptable.workingDirectory == "~")
        #expect(scriptable.agentState == "idle")
        #expect(scriptable.isActiveTab == false)
        #expect(scriptable.processName == "")
    }

    @Test("NSApplication scriptableTabs returns empty without AppDelegate")
    @MainActor
    func appScriptableTabsEmpty() {
        // NSApplication.shared may not have an AppDelegate in the test
        // environment. Guard against nil and verify the extension does
        // not crash when there is no window controller.
        guard let app = NSApplication.shared as NSApplication? else {
            // No shared application in this test host; skip silently.
            return
        }
        let tabs = app.scriptableTabs
        // Without an AppDelegate or window controller, expect empty.
        #expect(tabs.isEmpty)
    }
}
