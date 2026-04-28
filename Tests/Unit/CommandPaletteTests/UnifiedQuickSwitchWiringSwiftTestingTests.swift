// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UnifiedQuickSwitchWiringSwiftTestingTests.swift - Window wiring for unified QuickSwitch.

import Foundation
import Testing
import CocxyShared
@testable import CocxyTerminal

@MainActor
@Suite("Unified QuickSwitch wiring")
struct UnifiedQuickSwitchWiringSwiftTestingTests {

    @Test("items merge terminal tabs, browser tabs, and worktree tabs")
    func itemsMergeSupportedSurfaces() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let worktreeTab = controller.tabManager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp/project"))
        controller.tabManager.updateTab(id: worktreeTab.id) {
            $0.worktreeID = "wt_123"
            $0.worktreeRoot = URL(fileURLWithPath: "/tmp/project-wt")
            $0.worktreeBranch = "feat/smoke"
        }
        let browser = BrowserViewModel()
        browser.addBrowserTab(url: URL(string: "https://cocxy.dev")!)
        controller.browserViewModel = browser

        let items = controller.unifiedQuickSwitchItems(now: Date(timeIntervalSince1970: 1_800))

        #expect(items.contains(where: { $0.kind == .tab }))
        #expect(items.contains(where: { $0.kind == .browserTab && $0.subtitle == "https://cocxy.dev" }))
        #expect(items.contains(where: { $0.kind == .worktree && $0.id == "wt_123" }))
    }

    @Test("activating a terminal tab focuses it through the normal tab lifecycle")
    func activatesTerminalTab() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let first = controller.tabManager.tabs[0]
        _ = controller.tabManager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp/second"))
        #expect(controller.tabManager.activeTabID != first.id)

        controller.activateUnifiedQuickSwitchItem(
            UnifiedQuickSwitchItem(
                id: first.id.rawValue.uuidString,
                kind: .tab,
                title: "Tab: first"
            )
        )

        #expect(controller.tabManager.activeTabID == first.id)
    }

    @Test("activating a browser tab selects it without creating a second browser model")
    func activatesBrowserTab() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let browser = BrowserViewModel()
        browser.addBrowserTab(url: URL(string: "https://cocxy.dev")!)
        let targetID = browser.browserTabs.last!.id
        controller.browserViewModel = browser
        controller.isBrowserVisible = true

        controller.activateUnifiedQuickSwitchItem(
            UnifiedQuickSwitchItem(
                id: targetID.uuidString,
                kind: .browserTab,
                title: "Browser: Cocxy"
            )
        )

        #expect(browser.activeTabID == targetID)
        #expect(controller.browserViewModel === browser)
    }

    @Test("activating a worktree focuses the owning tab")
    func activatesWorktreeTab() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let first = controller.tabManager.tabs[0]
        let worktreeTab = controller.tabManager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp/worktree"))
        controller.tabManager.updateTab(id: worktreeTab.id) {
            $0.worktreeID = "wt_focus"
            $0.worktreeBranch = "feat/focus"
        }
        controller.tabManager.setActive(id: first.id)

        controller.activateUnifiedQuickSwitchItem(
            UnifiedQuickSwitchItem(
                id: "wt_focus",
                kind: .worktree,
                title: "Worktree: feat/focus"
            )
        )

        #expect(controller.tabManager.activeTabID == worktreeTab.id)
    }
}
