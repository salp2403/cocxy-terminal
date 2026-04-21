// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeConfigRoundTripTests.swift - TOML and Codable round-trip
// coverage for the `[worktree]` section introduced in v0.1.81.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConfigService — [worktree] TOML round-trip")
struct WorktreeConfigRoundTripTests {

    // MARK: - Helpers

    /// In-memory provider so tests can drive `ConfigService` without
    /// touching the filesystem.
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?

        init(content: String? = nil) {
            self.content = content
        }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
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

    @Test("default CocxyConfig has worktree feature disabled")
    func defaultConfigHasWorktreeDisabled() {
        let defaults = CocxyConfig.defaults
        #expect(defaults.worktree.enabled == false)
        #expect(defaults.worktree.basePath == "~/.cocxy/worktrees")
        #expect(defaults.worktree.branchTemplate == "cocxy/{agent}/{id}")
        #expect(defaults.worktree.baseRef == "HEAD")
        #expect(defaults.worktree.onClose == .keep)
        #expect(defaults.worktree.openInNewTab == true)
        #expect(defaults.worktree.idLength == 6)
        #expect(defaults.worktree.inheritProjectConfig == true)
        #expect(defaults.worktree.showBadge == true)
    }

    @Test("default TOML template contains [worktree] section with safe defaults")
    func defaultTomlTemplateContainsWorktreeSection() {
        let generated = ConfigService.generateDefaultToml()
        #expect(generated.contains("[worktree]"))
        #expect(generated.contains("enabled = false"))
        #expect(generated.contains("base-path = \"~/.cocxy/worktrees\""))
        #expect(generated.contains("branch-template = \"cocxy/{agent}/{id}\""))
        #expect(generated.contains("base-ref = \"HEAD\""))
        #expect(generated.contains("on-close = \"keep\""))
        #expect(generated.contains("open-in-new-tab = true"))
        #expect(generated.contains("id-length = 6"))
        #expect(generated.contains("inherit-project-config = true"))
        #expect(generated.contains("show-badge = true"))
    }

    // MARK: - Round-trip with all fields set

    @Test("TOML round-trip preserves every [worktree] field")
    func tomlRoundTripPreservesAllFields() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"

        [worktree]
        enabled = true
        base-path = "/tmp/worktree-storage"
        branch-template = "feat/{id}-{date}"
        base-ref = "develop"
        on-close = "remove"
        open-in-new-tab = false
        id-length = 8
        inherit-project-config = false
        show-badge = false
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree.enabled == true)
        #expect(config.worktree.basePath == "/tmp/worktree-storage")
        #expect(config.worktree.branchTemplate == "feat/{id}-{date}")
        #expect(config.worktree.baseRef == "develop")
        #expect(config.worktree.onClose == .remove)
        #expect(config.worktree.openInNewTab == false)
        #expect(config.worktree.idLength == 8)
        #expect(config.worktree.inheritProjectConfig == false)
        #expect(config.worktree.showBadge == false)
    }

    // MARK: - Tolerant parsing

    @Test("missing [worktree] section falls back to all defaults")
    func missingWorktreeSectionProducesDefaults() throws {
        let toml = """
        [appearance]
        theme = "catppuccin-mocha"
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree == WorktreeConfig.defaults)
    }

    @Test("partial [worktree] table fills gaps with defaults")
    func partialWorktreeTableFillsWithDefaults() throws {
        let toml = """
        [worktree]
        enabled = true
        id-length = 9
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree.enabled == true)
        #expect(config.worktree.idLength == 9)
        // Other fields stay at default.
        #expect(config.worktree.basePath == "~/.cocxy/worktrees")
        #expect(config.worktree.onClose == .keep)
        #expect(config.worktree.showBadge == true)
    }

    @Test("unknown on-close value falls back to keep (never destructive)")
    func invalidOnCloseValueFallsBackToKeep() throws {
        let toml = """
        [worktree]
        enabled = true
        on-close = "nuke-everything"
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree.onClose == .keep)
    }

    @Test("id-length below minimum clamps to WorktreeConfig.minIDLength")
    func idLengthClampedBelowMinimum() throws {
        let toml = """
        [worktree]
        id-length = 1
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree.idLength == WorktreeConfig.minIDLength)
    }

    @Test("id-length above maximum clamps to WorktreeConfig.maxIDLength")
    func idLengthClampedAboveMaximum() throws {
        let toml = """
        [worktree]
        id-length = 99
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree.idLength == WorktreeConfig.maxIDLength)
    }

    @Test("non-boolean enabled value falls back to default (false)")
    func invalidEnabledTypeFallsBackToDefault() throws {
        // Mirrors the tolerant contract used by every other parser.
        let toml = """
        [worktree]
        enabled = "yes"
        """
        let config = try loadConfig(from: toml)

        #expect(config.worktree.enabled == false)
    }

    // MARK: - Template round-trip

    @Test("generated default TOML toggled on disk round-trips the enabled flag")
    func generatedTomlWithEnabledToggleRoundTrips() throws {
        // Simulates Preferences writing an opt-in config back to disk.
        // `enabled = false` appears only in the [worktree] section of the
        // default template — all other sections with an `enabled` key
        // default to true — so a global replace is safe and targeted.
        let base = ConfigService.generateDefaultToml()
        let toggled = base.replacingOccurrences(
            of: "enabled = false",
            with: "enabled = true"
        )
        let config = try loadConfig(from: toggled)

        #expect(config.worktree.enabled == true)
        // Other fields stay at their template defaults.
        #expect(config.worktree.onClose == .keep)
        #expect(config.worktree.idLength == 6)
    }

    // MARK: - Codable backwards compatibility

    @Test("legacy JSON without worktree key decodes with defaults")
    func legacyJsonWithoutWorktreeKeyDecodesAsDefaults() throws {
        // Simulates a CocxyConfig JSON persisted before v0.1.81 when the
        // worktree key did not exist. Swift's explicit `init(from:)` uses
        // `decodeIfPresent(forKey: .worktree)` and falls back to defaults
        // so the new upgrade path never fails on legacy payloads.
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
            "fontThicken": false,
            "backgroundOpacity": 0.9,
            "backgroundBlurRadius": 0,
            "transparencyChromeTheme": "follow-system",
            "auroraEnabled": true
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
            "toggleQuickTerminal": "cmd+grave",
            "customOverrides": {}
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

        #expect(decoded.worktree == WorktreeConfig.defaults)
    }

    // MARK: - applying(projectOverrides:) passthrough

    @Test("applying(projectOverrides:) preserves the worktree section unchanged")
    func projectOverridesPreserveWorktree() {
        // Fase 1c will extend ProjectConfig with per-project worktree
        // overrides; until then the merge must not mutate the worktree
        // section even when unrelated overrides (fontSize etc.) are set.
        let base = CocxyConfig.defaults
        let enabledWorktree = WorktreeConfig(
            enabled: true,
            basePath: "/custom/path",
            branchTemplate: "task/{id}",
            baseRef: "main",
            onClose: .prompt,
            openInNewTab: false,
            idLength: 10,
            inheritProjectConfig: false,
            showBadge: false
        )
        let root = CocxyConfig(
            general: base.general,
            appearance: base.appearance,
            terminal: base.terminal,
            agentDetection: base.agentDetection,
            codeReview: base.codeReview,
            notifications: base.notifications,
            quickTerminal: base.quickTerminal,
            keybindings: base.keybindings,
            sessions: base.sessions,
            worktree: enabledWorktree
        )

        let merged = root.applying(projectOverrides: ProjectConfig(fontSize: 18))

        #expect(merged.worktree == enabledWorktree)
    }
}
