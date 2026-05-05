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
        var terminalText: [String] = []
        let viewModel = MacroSnippetPanelViewModel(
            snippetManager: manager,
            macroPlaybackHandler: { plan in
                replayedPlans.append(plan)
                return plan.events.count
            },
            terminalTextHandler: { text in
                terminalText.append(text)
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
        try viewModel.insertSelectedSnippetIntoTerminal()

        #expect(viewModel.snippetExpansionText == "func name(value) {\n\t\n}")
        #expect(viewModel.snippetTabStopLabels == ["1: name", "2: value", "0"])
        #expect(terminalText == ["func name(value) {\n\t\n}"])
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

    @Test("spanish localizer updates macro panel status text")
    func spanishLocalizerUpdatesMacroPanelStatusText() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SnippetManager(store: SnippetStore(fileURL: root.appendingPathComponent("snippets.json")))
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = MacroSnippetPanelViewModel(
            snippetManager: manager,
            localizer: spanish
        )

        try viewModel.refresh()
        #expect(MacroSnippetPanelSection.snippets.localizedTitle(using: spanish) == "Fragmentos")
        #expect(MacroSnippetPanelSection.aliases.localizedTitle(using: spanish) == "Alias")
        #expect(viewModel.statusText == "0 fragmentos")

        try viewModel.startRecordingMacro(named: "Build")
        try viewModel.recordTextEvent("swift build")
        try viewModel.stopRecordingMacro()
        #expect(viewModel.statusText == "Grabada 1 acción")

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))
        #expect(viewModel.statusText == "Recorded 1 event")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-macro-panel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
