// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserBookmarkStoreTests.swift - Tests for bookmark store tree operations.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - In-Memory Bookmark Store

/// In-memory bookmark store for deterministic testing without file I/O.
final class InMemoryBookmarkStore: BrowserBookmarkStoring, @unchecked Sendable {

    private var bookmarks: [BrowserBookmark] = []
    private let queue = DispatchQueue(label: "test.bookmark-store")

    func loadAll() throws -> [BrowserBookmark] {
        queue.sync { bookmarks }
    }

    func save(_ bookmark: BrowserBookmark) throws {
        queue.sync { bookmarks.append(bookmark) }
    }

    func update(_ bookmark: BrowserBookmark) throws {
        queue.sync {
            guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
            bookmarks[index] = bookmark
        }
    }

    func delete(id: UUID) throws {
        queue.sync {
            let idsToDelete = collectDescendantIDs(of: id)
            bookmarks.removeAll { idsToDelete.contains($0.id) }
        }
    }

    func move(id: UUID, toParent: UUID?, sortOrder: Int) throws {
        queue.sync {
            guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
            bookmarks[index].parentID = toParent
            bookmarks[index].sortOrder = sortOrder
        }
    }

    func search(query: String) -> [BrowserBookmark] {
        queue.sync {
            let lowered = query.lowercased()
            guard !lowered.isEmpty else { return [] }

            return bookmarks
                .filter { !$0.isFolder }
                .filter {
                    $0.title.lowercased().contains(lowered)
                        || ($0.url?.lowercased().contains(lowered) ?? false)
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
}

// MARK: - Browser Bookmark Store Tests

@Suite("BrowserBookmarkStore")
struct BrowserBookmarkStoreTests {

    private func makeStore() -> InMemoryBookmarkStore {
        InMemoryBookmarkStore()
    }

    // MARK: - Add Bookmark

    @Test("Save bookmark makes it retrievable via loadAll")
    func saveBookmark() throws {
        let store = makeStore()
        let bookmark = BrowserBookmark.bookmark(title: "Swift", url: "https://swift.org")

        try store.save(bookmark)
        let all = try store.loadAll()

        #expect(all.count == 1)
        #expect(all[0].title == "Swift")
        #expect(all[0].url == "https://swift.org")
    }

    @Test("Save folder makes it retrievable")
    func saveFolder() throws {
        let store = makeStore()
        let folder = BrowserBookmark.folder(name: "Dev Resources")

        try store.save(folder)
        let all = try store.loadAll()

        #expect(all.count == 1)
        #expect(all[0].isFolder == true)
        #expect(all[0].url == nil)
    }

    // MARK: - Add Folder with Children

    @Test("Children saved under a folder are retrievable via children(of:)")
    func folderWithChildren() throws {
        let store = makeStore()
        let folder = BrowserBookmark.folder(name: "Docs")
        try store.save(folder)

        let child1 = BrowserBookmark.bookmark(
            title: "Swift Docs", url: "https://swift.org", parentID: folder.id
        )
        let child2 = BrowserBookmark.bookmark(
            title: "Apple Docs", url: "https://developer.apple.com", parentID: folder.id
        )
        try store.save(child1)
        try store.save(child2)

        let kids = store.children(of: folder.id)

        #expect(kids.count == 2)
    }

    // MARK: - Delete

    @Test("Delete folder cascades to children")
    func deleteFolderCascadesChildren() throws {
        let store = makeStore()
        let folder = BrowserBookmark.folder(name: "To Delete")
        try store.save(folder)

        let child = BrowserBookmark.bookmark(
            title: "Child", url: "https://child.com", parentID: folder.id
        )
        try store.save(child)

        try store.delete(id: folder.id)
        let all = try store.loadAll()

        #expect(all.isEmpty)
    }

    @Test("Delete folder cascades to nested grandchildren")
    func deleteFolderCascadesGrandchildren() throws {
        let store = makeStore()
        let root = BrowserBookmark.folder(name: "Root")
        try store.save(root)

        let subfolder = BrowserBookmark.folder(name: "Sub", parentID: root.id)
        try store.save(subfolder)

        let leaf = BrowserBookmark.bookmark(
            title: "Leaf", url: "https://leaf.com", parentID: subfolder.id
        )
        try store.save(leaf)

        try store.delete(id: root.id)
        let all = try store.loadAll()

        #expect(all.isEmpty)
    }

    @Test("Deleting a bookmark does not affect siblings")
    func deleteSingleBookmark() throws {
        let store = makeStore()
        let a = BrowserBookmark.bookmark(title: "A", url: "https://a.com")
        let b = BrowserBookmark.bookmark(title: "B", url: "https://b.com")
        try store.save(a)
        try store.save(b)

        try store.delete(id: a.id)
        let all = try store.loadAll()

        #expect(all.count == 1)
        #expect(all[0].id == b.id)
    }

    // MARK: - Move

    @Test("Move bookmark to folder changes parentID")
    func moveBookmarkToFolder() throws {
        let store = makeStore()
        let folder = BrowserBookmark.folder(name: "Target")
        let bookmark = BrowserBookmark.bookmark(title: "Movable", url: "https://move.me")
        try store.save(folder)
        try store.save(bookmark)

        try store.move(id: bookmark.id, toParent: folder.id, sortOrder: 0)

        let kids = store.children(of: folder.id)
        #expect(kids.count == 1)
        #expect(kids[0].id == bookmark.id)
    }

    @Test("Move bookmark to root sets parentID to nil")
    func moveBookmarkToRoot() throws {
        let store = makeStore()
        let folder = BrowserBookmark.folder(name: "Folder")
        try store.save(folder)

        let bookmark = BrowserBookmark(
            title: "Nested", url: "https://nested.com", parentID: folder.id
        )
        try store.save(bookmark)

        try store.move(id: bookmark.id, toParent: nil, sortOrder: 0)

        let rootItems = store.children(of: nil)
        let movedItem = rootItems.first(where: { $0.id == bookmark.id })
        #expect(movedItem != nil)
        #expect(movedItem?.parentID == nil)
    }

    // MARK: - Reorder

    @Test("Reorder bookmarks via sort order")
    func reorderBookmarks() throws {
        let store = makeStore()
        let a = BrowserBookmark(title: "A", url: "https://a.com", sortOrder: 0)
        let b = BrowserBookmark(title: "B", url: "https://b.com", sortOrder: 1)
        let c = BrowserBookmark(title: "C", url: "https://c.com", sortOrder: 2)
        try store.save(a)
        try store.save(b)
        try store.save(c)

        try store.move(id: c.id, toParent: nil, sortOrder: 0)
        try store.move(id: a.id, toParent: nil, sortOrder: 1)
        try store.move(id: b.id, toParent: nil, sortOrder: 2)

        let ordered = store.children(of: nil)

        #expect(ordered[0].id == c.id)
        #expect(ordered[1].id == a.id)
        #expect(ordered[2].id == b.id)
    }

    // MARK: - Search

    @Test("Search finds bookmarks by title")
    func searchByTitle() throws {
        let store = makeStore()
        try store.save(BrowserBookmark.bookmark(title: "Swift Language", url: "https://swift.org"))
        try store.save(BrowserBookmark.bookmark(title: "Rust Language", url: "https://rust-lang.org"))

        let results = store.search(query: "Swift")

        #expect(results.count == 1)
        #expect(results[0].title == "Swift Language")
    }

    @Test("Search finds bookmarks by URL")
    func searchByURL() throws {
        let store = makeStore()
        try store.save(BrowserBookmark.bookmark(title: "GitHub", url: "https://github.com"))
        try store.save(BrowserBookmark.bookmark(title: "GitLab", url: "https://gitlab.com"))

        let results = store.search(query: "github")

        #expect(results.count == 1)
        #expect(results[0].title == "GitHub")
    }

    @Test("Search excludes folders from results")
    func searchExcludesFolders() throws {
        let store = makeStore()
        try store.save(BrowserBookmark.folder(name: "Swift Resources"))
        try store.save(BrowserBookmark.bookmark(title: "Swift Docs", url: "https://swift.org"))

        let results = store.search(query: "Swift")

        #expect(results.count == 1)
        #expect(results[0].isFolder == false)
    }

    @Test("Search with empty query returns empty results")
    func searchEmptyQuery() throws {
        let store = makeStore()
        try store.save(BrowserBookmark.bookmark(title: "Test", url: "https://test.com"))

        let results = store.search(query: "")

        #expect(results.isEmpty)
    }

    @Test("Search is case-insensitive")
    func searchCaseInsensitive() throws {
        let store = makeStore()
        try store.save(BrowserBookmark.bookmark(title: "UPPERCASE", url: "https://upper.com"))

        let results = store.search(query: "uppercase")

        #expect(results.count == 1)
    }

    // MARK: - Children

    @Test("children(of: nil) returns root items only")
    func childrenOfRoot() throws {
        let store = makeStore()
        let folder = BrowserBookmark.folder(name: "Folder")
        let rootBookmark = BrowserBookmark.bookmark(title: "Root", url: "https://root.com")
        try store.save(folder)
        try store.save(rootBookmark)

        let nestedBookmark = BrowserBookmark.bookmark(
            title: "Nested", url: "https://nested.com", parentID: folder.id
        )
        try store.save(nestedBookmark)

        let rootItems = store.children(of: nil)

        #expect(rootItems.count == 2)
        #expect(!rootItems.contains(where: { $0.id == nestedBookmark.id }))
    }

    @Test("children returns items sorted by sortOrder")
    func childrenSortedBySortOrder() throws {
        let store = makeStore()
        let b = BrowserBookmark(title: "B", url: "https://b.com", sortOrder: 1)
        let a = BrowserBookmark(title: "A", url: "https://a.com", sortOrder: 0)
        let c = BrowserBookmark(title: "C", url: "https://c.com", sortOrder: 2)
        try store.save(b)
        try store.save(a)
        try store.save(c)

        let ordered = store.children(of: nil)

        #expect(ordered[0].title == "A")
        #expect(ordered[1].title == "B")
        #expect(ordered[2].title == "C")
    }

    // MARK: - Update

    @Test("Update bookmark changes title")
    func updateBookmarkTitle() throws {
        let store = makeStore()
        var bookmark = BrowserBookmark.bookmark(title: "Old", url: "https://example.com")
        try store.save(bookmark)

        bookmark.title = "New"
        try store.update(bookmark)

        let all = try store.loadAll()
        #expect(all[0].title == "New")
    }
}
