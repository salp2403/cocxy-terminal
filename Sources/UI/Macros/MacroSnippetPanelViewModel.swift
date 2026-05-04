// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroSnippetPanelViewModel.swift - UI state for local macros, snippets, aliases, and clipboard history.

import Combine
import Foundation

enum MacroSnippetPanelSection: String, CaseIterable, Identifiable {
    case macros = "Macros"
    case snippets = "Snippets"
    case aliases = "Aliases"
    case clipboard = "Clipboard"

    var id: String { rawValue }
}

struct MacroPresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let eventCount: Int
    let updatedAt: Date
}

@MainActor
final class MacroSnippetPanelViewModel: ObservableObject {
    @Published var selectedSection: MacroSnippetPanelSection = .macros

    @Published private(set) var macros: [MacroPresentation] = []
    @Published var selectedMacroID: String?
    @Published var macroName = "New Macro"
    @Published var macroTextDraft = ""
    @Published var repeatCount = 1
    @Published private(set) var isRecording = false
    @Published private(set) var playbackEvents: [String] = []

    @Published private(set) var snippets: [Snippet] = []
    @Published var selectedSnippetID: String?
    @Published var snippetName = ""
    @Published var snippetTrigger = ""
    @Published var snippetScope = ""
    @Published var snippetBody = ""
    @Published private(set) var snippetExpansionText = ""
    @Published private(set) var snippetTabStopLabels: [String] = []

    @Published private(set) var aliases: [ShellAlias] = []
    @Published var aliasName = ""
    @Published var aliasValue = ""
    @Published var aliasDetail = ""
    @Published var selectedShell: ShellKind = .zsh
    @Published private(set) var renderedAliasBlock = ""

    @Published private(set) var clipboardItems: [ClipboardHistoryItem] = []
    @Published var clipboardDraft = ""
    @Published var clipboardQuery = ""

    @Published private(set) var statusText = "Ready"
    @Published private(set) var errorText: String?

    private let snippetManager: SnippetManager
    private let aliasManager: AliasManager
    private let player: MacroPlayer
    private var recorder = MacroRecorder()
    private var macroLibrary: [TerminalMacro] = []
    private var clipboardHistory: ClipboardHistoryStore

    init(
        snippetManager: SnippetManager = SnippetManager(),
        aliasManager: AliasManager = AliasManager(),
        player: MacroPlayer = MacroPlayer(),
        clipboardHistory: ClipboardHistoryStore = ClipboardHistoryStore()
    ) {
        self.snippetManager = snippetManager
        self.aliasManager = aliasManager
        self.player = player
        self.clipboardHistory = clipboardHistory
        self.clipboardItems = clipboardHistory.items
    }

    var selectedMacro: MacroPresentation? {
        guard let selectedMacroID else { return nil }
        return macros.first { $0.id == selectedMacroID }
    }

    var filteredClipboardItems: [ClipboardHistoryItem] {
        clipboardHistory.search(clipboardQuery)
    }

    func refresh() throws {
        do {
            snippets = try snippetManager.list()
            if selectedSnippetID == nil || snippets.contains(where: { $0.id == selectedSnippetID }) == false {
                selectedSnippetID = snippets.first?.id
            }
            populateSnippetDraft()
            errorText = nil
            statusText = snippets.count == 1 ? "1 snippet" : "\(snippets.count) snippets"
        } catch {
            snippets = []
            selectedSnippetID = nil
            clearSnippetDraft()
            errorText = error.localizedDescription
            statusText = "Refresh failed"
            throw error
        }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorText = error.localizedDescription
        }
    }

    func selectSnippet(id: String?) {
        selectedSnippetID = id
        populateSnippetDraft()
    }

    func startRecordingMacro(named name: String? = nil) throws {
        let resolvedName = cleanName(name ?? macroName, fallback: "New Macro")
        try recorder.start(name: resolvedName)
        macroName = resolvedName
        macroTextDraft = ""
        playbackEvents = []
        errorText = nil
        isRecording = true
        statusText = "Recording macro"
    }

    func recordTextEvent(_ text: String? = nil) throws {
        let value = (text ?? macroTextDraft).trimmingCharacters(in: .newlines)
        guard !value.isEmpty else { return }
        try recorder.record(.text(value))
        macroTextDraft = ""
        statusText = "Recorded text event"
    }

    func recordKeyEvent(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        try recorder.record(.key(value))
        statusText = "Recorded key event"
    }

    func stopRecordingMacro() throws {
        let macro = try recorder.stop()
        macroLibrary.removeAll { $0.id == macro.id }
        macroLibrary.insert(macro, at: 0)
        refreshMacroPresentations(selecting: macro.id)
        isRecording = false
        errorText = nil
        statusText = "Recorded \(macro.events.count) \(macro.events.count == 1 ? "event" : "events")"
    }

    func cancelRecordingMacro() {
        recorder.cancel()
        isRecording = false
        statusText = "Recording canceled"
    }

    func playSelectedMacro() throws {
        guard let macro = selectedMacroID.flatMap({ id in macroLibrary.first { $0.id == id } }) else {
            statusText = "Select a macro"
            return
        }
        let plan = try player.playback(macro, repeatCount: repeatCount)
        playbackEvents = plan.events.map(formatMacroEvent)
        errorText = nil
        statusText = "Prepared \(playbackEvents.count) playback events"
    }

    func saveSnippetDraft() throws {
        let id = selectedSnippetID ?? safeIdentifier(from: snippetTrigger.isEmpty ? snippetName : snippetTrigger)
        let snippet = Snippet(
            id: id,
            name: cleanName(snippetName, fallback: "Snippet"),
            trigger: snippetTrigger.trimmingCharacters(in: .whitespacesAndNewlines),
            body: snippetBody,
            scope: normalizedOptional(snippetScope)
        )
        try snippetManager.upsert(snippet)
        selectedSnippetID = snippet.id
        try refresh()
        errorText = nil
        statusText = "Saved snippet"
    }

    func expandSelectedSnippet() throws {
        let trigger = snippetTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let expansion = try snippetManager.expand(trigger: trigger, scope: normalizedOptional(snippetScope))
        snippetExpansionText = expansion.renderedText
        snippetTabStopLabels = expansion.orderedTabStops.map { stop in
            stop.placeholder.isEmpty ? "\(stop.index)" : "\(stop.index): \(stop.placeholder)"
        }
        errorText = nil
        statusText = "Expanded \(snippetTabStopLabels.count) tab stops"
    }

    func saveAliasDraft() throws {
        let alias = ShellAlias(
            name: aliasName.trimmingCharacters(in: .whitespacesAndNewlines),
            value: aliasValue,
            detail: normalizedOptional(aliasDetail)
        )
        try aliasManager.validate(alias)
        aliases.removeAll { $0.name == alias.name }
        aliases.append(alias)
        aliases.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        errorText = nil
        statusText = aliases.count == 1 ? "1 alias" : "\(aliases.count) aliases"
    }

    func renderAliases() throws {
        renderedAliasBlock = try aliasManager.renderBlock(aliases: aliases, shell: selectedShell)
        errorText = nil
        statusText = "Rendered aliases for \(selectedShell.rawValue)"
    }

    func recordClipboardDraft() {
        _ = clipboardHistory.record(text: clipboardDraft)
        clipboardItems = clipboardHistory.items
        clipboardDraft = ""
        errorText = nil
        statusText = clipboardItems.count == 1 ? "1 clipboard item" : "\(clipboardItems.count) clipboard items"
    }

    func clearClipboard() {
        clipboardHistory.clear()
        clipboardItems = []
        statusText = "Clipboard cleared"
    }

    private func refreshMacroPresentations(selecting id: String?) {
        macros = macroLibrary.map {
            MacroPresentation(id: $0.id, name: $0.name, eventCount: $0.events.count, updatedAt: $0.updatedAt)
        }
        selectedMacroID = id ?? macros.first?.id
    }

    private func populateSnippetDraft() {
        guard let selectedSnippetID,
              let snippet = snippets.first(where: { $0.id == selectedSnippetID }) else {
            clearSnippetDraft()
            return
        }
        snippetName = snippet.name
        snippetTrigger = snippet.trigger
        snippetScope = snippet.scope ?? ""
        snippetBody = snippet.body
        snippetExpansionText = ""
        snippetTabStopLabels = []
    }

    private func clearSnippetDraft() {
        snippetName = ""
        snippetTrigger = ""
        snippetScope = ""
        snippetBody = ""
        snippetExpansionText = ""
        snippetTabStopLabels = []
    }

    private func cleanName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func safeIdentifier(from value: String) -> String {
        let base = value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9._-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return base.isEmpty ? UUID().uuidString : String(base.prefix(80))
    }

    private func formatMacroEvent(_ event: MacroEvent) -> String {
        switch event {
        case .text(let value):
            return "text: \(value)"
        case .key(let value):
            return "key: \(value)"
        case .command(let value):
            return "command: \(value)"
        case .delay(let milliseconds):
            return "delay: \(milliseconds)ms"
        }
    }
}
