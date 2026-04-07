// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionRegistryTypes.swift - Core types for multi-window session synchronization.

import Foundation

// MARK: - Session ID

/// Unique identifier for a terminal session across all windows.
///
/// A session maps 1:1 to a tab. When a tab is dragged between windows,
/// the session ID remains stable — only the owner window changes.
struct SessionID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init() {
        self.rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

// MARK: - Window ID

/// Unique identifier for an application window.
///
/// Assigned once when a `MainWindowController` is created and never
/// changes for the lifetime of that window. Used to track session
/// ownership and route events to the correct window.
struct WindowID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init() {
        self.rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

// MARK: - Transfer State

/// Tracks the lifecycle of a tab being moved between windows.
///
/// A session is normally `.stable`. When a drag begins, it transitions to
/// `.inTransfer` and remains there until the drop target calls
/// `completeTransfer` or the operation is cancelled.
///
/// Only one transfer per session is allowed at a time — `prepareTransfer`
/// returns `false` if the session is already mid-transfer.
enum TransferState: Sendable, Equatable {
    /// The session is in its home window. No transfer in progress.
    case stable
    /// The session is being moved from one window to another.
    case inTransfer(from: WindowID, to: WindowID)
}

// MARK: - Session Entry

/// Metadata for a single terminal session tracked by the registry.
///
/// `SessionEntry` is a value type that stores identity, ownership, and
/// lightweight UI state. Heavy data (scrollback, view hierarchy) stays
/// in the owning `TerminalViewModel`.
///
/// The registry stores entries in a flat dictionary keyed by `SessionID`.
/// All mutations go through the registry's `@MainActor` methods to
/// ensure thread safety and publisher consistency.
struct SessionEntry: Sendable, Equatable {
    /// Unique session identifier. Stable across window transfers.
    let sessionID: SessionID

    /// Timestamp when this session was first created.
    let createdAt: Date

    /// The window that currently owns this session.
    var ownerWindowID: WindowID

    /// The tab ID within the owning window's `TabManager`.
    var tabID: TabID

    /// User-visible title (auto-generated or custom).
    var title: String

    /// Working directory of the primary terminal in this session.
    var workingDirectory: URL

    /// Current state of the AI agent in this session.
    var agentState: AgentState

    /// Name of the detected agent (e.g., "Claude Code", "Aider").
    var detectedAgentName: String?

    /// Whether this session has unread notifications.
    var hasUnreadNotification: Bool

    /// Current transfer state. Normally `.stable`.
    var transferState: TransferState

    init(
        sessionID: SessionID = SessionID(),
        createdAt: Date = Date(),
        ownerWindowID: WindowID,
        tabID: TabID,
        title: String = "Terminal",
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        agentState: AgentState = .idle,
        detectedAgentName: String? = nil,
        hasUnreadNotification: Bool = false,
        transferState: TransferState = .stable
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.ownerWindowID = ownerWindowID
        self.tabID = tabID
        self.title = title
        self.workingDirectory = workingDirectory
        self.agentState = agentState
        self.detectedAgentName = detectedAgentName
        self.hasUnreadNotification = hasUnreadNotification
        self.transferState = transferState
    }
}

// MARK: - Session Change Event

/// Describes what changed in a session update.
///
/// Published by the registry's `sessionUpdated` publisher so subscribers
/// can react to specific changes without polling the entire entry.
struct SessionChangeEvent: Sendable {
    /// The session that changed.
    let sessionID: SessionID

    /// The window that owns this session.
    let windowID: WindowID

    /// The type of change that occurred.
    let change: ChangeKind

    /// Specific kinds of session changes.
    enum ChangeKind: Sendable {
        case titleChanged(old: String, new: String)
        case workingDirectoryChanged(old: URL, new: URL)
        case agentStateChanged(old: AgentState, new: AgentState)
        case notificationStateChanged(hasUnread: Bool)
        case transferStateChanged(old: TransferState, new: TransferState)
        case ownerChanged(oldWindow: WindowID, newWindow: WindowID)
    }
}

/// Describes a session removal with ownership context.
///
/// Publishing the owner window avoids forcing subscribers to fan out updates
/// to every window when only one window's aggregate actually changed.
struct SessionRemovalEvent: Sendable {
    let sessionID: SessionID
    let windowID: WindowID
}
