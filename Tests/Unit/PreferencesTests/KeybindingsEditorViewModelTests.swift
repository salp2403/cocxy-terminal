// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingsEditorViewModelTests.swift - Editor view model behavior tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("KeybindingsEditorViewModel initial state")
@MainActor
struct KeybindingsEditorViewModelInitTests {

    @Test func loadsEveryActionFromConfig() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)

        for action in KeybindingActionCatalog.all {
            let resolved = viewModel.rawShortcut(for: action.id)
            #expect(!resolved.isEmpty, "Action \(action.id) should have a default shortcut")
        }
    }

    @Test func defaultsStartNotCustomized() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)

        for action in KeybindingActionCatalog.all {
            #expect(viewModel.isCustomized(action.id) == false, "\(action.id) should not appear customized")
        }
    }

    @Test func hasNoConflictsForFactoryDefaults() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        #expect(viewModel.hasConflicts == false)
        #expect(viewModel.conflictGroups().isEmpty)
    }
}

@Suite("KeybindingsEditorViewModel mutation")
@MainActor
struct KeybindingsEditorViewModelMutationTests {

    @Test func assignUpdatesShortcut() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        let target = KeybindingActionCatalog.tabNew

        let newShortcut = KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "t")
        let applied = viewModel.assign(newShortcut, to: target.id)

        #expect(applied == true)
        #expect(viewModel.rawShortcut(for: target.id) == "cmd+shift+t")
        #expect(viewModel.isCustomized(target.id) == true)
    }

    @Test func assignNilReportsFailure() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        let applied = viewModel.assign(nil, to: KeybindingActionCatalog.tabNew.id)
        #expect(applied == false)
        #expect(viewModel.statusMessage != nil)
    }

    @Test func resetRestoresDefault() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        let target = KeybindingActionCatalog.tabNew
        _ = viewModel.assign(KeybindingShortcut(requiresCommand: true, baseKey: "y"), to: target.id)
        #expect(viewModel.isCustomized(target.id) == true)

        viewModel.reset(target.id)
        #expect(viewModel.isCustomized(target.id) == false)
        #expect(viewModel.rawShortcut(for: target.id) == target.defaultShortcut.canonical)
    }

    @Test func resetAllRestoresEveryDefault() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        _ = viewModel.assign(KeybindingShortcut(requiresCommand: true, baseKey: "y"), to: KeybindingActionCatalog.tabNew.id)
        _ = viewModel.assign(KeybindingShortcut(requiresControl: true, baseKey: "p"), to: KeybindingActionCatalog.splitHorizontal.id)

        viewModel.resetAll()

        for action in KeybindingActionCatalog.all {
            #expect(viewModel.isCustomized(action.id) == false)
        }
    }

    @Test func clearEmptiesShortcut() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        let target = KeybindingActionCatalog.tabNew
        viewModel.clear(target.id)
        #expect(viewModel.rawShortcut(for: target.id) == "")
    }
}

@Suite("KeybindingsEditorViewModel conflicts")
@MainActor
struct KeybindingsEditorViewModelConflictTests {

    @Test func conflictDetectedAcrossActions() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)

        let shortcut = KeybindingShortcut(requiresCommand: true, baseKey: "t")
        // Cmd+T is the default for tab.new; assigning it to another action
        // should make conflictingActionIds return tab.new.
        _ = viewModel.assign(shortcut, to: KeybindingActionCatalog.splitHorizontal.id)

        let conflicts = viewModel.conflictingActionIds(
            for: "cmd+t",
            excluding: KeybindingActionCatalog.splitHorizontal.id
        )
        #expect(conflicts.contains(KeybindingActionCatalog.tabNew.id))
        #expect(viewModel.hasConflicts == true)
    }

    @Test func emptyShortcutNeverConflicts() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        viewModel.clear(KeybindingActionCatalog.tabNew.id)
        let conflicts = viewModel.conflictingActionIds(for: "", excluding: KeybindingActionCatalog.tabClose.id)
        #expect(conflicts.isEmpty)
    }

    @Test func resolvingConflictClearsHasConflicts() {
        let viewModel = KeybindingsEditorViewModel(config: .defaults)
        // Create a conflict, then resolve it.
        let clash = KeybindingShortcut(requiresCommand: true, baseKey: "t")
        _ = viewModel.assign(clash, to: KeybindingActionCatalog.splitHorizontal.id)
        #expect(viewModel.hasConflicts == true)

        // Rebind the second conflicting action to something unique.
        let free = KeybindingShortcut(requiresCommand: true, requiresOption: true, baseKey: "y")
        _ = viewModel.assign(free, to: KeybindingActionCatalog.splitHorizontal.id)
        #expect(viewModel.hasConflicts == false)
    }
}

@Suite("KeybindingsEditorViewModel persistence")
@MainActor
struct KeybindingsEditorViewModelPersistenceTests {

    /// In-memory file provider that captures the last-written TOML so tests
    /// can inspect it without touching the filesystem.
    final class InMemoryFileProvider: ConfigFileProviding, @unchecked Sendable {
        var stored: String?

        func readConfigFile() -> String? { stored }

        func writeConfigFile(_ content: String) throws {
            stored = content
        }
    }

    @Test func saveWritesCustomOverrideToToml() throws {
        let fileProvider = InMemoryFileProvider()
        let preferences = PreferencesViewModel(config: .defaults, fileProvider: fileProvider)
        let editor = preferences.keybindingsEditor

        // Customize an action that is NOT in the legacy-fields mapping so it
        // lands in customOverrides. Choose a non-default shortcut so the
        // override is persisted.
        let rebinding = KeybindingShortcut(requiresCommand: true, requiresControl: true, baseKey: "k")
        #expect(editor.assign(rebinding, to: KeybindingActionCatalog.splitClose.id) == true)

        try editor.save()

        let content = try #require(fileProvider.stored)
        #expect(content.contains("\"split.close\" = \"cmd+ctrl+k\""))
    }

    @Test func saveWritesLegacyFieldForTabNew() throws {
        let fileProvider = InMemoryFileProvider()
        let preferences = PreferencesViewModel(config: .defaults, fileProvider: fileProvider)
        let editor = preferences.keybindingsEditor

        let rebinding = KeybindingShortcut(requiresCommand: true, requiresShift: true, baseKey: "n")
        #expect(editor.assign(rebinding, to: KeybindingActionCatalog.tabNew.id) == true)

        try editor.save()
        let content = try #require(fileProvider.stored)

        #expect(content.contains("new-tab = \"cmd+shift+n\""))
        // Legacy overrides must not leak into the customOverrides section.
        #expect(!content.contains("\"tab.new\" ="))
    }

    @Test func saveBlockedByConflicts() {
        let preferences = PreferencesViewModel(config: .defaults, fileProvider: InMemoryFileProvider())
        let editor = preferences.keybindingsEditor

        let clash = KeybindingShortcut(requiresCommand: true, baseKey: "t")
        _ = editor.assign(clash, to: KeybindingActionCatalog.splitHorizontal.id)

        #expect(editor.hasConflicts == true)
        do {
            try editor.save()
            Issue.record("save() should throw when conflicts remain unresolved")
        } catch let error as KeybindingsEditorViewModel.SaveError {
            #expect(error == .conflictsUnresolved)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func savedSnapshotResetsUnsavedChanges() throws {
        let fileProvider = InMemoryFileProvider()
        let preferences = PreferencesViewModel(config: .defaults, fileProvider: fileProvider)
        let editor = preferences.keybindingsEditor

        let rebinding = KeybindingShortcut(requiresCommand: true, requiresControl: true, baseKey: "q")
        _ = editor.assign(rebinding, to: KeybindingActionCatalog.splitClose.id)
        #expect(editor.hasUnsavedChanges == true)

        try editor.save()
        #expect(editor.hasUnsavedChanges == false)
    }
}
