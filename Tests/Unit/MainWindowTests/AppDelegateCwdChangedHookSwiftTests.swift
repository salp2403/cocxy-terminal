// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateCwdChangedHookSwiftTests.swift

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("AppDelegate CwdChanged hook routing")
@MainActor
struct AppDelegateCwdChangedHookSwiftTests {

    @Test("Claude settings decoder refuses malformed or non-object JSON")
    func settingsDecoderRejectsUnsafeReplacementInputs() throws {
        let valid = try #require(AppDelegate.decodeClaudeSettingsForUpdate(
            Data(#"{"theme":"dark"}"#.utf8)
        ))

        #expect(valid["theme"] as? String == "dark")
        #expect(AppDelegate.decodeClaudeSettingsForUpdate(Data("invalid".utf8)) == nil)
        #expect(AppDelegate.decodeClaudeSettingsForUpdate(Data("[]".utf8)) == nil)
    }

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

    @Test("closing a tab removes every hook routing binding owned by it")
    func tabClosePrunesHookBindings() {
        let delegate = AppDelegate()
        let closingTabID = TabID()
        let otherTabID = TabID()
        delegate.bindHookSession("closing-one", to: closingTabID, surfaceID: SurfaceID())
        delegate.bindHookSession("closing-two", to: closingTabID, surfaceID: SurfaceID())
        delegate.bindHookSession("remaining", to: otherTabID, surfaceID: SurfaceID())

        delegate.unbindHookSessions(for: closingTabID)

        #expect(delegate.hookSessionTabBindings["closing-one"] == nil)
        #expect(delegate.hookSessionSurfaceBindings["closing-one"] == nil)
        #expect(delegate.hookSessionTabBindings["closing-two"] == nil)
        #expect(delegate.hookSessionTabBindings["remaining"] == otherTabID)
        #expect(delegate.hookSessionSurfaceBindings["remaining"] != nil)
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

    @Test("an already-applied CwdChanged requires a prior binding and exact new directory")
    func alreadyAppliedCwdChangedRequiresBoundDestination() {
        let delegate = AppDelegate()
        let controller = MainWindowController(bridge: MockTerminalEngine())
        delegate.additionalWindowControllers = [controller]
        let tabID = controller.tabManager.tabs.first!.id
        let newPath = "/tmp/cocxy-new-cwd"
        controller.tabManager.updateTab(id: tabID) {
            $0.workingDirectory = URL(fileURLWithPath: newPath, isDirectory: true)
        }
        let event = HookEvent(
            type: .cwdChanged,
            sessionId: "sess-osc-race",
            data: .cwdChanged(CwdChangedData(previousCwd: "/tmp/cocxy-old-cwd")),
            cwd: newPath
        )

        #expect(delegate.isBoundCwdChangedAlreadyApplied(event) == false)

        delegate.bindHookSession("sess-osc-race", to: tabID)

        #expect(delegate.isBoundCwdChangedAlreadyApplied(event) == true)
        #expect(delegate.isBoundCwdChangedAlreadyApplied(HookEvent(
            type: .cwdChanged,
            sessionId: "sess-osc-race",
            data: .cwdChanged(CwdChangedData(previousCwd: "/tmp/cocxy-old-cwd")),
            cwd: "/tmp/different-destination"
        )) == false)
    }
}
