// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserBookmark.swift - Domain model for browser bookmarks with folder hierarchy.

import Foundation

// MARK: - Browser Bookmark

/// A bookmark or folder within the bookmark tree.
///
/// Bookmarks have a URL and are leaf nodes. Folders have no URL and act
/// as containers for other bookmarks and folders. The tree structure is
/// represented via `parentID` references.
///
/// - SeeAlso: ``BrowserBookmarkStoring`` for persistence and tree queries.
struct BrowserBookmark: Identifiable, Codable, Equatable, Sendable {

    /// Unique identifier for this bookmark or folder.
    let id: UUID

    /// User-visible title.
    var title: String

    /// URL string. Nil for folders.
    var url: String?

    /// Parent folder ID. Nil for root-level items.
    var parentID: UUID?

    /// Whether this item is a folder (container) or a bookmark (leaf).
    var isFolder: Bool

    /// Position within its parent. Lower values appear first.
    var sortOrder: Int

    /// Timestamp when this item was created.
    let createdAt: Date

    /// Creates a bookmark or folder.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - title: Display title.
    ///   - url: URL string. Nil for folders.
    ///   - parentID: Parent folder ID. Nil for root items.
    ///   - isFolder: Whether this is a folder.
    ///   - sortOrder: Sort position within parent. Defaults to 0.
    ///   - createdAt: Creation timestamp. Defaults to now.
    init(
        id: UUID = UUID(),
        title: String,
        url: String? = nil,
        parentID: UUID? = nil,
        isFolder: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.parentID = parentID
        self.isFolder = isFolder
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    // MARK: - Factory Methods

    /// Creates a folder with the given name.
    ///
    /// - Parameters:
    ///   - name: Display name for the folder.
    ///   - parentID: Parent folder ID. Nil for root-level folders.
    /// - Returns: A new folder bookmark.
    static func folder(name: String, parentID: UUID? = nil) -> BrowserBookmark {
        BrowserBookmark(
            title: name,
            url: nil,
            parentID: parentID,
            isFolder: true
        )
    }

    /// Creates a bookmark with the given title and URL.
    ///
    /// - Parameters:
    ///   - title: Display title.
    ///   - url: URL string.
    ///   - parentID: Parent folder ID. Nil for root-level bookmarks.
    /// - Returns: A new bookmark.
    static func bookmark(title: String, url: String, parentID: UUID? = nil) -> BrowserBookmark {
        BrowserBookmark(
            title: title,
            url: url,
            parentID: parentID,
            isFolder: false
        )
    }
}
