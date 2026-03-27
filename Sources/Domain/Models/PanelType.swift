// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PanelType.swift - Content type for workspace panels.

import Foundation

// MARK: - Panel Type

/// The type of content hosted by a panel within a workspace.
///
/// Each leaf in the `SplitNode` tree can host one of these content types.
/// Terminal is the default. Browser and Markdown panels can be added
/// alongside terminals within the same workspace (tab).
///
/// - SeeAlso: `SplitManager` for panel type tracking.
/// - SeeAlso: `SplitContainer` for rendering different panel types.
enum PanelType: String, Codable, Sendable, Equatable {
    /// A terminal emulator surface (GPU-accelerated via libghostty).
    case terminal

    /// An embedded web browser (WKWebView).
    case browser

    /// A markdown document viewer.
    case markdown
}

// MARK: - Panel Info

/// Metadata for a panel within a workspace.
///
/// Carries the content type and an optional initial configuration
/// (e.g., the URL for a browser panel or the file path for markdown).
struct PanelInfo: Equatable, Sendable {
    /// The type of content this panel displays.
    let type: PanelType

    /// Optional initial URL for browser panels.
    let initialURL: URL?

    /// Optional file path for markdown panels.
    let filePath: URL?

    init(type: PanelType, initialURL: URL? = nil, filePath: URL? = nil) {
        self.type = type
        self.initialURL = initialURL
        self.filePath = filePath
    }

    static let terminal = PanelInfo(type: .terminal)
    static func browser(url: URL? = nil) -> PanelInfo {
        PanelInfo(type: .browser, initialURL: url ?? URL(string: "http://localhost:3000"))
    }
    static func markdown(path: URL) -> PanelInfo {
        PanelInfo(type: .markdown, filePath: path)
    }
}
