// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingsEditorViewModel.swift - Editable view model for the Keybindings preferences tab.

import Foundation
import Combine

// MARK: - Keybindings Editor View Model

/// View model backing the Keybindings tab in Preferences.
///
/// Owns an editable copy of every rebindable shortcut (per action id) and
/// exposes:
/// - live conflict detection (`conflictingActionIds(for:)`, `hasConflicts`),
/// - reset-to-default per action,
/// - a `save()` path that asks an injected editor to persist the changes
///   back to `config.toml` via `PreferencesViewModel.save()`.
///
/// ## Lifetime and binding
///
/// Hot-reload is driven by `PreferencesViewModel` which also owns the file
/// writer. Callers construct one view model per Preferences window and
/// rebuild it from the saved config snapshot when the file changes on disk.
///
/// ## Conflicts
///
/// Two bindings conflict when their pending canonical strings are identical.
/// The editor surfaces this as an inline warning and blocks save via
/// `hasConflicts`. Empty strings (blank shortcut) never conflict; they
/// represent "no binding".
///
/// - SeeAlso: `KeybindingsEditorView` for the SwiftUI presentation.
/// - SeeAlso: `PreferencesViewModel` for persistence and cross-section save.
@MainActor
final class KeybindingsEditorViewModel: ObservableObject {

    // MARK: - Public State

    /// Canonical shortcut string per catalog action id (e.g.,
    /// `"split.vertical": "cmd+d"`). Always contains an entry for every
    /// action in `KeybindingActionCatalog.all` so the UI can bind directly.
    @Published private(set) var shortcutsById: [String: String]

    /// Validation and change errors surfaced in the list footer.
    ///
    /// Non-nil when a capture event returned an invalid shortcut or when a
    /// save is blocked by conflicts.
    @Published private(set) var statusMessage: String?

    // MARK: - Dependencies

    /// Persistence provider. `nil` disables `save()` (useful for tests and
    /// previews).
    private weak var persistence: PreferencesViewModel?

    /// Localizer used for transient validation and persistence status text.
    private var localizer: AppLocalizer

    /// Semantic source for `statusMessage`, retained so language changes can
    /// relocalize the current banner without comparing already-rendered copy.
    private var statusState: StatusState?

    /// Snapshot of the last-saved config, used to rebuild the editable state
    /// when `reload(from:)` is called after a successful save.
    private var snapshot: KeybindingsConfig

    // MARK: - Initialization

    /// Creates an editor populated from the current saved config.
    ///
    /// - Parameters:
    ///   - config: The current application config. The `keybindings` section
    ///     drives the initial state.
    ///   - persistence: The preferences view model used to persist changes.
    ///     When `nil`, `save()` throws `SaveError.persistenceUnavailable` so
    ///     previews and tests cannot accidentally report a persisted change.
    init(
        config: CocxyConfig,
        persistence: PreferencesViewModel? = nil,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.snapshot = config.keybindings
        self.persistence = persistence
        self.localizer = localizer
        self.shortcutsById = Self.buildShortcutMap(from: config.keybindings)
    }

    // MARK: - Reload

    /// Rebuilds the editable state from a fresh config snapshot.
    ///
    /// Called by the parent preferences view when an external save or
    /// hot-reload produces new values on disk. Clears any transient status
    /// message.
    func reload(from config: CocxyConfig) {
        snapshot = config.keybindings
        shortcutsById = Self.buildShortcutMap(from: config.keybindings)
        clearStatus()
    }

    /// Updates the localizer and re-renders the active status message.
    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        if let statusState {
            statusMessage = Self.localizedStatus(statusState, using: localizer)
        }
    }

    // MARK: - Lookup Helpers

    /// Returns the parsed shortcut for the action, or `nil` if the stored
    /// string is empty.
    func shortcut(for actionId: String) -> KeybindingShortcut? {
        guard let raw = shortcutsById[actionId], !raw.isEmpty else { return nil }
        return KeybindingShortcut.parse(raw)
    }

    /// Returns the raw canonical string for the action, defaulting to an
    /// empty string when unknown.
    func rawShortcut(for actionId: String) -> String {
        shortcutsById[actionId] ?? ""
    }

    /// Whether the action has been customized versus its catalog default.
    func isCustomized(_ actionId: String) -> Bool {
        guard let entry = KeybindingAction.catalogEntry(for: actionId) else {
            return false
        }
        return rawShortcut(for: actionId) != entry.defaultShortcut.canonical
    }

    /// Whether pending edits are different from the last-saved snapshot.
    var hasUnsavedChanges: Bool {
        shortcutsById != Self.buildShortcutMap(from: snapshot)
    }

    // MARK: - Conflict Detection

    /// Returns the ids of other actions that share the given canonical string.
    ///
    /// - Parameter candidate: The canonical shortcut under consideration,
    ///   produced either by NSEvent capture or manual edit.
    /// - Parameter excluding: The action id whose current value to ignore
    ///   (so a row never reports a conflict against itself).
    /// - Returns: All other action ids currently bound to `candidate`.
    ///   Empty candidates never conflict.
    func conflictingActionIds(for candidate: String, excluding actionId: String) -> [String] {
        guard !candidate.isEmpty else { return [] }
        return shortcutsById
            .filter { $0.key != actionId && $0.value == candidate }
            .map(\.key)
            .sorted()
    }

    /// Whether any pair of pending shortcuts conflict with each other.
    var hasConflicts: Bool {
        var seen: [String: String] = [:]
        for (id, shortcut) in shortcutsById where !shortcut.isEmpty {
            if seen[shortcut] != nil {
                return true
            }
            seen[shortcut] = id
        }
        return false
    }

    /// Returns the conflict groups as arrays of ids sharing a shortcut.
    ///
    /// Useful for rendering "X conflicts with Y, Z" messages at the top of
    /// the editor; every id in a returned group is flagged.
    func conflictGroups() -> [[String]] {
        var buckets: [String: [String]] = [:]
        for (id, shortcut) in shortcutsById where !shortcut.isEmpty {
            buckets[shortcut, default: []].append(id)
        }
        return buckets.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
    }

    // MARK: - Mutation

    /// Assigns a shortcut to the action after validating it parses cleanly.
    ///
    /// - Parameters:
    ///   - shortcut: Parsed shortcut from the capture field.
    ///   - actionId: The action being rebound.
    /// - Returns: `true` if applied, `false` if the shortcut is nil or
    ///   fails to round-trip via `KeybindingShortcut.parse`.
    @discardableResult
    func assign(_ shortcut: KeybindingShortcut?, to actionId: String) -> Bool {
        guard let shortcut else {
            setStatus(.invalidShortcut)
            return false
        }
        guard KeybindingShortcut.parse(shortcut.canonical) != nil else {
            setStatus(.unparseableShortcut)
            return false
        }
        shortcutsById[actionId] = shortcut.canonical
        clearStatus()
        return true
    }

    /// Clears the shortcut for the given action. Equivalent to "no binding".
    func clear(_ actionId: String) {
        shortcutsById[actionId] = ""
        clearStatus()
    }

    /// Restores the catalog default for a single action.
    func reset(_ actionId: String) {
        guard let entry = KeybindingAction.catalogEntry(for: actionId) else { return }
        shortcutsById[actionId] = entry.defaultShortcut.canonical
        clearStatus()
    }

    /// Restores catalog defaults for every action in the editor.
    func resetAll() {
        shortcutsById = Self.defaultShortcutMap()
        clearStatus()
    }

    // MARK: - Save

    /// Error raised by `save()` when the current edit state cannot be
    /// persisted as-is.
    enum SaveError: LocalizedError, Equatable {
        case conflictsUnresolved
        case invalidShortcut(actionId: String)
        case persistenceUnavailable

        var errorDescription: String? {
            switch self {
            case .conflictsUnresolved:
                return "Resolve conflicting shortcuts before saving."
            case .invalidShortcut(let actionId):
                return "Shortcut for \(actionId) is invalid."
            case .persistenceUnavailable:
                return "Preferences window is not available to persist changes."
            }
        }
    }

    private enum StatusState: Equatable {
        case invalidShortcut
        case unparseableShortcut
        case saveError(SaveError)
        case saved
    }

    /// Persists the pending edits via the injected `PreferencesViewModel`.
    ///
    /// The caller is responsible for first clearing conflicts; `save()`
    /// refuses to write when `hasConflicts == true`.
    ///
    /// - Throws: `SaveError` for editor-side validation, or any error raised
    ///   by the persistence layer (e.g., file I/O failure).
    func save() throws {
        if hasConflicts {
            setStatus(.saveError(.conflictsUnresolved))
            throw SaveError.conflictsUnresolved
        }
        for (id, shortcut) in shortcutsById where !shortcut.isEmpty {
            if KeybindingShortcut.parse(shortcut) == nil {
                setStatus(.saveError(.invalidShortcut(actionId: id)))
                throw SaveError.invalidShortcut(actionId: id)
            }
        }
        guard let persistence else {
            setStatus(.saveError(.persistenceUnavailable))
            throw SaveError.persistenceUnavailable
        }

        let updatedConfig = makeUpdatedKeybindings()
        persistence.applyKeybindings(updatedConfig)
        try persistence.save()

        snapshot = updatedConfig
        setStatus(.saved)
    }

    // MARK: - Localization

    func localizedDescription(for error: SaveError) -> String {
        Self.localizedDescription(for: error, using: localizer)
    }

    static func localizedInvalidShortcut(using localizer: AppLocalizer) -> String {
        localizer.string("keybindings.invalidShortcut", fallback: "That is not a valid shortcut.")
    }

    static func localizedUnparseableShortcut(using localizer: AppLocalizer) -> String {
        localizer.string("keybindings.unparseableShortcut", fallback: "That shortcut could not be parsed.")
    }

    static func localizedSaved(using localizer: AppLocalizer) -> String {
        localizer.string("keybindings.saved", fallback: "Keybindings saved.")
    }

    static func localizedDescription(for error: SaveError, using localizer: AppLocalizer) -> String {
        switch error {
        case .conflictsUnresolved:
            return localizer.string(
                "keybindings.resolveConflicts",
                fallback: error.errorDescription ?? "Resolve conflicts before saving."
            )
        case .invalidShortcut(let actionId):
            let actionName = KeybindingAction.catalogEntry(for: actionId)?
                .localizedDisplayName(using: localizer) ?? actionId
            return String(
                format: localizer.string(
                    "keybindings.invalidShortcutFor",
                    fallback: "Shortcut for %@ is invalid."
                ),
                actionName
            )
        case .persistenceUnavailable:
            return localizer.string(
                "keybindings.persistenceUnavailable",
                fallback: error.errorDescription ?? "Preferences window is not available to persist changes."
            )
        }
    }

    static func localizedStatusMessage(_ status: String, using localizer: AppLocalizer) -> String {
        if status == "That is not a valid shortcut." {
            return localizedInvalidShortcut(using: localizer)
        }
        if status == "That shortcut could not be parsed." {
            return localizedUnparseableShortcut(using: localizer)
        }
        if status == "Keybindings saved." {
            return localizedSaved(using: localizer)
        }
        if status == (SaveError.conflictsUnresolved.errorDescription ?? "") {
            return localizedDescription(for: .conflictsUnresolved, using: localizer)
        }
        if status == (SaveError.persistenceUnavailable.errorDescription ?? "") {
            return localizedDescription(for: .persistenceUnavailable, using: localizer)
        }
        return status
    }

    private static func localizedStatus(_ state: StatusState, using localizer: AppLocalizer) -> String {
        switch state {
        case .invalidShortcut:
            return localizedInvalidShortcut(using: localizer)
        case .unparseableShortcut:
            return localizedUnparseableShortcut(using: localizer)
        case .saveError(let error):
            return localizedDescription(for: error, using: localizer)
        case .saved:
            return localizedSaved(using: localizer)
        }
    }

    private func setStatus(_ state: StatusState) {
        statusState = state
        statusMessage = Self.localizedStatus(state, using: localizer)
    }

    private func clearStatus() {
        statusState = nil
        statusMessage = nil
    }

    // MARK: - Assembly

    /// Builds a new `KeybindingsConfig` merging pending edits into the
    /// last-saved snapshot (so non-keybinding state is untouched).
    private func makeUpdatedKeybindings() -> KeybindingsConfig {
        func raw(_ actionId: String, fallback: String) -> String {
            let value = shortcutsById[actionId] ?? fallback
            return value.isEmpty ? fallback : value
        }

        var customOverrides: [String: String] = [:]
        for action in KeybindingActionCatalog.all {
            if KeybindingActionCatalog.legacyFieldMapping.values.contains(action.id) {
                continue    // legacy ids map to typed fields below
            }
            let current = rawShortcut(for: action.id)
            guard !current.isEmpty, current != action.defaultShortcut.canonical else {
                continue
            }
            customOverrides[action.id] = current
        }

        return KeybindingsConfig(
            newTab: raw(KeybindingActionCatalog.tabNew.id, fallback: snapshot.newTab),
            closeTab: raw(KeybindingActionCatalog.tabClose.id, fallback: snapshot.closeTab),
            nextTab: raw(KeybindingActionCatalog.tabNext.id, fallback: snapshot.nextTab),
            prevTab: raw(KeybindingActionCatalog.tabPrevious.id, fallback: snapshot.prevTab),
            splitVertical: raw(KeybindingActionCatalog.splitVertical.id, fallback: snapshot.splitVertical),
            splitHorizontal: raw(KeybindingActionCatalog.splitHorizontal.id, fallback: snapshot.splitHorizontal),
            gotoAttention: raw(KeybindingActionCatalog.remoteGoToAttention.id, fallback: snapshot.gotoAttention),
            toggleQuickTerminal: raw(KeybindingActionCatalog.windowQuickTerminal.id, fallback: snapshot.toggleQuickTerminal),
            customOverrides: customOverrides
        )
    }

    // MARK: - Map Builders

    /// Resolves every catalog action against the saved config and returns
    /// a fully populated map suitable for direct UI binding.
    private static func buildShortcutMap(from config: KeybindingsConfig) -> [String: String] {
        var result: [String: String] = [:]
        for action in KeybindingActionCatalog.all {
            result[action.id] = config.shortcutString(for: action.id)
        }
        return result
    }

    /// Factory default map used by `resetAll()`.
    private static func defaultShortcutMap() -> [String: String] {
        var result: [String: String] = [:]
        for action in KeybindingActionCatalog.all {
            result[action.id] = action.defaultShortcut.canonical
        }
        return result
    }
}
