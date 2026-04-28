// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteStore` contract: CRUD operations land at the documented
/// path, the directory layout is created on demand, listings sort by
/// `updatedAt` descending, the debounce coalesces rapid scheduled
/// saves, deletes are idempotent, and `flushPendingSaves` settles the
/// actor before the test asserts. Each suite member uses an isolated
/// temporary directory so the runs never interfere with each other or
/// with the user's real notes.
@Suite("NoteStore", .serialized)
struct NoteStoreSwiftTestingTests {

    private static let workspaceID = NoteWorkspaceID(
        workspaceRoot: URL(fileURLWithPath: "/Users/sample/projects/foo")
    )

    // MARK: - Helpers

    private func makeStore(
        format: NoteFormat = .markdown,
        autoSaveInterval: TimeInterval = 0
    ) -> (NoteStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-notestore-tests-\(UUID().uuidString)",
                isDirectory: true
            )
        let store = NoteStore(
            storageRoot: root,
            format: format,
            autoSaveInterval: autoSaveInterval
        )
        return (store, root)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Listing

    @Test("notes returns an empty array when the workspace folder does not exist yet so the UI shows a clean empty state on first use")
    func emptyListingForFreshWorkspace() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let listed = try await store.notes(in: Self.workspaceID)

        #expect(listed.isEmpty)
    }

    @Test("create writes the note to the documented path so listings can find it on the next call")
    func createWritesNoteToExpectedPath() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let note = try await store.create(in: Self.workspaceID, body: "# Title\nbody")
        let expectedPath = await store.fileURL(for: note.id, in: Self.workspaceID).path

        #expect(FileManager.default.fileExists(atPath: expectedPath))
    }

    @Test("notes listing returns every persisted note in the workspace so the sidebar reflects the actual on-disk state")
    func listingReturnsEveryNote() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let first = try await store.create(in: Self.workspaceID, body: "# First\nfirst body")
        let second = try await store.create(in: Self.workspaceID, body: "# Second\nsecond body")

        let listed = try await store.notes(in: Self.workspaceID)

        #expect(listed.count == 2)
        #expect(Set(listed.map(\.id)) == [first.id, second.id])
    }

    @Test("notes listing sorts by updatedAt descending so the most recently edited note appears first")
    func listingSortsByUpdatedAtDescending() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let oldest = try await store.create(in: Self.workspaceID, body: "old")
        // Force a deterministic gap between the two writes so the
        // sort comparison is unambiguous on filesystems with coarse
        // mtime resolution.
        try await Task.sleep(nanoseconds: 50_000_000)
        let newest = try await store.create(in: Self.workspaceID, body: "new")

        let listed = try await store.notes(in: Self.workspaceID)

        #expect(listed.first?.id == newest.id)
        #expect(listed.last?.id == oldest.id)
    }

    // MARK: - Single fetch

    @Test("note(id:) returns nil when the file does not exist so the UI can disambiguate deletion races from genuine errors")
    func noteForUnknownIDReturnsNil() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let result = try await store.note(id: UUID(), in: Self.workspaceID)

        #expect(result == nil)
    }

    @Test("note(id:) round-trips body content for the markdown format so the editor receives exactly what was saved")
    func noteRoundTripsMarkdownBody() async throws {
        let (store, root) = makeStore(format: .markdown)
        defer { cleanup(root) }

        let saved = try await store.create(in: Self.workspaceID, body: "# Title\nbody")
        let loaded = try await store.note(id: saved.id, in: Self.workspaceID)

        #expect(loaded?.body == "# Title\nbody")
    }

    @Test("note(id:) round-trips frontmatter metadata so the createdAt/id are preserved across reloads")
    func noteRoundTripsFrontmatterMetadata() async throws {
        let (store, root) = makeStore(format: .markdownFrontmatter)
        defer { cleanup(root) }

        let saved = try await store.create(in: Self.workspaceID, body: "# Title\nbody")
        let loaded = try await store.note(id: saved.id, in: Self.workspaceID)

        #expect(loaded?.id == saved.id)
        #expect(loaded?.body == "# Title\nbody")
        // Timestamps round-trip with second-level precision because the
        // ISO-8601 formatter strips fractional seconds.
        let savedSecond = Int(saved.createdAt.timeIntervalSince1970)
        let loadedSecond = loaded.map { Int($0.createdAt.timeIntervalSince1970) }
        #expect(loadedSecond == savedSecond)
    }

    // MARK: - Save / update

    @Test("save bumps updatedAt so the listing order reflects the most recent edit")
    func saveBumpsUpdatedAt() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let original = try await store.create(in: Self.workspaceID, body: "first")
        try await Task.sleep(nanoseconds: 50_000_000)
        try await store.save(original)

        let loaded = try await store.note(id: original.id, in: Self.workspaceID)
        #expect(loaded?.updatedAt ?? .distantPast > original.updatedAt)
    }

    // MARK: - Delete

    @Test("delete removes the file so subsequent listings drop the note")
    func deleteRemovesFile() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let note = try await store.create(in: Self.workspaceID, body: "body")
        try await store.delete(id: note.id, in: Self.workspaceID)

        let listed = try await store.notes(in: Self.workspaceID)
        #expect(listed.isEmpty)
    }

    @Test("delete is idempotent so a missing file does not throw — the caller's intent is already satisfied")
    func deleteIsIdempotent() async throws {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        try await store.delete(id: UUID(), in: Self.workspaceID)
        // No expectation needed beyond "did not throw".
    }

    // MARK: - Debounce

    @Test("scheduleSave coalesces rapid keystrokes so only the latest body lands on disk")
    func scheduleSaveCoalescesRapidEdits() async throws {
        let (store, root) = makeStore(autoSaveInterval: 0)
        defer { cleanup(root) }

        var note = try await store.create(in: Self.workspaceID, body: "v0")
        for index in 1...10 {
            note.body = "v\(index)"
            await store.scheduleSave(note)
        }
        try await store.flushPendingSaves()

        let loaded = try await store.note(id: note.id, in: Self.workspaceID)
        #expect(loaded?.body == "v10")
    }

    @Test("delete cancels any pending debounced save so the file does not reappear after the delete")
    func deleteCancelsPendingDebouncedSave() async throws {
        let (store, root) = makeStore(autoSaveInterval: 1)
        defer { cleanup(root) }

        let note = try await store.create(in: Self.workspaceID, body: "body")
        var updated = note
        updated.body = "updated"
        await store.scheduleSave(updated)
        try await store.delete(id: note.id, in: Self.workspaceID)
        try await store.flushPendingSaves()

        let loaded = try await store.note(id: note.id, in: Self.workspaceID)
        #expect(loaded == nil)
    }

    // MARK: - Path helpers

    @Test("directory and file URL helpers compose the documented filesystem layout so the layout stays stable across upgrades")
    func pathHelpersComposeDocumentedLayout() async {
        let (store, root) = makeStore()
        defer { cleanup(root) }

        let id = UUID()
        let directoryURL = await store.directoryURL(for: Self.workspaceID)
        let fileURL = await store.fileURL(for: id, in: Self.workspaceID)

        #expect(directoryURL.path == root.appendingPathComponent(Self.workspaceID.rawValue).path)
        #expect(fileURL.lastPathComponent == "\(id.uuidString).md")
    }
}
