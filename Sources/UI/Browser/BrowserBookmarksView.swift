// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserBookmarksView.swift - Bookmark management panel with folder hierarchy.

import SwiftUI

// MARK: - Browser Bookmarks View

/// A panel showing bookmarks organized in a folder tree with search.
///
/// ## Layout
///
/// ```
/// +-- Bookmarks -------------------+
/// |                          [+] X |
/// +--------------------------------+
/// | Search bookmarks...            |
/// +--------------------------------+
/// | > Development                  |
/// |     localhost:3000             |
/// |     GitHub                     |
/// | > Documentation                |
/// |     Swift Docs                 |
/// |     MDN                        |
/// | Stack Overflow                 |  <- root level
/// +--------------------------------+
/// ```
///
/// ## Features
///
/// - Tree view with expandable folders.
/// - Search filters by title and URL.
/// - Click a bookmark to navigate the browser.
/// - Add bookmark button for the current page.
/// - Delete bookmarks via context menu.
///
/// - SeeAlso: ``BrowserBookmark`` for the data model.
/// - SeeAlso: ``BrowserBookmarkStoring`` for the persistence layer.
struct BrowserBookmarksView: View {

    /// The bookmark store providing tree CRUD operations.
    let bookmarkStore: BrowserBookmarkStoring

    /// Called when the user clicks a bookmark to navigate to its URL.
    let onNavigate: (String) -> Void

    /// Called to add a bookmark for the current page.
    let onAddBookmark: () -> Void

    /// Called when the user taps the close button.
    let onDismiss: () -> Void

    /// Search query text.
    @State private var searchText: String = ""

    /// Set of expanded folder IDs for tree state.
    @State private var expandedFolderIDs: Set<UUID> = []

    /// Bookmark selected for deletion confirmation.
    @State private var bookmarkToDelete: BrowserBookmark? = nil

    /// Whether the delete confirmation alert is showing.
    @State private var showDeleteConfirmation: Bool = false

    /// Incremented after mutations to force SwiftUI to re-evaluate the body.
    /// The store is not observable, so this is the reactive bridge.
    @State private var storeRevision: UInt = 0

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            searchBar
            Divider()
            bookmarkListView
        }
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bookmarks")
        .alert("Delete Bookmark", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let bookmark = bookmarkToDelete {
                    try? bookmarkStore.delete(id: bookmark.id)
                    bookmarkToDelete = nil
                    storeRevision &+= 1
                }
            }
            Button("Cancel", role: .cancel) {
                bookmarkToDelete = nil
            }
        } message: {
            if let bookmark = bookmarkToDelete {
                let itemType = bookmark.isFolder ? "folder and all its contents" : "bookmark"
                Text("Are you sure you want to delete this \(itemType)?")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Bookmarks")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button {
                onAddBookmark()
                storeRevision &+= 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Add bookmark")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close bookmarks")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))

            TextField("Search bookmarks...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.text))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: CocxyColors.surface0).opacity(0.5))
    }

    // MARK: - Bookmark List

    @ViewBuilder
    private var bookmarkListView: some View {
        if isSearchActive {
            searchResultsView
                .id(storeRevision)
        } else {
            treeView
                .id(storeRevision)
        }
    }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Search Results

    private var searchResultsView: some View {
        let results = bookmarkStore.search(query: searchText)

        return Group {
            if results.isEmpty {
                bookmarksEmptyState(
                    symbol: "magnifyingglass",
                    title: "No results",
                    detail: "No bookmarks match your search."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.id) { bookmark in
                            bookmarkRow(bookmark, depth: 0)
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tree View

    private var treeView: some View {
        let rootItems = bookmarkStore.children(of: nil)

        return Group {
            if rootItems.isEmpty {
                bookmarksEmptyState(
                    symbol: "bookmark",
                    title: "No bookmarks",
                    detail: "Add bookmarks to quickly access your favorite pages."
                )
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rootItems, id: \.id) { item in
                            bookmarkTreeNode(item, depth: 0)
                        }
                    }
                }
            }
        }
    }

    private func bookmarkTreeNode(_ item: BrowserBookmark, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                if item.isFolder {
                    folderRow(item, depth: depth)

                    if expandedFolderIDs.contains(item.id) {
                        let children = bookmarkStore.children(of: item.id)
                        ForEach(children, id: \.id) { child in
                            bookmarkTreeNode(child, depth: depth + 1)
                        }
                    }
                } else {
                    bookmarkRow(item, depth: depth)
                }

                Divider()
                    .padding(.leading, CGFloat(depth) * 16 + 12)
            }
        )
    }

    // MARK: - Folder Row

    private func folderRow(_ folder: BrowserBookmark, depth: Int) -> some View {
        let isExpanded = expandedFolderIDs.contains(folder.id)

        return HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .frame(width: 12)

            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.yellow))

            Text(folder.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 16 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleFolder(folder.id)
        }
        .contextMenu {
            Button("Delete Folder") {
                bookmarkToDelete = folder
                showDeleteConfirmation = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folder: \(folder.title)")
        .accessibilityHint(isExpanded ? "Expanded" : "Collapsed")
    }

    // MARK: - Bookmark Row

    private func bookmarkRow(_ bookmark: BrowserBookmark, depth: Int) -> some View {
        HStack(spacing: 6) {
            Spacer()
                .frame(width: 12)

            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundColor(Color(nsColor: CocxyColors.peach))

            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.title)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: CocxyColors.text))
                    .lineLimit(1)

                if let url = bookmark.url {
                    Text(url)
                        .font(.system(size: 9))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()
        }
        .padding(.leading, CGFloat(depth) * 16 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = bookmark.url {
                onNavigate(url)
            }
        }
        .contextMenu {
            if let url = bookmark.url {
                Button("Open") { onNavigate(url) }
            }
            Button("Delete", role: .destructive) {
                bookmarkToDelete = bookmark
                showDeleteConfirmation = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bookmark: \(bookmark.title)")
    }

    // MARK: - Empty State

    private func bookmarksEmptyState(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - State Management

    private func toggleFolder(_ folderID: UUID) {
        if expandedFolderIDs.contains(folderID) {
            expandedFolderIDs.remove(folderID)
        } else {
            expandedFolderIDs.insert(folderID)
        }
    }
}
