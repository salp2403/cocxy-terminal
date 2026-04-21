// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionManaging.swift - Contract for session persistence and restoration.

import Foundation

// MARK: - Session Managing Protocol

/// Manages persistence and restoration of the full application state.
///
/// Sessions capture window geometry, tab order, split tree layout and working
/// directories. They are stored as versioned JSON files in
/// `~/.config/cocxy/sessions/`.
///
/// What is persisted:
/// - Window frame (position and size).
/// - Tab list with working directory, title and last detected agent name.
/// - Split tree (recursive binary tree of panes).
/// - Quick terminal state (open/closed, directory).
///
/// What is NOT persisted:
/// - Terminal scrollback content (too heavy for session snapshots).
/// - Agent state (ephemeral; reconstructed from live detection).
/// - Running processes (a new shell is launched in the persisted directory).
///
/// - SeeAlso: ARCHITECTURE.md Section 7.4
protocol SessionManaging: Sendable {

    /// Saves the current session.
    ///
    /// - Parameters:
    ///   - session: The session state to persist.
    ///   - name: Optional name. When `nil`, saves as the "last" session
    ///     (used for auto-restore on launch).
    /// - Throws: `SessionError` if the write fails.
    func saveSession(_ session: Session, named name: String?) throws

    /// Loads the most recently saved session.
    ///
    /// - Returns: The last session, or `nil` if none exists.
    /// - Throws: `SessionError` if the file exists but cannot be parsed.
    func loadLastSession() throws -> Session?

    /// Loads a session by its name.
    ///
    /// - Parameter name: The name used when saving the session.
    /// - Returns: The session, or `nil` if no session with that name exists.
    /// - Throws: `SessionError` if the file exists but cannot be parsed.
    func loadSession(named name: String) throws -> Session?

    /// Lists all saved sessions with their metadata.
    ///
    /// - Returns: An array of metadata for each saved session, sorted by
    ///   date (most recent first).
    func listSessions() -> [SessionMetadata]

    /// Deletes a saved session.
    ///
    /// - Parameter name: The name of the session to delete, or `nil` for the
    ///   unnamed auto-save session (`last.json`).
    /// - Throws: `SessionError` if the deletion fails.
    func deleteSession(named name: String?) throws
}

// MARK: - Session Model

/// Complete snapshot of the application state at a point in time.
struct Session: Codable, Sendable {
    /// Schema version for forward-compatible migration.
    let version: Int
    /// Timestamp when this session was saved.
    let savedAt: Date
    /// State of all open windows.
    let windows: [WindowState]
    /// Index of the window that was key (focused) at save time.
    /// Defaults to 0 for v1 sessions.
    let focusedWindowIndex: Int

    /// Current schema version. Increment when the format changes.
    static let currentVersion = 2

    init(
        version: Int = Self.currentVersion,
        savedAt: Date = Date(),
        windows: [WindowState],
        focusedWindowIndex: Int = 0
    ) {
        self.version = version
        self.savedAt = savedAt
        self.windows = windows
        self.focusedWindowIndex = focusedWindowIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        windows = try container.decode([WindowState].self, forKey: .windows)
        // v1 sessions do not have focusedWindowIndex — default to 0.
        focusedWindowIndex = try container.decodeIfPresent(Int.self, forKey: .focusedWindowIndex) ?? 0
    }
}

/// State of a single application window.
struct WindowState: Codable, Sendable {
    /// Window frame in screen coordinates.
    let frame: CodableRect
    /// Whether the window is in full-screen mode.
    let isFullScreen: Bool
    /// Ordered list of tabs in this window.
    let tabs: [TabState]
    /// Index of the currently active tab.
    let activeTabIndex: Int
    /// Stable identifier for this window. Fresh UUID assigned on v1 migration.
    let windowID: WindowID?
    /// Display index (for multi-monitor placement). Nil for v1 sessions.
    let displayIndex: Int?

    init(
        frame: CodableRect,
        isFullScreen: Bool,
        tabs: [TabState],
        activeTabIndex: Int,
        windowID: WindowID? = nil,
        displayIndex: Int? = nil
    ) {
        self.frame = frame
        self.isFullScreen = isFullScreen
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
        self.windowID = windowID
        self.displayIndex = displayIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frame = try container.decode(CodableRect.self, forKey: .frame)
        isFullScreen = try container.decode(Bool.self, forKey: .isFullScreen)
        tabs = try container.decode([TabState].self, forKey: .tabs)
        activeTabIndex = try container.decode(Int.self, forKey: .activeTabIndex)
        // v1 sessions do not have these fields.
        windowID = try container.decodeIfPresent(WindowID.self, forKey: .windowID)
        displayIndex = try container.decodeIfPresent(Int.self, forKey: .displayIndex)
    }
}

/// State of a single tab within a window.
struct TabState: Codable, Sendable {
    /// Unique identifier for this tab.
    let id: TabID
    /// Stable session identifier used by the multi-window registry.
    /// v1 sessions do not have this field and migrate to a fresh UUID.
    let sessionID: SessionID
    /// User-visible title, if manually set.
    let title: String?
    /// Working directory of the tab's primary terminal.
    let workingDirectory: URL
    /// Layout of the split panes inside this tab.
    let splitTree: SplitNodeState
    /// Cocxy-managed worktree identifier, if the tab was attached to a
    /// worktree when the session was saved. Added in v0.1.81.
    let worktreeID: String?
    /// Immutable on-disk worktree root, if `worktreeID` is set.
    let worktreeRoot: URL?
    /// Origin repository the worktree was created from. Enables the
    /// `.cocxy.toml` origin-repo fallback on restore.
    let worktreeOriginRepo: URL?
    /// Cached branch name of the worktree at save time.
    let worktreeBranch: String?

    init(
        id: TabID,
        sessionID: SessionID = SessionID(),
        title: String?,
        workingDirectory: URL,
        splitTree: SplitNodeState,
        worktreeID: String? = nil,
        worktreeRoot: URL? = nil,
        worktreeOriginRepo: URL? = nil,
        worktreeBranch: String? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.workingDirectory = workingDirectory
        self.splitTree = splitTree
        self.worktreeID = worktreeID
        self.worktreeRoot = worktreeRoot
        self.worktreeOriginRepo = worktreeOriginRepo
        self.worktreeBranch = worktreeBranch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(TabID.self, forKey: .id)
        sessionID = try container.decodeIfPresent(SessionID.self, forKey: .sessionID) ?? SessionID()
        title = try container.decodeIfPresent(String.self, forKey: .title)
        workingDirectory = try container.decode(URL.self, forKey: .workingDirectory)
        splitTree = try container.decode(SplitNodeState.self, forKey: .splitTree)
        // Worktree fields are all optional and `decodeIfPresent` by
        // design: sessions persisted before v0.1.81 simply omit them
        // and every field falls back to nil, which is indistinguishable
        // from a tab that never had a worktree attached.
        worktreeID = try container.decodeIfPresent(String.self, forKey: .worktreeID)
        worktreeRoot = try container.decodeIfPresent(URL.self, forKey: .worktreeRoot)
        worktreeOriginRepo = try container.decodeIfPresent(URL.self, forKey: .worktreeOriginRepo)
        worktreeBranch = try container.decodeIfPresent(String.self, forKey: .worktreeBranch)
    }
}

/// Recursive tree structure representing split pane layouts.
///
/// Each node is either a leaf (single terminal) or a split
/// (two children with a direction and ratio).
indirect enum SplitNodeState: Codable, Sendable, Equatable {
    /// A terminal pane with its working directory and optional shell command.
    case leaf(workingDirectory: URL, command: String?)
    /// A split containing two child nodes.
    case split(
        direction: SplitDirection,
        first: SplitNodeState,
        second: SplitNodeState,
        ratio: Double
    )
}

/// Direction of a split pane division.
enum SplitDirection: String, Codable, Sendable {
    /// Side-by-side (left | right).
    case horizontal
    /// Stacked (top / bottom).
    case vertical
}

/// Metadata for a saved session (used in session listing without loading full data).
struct SessionMetadata: Sendable {
    /// Display name of the session.
    let name: String
    /// When the session was saved.
    let savedAt: Date
    /// Number of windows in the session.
    let windowCount: Int
    /// Total number of tabs across all windows.
    let tabCount: Int
}

/// A `CGRect`-equivalent that conforms to `Codable` and `Sendable`.
///
/// We avoid using `CGRect` directly in the session model because it requires
/// importing CoreGraphics and its `Codable` conformance is not guaranteed
/// across all platforms.
struct CodableRect: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// Errors that can occur during session operations.
enum SessionError: Error, Sendable {
    /// The session file could not be written to disk.
    case writeFailed(reason: String)
    /// The session file exists but contains invalid data.
    case parseFailed(reason: String)
    /// The session file could not be deleted.
    case deleteFailed(reason: String)
    /// The session format version is newer than what this app understands.
    case unsupportedVersion(found: Int, supported: Int)
}
