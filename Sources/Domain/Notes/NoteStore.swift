// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteStore.swift - Actor-based persistent store for the Notes module.

import Foundation

/// Errors surfaced by `NoteStore`. Distinct cases let callers
/// distinguish "the note never existed" (potentially a UI bug) from
/// "the file is corrupt" (potentially user-fixable) and from generic
/// I/O failures.
enum NoteStoreError: Error, Sendable, Equatable {

    /// The requested note was not present in the workspace folder.
    case noteNotFound(id: UUID, workspaceID: NoteWorkspaceID)

    /// The on-disk content for a note could not be parsed back into a
    /// `Note`. Carries the underlying serializer error for diagnostics.
    case malformedNoteFile(path: String)

    /// A filesystem operation failed. Carries the underlying error's
    /// localized description so the caller can surface it without
    /// importing the original error type.
    case ioFailure(String)
}

/// Persistent store for notes, isolated as an `actor` so all CRUD
/// operations are serialised without the caller needing to coordinate
/// queues. Backed by a directory-per-workspace layout under
/// `storageRoot`:
///
/// ```text
/// storageRoot/
/// ├── <workspace-id-1>/
/// │   ├── <uuid-1>.md
/// │   └── <uuid-2>.md
/// └── <workspace-id-2>/
///     └── ...
/// ```
///
/// ## Concurrency
///
/// The store debounces saves per-note ID. Callers stream user
/// keystrokes through `scheduleSave(_:)`; the actor cancels any
/// previously pending task for the same note and schedules a new one
/// after `autoSaveInterval`. The most recent body wins. `save(_:)` is
/// the immediate, non-debounced variant — used when the user closes
/// the editor or when a test wants to bypass the debounce.
///
/// ## Tests
///
/// Tests inject a temporary `storageRoot` and use `autoSaveInterval: 0`
/// to make scheduled saves run immediately. `flushPendingSaves()` waits
/// for every in-flight scheduled save to finish so a test can assert
/// against the on-disk state right after the call without polling.
actor NoteStore {

    // MARK: - Stored state

    /// Root directory under which every workspace gets its own folder.
    /// Created on demand on the first write — the store never assumes
    /// the path already exists. `nonisolated` because the value is
    /// frozen at construction time, so callers can read it without
    /// re-entering the actor.
    nonisolated let storageRoot: URL

    /// On-disk format used for serialisation. Frozen at construction
    /// time so a single store instance produces a single layout —
    /// switching formats is a user action that goes through `Settings`
    /// and creates a new store on hot-reload.
    nonisolated let format: NoteFormat

    /// Debounce window for `scheduleSave(_:)`. Tests use `0` to make
    /// scheduled saves run synchronously.
    nonisolated let autoSaveInterval: TimeInterval

    /// Open debounce tasks keyed by the note ID. A new schedule call
    /// cancels and replaces the existing task so only the latest body
    /// is written.
    private var pendingSaves: [UUID: Task<Void, Error>] = [:]

    // MARK: - Initialisation

    init(
        storageRoot: URL,
        format: NoteFormat = .default,
        autoSaveInterval: TimeInterval = 0.5
    ) {
        self.storageRoot = storageRoot
        self.format = format
        self.autoSaveInterval = autoSaveInterval
    }

    // MARK: - Listing

    /// Lists every note persisted under `workspaceID`, sorted by
    /// `updatedAt` descending so the most recently edited note is first.
    /// Returns an empty array (not an error) when the workspace folder
    /// does not exist yet — that just means the user has not created a
    /// note in this workspace yet.
    func notes(in workspaceID: NoteWorkspaceID) throws -> [Note] {
        let directory = directoryURL(for: workspaceID)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let extensionMatch = format.fileExtension
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw NoteStoreError.ioFailure(error.localizedDescription)
        }
        var loaded: [Note] = []
        for file in files where file.pathExtension == extensionMatch {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                continue
            }
            if let note = try? loadNote(at: file, id: id, workspaceID: workspaceID) {
                loaded.append(note)
            }
        }
        return loaded.sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    /// Loads a single note by ID. Returns `nil` when the note does not
    /// exist (the UI uses this to detect deletion races); throws for
    /// malformed-file or generic I/O issues so the caller can show a
    /// banner without confusing "missing" with "broken".
    func note(id: UUID, in workspaceID: NoteWorkspaceID) throws -> Note? {
        let url = fileURL(for: id, in: workspaceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try loadNote(at: url, id: id, workspaceID: workspaceID)
    }

    // MARK: - Mutation

    /// Creates a fresh note in `workspaceID` with the supplied body
    /// (defaults to empty), persists it immediately, and returns the
    /// in-memory representation. Used by the UI when the user clicks
    /// "New note".
    func create(
        in workspaceID: NoteWorkspaceID,
        body: String = ""
    ) throws -> Note {
        let now = Date()
        let note = Note(
            id: UUID(),
            workspaceID: workspaceID,
            body: body,
            createdAt: now,
            updatedAt: now
        )
        try writeNote(note)
        return note
    }

    /// Persists `note` immediately, bypassing the debounce. Bumps the
    /// `updatedAt` timestamp on disk so the listing order tracks the
    /// most recent save.
    func save(_ note: Note) throws {
        var updated = note
        updated.updatedAt = Date()
        try writeNote(updated)
    }

    /// Schedules a debounced save. The note is written after
    /// `autoSaveInterval` seconds unless another schedule call replaces
    /// it. Cancellation is silent: the most recent call wins, earlier
    /// calls do not surface a "task was cancelled" error to the caller.
    func scheduleSave(_ note: Note) {
        pendingSaves[note.id]?.cancel()
        let interval = autoSaveInterval
        pendingSaves[note.id] = Task { [weak self] in
            guard let self else { return }
            if interval > 0 {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
            }
            try Task.checkCancellation()
            try await self.commitDebouncedSave(note)
        }
    }

    /// Removes the note's file. Idempotent — a "not found" failure
    /// silently returns success because the caller's intent is "this
    /// note must not exist on disk", which is already true.
    func delete(id: UUID, in workspaceID: NoteWorkspaceID) throws {
        // Cancel any pending debounced save so it does not race the
        // delete and recreate the file.
        pendingSaves[id]?.cancel()
        pendingSaves.removeValue(forKey: id)

        let url = fileURL(for: id, in: workspaceID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw NoteStoreError.ioFailure(error.localizedDescription)
        }
    }

    /// Waits for every in-flight debounced save to settle. Tests call
    /// this before asserting against the on-disk state so they never
    /// race the actor's internal scheduling. Cancelled tasks resolve
    /// silently — only true I/O failures propagate.
    func flushPendingSaves() async throws {
        // Snapshot the open tasks before clearing the map so a
        // concurrent `scheduleSave` cannot race the iteration with a
        // new entry. The actor's await suspension below will release
        // isolation, allowing the inner tasks to re-enter the actor
        // and run `commitDebouncedSave` to completion.
        let tasks = Array(pendingSaves.values)
        pendingSaves.removeAll()
        for task in tasks {
            do {
                _ = try await task.value
            } catch is CancellationError {
                continue
            }
        }
    }

    // MARK: - Path helpers

    /// Folder under which every note for `workspaceID` lives.
    func directoryURL(for workspaceID: NoteWorkspaceID) -> URL {
        storageRoot.appendingPathComponent(workspaceID.rawValue, isDirectory: true)
    }

    /// File path for a single note. Pure helper; does not touch disk.
    func fileURL(for id: UUID, in workspaceID: NoteWorkspaceID) -> URL {
        directoryURL(for: workspaceID)
            .appendingPathComponent("\(id.uuidString).\(format.fileExtension)")
    }

    // MARK: - Private I/O

    private func commitDebouncedSave(_ note: Note) throws {
        // Bump the timestamp so listings reflect the actual save time.
        var updated = note
        updated.updatedAt = Date()
        try writeNote(updated)
    }

    private func writeNote(_ note: Note) throws {
        let directory = directoryURL(for: note.workspaceID)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw NoteStoreError.ioFailure(error.localizedDescription)
        }
        let payload = NoteSerializer.serialize(note, format: format)
        let url = fileURL(for: note.id, in: note.workspaceID)
        do {
            try payload.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw NoteStoreError.ioFailure(error.localizedDescription)
        }
        // Touch the modification date so the listing layer can sort
        // by it. `String.write(atomically:)` already updates mtime, so
        // this is a defensive guarantee for filesystems that ignore
        // implicit timestamp updates.
        try? FileManager.default.setAttributes(
            [.modificationDate: note.updatedAt],
            ofItemAtPath: url.path
        )
    }

    private func loadNote(
        at url: URL,
        id: UUID,
        workspaceID: NoteWorkspaceID
    ) throws -> Note {
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw NoteStoreError.ioFailure(error.localizedDescription)
        }
        let parsed: NoteSerializer.DeserialisedNote
        do {
            parsed = try NoteSerializer.deserialize(content, format: format)
        } catch {
            throw NoteStoreError.malformedNoteFile(path: url.path)
        }
        // File-system metadata supplies any missing timestamps so the
        // markdown variant (which has no embedded metadata) still
        // produces sensible values.
        let attributes = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let modificationDate = attributes[.modificationDate] as? Date
        let creationDate = attributes[.creationDate] as? Date
        let createdAt = parsed.createdAt
            ?? creationDate
            ?? modificationDate
            ?? Date()
        let updatedAt = parsed.updatedAt
            ?? modificationDate
            ?? createdAt
        return Note(
            id: parsed.frontmatterID ?? id,
            workspaceID: workspaceID,
            body: parsed.body,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
