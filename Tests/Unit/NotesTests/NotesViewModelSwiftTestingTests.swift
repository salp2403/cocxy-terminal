// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NotesViewModel` orchestration contract: workspace load
/// resolves and lists notes, create / update / delete keep the
/// in-memory cache in sync with disk, search debounces and races the
/// latest query, and errors surface via `lastError` instead of
/// throwing through the published surface.
@Suite("NotesViewModel", .serialized)
@MainActor
struct NotesViewModelSwiftTestingTests {

    /// Stub `mdfind`-style implementation that returns canned hits so
    /// the search tests are deterministic without depending on the
    /// real Spotlight index or sqlite3.
    private struct StubSearchEngine: NoteSearching {
        let kind: NoteSearchEngineKind
        var results: [NoteSearchResult] = []
        var error: NoteSearchError?

        init(
            kind: NoteSearchEngineKind = .grep,
            results: [NoteSearchResult] = [],
            error: NoteSearchError? = nil
        ) {
            self.kind = kind
            self.results = results
            self.error = error
        }

        func search(
            query: String,
            in workspaceID: NoteWorkspaceID
        ) async throws -> [NoteSearchResult] {
            if let error { throw error }
            // Mimic a real engine: blank queries return nothing.
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return []
            }
            return results
        }
    }

    private struct StubResolver: NoteWorkspaceResolving {
        let canned: ResolvedNoteWorkspace?
        func resolveWorkspace(for directory: URL) -> ResolvedNoteWorkspace? {
            canned
        }
    }

    private func makeWorkspace(workspaceRoot: URL? = nil) -> (URL, ResolvedNoteWorkspace) {
        let storageRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-notes-vm-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        let workspaceRoot = workspaceRoot ?? URL(fileURLWithPath: "/Users/sample/projects/foo")
        let resolved = ResolvedNoteWorkspace(
            workspaceID: NoteWorkspaceID(workspaceRoot: workspaceRoot),
            rootURL: workspaceRoot,
            displayName: "foo"
        )
        return (storageRoot, resolved)
    }

    private func makeViewModel(
        searchEngine: any NoteSearching = StubSearchEngine(),
        autoSaveEnabled: Bool = true,
        workspaceRoot: URL? = nil
    ) -> (NotesViewModel, NoteStore, ResolvedNoteWorkspace, URL) {
        let (storageRoot, resolved) = makeWorkspace(workspaceRoot: workspaceRoot)
        let store = NoteStore(storageRoot: storageRoot, format: .markdown, autoSaveInterval: 0)
        let resolver = StubResolver(canned: resolved)
        let viewModel = NotesViewModel(
            store: store,
            resolver: resolver,
            searchEngine: searchEngine,
            autoSaveEnabled: autoSaveEnabled
        )
        return (viewModel, store, resolved, storageRoot)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Workspace lifecycle

    @Test("load resolves the workspace and exposes its display name on the published surface")
    func loadExposesWorkspaceMetadata() async throws {
        let (viewModel, _, resolved, root) = makeViewModel()
        defer { cleanup(root) }

        await viewModel.load(directory: resolved.rootURL)

        #expect(viewModel.workspace?.workspaceID == resolved.workspaceID)
        #expect(viewModel.workspace?.displayName == "foo")
    }

    @Test("load with no resolved workspace leaves the published state empty so the UI can render the empty state")
    func loadHandlesUnresolvedWorkspace() async {
        let storageRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cocxy-notes-vm-empty-\(UUID().uuidString)", isDirectory: true)
        defer { cleanup(storageRoot) }
        let store = NoteStore(storageRoot: storageRoot, format: .markdown)
        let resolver = StubResolver(canned: nil)
        let viewModel = NotesViewModel(
            store: store,
            resolver: resolver,
            searchEngine: StubSearchEngine()
        )

        await viewModel.load(directory: URL(fileURLWithPath: "/tmp"))

        #expect(viewModel.workspace == nil)
        #expect(viewModel.notes.isEmpty)
        #expect(viewModel.selectedNote == nil)
    }

    @Test("load sorts notes by updatedAt descending and selects the most recent so the editor opens on the freshest note")
    func loadSortsNotesAndSelectsFirst() async throws {
        let (viewModel, store, resolved, root) = makeViewModel()
        defer { cleanup(root) }

        _ = try await store.create(in: resolved.workspaceID, body: "old")
        try await Task.sleep(nanoseconds: 50_000_000)
        let newest = try await store.create(in: resolved.workspaceID, body: "new")

        await viewModel.load(directory: resolved.rootURL)

        #expect(viewModel.notes.first?.id == newest.id)
        #expect(viewModel.selectedNote?.id == newest.id)
    }

    // MARK: - Note lifecycle

    @Test("createNote prepends the new note and selects it so the editor lands on a fresh canvas")
    func createNoteSelectsTheNewEntry() async {
        let (viewModel, _, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)

        let created = await viewModel.createNote(body: "# Hello")

        #expect(created != nil)
        #expect(viewModel.notes.first?.id == created?.id)
        #expect(viewModel.selectedNote?.id == created?.id)
    }

    @Test("updateNote replaces the in-memory entry so the listing reflects the latest body without a reload")
    func updateNoteReplacesListingEntry() async {
        let (viewModel, _, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)
        guard var created = await viewModel.createNote(body: "first") else {
            Issue.record("expected createNote to succeed")
            return
        }
        created.body = "updated"

        await viewModel.updateNote(created)

        #expect(viewModel.notes.first?.body == "updated")
        #expect(viewModel.selectedNote?.body == "updated")
    }

    @Test("deleteNote removes the entry from the listing and shifts selection so the editor never points at a missing note")
    func deleteNoteShiftsSelection() async {
        let (viewModel, _, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)
        guard let first = await viewModel.createNote(body: "first") else {
            Issue.record("expected createNote to succeed")
            return
        }
        guard let second = await viewModel.createNote(body: "second") else {
            Issue.record("expected createNote to succeed")
            return
        }
        viewModel.selectNote(first)

        await viewModel.deleteNote(first)

        #expect(viewModel.notes.contains(where: { $0.id == first.id }) == false)
        #expect(viewModel.selectedNote?.id == second.id)
    }

    @Test("flushPendingSaves drains the underlying store so a save right before window close lands on disk")
    func flushPendingSavesSettlesScheduledWrites() async {
        let (viewModel, store, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)
        guard var note = await viewModel.createNote(body: "v0") else {
            Issue.record("expected createNote to succeed")
            return
        }

        for index in 1...5 {
            note.body = "v\(index)"
            await viewModel.updateNote(note)
        }
        await viewModel.flushPendingSaves()

        let loaded = try? await store.note(id: note.id, in: resolved.workspaceID)
        #expect(loaded?.body == "v5")
    }

    @Test("auto-save disabled keeps edits in memory until an explicit save so the config switch is respected")
    func autoSaveDisabledRequiresExplicitSave() async {
        let (viewModel, store, resolved, root) = makeViewModel(autoSaveEnabled: false)
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)
        guard var note = await viewModel.createNote(body: "v0") else {
            Issue.record("expected createNote to succeed")
            return
        }
        note.body = "draft"

        await viewModel.updateNote(note)
        await viewModel.flushPendingSaves()

        let beforeSave = try? await store.note(id: note.id, in: resolved.workspaceID)
        #expect(viewModel.selectedNote?.body == "draft")
        #expect(beforeSave?.body == "v0")

        await viewModel.saveSelectedNote()

        let afterSave = try? await store.note(id: note.id, in: resolved.workspaceID)
        #expect(afterSave?.body == "draft")
    }

    // MARK: - Search

    @Test("setting searchQuery to a non-empty value publishes results so the UI can render the hits list")
    func searchPublishesResults() async {
        let firstHit = NoteSearchResult(
            noteID: UUID(),
            title: "Hit",
            preview: "preview",
            score: 0.9
        )
        let stub = StubSearchEngine(results: [firstHit])
        let (viewModel, _, resolved, root) = makeViewModel(searchEngine: stub)
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)

        viewModel.searchQuery = "alpha"
        await viewModel.runSearch()

        #expect(viewModel.searchResults == [firstHit])
        #expect(viewModel.isSearching == false)
    }

    @Test("blank searchQuery clears results so the UI returns to the listing view without a stale search hit")
    func blankSearchClearsResults() async {
        let stub = StubSearchEngine(results: [
            NoteSearchResult(noteID: UUID(), title: "T", preview: "P", score: 1)
        ])
        let (viewModel, _, resolved, root) = makeViewModel(searchEngine: stub)
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)
        viewModel.searchQuery = "alpha"
        await viewModel.runSearch()

        viewModel.searchQuery = "  "
        await viewModel.runSearch()

        #expect(viewModel.searchResults.isEmpty)
    }

    @Test("search errors surface via lastError so the UI can show a banner")
    func searchErrorsSurfaceOnLastError() async {
        let stub = StubSearchEngine(error: .sqlite3NotFound(path: "/nonexistent"))
        let (viewModel, _, resolved, root) = makeViewModel(searchEngine: stub)
        defer { cleanup(root) }
        await viewModel.load(directory: resolved.rootURL)

        viewModel.searchQuery = "alpha"
        await viewModel.runSearch()

        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.lastError != nil)
    }

    @Test("Spotlight search honors .cocxy-spotlight-ignore at the workspace root")
    func spotlightSearchHonorsWorkspaceIgnoreMarker() async throws {
        let hit = NoteSearchResult(
            noteID: UUID(),
            title: "Hidden",
            preview: "alpha",
            score: 1
        )
        let workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-notes-spotlight-ignore-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: workspaceRoot,
            withIntermediateDirectories: true
        )
        try Data().write(to: workspaceRoot.appendingPathComponent(NoteSpotlightScopePolicy.ignoreFileName))

        let stub = StubSearchEngine(kind: .spotlight, results: [hit])
        let (viewModel, _, resolved, root) = makeViewModel(
            searchEngine: stub,
            workspaceRoot: workspaceRoot
        )
        defer {
            cleanup(root)
            cleanup(workspaceRoot)
        }
        await viewModel.load(directory: resolved.rootURL)

        viewModel.searchQuery = "alpha"
        await viewModel.runSearch()

        #expect(viewModel.searchResults.isEmpty)
        #expect(viewModel.lastError == nil)
    }

    // MARK: - Select by raw ID

    @Test("selectNote(byRawID:) selects the matching note so the Aurora sidebar can deep-link into a specific note from the per-workspace section")
    func selectByRawIDPicksMatchingNote() async throws {
        let (viewModel, store, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        let first = try await store.create(in: resolved.workspaceID, body: "# First")
        try await Task.sleep(nanoseconds: 5_000_000)
        let second = try await store.create(in: resolved.workspaceID, body: "# Second")
        await viewModel.load(directory: resolved.rootURL)
        // Default selection is the most recently edited note.
        #expect(viewModel.selectedNote?.id == second.id)

        let result = viewModel.selectNote(byRawID: first.id.uuidString)

        #expect(result == true)
        #expect(viewModel.selectedNote?.id == first.id)
    }

    @Test("selectNote(byRawID:) returns false when the rawID is malformed so the caller can fall back to the default selection")
    func selectByRawIDRejectsMalformed() async throws {
        let (viewModel, store, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        _ = try await store.create(in: resolved.workspaceID, body: "# Note")
        await viewModel.load(directory: resolved.rootURL)
        let beforeID = viewModel.selectedNote?.id

        let result = viewModel.selectNote(byRawID: "not-a-uuid")

        #expect(result == false)
        #expect(viewModel.selectedNote?.id == beforeID)
    }

    @Test("selectNote(byRawID:) returns false when the note is not in the listing so a stale sidebar tap does not steal selection from the open note")
    func selectByRawIDRejectsUnknownNote() async throws {
        let (viewModel, store, resolved, root) = makeViewModel()
        defer { cleanup(root) }
        _ = try await store.create(in: resolved.workspaceID, body: "# Note")
        await viewModel.load(directory: resolved.rootURL)
        let beforeID = viewModel.selectedNote?.id

        let result = viewModel.selectNote(byRawID: UUID().uuidString)

        #expect(result == false)
        #expect(viewModel.selectedNote?.id == beforeID)
    }
}
