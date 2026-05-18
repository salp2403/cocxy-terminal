// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalConfigImportersSwiftTestingTests.swift - Terminal config importer coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Terminal config importers")
struct TerminalConfigImportersSwiftTestingTests {
    @Test("registry exposes the five supported terminal config sources")
    func registryExposesSupportedSources() {
        let registry = TerminalConfigImporterRegistry()

        #expect(registry.sources.map(\.rawValue) == ["ghostty", "iterm2", "alacritty", "kitty", "wezterm"])
    }

    @Test("Ghostty importer maps font theme cursor and background opacity")
    func ghosttyImporterMapsKnownKeys() throws {
        let importer = try #require(TerminalConfigImporterRegistry().importer(for: .ghostty))
        let preview = try importer.preview(
            contents: """
            font-family = JetBrains Mono
            font-size = 14
            theme = Catppuccin Mocha
            cursor-style = block
            background-opacity = 0.86
            """,
            sourceURL: URL(fileURLWithPath: "/tmp/ghostty/config")
        )

        #expect(preview.source == .ghostty)
        #expect(preview.changes.map(\.keyPath) == [
            "appearance.font-family",
            "appearance.font-size",
            "appearance.theme",
            "terminal.cursor-style",
            "appearance.background-opacity",
        ])
        #expect(preview.changes.map(\.value) == [
            "JetBrains Mono",
            "14",
            "Catppuccin Mocha",
            "block",
            "0.86",
        ])
        #expect(preview.requiresBackupBeforeApply)
    }

    @Test("Kitty importer maps underscore keys without leaking comments")
    func kittyImporterMapsKnownKeys() throws {
        let importer = try #require(TerminalConfigImporterRegistry().importer(for: .kitty))
        let preview = try importer.preview(
            contents: """
            # local terminal style
            font_family FiraCode Nerd Font
            font_size 13.5
            cursor_shape beam
            background_opacity 0.91
            """,
            sourceURL: URL(fileURLWithPath: "/tmp/kitty.conf")
        )

        #expect(preview.changes.map(\.keyPath) == [
            "appearance.font-family",
            "appearance.font-size",
            "terminal.cursor-style",
            "appearance.background-opacity",
        ])
        #expect(preview.changes.map(\.value) == [
            "FiraCode Nerd Font",
            "13.5",
            "beam",
            "0.91",
        ])
    }

    @Test("Alacritty importer maps YAML and TOML font keys")
    func alacrittyImporterMapsYamlAndTomlKeys() throws {
        let importer = try #require(TerminalConfigImporterRegistry().importer(for: .alacritty))
        let preview = try importer.preview(
            contents: """
            [font.normal]
            family = "SF Mono"
            [font]
            size = 15
            [window]
            opacity = 0.9
            """,
            sourceURL: URL(fileURLWithPath: "/tmp/alacritty.toml")
        )

        #expect(preview.changes.map(\.keyPath) == [
            "appearance.font-family",
            "appearance.font-size",
            "appearance.background-opacity",
        ])
        #expect(preview.changes.map(\.value) == ["SF Mono", "15", "0.9"])
    }

    @Test("WezTerm importer maps Lua assignments")
    func wezTermImporterMapsLuaAssignments() throws {
        let importer = try #require(TerminalConfigImporterRegistry().importer(for: .wezterm))
        let preview = try importer.preview(
            contents: """
            config.font = wezterm.font("Iosevka Term")
            config.font_size = 12.5
            config.color_scheme = "Tokyo Night"
            config.window_background_opacity = 0.88
            """,
            sourceURL: URL(fileURLWithPath: "/tmp/wezterm.lua")
        )

        #expect(preview.changes.map(\.keyPath) == [
            "appearance.font-family",
            "appearance.font-size",
            "appearance.theme",
            "appearance.background-opacity",
        ])
        #expect(preview.changes.map(\.value) == ["Iosevka Term", "12.5", "Tokyo Night", "0.88"])
    }

    @Test("iTerm2 importer reads XML plist font and color preset name")
    func iterm2ImporterReadsPlistKeys() throws {
        let importer = try #require(TerminalConfigImporterRegistry().importer(for: .iterm2))
        let preview = try importer.preview(
            contents: """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>Normal Font</key>
              <string>JetBrainsMonoNL-Regular 14</string>
              <key>Color Preset Name</key>
              <string>Dracula</string>
            </dict>
            </plist>
            """,
            sourceURL: URL(fileURLWithPath: "/tmp/theme.itermcolors")
        )

        #expect(preview.changes.map(\.keyPath) == ["appearance.font-family", "appearance.font-size", "appearance.theme"])
        #expect(preview.changes.map(\.value) == ["JetBrainsMonoNL-Regular", "14", "Dracula"])
    }
}
