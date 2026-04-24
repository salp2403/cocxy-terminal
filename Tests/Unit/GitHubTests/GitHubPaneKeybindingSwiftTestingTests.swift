// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneKeybindingSwiftTestingTests.swift - Verifies the
// `windowGitHubPane` catalog entry is wired into every surface the
// pane reaches: the keybinding catalog and the command palette
// mapping. These are tiny pure checks that fail loudly when someone
// removes the action id without updating its consumers.

import Testing
@testable import CocxyTerminal

@Suite("GitHubPane keybinding")
struct GitHubPaneKeybindingSwiftTestingTests {

    @Test("Catalog exposes the window.githubPane action")
    func catalog_exposesWindowGithubPaneAction() {
        let action = KeybindingActionCatalog.windowGitHubPane
        #expect(action.id == "window.githubPane")
        #expect(action.category == .window)
        #expect(action.displayName == "Toggle GitHub Pane")
    }

    @Test("Default shortcut is Cmd+Option+G")
    func catalog_defaultShortcutIsCmdOptionG() {
        let shortcut = KeybindingActionCatalog.windowGitHubPane.defaultShortcut
        #expect(shortcut.requiresCommand)
        #expect(shortcut.requiresOption)
        #expect(shortcut.requiresShift == false)
        #expect(shortcut.requiresControl == false)
        #expect(shortcut.baseKey == "g")
    }

    @Test("Catalog.all contains the GitHub pane action exactly once")
    func catalog_allContainsGithubPaneExactlyOnce() {
        let count = KeybindingActionCatalog.all.filter { $0.id == "window.githubPane" }.count
        #expect(count == 1)
    }

    @Test("catalogEntry(for:) resolves the GitHub pane action id")
    func catalogEntry_resolvesGithubPaneID() {
        let entry = KeybindingAction.catalogEntry(for: "window.githubPane")
        #expect(entry != nil)
        #expect(entry?.displayName == "Toggle GitHub Pane")
    }
}
