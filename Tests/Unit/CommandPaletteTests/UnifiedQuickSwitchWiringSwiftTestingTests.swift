// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UnifiedQuickSwitchWiringSwiftTestingTests.swift - Window wiring for unified QuickSwitch.

import Foundation
import Testing
import Combine
import CocxyShared
@testable import CocxyTerminal

@MainActor
@Suite("Unified QuickSwitch wiring")
struct UnifiedQuickSwitchWiringSwiftTestingTests {

    private final class InMemoryConfigProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String) {
            self.content = content
        }

        func readConfigFile() -> String? { content }
        func writeConfigFile(_ content: String) throws { self.content = content }
    }

    private final class NotificationSpy: NotificationManaging {
        var nextUnreadTabID: TabID?
        private(set) var gotoNextUnreadCallCount = 0

        var unreadCount: Int { nextUnreadTabID == nil ? 0 : 1 }
        var notificationsPublisher: AnyPublisher<CocxyNotification, Never> {
            Empty().eraseToAnyPublisher()
        }
        var unreadCountPublisher: AnyPublisher<Int, Never> {
            Empty().eraseToAnyPublisher()
        }

        func notify(_ notification: CocxyNotification) {}
        func markAsRead(tabId: TabID) {}
        func markAllAsRead() {}

        func gotoNextUnread() -> TabID? {
            gotoNextUnreadCallCount += 1
            return nextUnreadTabID
        }
    }

    private func configService(quickSwitchMode: QuickSwitchMode) throws -> ConfigService {
        let provider = InMemoryConfigProvider(content: """
        [appearance]
        quickswitch-mode = "\(quickSwitchMode.rawValue)"
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service
    }

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

    @Test("item labels follow configured app language")
    func itemLabelsFollowConfiguredAppLanguage() throws {
        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        #expect(MainWindowController.localizedUnifiedQuickSwitchTabTitle("main", using: spanish) == "Pestaña: main")
        #expect(MainWindowController.localizedUnifiedQuickSwitchBrowserTitle("Docs", using: spanish) == "Navegador: Docs")
        #expect(MainWindowController.localizedUnifiedQuickSwitchWorktreeTitle("feat/a", using: spanish) == "Worktree: feat/a")
        #expect(MainWindowController.localizedUnifiedQuickSwitchNoteTitle("Ideas", using: spanish) == "Nota: Ideas")
        #expect(MainWindowController.localizedUnifiedQuickSwitchNotesSubtitle(using: spanish) == "Notas del workspace")
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

    @Test("configured QuickSwitch defaults to the unified command palette")
    func configuredQuickSwitchOpensUnifiedOverlay() throws {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: try configService(quickSwitchMode: .unified)
        )
        controller.showWindow(nil)

        controller.performConfiguredQuickSwitch()

        #expect(controller.isCommandPaletteVisible == true)
        #expect(controller.commandPaletteViewModel != nil)
    }

    @Test("tabs-only mode uses the legacy unread-tab rotation")
    func configuredQuickSwitchUsesLegacyTabsOnlyMode() throws {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: try configService(quickSwitchMode: .tabsOnly)
        )
        let first = controller.tabManager.tabs[0]
        let target = controller.tabManager.addTab(workingDirectory: URL(fileURLWithPath: "/tmp/attention"))
        controller.tabManager.setActive(id: first.id)

        let notificationSpy = NotificationSpy()
        notificationSpy.nextUnreadTabID = target.id
        controller.quickSwitchController = QuickSwitchController(
            notificationManager: notificationSpy,
            tabActivator: controller.tabManager
        )

        controller.performConfiguredQuickSwitch()

        #expect(notificationSpy.gotoNextUnreadCallCount == 1)
        #expect(controller.tabManager.activeTabID == target.id)
        #expect(controller.isCommandPaletteVisible == false)
        #expect(controller.commandPaletteViewModel == nil)
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
