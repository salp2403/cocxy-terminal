// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserBookmarkStore.swift - Persistent storage for browser bookmarks with tree structure.

import Foundation

// MARK: - Bookmark Storing Protocol

/// Contract for bookmark persistence with tree-structured CRUD.
///
/// Implementations manage a flat list of bookmarks internally but expose
/// tree operations (children of a parent, cascade delete of folders, move
/// with reparenting). Search covers both title and URL fields.
///
/// - SeeAlso: ``JSONBrowserBookmarkStore`` for the default implementation.
protocol BrowserBookmarkStoring: Sendable {

    /// Loads all bookmarks from persistent storage.
    ///
    /// - Returns: Every bookmark and folder, regardless of hierarchy.
    /// - Throws: If the storage cannot be read.
    func loadAll() throws -> [BrowserBookmark]

    /// Saves a new bookmark or folder.
    ///
    /// - Parameter bookmark: The item to save.
    /// - Throws: If the storage cannot be written.
    func save(_ bookmark: BrowserBookmark) throws

    /// Updates an existing bookmark or folder.
    ///
    /// Matches by `id`. No-op if not found.
    ///
    /// - Parameter bookmark: The item with updated values.
    /// - Throws: If the storage cannot be written.
    func update(_ bookmark: BrowserBookmark) throws

    /// Deletes a bookmark or folder by ID.
    ///
    /// If the item is a folder, all children (recursively) are deleted too.
    ///
    /// - Parameter id: The ID of the item to delete.
    /// - Throws: If the storage cannot be written.
    func delete(id: UUID) throws

    /// Moves a bookmark or folder to a new parent and/or sort position.
    ///
    /// - Parameters:
    ///   - id: The item to move.
    ///   - toParent: The new parent folder ID. Nil moves to root.
    ///   - sortOrder: The new sort position within the parent.
    /// - Throws: If the storage cannot be written.
    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws

    /// Searches bookmarks by title and URL (case-insensitive substring match).
    ///
    /// Folders are excluded from results.
    ///
    /// - Parameter query: The search string.
    /// - Returns: Matching bookmarks sorted by title.
    func search(query: String) -> [BrowserBookmark]

    /// Returns the direct children of a parent, sorted by `sortOrder`.
    ///
    /// - Parameter parentID: The parent folder ID. Nil returns root items.
    /// - Returns: Direct children sorted by sort order.
    func children(of parentID: UUID?) -> [BrowserBookmark]
}

// MARK: - JSON Bookmark Store

/// File-based bookmark store using JSON serialization.
///
/// Stores all bookmarks in `~/.config/cocxy/browser/bookmarks.json`.
/// Keeps the full list in memory for fast tree operations and flushes
/// to disk on every mutation.
///
/// ## Thread Safety
///
/// All mutations are serialized on a private dispatch queue. The
/// `@unchecked Sendable` conformance is safe because the queue
/// protects all mutable state.
///
/// - SeeAlso: ``BrowserBookmarkStoring``
final class JSONBrowserBookmarkStore: BrowserBookmarkStoring, @unchecked Sendable {

    // MARK: - Properties

    private var bookmarks: [BrowserBookmark]
    private let filePath: String
    private let queue: DispatchQueue

    // MARK: - Initialization

    /// Creates a bookmark store at the given file path.
    ///
    /// Loads existing bookmarks from disk. If the file does not exist,
    /// starts with an empty collection.
    ///
    /// - Parameter filePath: Path to the JSON file. Defaults to the standard config location.
    init(filePath: String = NSHomeDirectory() + "/.config/cocxy/browser/bookmarks.json") {
        self.filePath = filePath
        self.queue = DispatchQueue(label: "com.cocxy.browser-bookmarks", qos: .userInitiated)
        self.bookmarks = Self.loadFromDisk(path: filePath)
    }

    // MARK: - BrowserBookmarkStoring

    func loadAll() throws -> [BrowserBookmark] {
        queue.sync { bookmarks }
    }

    func save(_ bookmark: BrowserBookmark) throws {
        try queue.sync {
            bookmarks.append(bookmark)
            try persist()
        }
    }

    func update(_ bookmark: BrowserBookmark) throws {
        try queue.sync {
            guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
            bookmarks[index] = bookmark
            try persist()
        }
    }

    func delete(id: UUID) throws {
        try queue.sync {
            let idsToDelete = collectDescendantIDs(of: id)
            bookmarks.removeAll { idsToDelete.contains($0.id) }
            try persist()
        }
    }

    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws {
        try queue.sync {
            guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }

            if let toParent {
                let descendants = collectDescendantIDs(of: id)
                guard !descendants.contains(toParent) else { return }
            }

            bookmarks[index].parentID = toParent
            bookmarks[index].sortOrder = sortOrder
            try persist()
        }
    }

    func search(query: String) -> [BrowserBookmark] {
        queue.sync {
            let lowered = query.lowercased()
            guard !lowered.isEmpty else { return [] }

            return bookmarks
                .filter { !$0.isFolder }
                .filter { bookmark in
                    bookmark.title.lowercased().contains(lowered)
                        || (bookmark.url?.lowercased().contains(lowered) ?? false)
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    func children(of parentID: UUID?) -> [BrowserBookmark] {
        queue.sync {
            bookmarks
                .filter { $0.parentID == parentID }
                .sorted { $0.sortOrder < $1.sortOrder }
        }
    }

    // MARK: - Tree Helpers

    /// Collects the ID of the given item plus all descendant IDs (recursive).
    private func collectDescendantIDs(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = [id]
        var frontier: [UUID] = [id]

        while !frontier.isEmpty {
            let current = frontier.removeFirst()
            let childIDs = bookmarks
                .filter { $0.parentID == current }
                .map { $0.id }
            for childID in childIDs {
                result.insert(childID)
                frontier.append(childID)
            }
        }

        return result
    }

    // MARK: - Persistence

    private func persist() throws {
        let url = URL(fileURLWithPath: filePath)
        let directory = url.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bookmarks)
        try data.write(to: url, options: .atomic)
    }

    private static func loadFromDisk(path: String) -> [BrowserBookmark] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [] }
        return (try? JSONDecoder().decode([BrowserBookmark].self, from: data)) ?? []
    }
}
