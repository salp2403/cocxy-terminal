// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroSnippetPanelViewModelSwiftTestingTests.swift - UI state for local macros and snippets.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Macro and snippet panel view model")
@MainActor
struct MacroSnippetPanelViewModelSwiftTestingTests {
    @Test("refresh loads persisted snippets and selects the first one")
    func refreshLoadsPersistedSnippetsAndSelectsFirstOne() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SnippetManager(store: SnippetStore(fileURL: root.appendingPathComponent("snippets.json")))
        try manager.upsert(Snippet(id: "swift-fn", name: "Swift Function", trigger: "fn", body: "func ${1:name}() {\n\t$0\n}"))
        let viewModel = MacroSnippetPanelViewModel(snippetManager: manager)

        try viewModel.refresh()

        #expect(viewModel.snippets.map(\.id) == ["swift-fn"])
        #expect(viewModel.selectedSnippetID == "swift-fn")
        #expect(viewModel.snippetTrigger == "fn")
        #expect(viewModel.statusText == "1 snippet")
    }

    @Test("records a macro, replays it, and expands a selected snippet with tab stops")
    func recordsMacroReplaysItAndExpandsSnippetWithTabStops() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SnippetManager(store: SnippetStore(fileURL: root.appendingPathComponent("snippets.json")))
        var replayedPlans: [MacroPlaybackPlan] = []
        let viewModel = MacroSnippetPanelViewModel(
            snippetManager: manager,
            macroPlaybackHandler: { plan in
                replayedPlans.append(plan)
                return plan.events.count
            }
        )

        try viewModel.startRecordingMacro(named: "Build")
        try viewModel.recordTextEvent("swift build")
        try viewModel.recordKeyEvent("return")
        try viewModel.stopRecordingMacro()
        viewModel.repeatCount = 2
        try viewModel.playSelectedMacro()

        #expect(viewModel.macros.map(\.name) == ["Build"])
        #expect(viewModel.macros.first?.eventCount == 2)
        #expect(viewModel.playbackEvents == [
            "text: swift build",
            "key: return",
            "text: swift build",
            "key: return",
        ])
        #expect(replayedPlans.map(\.events) == [
            [
                .text("swift build"),
                .key("return"),
                .text("swift build"),
                .key("return"),
            ],
        ])
        #expect(viewModel.statusText == "Replayed 4 events")

        viewModel.snippetName = "Swift Function"
        viewModel.snippetTrigger = "fn"
        viewModel.snippetBody = "func ${1:name}(${2:value}) {\n\t$0\n}"
        try viewModel.saveSnippetDraft()
        try viewModel.expandSelectedSnippet()

        #expect(viewModel.snippetExpansionText == "func name(value) {\n\t\n}")
        #expect(viewModel.snippetTabStopLabels == ["1: name", "2: value", "0"])
    }

    @Test("renders aliases and keeps clipboard history local and searchable")
    func rendersAliasesAndKeepsClipboardHistoryLocalAndSearchable() throws {
        var terminalText: [String] = []
        let viewModel = MacroSnippetPanelViewModel(
            terminalTextHandler: { text in
                terminalText.append(text)
            }
        )

        viewModel.aliasName = "gs"
        viewModel.aliasValue = "git status"
        try viewModel.saveAliasDraft()
        viewModel.selectedShell = .zsh
        try viewModel.renderAliases()
        try viewModel.applyAliasesToTerminal()
        viewModel.clipboardDraft = "alpha"
        viewModel.recordClipboardDraft()
        viewModel.clipboardDraft = "beta"
        viewModel.recordClipboardDraft()
        viewModel.clipboardQuery = "alp"

        #expect(viewModel.renderedAliasBlock.contains("# Cocxy aliases begin"))
        #expect(viewModel.renderedAliasBlock.contains("alias gs='git status'"))
        #expect(terminalText == ["alias gs='git status'\n"])
        #expect(viewModel.filteredClipboardItems.map(\.text) == ["alpha"])
        #expect(viewModel.statusText == "2 clipboard items")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-macro-panel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
