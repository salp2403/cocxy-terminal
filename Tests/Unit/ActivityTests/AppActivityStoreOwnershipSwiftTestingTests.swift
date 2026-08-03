// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppActivityStoreOwnershipSwiftTestingTests.swift - Cross-window activity ownership.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("App activity store ownership")
struct AppActivityStoreOwnershipSwiftTestingTests {
    @Test("every configured window receives the same app-scoped store")
    func everyWindowReceivesSameStore() {
        let delegate = AppDelegate()
        let first = MainWindowController(
            bridge: MockTerminalEngine(),
            appStores: delegate.mainWindowAppStores
        )
        let second = MainWindowController(
            bridge: MockTerminalEngine(),
            appStores: delegate.mainWindowAppStores
        )

        delegate.configureSharedServices(for: first, registerWindow: false)
        delegate.configureSharedServices(for: second, registerWindow: false)

        #expect(first.injectedActivityStore === delegate.activityStoreCoordinator)
        #expect(second.injectedActivityStore === delegate.activityStoreCoordinator)
        #expect(first.activityWorkingDirectoryProvider === delegate.activityWorkingDirectoryProvider)
        #expect(second.activityWorkingDirectoryProvider === delegate.activityWorkingDirectoryProvider)
        #expect(first.commandBlockStore === delegate.terminalBlockStore)
        #expect(second.commandBlockStore === delegate.terminalBlockStore)
    }

    @Test("shared provider aggregates every app window")
    func sharedProviderAggregatesEveryWindow() throws {
        let delegate = AppDelegate()
        let first = MainWindowController(
            bridge: MockTerminalEngine(),
            appStores: delegate.mainWindowAppStores
        )
        let second = MainWindowController(
            bridge: MockTerminalEngine(),
            appStores: delegate.mainWindowAppStores
        )
        let firstDirectory = URL(fileURLWithPath: "/tmp/activity-window-one", isDirectory: true)
        let secondDirectory = URL(fileURLWithPath: "/tmp/activity-window-two", isDirectory: true)
        let firstTabID = try #require(first.tabManager.activeTabID)
        let secondTabID = try #require(second.tabManager.activeTabID)
        first.tabManager.updateTab(id: firstTabID) { $0.workingDirectory = firstDirectory }
        second.tabManager.updateTab(id: secondTabID) { $0.workingDirectory = secondDirectory }
        delegate.additionalWindowControllers = [first, second]

        let paths = Set(delegate.activityWorkingDirectoryProvider.directories().map(\.path))

        #expect(paths.contains(firstDirectory.path))
        #expect(paths.contains(secondDirectory.path))
    }
}
