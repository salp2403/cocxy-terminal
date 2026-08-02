// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppActivityStoreOwnershipSwiftTestingTests.swift - Cross-window activity ownership.

import Testing
@testable import CocxyTerminal

@MainActor
@Suite("App activity store ownership")
struct AppActivityStoreOwnershipSwiftTestingTests {
    @Test("every configured window receives the same app-scoped store")
    func everyWindowReceivesSameStore() {
        let delegate = AppDelegate()
        let first = MainWindowController(bridge: MockTerminalEngine())
        let second = MainWindowController(bridge: MockTerminalEngine())

        delegate.configureSharedServices(for: first, registerWindow: false)
        delegate.configureSharedServices(for: second, registerWindow: false)

        #expect(first.injectedActivityStore === delegate.activityStoreCoordinator)
        #expect(second.injectedActivityStore === delegate.activityStoreCoordinator)
    }
}
