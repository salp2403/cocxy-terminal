// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemeBrowserSwiftTestingTests.swift - Searchable theme browser coverage.

import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("ThemeBrowser")
@MainActor
struct ThemeBrowserSwiftTestingTests {

    @Test("ThemeBrowserCatalog exposes existing engine themes and fuzzy search")
    func catalogSearchesAvailableThemes() throws {
        let engine = ThemeEngineImpl()
        let catalog = ThemeBrowserCatalog(themeEngine: engine)

        #expect(catalog.items.count >= 11)
        #expect(catalog.filteredItems(query: "mocha", filter: .all).first?.name == "Catppuccin Mocha")
        #expect(catalog.filteredItems(query: "solar dark", filter: .all).contains { $0.name == "Solarized Dark" })
    }

    @Test("ThemeBrowserCatalog filters by variant and source")
    func catalogFiltersByVariantAndSource() throws {
        let engine = ThemeEngineImpl()
        let catalog = ThemeBrowserCatalog(themeEngine: engine)

        #expect(catalog.filteredItems(query: "", filter: .dark).allSatisfy { $0.variant == .dark })
        #expect(catalog.filteredItems(query: "", filter: .light).allSatisfy { $0.variant == .light })
        #expect(catalog.filteredItems(query: "", filter: .builtIn).allSatisfy { $0.sourceKind == .builtIn })
    }

    @Test("ExternalTerminalThemeParser maps terminal palette files to Cocxy themes")
    func externalParserMapsPalette() throws {
        let theme = try ExternalTerminalThemeParser.parse(
            externalThemeFixture(name: "Imported Smoke"),
            displayName: "Imported Smoke",
            author: "Local"
        )

        #expect(theme.metadata.name == "Imported Smoke")
        #expect(theme.metadata.variant == .dark)
        #expect(theme.palette.background == "#101014")
        #expect(theme.palette.foreground == "#f4f4f5")
        #expect(theme.palette.cursor == "#f4f4f5")
        #expect(theme.palette.selectionBackground == "#353542")
        #expect(theme.palette.selectionForeground == "#ffffff")
        #expect(theme.palette.ansiColors.count == 16)
        #expect(theme.palette.ansiColors[1] == "#ff5555")
        #expect(theme.palette.ansiColors[15] == "#ffffff")
    }

    @Test("ThemeImporter persists parsed external themes as Cocxy TOML")
    func importerPersistsExternalThemes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-theme-import-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("smoke-palette.theme")
        try externalThemeFixture(name: "Smoke Palette").write(to: source, atomically: true, encoding: .utf8)

        let importer = ThemeImporter(destinationDirectory: root.appendingPathComponent("themes"))
        let imported = try importer.importExternalTheme(from: source)

        #expect(FileManager.default.fileExists(atPath: imported.fileURL.path))
        let saved = try String(contentsOf: imported.fileURL, encoding: .utf8)
        let reparsed = try ThemeTomlParser.parse(saved)

        #expect(imported.theme.metadata.name == "Smoke Palette")
        #expect(reparsed.metadata.name == "Smoke Palette")
        #expect(reparsed.palette.ansiColors == imported.theme.palette.ansiColors)
    }

    @Test("ThemeBrowserViewModel previews applies and restores themes")
    func viewModelPreviewsAppliesAndRestores() throws {
        let engine = ThemeEngineImpl()
        var applied: [String] = []
        let viewModel = ThemeBrowserViewModel(
            themeEngine: engine,
            importer: ThemeImporter(destinationDirectory: FileManager.default.temporaryDirectory),
            applyTheme: { applied.append($0) }
        )

        let oneDark = try #require(viewModel.items.first { $0.name == "One Dark" })
        viewModel.preview(oneDark)
        viewModel.restorePreviewIfNeeded()

        #expect(applied == ["One Dark", "Catppuccin Mocha"])
    }

    @Test("ThemePickerView can be constructed for the real theme engine")
    func themePickerViewConstructs() throws {
        let engine = ThemeEngineImpl()
        let viewModel = ThemeBrowserViewModel(
            themeEngine: engine,
            importer: ThemeImporter(destinationDirectory: FileManager.default.temporaryDirectory),
            applyTheme: { _ in }
        )

        let view = ThemePickerView(
            viewModel: viewModel,
            onImportRequested: {},
            onClose: {}
        )

        _ = view.body
        #expect(viewModel.items.count >= 11)
    }

    @Test("ThemeBrowserCatalog exposes at least 200 searchable built-in themes")
    func catalogExposesLargeSearchableBuiltInSet() throws {
        let engine = ThemeEngineImpl()
        let catalog = ThemeBrowserCatalog(themeEngine: engine)

        #expect(catalog.items.count >= 200)
        #expect(catalog.filteredItems(query: "spectrum 042", filter: .all).contains {
            $0.name == "Cocxy Spectrum 042"
        })
        #expect(catalog.filteredItems(query: "spectrum", filter: .dark).count >= 80)
        #expect(catalog.filteredItems(query: "spectrum", filter: .light).count >= 80)
    }

    private func externalThemeFixture(name: String) -> String {
        """
        name = \(name)
        background = #101014
        foreground = #f4f4f5
        cursor-color = #f4f4f5
        selection-background = #353542
        selection-foreground = #ffffff
        palette = 0=#000000
        palette = 1=#ff5555
        palette = 2=#50fa7b
        palette = 3=#f1fa8c
        palette = 4=#bd93f9
        palette = 5=#ff79c6
        palette = 6=#8be9fd
        palette = 7=#bbbbbb
        palette = 8=#44475a
        palette = 9=#ff6e6e
        palette = 10=#69ff94
        palette = 11=#ffffa5
        palette = 12=#d6acff
        palette = 13=#ff92df
        palette = 14=#a4ffff
        palette = 15=#ffffff
        """
    }
}
