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
    /// A terminal emulator surface backed by the native renderer.
    case terminal

    /// An embedded web browser (WKWebView).
    case browser

    /// A markdown document viewer.
    case markdown

    /// A general-purpose local text editor.
    case editor

    /// A local executable notebook panel.
    case notebook

    /// A local reusable workflow panel.
    case workflow

    /// A local terminal session recording library and replay panel.
    case sessionReplay = "session-replay"

    /// A local timeline of recorded agent file edits.
    case aiEditHistory = "ai-edit-history"

    /// A local project scaffold template picker.
    case templates

    /// A local macro, snippet, alias, and clipboard manager.
    case macros

    /// A local DB/cloud helper panel that runs user-triggered local CLIs.
    case dbCloud = "db-cloud"

    /// A live subagent activity panel.
    case subagent
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

    /// Optional file path for document-backed panels.
    let filePath: URL?

    /// Subagent identifier for linking the panel to dashboard data.
    let subagentId: String?

    /// Parent session identifier for linking the panel to dashboard data.
    let sessionId: String?

    init(type: PanelType, initialURL: URL? = nil, filePath: URL? = nil,
         subagentId: String? = nil, sessionId: String? = nil) {
        self.type = type
        self.initialURL = initialURL
        self.filePath = filePath
        self.subagentId = subagentId
        self.sessionId = sessionId
    }

    static let terminal = PanelInfo(type: .terminal)
    static func browser(url: URL? = nil) -> PanelInfo {
        PanelInfo(type: .browser, initialURL: url ?? URL(string: "http://localhost:3000"))
    }
    static func markdown(path: URL) -> PanelInfo {
        PanelInfo(type: .markdown, filePath: path)
    }
    static func editor(path: URL? = nil) -> PanelInfo {
        PanelInfo(type: .editor, filePath: path)
    }
    static func notebook(path: URL? = nil) -> PanelInfo {
        PanelInfo(type: .notebook, filePath: path)
    }
    static func workflow(path: URL? = nil) -> PanelInfo {
        PanelInfo(type: .workflow, filePath: path)
    }
    static func sessionReplay() -> PanelInfo {
        PanelInfo(type: .sessionReplay)
    }
    static func aiEditHistory(sessionID: String? = nil, workingDirectory: URL? = nil) -> PanelInfo {
        PanelInfo(type: .aiEditHistory, filePath: workingDirectory, sessionId: sessionID)
    }
    static func templates(workingDirectory: URL? = nil) -> PanelInfo {
        PanelInfo(type: .templates, filePath: workingDirectory)
    }
    static func macros(workingDirectory: URL? = nil) -> PanelInfo {
        PanelInfo(type: .macros, filePath: workingDirectory)
    }
    static func dbCloud(workingDirectory: URL? = nil) -> PanelInfo {
        PanelInfo(type: .dbCloud, filePath: workingDirectory)
    }
    static func subagent(id: String, sessionId: String) -> PanelInfo {
        PanelInfo(type: .subagent, subagentId: id, sessionId: sessionId)
    }
}
