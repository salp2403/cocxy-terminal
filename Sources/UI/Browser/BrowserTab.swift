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

    /// Title safe for browser chrome.
    ///
    /// WebKit can report an empty title while a page is loading, when a
    /// localhost server is down, or when the document simply has no title.
    /// The tab strip should still expose a stable label and hit target.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !Self.placeholderTitles.contains(trimmed.lowercased()) {
            return trimmed
        }
        return Self.fallbackDisplayTitle(for: url)
    }

    /// Default URL for new tabs.
    static let defaultURL = URL(string: "http://localhost:3000")!

    private static let placeholderTitles: Set<String> = [
        "new tab",
    ]

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

    static func fallbackDisplayTitle(for url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            if let port = url.port {
                return "\(host):\(port)"
            }
            return host
        }

        let lastPathComponent = url.lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }

        if !url.absoluteString.isEmpty {
            return url.absoluteString
        }

        return "New Tab"
    }
}
