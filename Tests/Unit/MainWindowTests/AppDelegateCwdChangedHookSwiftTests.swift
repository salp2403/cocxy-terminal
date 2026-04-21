// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateCwdChangedHookSwiftTests.swift

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("AppDelegate CwdChanged hook routing")
@MainActor
struct AppDelegateCwdChangedHookSwiftTests {

    @Test("bound hook sessions can retain the exact originating surface")
    func boundHookSessionRetainsSurfaceID() {
        let delegate = AppDelegate()
        let tabID = TabID()
        let surfaceID = SurfaceID()

        delegate.bindHookSession("sess-surface", to: tabID, surfaceID: surfaceID)

        #expect(delegate.hookSessionTabBindings["sess-surface"] == tabID)
        #expect(delegate.boundSurfaceIDForHookSession("sess-surface") == surfaceID)

        delegate.unbindHookSession("sess-surface")

        #expect(delegate.hookSessionTabBindings["sess-surface"] == nil)
        #expect(delegate.boundSurfaceIDForHookSession("sess-surface") == nil)
    }

    @Test("bound session wins when multiple tabs share the same previous directory")
    func cwdChangedPrefersBoundSessionWhenMultipleTabsShareTheSameDirectory() {
        let delegate = AppDelegate()
        let firstController = MainWindowController(bridge: MockTerminalEngine())
        let secondController = MainWindowController(bridge: MockTerminalEngine())
        delegate.additionalWindowControllers = [firstController, secondController]

        let sharedPath = "/tmp/cocxy-shared-cwd"
        let updatedPath = "/tmp/cocxy-updated-cwd"
        let firstTabID = firstController.tabManager.tabs.first!.id
        let secondTabID = secondController.tabManager.tabs.first!.id

        firstController.tabManager.updateTab(id: firstTabID) {
            $0.workingDirectory = URL(fileURLWithPath: sharedPath, isDirectory: true)
        }
        secondController.tabManager.updateTab(id: secondTabID) {
            $0.workingDirectory = URL(fileURLWithPath: sharedPath, isDirectory: true)
        }
        delegate.bindHookSession("sess-bound-cwd", to: secondTabID)

        delegate.handleCwdChangedHook(HookEvent(
            type: .cwdChanged,
            sessionId: "sess-bound-cwd",
            data: .cwdChanged(CwdChangedData(previousCwd: sharedPath)),
            cwd: updatedPath
        ))

        #expect(firstController.tabManager.tab(for: firstTabID)?.workingDirectory.path == sharedPath)
        #expect(secondController.tabManager.tab(for: secondTabID)?.workingDirectory.path == updatedPath)
    }

    @Test("unbound ambiguous duplicate previous directories are dropped")
    func cwdChangedWithoutBindingDropsAmbiguousDuplicatePreviousCwds() {
        let delegate = AppDelegate()
        let firstController = MainWindowController(bridge: MockTerminalEngine())
        let secondController = MainWindowController(bridge: MockTerminalEngine())
        delegate.additionalWindowControllers = [firstController, secondController]

        let sharedPath = "/tmp/cocxy-shared-cwd"
        let updatedPath = "/tmp/cocxy-updated-cwd"
        let firstTabID = firstController.tabManager.tabs.first!.id
        let secondTabID = secondController.tabManager.tabs.first!.id

        firstController.tabManager.updateTab(id: firstTabID) {
            $0.workingDirectory = URL(fileURLWithPath: sharedPath, isDirectory: true)
        }
        secondController.tabManager.updateTab(id: secondTabID) {
            $0.workingDirectory = URL(fileURLWithPath: sharedPath, isDirectory: true)
        }

        delegate.handleCwdChangedHook(HookEvent(
            type: .cwdChanged,
            sessionId: "sess-unbound-ambiguous",
            data: .cwdChanged(CwdChangedData(previousCwd: sharedPath)),
            cwd: updatedPath
        ))

        #expect(firstController.tabManager.tab(for: firstTabID)?.workingDirectory.path == sharedPath)
        #expect(secondController.tabManager.tab(for: secondTabID)?.workingDirectory.path == sharedPath)
    }
}
