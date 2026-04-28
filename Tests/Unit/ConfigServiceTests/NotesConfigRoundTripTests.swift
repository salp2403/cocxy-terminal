// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotesConfigRoundTripTests.swift - TOML round-trip coverage for the
// `[notes]` section.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `[notes]` section's load/save contract: defaults are the
/// documented values, the round-trip preserves every key, the parser
/// is tolerant of malformed values, missing sections degrade to
/// defaults, and the merge layer never silently drops the section
/// when project overrides apply.
@Suite("ConfigService — notes TOML round-trip")
struct NotesConfigRoundTripTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        private(set) var writtenContent: String?

        init(content: String? = nil) { self.content = content }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
            writtenContent = content
            self.content = content
        }
    }

    private func loadConfig(from toml: String) throws -> CocxyConfig {
        let provider = InMemoryProvider(content: toml)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        return service.current
    }

    // MARK: - Defaults

    @Test
    func defaultConfigCarriesDocumentedNotesValues() {
        let defaults = CocxyConfig.defaults
        #expect(defaults.notes.enabled == true)
        #expect(defaults.notes.format == .markdown)
        #expect(defaults.notes.searchEngine == .grep)
        #expect(defaults.notes.storageDir == "~/.config/cocxy/notes")
        #expect(defaults.notes.shortcut == "cmd+alt+n")
        #expect(defaults.notes.autoSave == true)
        #expect(defaults.notes.autoSaveIntervalSeconds == 5)
    }

    @Test
    func defaultTomlTemplateContainsNotesSection() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("[notes]"))
        #expect(generated.contains("format = \"markdown\""))
        #expect(generated.contains("search-engine = \"grep\""))
        #expect(generated.contains("shortcut = \"cmd+alt+n\""))
    }

    // MARK: - Round-trip

    @Test
    func tomlRoundTripPreservesEveryNotesKey() throws {
        let toml = """
        [notes]
        enabled = false
        format = "markdown-frontmatter"
        search-engine = "fts5"
        storage-dir = "/Users/sample/Notes"
        shortcut = "cmd+shift+e"
        auto-save = false
        auto-save-interval-seconds = 1.25
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.enabled == false)
        #expect(config.notes.format == .markdownFrontmatter)
        #expect(config.notes.searchEngine == .fts5)
        #expect(config.notes.storageDir == "/Users/sample/Notes")
        #expect(config.notes.shortcut == "cmd+shift+e")
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.windowNotes.id) == "cmd+shift+e")
        #expect(config.notes.autoSave == false)
        #expect(config.notes.autoSaveIntervalSeconds == 1.25)
    }

    @Test
    func notesShortcutAcceptsOptionAliasAndNormalizesToKeybindingsCatalog() throws {
        let toml = """
        [notes]
        shortcut = "cmd+option+n"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.shortcut == "cmd+alt+n")
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.windowNotes.id) == "cmd+alt+n")
    }

    @Test
    func explicitKeybindingOverrideWinsOverNotesShortcutFallback() throws {
        let toml = """
        [notes]
        shortcut = "cmd+shift+n"

        [keybindings]
        "window.notes" = "cmd+ctrl+n"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.shortcut == "cmd+shift+n")
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.windowNotes.id) == "cmd+ctrl+n")
    }

    @Test
    func invalidNotesShortcutFallsBackToDefault() throws {
        let toml = """
        [notes]
        shortcut = "cmd+bad+shortcut"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.shortcut == NotesConfig.defaults.shortcut)
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.windowNotes.id) == NotesConfig.defaults.shortcut)
    }

    @Test
    func unassignableNotesShortcutFallsBackToDefault() throws {
        let toml = """
        [notes]
        shortcut = "cmd+shift+period"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.shortcut == NotesConfig.defaults.shortcut)
        #expect(config.keybindings.shortcutString(for: KeybindingActionCatalog.windowNotes.id) == NotesConfig.defaults.shortcut)
    }

    @Test
    func tomlRoundTripAcceptsSpotlightEngine() throws {
        let toml = """
        [notes]
        search-engine = "spotlight"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.searchEngine == .spotlight)
    }

    // MARK: - Tolerant parsing

    @Test
    func missingSectionProducesDefaults() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        background-opacity = 0.9
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes == NotesConfig.defaults)
    }

    @Test
    func invalidFormatStringFallsBackToDefault() throws {
        let toml = """
        [notes]
        format = "yaml"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.format == .markdown)
    }

    @Test
    func invalidSearchEngineFallsBackToDefault() throws {
        let toml = """
        [notes]
        search-engine = "ripgrep"
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.searchEngine == .grep)
    }

    @Test
    func autoSaveIntervalIsClampedAtLowerBound() throws {
        let toml = """
        [notes]
        auto-save-interval-seconds = 0.0
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.autoSaveIntervalSeconds >= 0.1)
    }

    @Test
    func autoSaveIntervalIsClampedAtUpperBound() throws {
        let toml = """
        [notes]
        auto-save-interval-seconds = 9999
        """
        let config = try loadConfig(from: toml)

        #expect(config.notes.autoSaveIntervalSeconds <= 60)
    }

    // MARK: - Decoder backwards compatibility

    @Test
    func legacyJsonWithoutNotesSectionDecodesAsDefaults() throws {
        // Simulates a CocxyConfig persisted before the `[notes]` section
        // existed. The decoder must treat the missing key as the
        // runtime default so older session JSON snapshots load cleanly.
        let legacyJson = """
        {
          "general": {
            "shell": "/bin/zsh",
            "workingDirectory": "~",
            "confirmCloseProcess": true
          },
          "appearance": {
            "theme": "catppuccin-mocha",
            "lightTheme": "catppuccin-latte",
            "fontFamily": "Menlo",
            "fontSize": 14,
            "tabPosition": "left",
            "windowPadding": 8,
            "windowPaddingX": null,
            "windowPaddingY": null,
            "ligatures": false,
            "backgroundOpacity": 0.9,
            "backgroundBlurRadius": 0
          },
          "terminal": {
            "scrollbackLines": 10000,
            "cursorStyle": "bar",
            "cursorBlink": true,
            "cursorOpacity": 0.8,
            "mouseHideWhileTyping": true,
            "copyOnSelect": true,
            "clipboardPasteProtection": true,
            "clipboardReadAccess": "prompt",
            "imageMemoryLimitMB": 256,
            "imageFileTransfer": false,
            "enableSixelImages": true,
            "enableKittyImages": true
          },
          "agentDetection": {
            "enabled": true,
            "oscNotifications": true,
            "patternMatching": true,
            "timingHeuristics": true,
            "idleTimeoutSeconds": 5
          },
          "codeReview": {
            "autoShowOnSessionEnd": true
          },
          "notifications": {
            "macosNotifications": true,
            "sound": true,
            "badgeOnTab": true,
            "flashTab": true,
            "showDockBadge": true,
            "soundFinished": "Sounds/cocxy-finished.caf",
            "soundAttention": "Sounds/cocxy-attention.caf",
            "soundError": "Sounds/cocxy-error.caf"
          },
          "quickTerminal": {
            "enabled": true,
            "hotkey": "cmd+grave",
            "position": "top",
            "heightPercentage": 40,
            "hideOnDeactivate": true,
            "workingDirectory": "~",
            "animationDuration": 0.15,
            "screen": "mouse"
          },
          "keybindings": {
            "newTab": "cmd+t",
            "closeTab": "cmd+w",
            "nextTab": "cmd+shift+]",
            "prevTab": "cmd+shift+[",
            "splitVertical": "cmd+d",
            "splitHorizontal": "cmd+shift+d",
            "gotoAttention": "cmd+shift+u",
            "toggleQuickTerminal": "cmd+grave"
          },
          "sessions": {
            "autoSave": true,
            "autoSaveInterval": 30,
            "restoreOnLaunch": true
          }
        }
        """

        let data = Data(legacyJson.utf8)
        let decoded = try JSONDecoder().decode(CocxyConfig.self, from: data)
        #expect(decoded.notes == NotesConfig.defaults)
    }

    // MARK: - Project overrides preserve the section

    @Test
    func projectOverridesPreserveNotesSectionVerbatim() {
        // Notes is global by design — the merge layer must round-trip
        // it unchanged regardless of which fields the project supplies.
        let base = CocxyConfig.defaults
        let custom = NotesConfig(
            enabled: false,
            format: .markdownFrontmatter,
            searchEngine: .fts5,
            storageDir: "/var/notes",
            shortcut: "cmd+shift+e",
            autoSave: false,
            autoSaveIntervalSeconds: 0.5
        )
        let rootWithCustomNotes = CocxyConfig(
            general: base.general,
            appearance: base.appearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions,
            worktree: base.worktree,
            github: base.github,
            notes: custom
        )
        let overrides = ProjectConfig(fontSize: 18, windowPadding: 12)

        let merged = rootWithCustomNotes.applying(projectOverrides: overrides)

        #expect(merged.notes == custom)
        #expect(merged.appearance.fontSize == 18)
    }

    // MARK: - Preferences wiring

    @Test
    @MainActor
    func preferencesGenerateTomlEmitsNotesSectionFromSavedConfig() throws {
        // Preferences exposes the notes section now, so `generateToml`
        // must emit the editable snapshot loaded from `savedConfig`.
        // Saving an unrelated setting must not reset these fields.
        let custom = NotesConfig(
            enabled: false,
            format: .markdownFrontmatter,
            searchEngine: .fts5,
            storageDir: "/var/notes",
            shortcut: "cmd+shift+e",
            autoSave: false,
            autoSaveIntervalSeconds: 1.5
        )
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            notes: custom
        )
        let provider = InMemoryProvider()
        let viewModel = PreferencesViewModel(config: config, fileProvider: provider)

        let toml = viewModel.generateToml()

        #expect(toml.contains("[notes]"))
        #expect(toml.contains("enabled = false"))
        #expect(toml.contains("format = \"markdown-frontmatter\""))
        #expect(toml.contains("search-engine = \"fts5\""))
        #expect(toml.contains("storage-dir = \"/var/notes\""))
        #expect(toml.contains("shortcut = \"cmd+shift+e\""))
        #expect(toml.contains("auto-save = false"))
    }

    @Test
    @MainActor
    func preferencesSavedSnapshotPreservesNotesAfterUnrelatedEdit() throws {
        // Regression guard for the canonical config-pipeline bug:
        // an unrelated edit (font size, etc.) must save the current
        // Notes values rather than reverting the section to defaults.
        let custom = NotesConfig(
            enabled: false,
            format: .markdownFrontmatter,
            searchEngine: .fts5,
            storageDir: "/var/notes",
            shortcut: "cmd+shift+e",
            autoSave: false,
            autoSaveIntervalSeconds: 1.5
        )
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults,
            notes: custom
        )
        let provider = InMemoryProvider()
        let viewModel = PreferencesViewModel(config: config, fileProvider: provider)

        viewModel.fontSize = 18

        try viewModel.save()

        // The view model rebuilds savedConfig as part of save; the
        // notes section must round-trip through that rebuild.
        let saved = provider.writtenContent ?? ""
        #expect(saved.contains("storage-dir = \"/var/notes\""))
        #expect(saved.contains("shortcut = \"cmd+shift+e\""))
    }

    @Test
    @MainActor
    func preferencesCanEditEveryNotesField() throws {
        let provider = InMemoryProvider()
        let viewModel = PreferencesViewModel(config: .defaults, fileProvider: provider)

        viewModel.notesEnabled = false
        viewModel.notesFormat = NoteFormat.markdownFrontmatter.rawValue
        viewModel.notesSearchEngine = NoteSearchEngineKind.spotlight.rawValue
        viewModel.notesStorageDir = "/tmp/cocxy-notes"
        viewModel.notesShortcut = "cmd+shift+."
        viewModel.notesAutoSave = false
        viewModel.notesAutoSaveIntervalSeconds = 2.5

        try viewModel.save()
        let saved = provider.writtenContent ?? ""

        #expect(saved.contains("enabled = false"))
        #expect(saved.contains("format = \"markdown-frontmatter\""))
        #expect(saved.contains("search-engine = \"spotlight\""))
        #expect(saved.contains("storage-dir = \"/tmp/cocxy-notes\""))
        #expect(saved.contains("shortcut = \"cmd+shift+.\""))
        #expect(saved.contains("auto-save = false"))
        #expect(saved.contains("auto-save-interval-seconds = 2.5"))
    }
}
