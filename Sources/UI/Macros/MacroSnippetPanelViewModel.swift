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

    func localizedTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .macros:
            return localizer.string("macros.section.macros", fallback: "Macros")
        case .snippets:
            return localizer.string("macros.section.snippets", fallback: "Snippets")
        case .aliases:
            return localizer.string("macros.section.aliases", fallback: "Aliases")
        case .clipboard:
            return localizer.string("macros.section.clipboard", fallback: "Clipboard")
        }
    }
}

struct MacroPresentation: Identifiable, Equatable {
    let id: String
    let name: String
    let eventCount: Int
    let updatedAt: Date
}

@MainActor
final class MacroSnippetPanelViewModel: ObservableObject {
    private enum StatusState: Equatable {
        case ready
        case snippets(Int)
        case refreshFailed
        case recording
        case recordedText
        case recordedKey
        case recorded(Int)
        case recordingCanceled
        case selectMacro
        case replayed(Int)
        case prepared(Int)
        case savedSnippet
        case expanded(Int)
        case inserted(Int)
        case aliases(Int)
        case renderedAliases(String)
        case noAliasesToApply
        case appliedAliases
        case clipboardItems(Int)
        case clipboardCleared
    }

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

    @Published private(set) var statusText: String
    @Published private(set) var errorText: String?

    private let snippetManager: SnippetManager
    private let aliasManager: AliasManager
    private let player: MacroPlayer
    private let macroPlaybackHandler: ((MacroPlaybackPlan) throws -> Int)?
    private let terminalTextHandler: ((String) throws -> Void)?
    private var recorder = MacroRecorder()
    private var macroLibrary: [TerminalMacro] = []
    private var clipboardHistory: ClipboardHistoryStore
    private var clipboardObserver: ClipboardHistoryObserver?
    private var localizer: AppLocalizer
    private var statusState: StatusState = .ready

    init(
        snippetManager: SnippetManager = SnippetManager(),
        aliasManager: AliasManager = AliasManager(),
        player: MacroPlayer = MacroPlayer(),
        clipboardHistory: ClipboardHistoryStore = ClipboardHistoryStore(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        observeSystemClipboard: Bool = false,
        clipboardSnapshotProvider: @escaping ClipboardHistoryObserver.SnapshotProvider = ClipboardHistoryObserver.generalPasteboardSnapshot,
        macroPlaybackHandler: ((MacroPlaybackPlan) throws -> Int)? = nil,
        terminalTextHandler: ((String) throws -> Void)? = nil
    ) {
        self.snippetManager = snippetManager
        self.aliasManager = aliasManager
        self.player = player
        self.macroPlaybackHandler = macroPlaybackHandler
        self.terminalTextHandler = terminalTextHandler
        self.clipboardHistory = clipboardHistory
        self.localizer = localizer
        self.clipboardItems = clipboardHistory.items
        self.statusText = Self.localizedStatusText(.ready, localizer: localizer)
        self.macroName = localizer.string("macros.default.macroName", fallback: "New Macro")
        if observeSystemClipboard {
            startClipboardObservation(snapshotProvider: clipboardSnapshotProvider)
        }
    }

    deinit {
        clipboardObserver?.stop()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        statusText = Self.localizedStatusText(statusState, localizer: localizer)
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
            setStatus(.snippets(snippets.count))
        } catch {
            snippets = []
            selectedSnippetID = nil
            clearSnippetDraft()
            errorText = error.localizedDescription
            setStatus(.refreshFailed)
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
        let resolvedName = cleanName(
            name ?? macroName,
            fallback: localizer.string("macros.default.macroName", fallback: "New Macro")
        )
        try recorder.start(name: resolvedName)
        macroName = resolvedName
        macroTextDraft = ""
        playbackEvents = []
        errorText = nil
        isRecording = true
        setStatus(.recording)
    }

    func recordTextEvent(_ text: String? = nil) throws {
        let value = (text ?? macroTextDraft).trimmingCharacters(in: .newlines)
        guard !value.isEmpty else { return }
        try recorder.record(.text(value))
        macroTextDraft = ""
        setStatus(.recordedText)
    }

    func recordKeyEvent(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        try recorder.record(.key(value))
        setStatus(.recordedKey)
    }

    func stopRecordingMacro() throws {
        let macro = try recorder.stop()
        macroLibrary.removeAll { $0.id == macro.id }
        macroLibrary.insert(macro, at: 0)
        refreshMacroPresentations(selecting: macro.id)
        isRecording = false
        errorText = nil
        setStatus(.recorded(macro.events.count))
    }

    func cancelRecordingMacro() {
        recorder.cancel()
        isRecording = false
        setStatus(.recordingCanceled)
    }

    func playSelectedMacro() throws {
        guard let macro = selectedMacroID.flatMap({ id in macroLibrary.first { $0.id == id } }) else {
            setStatus(.selectMacro)
            return
        }
        let plan = try player.playback(macro, repeatCount: repeatCount)
        playbackEvents = plan.events.map(formatMacroEvent)
        if let macroPlaybackHandler {
            let replayedCount = try macroPlaybackHandler(plan)
            setStatus(.replayed(replayedCount))
        } else {
            setStatus(.prepared(playbackEvents.count))
        }
        errorText = nil
    }

    func saveSnippetDraft() throws {
        let id = selectedSnippetID ?? safeIdentifier(from: snippetTrigger.isEmpty ? snippetName : snippetTrigger)
        let snippet = Snippet(
            id: id,
            name: cleanName(snippetName, fallback: localizer.string("macros.default.snippetName", fallback: "Snippet")),
            trigger: snippetTrigger.trimmingCharacters(in: .whitespacesAndNewlines),
            body: snippetBody,
            scope: normalizedOptional(snippetScope)
        )
        try snippetManager.upsert(snippet)
        selectedSnippetID = snippet.id
        try refresh()
        errorText = nil
        setStatus(.savedSnippet)
    }

    func expandSelectedSnippet() throws {
        let trigger = snippetTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        let expansion = try snippetManager.expand(trigger: trigger, scope: normalizedOptional(snippetScope))
        snippetExpansionText = expansion.renderedText
        snippetTabStopLabels = expansion.orderedTabStops.map { stop in
            stop.placeholder.isEmpty ? "\(stop.index)" : "\(stop.index): \(stop.placeholder)"
        }
        errorText = nil
        setStatus(.expanded(snippetTabStopLabels.count))
    }

    func insertSelectedSnippetIntoTerminal() throws {
        if snippetExpansionText.isEmpty {
            try expandSelectedSnippet()
        }
        guard let terminalTextHandler else {
            setStatus(.expanded(snippetTabStopLabels.count))
            return
        }
        try terminalTextHandler(snippetExpansionText)
        errorText = nil
        setStatus(.inserted(snippetTabStopLabels.count))
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
        setStatus(.aliases(aliases.count))
    }

    func renderAliases() throws {
        renderedAliasBlock = try aliasManager.renderBlock(aliases: aliases, shell: selectedShell)
        errorText = nil
        setStatus(.renderedAliases(selectedShell.rawValue))
    }

    func applyAliasesToTerminal() throws {
        if renderedAliasBlock.isEmpty {
            try renderAliases()
        }
        guard let terminalTextHandler else {
            setStatus(.renderedAliases(selectedShell.rawValue))
            return
        }
        let terminalInput = terminalAliasInput(from: renderedAliasBlock)
        guard !terminalInput.isEmpty else {
            errorText = nil
            setStatus(.noAliasesToApply)
            return
        }
        try terminalTextHandler(terminalInput)
        errorText = nil
        setStatus(.appliedAliases)
    }

    func recordClipboardDraft() {
        recordClipboardText(clipboardDraft)
        clipboardDraft = ""
    }

    func clearClipboard() {
        clipboardHistory.clear()
        clipboardItems = []
        setStatus(.clipboardCleared)
    }

    func pollSystemClipboardForTesting() {
        clipboardObserver?.pollNow()
    }

    private func startClipboardObservation(
        snapshotProvider: @escaping ClipboardHistoryObserver.SnapshotProvider
    ) {
        let observer = ClipboardHistoryObserver(snapshotProvider: snapshotProvider) { [weak self] text in
            self?.recordClipboardText(text)
        }
        observer.start()
        clipboardObserver = observer
    }

    private func recordClipboardText(_ text: String) {
        _ = clipboardHistory.record(text: text)
        clipboardItems = clipboardHistory.items
        errorText = nil
        setStatus(.clipboardItems(clipboardItems.count))
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
            return "\(localizer.string("macros.event.text", fallback: "text")): \(value)"
        case .key(let value):
            return "\(localizer.string("macros.event.key", fallback: "key")): \(value)"
        case .command(let value):
            return "\(localizer.string("macros.event.command", fallback: "command")): \(value)"
        case .delay(let milliseconds):
            return "\(localizer.string("macros.event.delay", fallback: "delay")): \(milliseconds)ms"
        }
    }

    private func terminalAliasInput(from renderedBlock: String) -> String {
        let executableLines = renderedBlock
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("#")
            }
        return executableLines.isEmpty ? "" : executableLines.joined(separator: "\n") + "\n"
    }

    private func setStatus(_ status: StatusState) {
        statusState = status
        statusText = Self.localizedStatusText(status, localizer: localizer)
    }

    private static func localizedStatusText(_ status: StatusState, localizer: AppLocalizer) -> String {
        switch status {
        case .ready:
            return localizer.string("macros.status.ready", fallback: "Ready")
        case .snippets(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.snippets.one" : "macros.status.snippets.many",
                    fallback: count == 1 ? "%d snippet" : "%d snippets"
                ),
                count
            )
        case .refreshFailed:
            return localizer.string("macros.status.refreshFailed", fallback: "Refresh failed")
        case .recording:
            return localizer.string("macros.status.recording", fallback: "Recording macro")
        case .recordedText:
            return localizer.string("macros.status.recordedText", fallback: "Recorded text event")
        case .recordedKey:
            return localizer.string("macros.status.recordedKey", fallback: "Recorded key event")
        case .recorded(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.recorded.one" : "macros.status.recorded.many",
                    fallback: count == 1 ? "Recorded %d event" : "Recorded %d events"
                ),
                count
            )
        case .recordingCanceled:
            return localizer.string("macros.status.recordingCanceled", fallback: "Recording canceled")
        case .selectMacro:
            return localizer.string("macros.status.selectMacro", fallback: "Select a macro")
        case .replayed(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.replayed.one" : "macros.status.replayed.many",
                    fallback: count == 1 ? "Replayed %d event" : "Replayed %d events"
                ),
                count
            )
        case .prepared(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.prepared.one" : "macros.status.prepared.many",
                    fallback: count == 1 ? "Prepared %d playback event" : "Prepared %d playback events"
                ),
                count
            )
        case .savedSnippet:
            return localizer.string("macros.status.savedSnippet", fallback: "Saved snippet")
        case .expanded(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.expanded.one" : "macros.status.expanded.many",
                    fallback: count == 1 ? "Expanded %d tab stop" : "Expanded %d tab stops"
                ),
                count
            )
        case .inserted(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.inserted.one" : "macros.status.inserted.many",
                    fallback: count == 1 ? "Inserted snippet with %d tab stop" : "Inserted snippet with %d tab stops"
                ),
                count
            )
        case .aliases(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.aliases.one" : "macros.status.aliases.many",
                    fallback: count == 1 ? "%d alias" : "%d aliases"
                ),
                count
            )
        case .renderedAliases(let shell):
            return String(format: localizer.string("macros.status.renderedAliases", fallback: "Rendered aliases for %@"), shell)
        case .noAliasesToApply:
            return localizer.string("macros.status.noAliasesToApply", fallback: "No aliases to apply")
        case .appliedAliases:
            return localizer.string("macros.status.appliedAliases", fallback: "Applied aliases to terminal")
        case .clipboardItems(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "macros.status.clipboard.one" : "macros.status.clipboard.many",
                    fallback: count == 1 ? "%d clipboard item" : "%d clipboard items"
                ),
                count
            )
        case .clipboardCleared:
            return localizer.string("macros.status.clipboardCleared", fallback: "Clipboard cleared")
        }
    }
}
