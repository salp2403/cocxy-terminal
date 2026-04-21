// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteWorktreeSwiftTestingTests.swift - Coverage for the
// worktree-aware protocol additions and engine registration added in
// v0.1.81 (ajuste #3).

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CommandPalette — worktree actions")
@MainActor
struct CommandPaletteWorktreeSwiftTestingTests {

    // MARK: - Fixtures

    private func makeCoordinator() -> CommandPaletteCoordinatorImpl {
        CommandPaletteCoordinatorImpl(
            tabManager: TabManager(),
            splitManager: SplitManager(),
            dashboardViewModel: AgentDashboardViewModel(),
            themeEngine: nil
        )
    }

    // MARK: - Coordinator hooks

    @Test("createWorktreeTab invokes the onCreateWorktree closure")
    func createWorktreeTabInvokesClosure() {
        let coordinator = makeCoordinator()
        let hook = Hook()
        coordinator.onCreateWorktree = { hook.count += 1 }

        coordinator.createWorktreeTab()
        coordinator.createWorktreeTab()

        #expect(hook.count == 2)
    }

    @Test("createWorktreeTab with no hook is a silent no-op")
    func createWorktreeTabWithoutHook() {
        let coordinator = makeCoordinator()
        coordinator.createWorktreeTab() // Must not crash.
    }

    @Test("removeCurrentWorktree invokes the onRemoveWorktree closure")
    func removeCurrentWorktreeInvokesClosure() {
        let coordinator = makeCoordinator()
        let hook = Hook()
        coordinator.onRemoveWorktree = { hook.count += 1 }

        coordinator.removeCurrentWorktree()

        #expect(hook.count == 1)
    }

    @Test("removeCurrentWorktree with no hook is a silent no-op")
    func removeCurrentWorktreeWithoutHook() {
        let coordinator = makeCoordinator()
        coordinator.removeCurrentWorktree() // Must not crash.
    }

    // MARK: - Engine registration

    @Test("engine registers the worktree.create action with coordinator routing")
    func engineRegistersCreateAction() {
        let coordinator = makeCoordinator()
        let hook = Hook()
        coordinator.onCreateWorktree = { hook.count += 1 }
        let engine = CommandPaletteEngineImpl(coordinator: coordinator)

        guard let action = engine.allActions.first(where: { $0.id == "worktree.create" }) else {
            Issue.record("worktree.create action is missing from the engine registry")
            return
        }

        #expect(action.category == .worktree)
        #expect(action.name == "Create Agent Worktree Tab")
        action.handler()
        #expect(hook.count == 1)
    }

    @Test("engine registers the worktree.remove action with coordinator routing")
    func engineRegistersRemoveAction() {
        let coordinator = makeCoordinator()
        let hook = Hook()
        coordinator.onRemoveWorktree = { hook.count += 1 }
        let engine = CommandPaletteEngineImpl(coordinator: coordinator)

        guard let action = engine.allActions.first(where: { $0.id == "worktree.remove" }) else {
            Issue.record("worktree.remove action is missing from the engine registry")
            return
        }

        #expect(action.category == .worktree)
        action.handler()
        #expect(hook.count == 1)
    }

    @Test("CommandCategory enumerates the worktree category")
    func worktreeCategoryIsPresent() {
        #expect(CommandCategory.allCases.contains(.worktree))
        #expect(CommandCategory.worktree.rawValue == "Worktree")
    }

    // MARK: - Helpers

    /// Simple counter shared across the closure and the assertion.
    @MainActor
    private final class Hook {
        var count: Int = 0
    }
}
