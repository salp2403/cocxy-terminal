// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotesViewModel.swift - Main-actor coordinator that wires the
// `NoteStore`, `NoteWorkspaceResolver`, and the configured search
// backend behind a single observable surface for SwiftUI views.

import Combine
import Foundation

/// Single-source-of-truth view model for the Notes feature.
///
/// The view model is intentionally UI-agnostic — it does not import
/// SwiftUI nor AppKit — so the test suite can drive every flow
/// without booting a window. Each `@Published` property maps onto a
/// concrete view affordance:
///
///   * `workspace` — header label (display name) and the storage path.
///   * `notes` — sidebar list, sorted by `updatedAt` descending.
///   * `selectedNote` — currently open note in the editor.
///   * `searchQuery` — bound to the search bar text field.
///   * `searchResults` — replaces the listing while a query is active.
///   * `isSearching` — drives the spinner / progress affordance.
///   * `lastError` — wired to the error banner.
///
/// ## Concurrency
///
/// `@MainActor` so SwiftUI subscribers always observe state on the
/// main run loop. Actor I/O (loading, saving, deleting, searching)
/// happens through `await` calls on the underlying `NoteStore` actor
/// and on the `NoteSearching` backend.
@MainActor
final class NotesViewModel: ObservableObject {

    // MARK: - Published surface

    @Published private(set) var workspace: ResolvedNoteWorkspace?
    @Published private(set) var notes: [Note] = []
    @Published private(set) var selectedNote: Note?
    @Published var searchQuery: String = "" {
        didSet { scheduleSearch() }
    }
    @Published private(set) var searchResults: [NoteSearchResult] = []
    @Published private(set) var isSearching: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Dependencies

    private let store: NoteStore
    private let resolver: any NoteWorkspaceResolving
    private let searchEngine: any NoteSearching
    private let autoSaveEnabled: Bool

    /// Last in-flight search. Cancelled when a fresh query arrives so
    /// only the latest input renders results.
    private var searchTask: Task<Void, Never>?

    // MARK: - Init

    init(
        store: NoteStore,
        resolver: any NoteWorkspaceResolving,
        searchEngine: any NoteSearching,
        autoSaveEnabled: Bool = true
    ) {
        self.store = store
        self.resolver = resolver
        self.searchEngine = searchEngine
        self.autoSaveEnabled = autoSaveEnabled
    }

    // MARK: - Workspace lifecycle

    /// Resolves the workspace for `directory`, loads its notes, and
    /// selects the most recently edited one (or `nil` for an empty
    /// workspace). Errors surface via `lastError` so the UI can show a
    /// banner without throwing.
    func load(directory: URL) async {
        lastError = nil
        guard let resolved = resolver.resolveWorkspace(for: directory) else {
            workspace = nil
            notes = []
            selectedNote = nil
            return
        }
        workspace = resolved
        await reloadNotes(in: resolved.workspaceID, preserveSelection: false)
    }

    /// Re-reads the current workspace's notes. Public so the wiring
    /// layer can call it from external triggers (e.g. a CwdChanged
    /// hook in another tab) without resetting the workspace.
    func refresh() async {
        guard let workspace else { return }
        await reloadNotes(in: workspace.workspaceID, preserveSelection: true)
    }

    // MARK: - Note lifecycle

    /// Creates a fresh note in the current workspace, prepends it to
    /// the listing, and selects it so the editor opens with the empty
    /// body ready for input.
    @discardableResult
    func createNote(body: String = "") async -> Note? {
        lastError = nil
        guard let workspace else { return nil }
        do {
            let note = try await store.create(in: workspace.workspaceID, body: body)
            notes.insert(note, at: 0)
            selectedNote = note
            return note
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Streams an in-progress edit to the store via the debounced save
    /// path and updates the in-memory note + listing immediately so
    /// the UI reflects the user's input without waiting on disk.
    func updateNote(_ note: Note) async {
        guard let workspace, note.workspaceID == workspace.workspaceID else { return }
        replaceNoteInListing(note)
        if selectedNote?.id == note.id {
            selectedNote = note
        }
        if autoSaveEnabled {
            await store.scheduleSave(note)
        }
    }

    /// Persists a note immediately, bypassing the debounce path. Used
    /// by explicit-save UI and by users who turned off auto-save.
    func saveNote(_ note: Note) async {
        lastError = nil
        guard let workspace, note.workspaceID == workspace.workspaceID else { return }
        do {
            try await store.save(note)
            await reloadNotes(in: workspace.workspaceID, preserveSelection: true)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Saves the currently selected note if one is open.
    func saveSelectedNote() async {
        guard let selectedNote else { return }
        await saveNote(selectedNote)
    }

    /// Deletes the note from disk and from the in-memory listing. If
    /// the deleted note was selected, selection moves to the next
    /// most-recently-edited note (or `nil` when the workspace empties).
    func deleteNote(_ note: Note) async {
        lastError = nil
        guard let workspace, note.workspaceID == workspace.workspaceID else { return }
        do {
            try await store.delete(id: note.id, in: workspace.workspaceID)
            notes.removeAll { $0.id == note.id }
            if selectedNote?.id == note.id {
                selectedNote = notes.first
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Selects the supplied note. `nil` collapses the editor — useful
    /// when the user closes the overlay without picking a new note.
    func selectNote(_ note: Note?) {
        selectedNote = note
    }

    /// Forces every in-flight scheduled save to complete. Wraps
    /// `NoteStore.flushPendingSaves()` so callers (notably tests and
    /// the window-close path) do not have to import the actor type.
    func flushPendingSaves() async {
        do {
            try await store.flushPendingSaves()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Search

    /// Cancels any in-flight search and starts a new one with the
    /// current `searchQuery`. Public so the view layer can call it
    /// after a programmatic query change without waiting on the
    /// debounce window.
    func runSearch() async {
        searchTask?.cancel()
        let query = searchQuery
        let workspaceID = workspace?.workspaceID
        guard let workspaceID else {
            searchResults = []
            isSearching = false
            return
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let hits = try await searchEngine.search(query: query, in: workspaceID)
            // The actor isolation hop above means the published value
            // could otherwise race a fresh query that arrived while we
            // awaited. Compare against the current text to make sure
            // the latest query wins.
            guard searchQuery == query else { return }
            searchResults = hits
        } catch {
            guard searchQuery == query else { return }
            searchResults = []
            lastError = error.localizedDescription
        }
    }

    // MARK: - Private helpers

    private func reloadNotes(
        in workspaceID: NoteWorkspaceID,
        preserveSelection: Bool
    ) async {
        do {
            let loaded = try await store.notes(in: workspaceID)
            notes = loaded
            if preserveSelection,
               let selected = selectedNote,
               loaded.contains(where: { $0.id == selected.id }) {
                // Keep the existing selection but pick up its new body.
                selectedNote = loaded.first(where: { $0.id == selected.id })
            } else {
                selectedNote = loaded.first
            }
        } catch {
            notes = []
            selectedNote = nil
            lastError = error.localizedDescription
        }
    }

    private func replaceNoteInListing(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        }
    }

    /// Re-runs the search whenever `searchQuery` changes. The actual
    /// async work is scheduled into a `Task` so the `didSet` observer
    /// stays sync.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            await self?.runSearch()
        }
    }
}
