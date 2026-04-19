// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pure coverage for the Aurora command palette's data layer.
///
/// The SwiftUI view itself renders through AppKit and can't easily be
/// diffed in a unit test, but its filtering behaviour is the single
/// observable contract the host depends on: the integration layer
/// types into the palette and expects `AuroraPaletteFilter.filter(...)`
/// to trim the list to the rows that match. Pinning the rules here
/// keeps the view a thin declarative shell and catches regressions the
/// moment the rules drift.
@Suite("Aurora command palette — filter")
struct AuroraCommandPaletteFilterTests {

    // MARK: - Empty query

    @Test("Empty query returns every action in the supplied order")
    func emptyQueryReturnsAllActions() {
        let result = Design.AuroraPaletteFilter.filter(Design.samplePaletteActions, by: "")
        #expect(result == Design.samplePaletteActions)
    }

    @Test("Whitespace-only query is treated the same as empty")
    func whitespaceQueryReturnsAllActions() {
        let result = Design.AuroraPaletteFilter.filter(Design.samplePaletteActions, by: "   \t\n")
        #expect(result == Design.samplePaletteActions)
    }

    // MARK: - Label / category / subtitle

    @Test("Matches the label case-insensitively")
    func matchesLabelCaseInsensitive() {
        let result = Design.AuroraPaletteFilter.filter(Design.samplePaletteActions, by: "SPLIT")
        #expect(result.map(\.id) == ["split.horizontal", "split.vertical", "split.close"])
    }

    @Test("Matches the category when the label does not contain the query")
    func matchesCategory() {
        let actions = [
            Design.AuroraPaletteAction(id: "foo.bar", label: "Foo bar", category: "Alpha"),
            Design.AuroraPaletteAction(id: "baz.qux", label: "Baz qux", category: "Beta"),
        ]
        let result = Design.AuroraPaletteFilter.filter(actions, by: "alpha")
        #expect(result.map(\.id) == ["foo.bar"])
    }

    @Test("Matches the subtitle when present")
    func matchesSubtitle() {
        let actions = [
            Design.AuroraPaletteAction(
                id: "theme.cycle",
                label: "Cycle theme",
                category: "Theme",
                subtitle: "aurora → paper → nocturne"
            ),
            Design.AuroraPaletteAction(id: "tab.new", label: "New tab", category: "Tabs"),
        ]
        let result = Design.AuroraPaletteFilter.filter(actions, by: "nocturne")
        #expect(result.map(\.id) == ["theme.cycle"])
    }

    @Test("Nil subtitle does not affect matching semantics")
    func nilSubtitleIsSafe() {
        let actions = [
            Design.AuroraPaletteAction(id: "tab.new", label: "New tab", category: "Tabs"),
        ]
        let result = Design.AuroraPaletteFilter.filter(actions, by: "tab")
        #expect(result.count == 1)
    }

    // MARK: - No match

    @Test("Unknown query returns an empty list")
    func unknownQueryReturnsEmpty() {
        let result = Design.AuroraPaletteFilter.filter(Design.samplePaletteActions, by: "qzxzzz")
        #expect(result.isEmpty)
    }

    // MARK: - Sample shape

    @Test("Sample catalog covers all major categories the design reference lists")
    func sampleCatalogCoversCategories() {
        let categories = Set(Design.samplePaletteActions.map(\.category))
        #expect(categories.isSuperset(of: ["Tabs", "Splits", "Window", "Theme"]))
    }

    @Test("Sample catalog entries all carry a shortcut hint")
    func sampleActionsExposeShortcut() {
        for action in Design.samplePaletteActions {
            #expect(
                action.shortcut != nil && !(action.shortcut ?? "").isEmpty,
                "Expected shortcut hint for \(action.id)"
            )
        }
    }
}
