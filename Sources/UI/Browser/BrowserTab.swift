// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserTab.swift - Model for individual browser tabs.

import Foundation

// MARK: - Browser Tab

/// Represents a single tab within the in-app browser panel.
///
/// Each tab tracks its own URL, title, and loading state independently.
/// The `BrowserViewModel` manages a collection of these tabs.
///
/// - SeeAlso: `BrowserViewModel` for multi-tab orchestration.
struct BrowserTab: Identifiable, Equatable {

    /// Unique identifier for this tab.
    let id: UUID

    /// The URL currently loaded in this tab.
    var url: URL

    /// The page title shown in the tab bar.
    var title: String

    /// Whether this tab's web view is currently loading.
    var isLoading: Bool

    /// Default URL for new tabs.
    static let defaultURL = URL(string: "http://localhost:3000")!

    /// Creates a new browser tab.
    ///
    /// - Parameters:
    ///   - id: Unique identifier. Defaults to a new UUID.
    ///   - url: The initial URL. Defaults to `http://localhost:3000`.
    ///   - title: The initial tab title. Defaults to "New Tab".
    ///   - isLoading: Whether the tab is loading. Defaults to false.
    init(
        id: UUID = UUID(),
        url: URL = BrowserTab.defaultURL,
        title: String = "New Tab",
        isLoading: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.isLoading = isLoading
    }
}
