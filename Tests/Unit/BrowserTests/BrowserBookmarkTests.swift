// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserBookmarkTests.swift - Tests for bookmark model and factory methods.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - Browser Bookmark Tests

@Suite("BrowserBookmark model")
struct BrowserBookmarkTests {

    // MARK: - Initialization

    @Test("Default initialization sets expected values")
    func defaultInitialization() {
        let bookmark = BrowserBookmark(title: "Test")

        #expect(bookmark.title == "Test")
        #expect(bookmark.url == nil)
        #expect(bookmark.parentID == nil)
        #expect(bookmark.isFolder == false)
        #expect(bookmark.sortOrder == 0)
        #expect(!bookmark.id.uuidString.isEmpty)
    }

    @Test("Full initialization preserves all parameters")
    func fullInitialization() {
        let fixedID = UUID()
        let parentID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let bookmark = BrowserBookmark(
            id: fixedID,
            title: "Custom",
            url: "https://swift.org",
            parentID: parentID,
            isFolder: false,
            sortOrder: 5,
            createdAt: fixedDate
        )

        #expect(bookmark.id == fixedID)
        #expect(bookmark.title == "Custom")
        #expect(bookmark.url == "https://swift.org")
        #expect(bookmark.parentID == parentID)
        #expect(bookmark.isFolder == false)
        #expect(bookmark.sortOrder == 5)
        #expect(bookmark.createdAt == fixedDate)
    }

    // MARK: - Factory Methods

    @Test("Folder factory creates a folder with no URL")
    func folderFactoryMethod() {
        let folder = BrowserBookmark.folder(name: "Dev Resources")

        #expect(folder.title == "Dev Resources")
        #expect(folder.isFolder == true)
        #expect(folder.url == nil)
        #expect(folder.parentID == nil)
    }

    @Test("Folder factory respects parent ID")
    func folderFactoryWithParent() {
        let parentID = UUID()
        let folder = BrowserBookmark.folder(name: "Subfolder", parentID: parentID)

        #expect(folder.parentID == parentID)
        #expect(folder.isFolder == true)
    }

    @Test("Bookmark factory creates a bookmark with URL")
    func bookmarkFactoryMethod() {
        let bookmark = BrowserBookmark.bookmark(
            title: "Swift Docs",
            url: "https://swift.org/documentation"
        )

        #expect(bookmark.title == "Swift Docs")
        #expect(bookmark.url == "https://swift.org/documentation")
        #expect(bookmark.isFolder == false)
        #expect(bookmark.parentID == nil)
    }

    @Test("Bookmark factory respects parent ID")
    func bookmarkFactoryWithParent() {
        let parentID = UUID()
        let bookmark = BrowserBookmark.bookmark(
            title: "Nested",
            url: "https://example.com",
            parentID: parentID
        )

        #expect(bookmark.parentID == parentID)
        #expect(bookmark.isFolder == false)
    }

    // MARK: - Codable Roundtrip

    @Test("Bookmark survives JSON encode-decode roundtrip")
    func bookmarkCodableRoundtrip() throws {
        let original = BrowserBookmark.bookmark(
            title: "Roundtrip Test",
            url: "https://roundtrip.test"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserBookmark.self, from: data)

        #expect(decoded == original)
    }

    @Test("Folder survives JSON encode-decode roundtrip")
    func folderCodableRoundtrip() throws {
        let original = BrowserBookmark.folder(name: "Roundtrip Folder")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BrowserBookmark.self, from: data)

        #expect(decoded == original)
    }

    // MARK: - Equality

    @Test("Bookmarks with same properties are equal")
    func equalBookmarks() {
        let fixedID = UUID()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let a = BrowserBookmark(
            id: fixedID, title: "Same", url: "https://same.com",
            parentID: nil, isFolder: false, sortOrder: 0, createdAt: fixedDate
        )
        let b = BrowserBookmark(
            id: fixedID, title: "Same", url: "https://same.com",
            parentID: nil, isFolder: false, sortOrder: 0, createdAt: fixedDate
        )

        #expect(a == b)
    }

    @Test("Bookmarks with different IDs are not equal")
    func differentBookmarks() {
        let a = BrowserBookmark.bookmark(title: "A", url: "https://a.com")
        let b = BrowserBookmark.bookmark(title: "A", url: "https://a.com")

        #expect(a != b)
    }
}
