// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputSnippetExpanderSwiftTestingTests.swift - Rich Input snippet expansion tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Rich input snippet expander")
struct RichInputSnippetExpanderSwiftTestingTests {
    @Test("tab expansion replaces colon trigger before cursor and selects first tab stop")
    func tabExpansionReplacesColonTriggerBeforeCursorAndSelectsFirstTabStop() throws {
        let fixture = try snippetFixture(with: [
            Snippet(
                id: "swift-fn",
                name: "Swift Function",
                trigger: "snippet-name",
                body: "run ${1:target}\n$0"
            )
        ])
        defer { removeSnippetFixture(fixture) }
        let expander = RichInputSnippetExpander(snippetManager: fixture.manager)
        let text = "please :snippet-name"
        let cursor = NSRange(location: (text as NSString).length, length: 0)

        let edit = try #require(expander.expandSnippet(in: text, selectedRange: cursor))

        #expect(edit.text == "please run target\n")
        #expect(edit.selectedRange == NSRange(location: ("please run " as NSString).length, length: 6))
    }

    @Test("tab expansion returns nil when cursor is not after colon trigger")
    func tabExpansionReturnsNilWithoutColonTrigger() throws {
        let fixture = try snippetFixture(with: [
            Snippet(id: "plain", name: "Plain", trigger: "plain", body: "expanded")
        ])
        defer { removeSnippetFixture(fixture) }
        let expander = RichInputSnippetExpander(snippetManager: fixture.manager)
        let text = "plain"
        let cursor = NSRange(location: (text as NSString).length, length: 0)

        #expect(expander.expandSnippet(in: text, selectedRange: cursor) == nil)
    }

    @Test("tab expansion returns nil for missing snippet")
    func tabExpansionReturnsNilForMissingSnippet() throws {
        let fixture = try snippetFixture(with: [])
        defer { removeSnippetFixture(fixture) }
        let expander = RichInputSnippetExpander(snippetManager: fixture.manager)
        let text = ":missing"
        let cursor = NSRange(location: (text as NSString).length, length: 0)

        #expect(expander.expandSnippet(in: text, selectedRange: cursor) == nil)
    }

    @MainActor
    @Test("composer view model exposes snippet expansion for text view tab handling")
    func composerViewModelExposesSnippetExpansionForTextViewTabHandling() throws {
        let fixture = try snippetFixture(with: [
            Snippet(id: "cmd", name: "Command", trigger: "cmd", body: "echo ${1:value}")
        ])
        defer { removeSnippetFixture(fixture) }
        let viewModel = RichInputComposerViewModel(
            snippetExpander: RichInputSnippetExpander(snippetManager: fixture.manager)
        )
        let text = "run :cmd"
        let cursor = NSRange(location: (text as NSString).length, length: 0)

        let edit = try #require(viewModel.expandSnippet(in: text, selectedRange: cursor))

        #expect(edit.text == "run echo value")
        #expect(edit.selectedRange == NSRange(location: ("run echo " as NSString).length, length: 5))
    }

    private struct SnippetFixture {
        let manager: SnippetManager
        let root: URL
    }

    private func snippetFixture(with snippets: [Snippet]) throws -> SnippetFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-rich-input-snippets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))
        let manager = SnippetManager(store: store)
        for snippet in snippets {
            try manager.upsert(snippet)
        }
        return SnippetFixture(manager: manager, root: root)
    }

    private func removeSnippetFixture(_ fixture: SnippetFixture) {
        try? FileManager.default.removeItem(at: fixture.root)
    }
}
