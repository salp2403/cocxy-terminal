// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Tab.swift - Domain model for a terminal tab.

import Foundation

// MARK: - Tab ID

/// Unique identifier for a tab.
///
/// Wraps a `UUID` for type safety -- prevents accidentally passing a
/// `SurfaceID` where a `TabID` is expected.
struct TabID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init() {
        self.rawValue = UUID()
    }

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

// MARK: - Tab Model

/// Domain model representing a terminal tab.
///
/// A tab contains one or more terminal surfaces arranged in a split tree.
/// Each tab tracks its working directory, git branch, and the state of any
/// AI agent running inside it.
///
/// Conforms to `Codable` for session persistence and `Equatable` for
/// efficient UI diffing.
struct Tab: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier.
    let id: TabID

    /// User-visible title. Auto-generated from the working directory and
    /// git branch when not manually set.
    var title: String

    /// Working directory of the primary terminal in this tab.
    var workingDirectory: URL

    /// Current git branch name, if inside a git repository.
    var gitBranch: String?

    /// Current state of the AI agent in this tab.
    var agentState: AgentState

    /// Information about the detected agent, if any.
    var detectedAgent: DetectedAgent?

    /// Whether this tab has unread notifications.
    var hasUnreadNotification: Bool

    /// Timestamp of the last activity in this tab.
    var lastActivityAt: Date

    /// Whether this tab is the currently active (focused) tab.
    var isActive: Bool

    /// Name of the foreground process running in this tab (e.g., "zsh", "claude", "node").
    var processName: String?

    /// Active SSH session info, if the foreground process is an SSH client.
    var sshSession: SSHSessionInfo?

    /// User-defined custom title. When set, overrides the auto-generated displayTitle.
    var customTitle: String?

    /// Description of the agent's current activity (e.g., "Read: main.swift").
    /// Updated by hook events. Shown in the tab sidebar for real-time visibility.
    var agentActivity: String?

    /// Whether this tab is pinned. Pinned tabs are sorted to the top and cannot be closed.
    var isPinned: Bool

    /// Timestamp when this tab was created.
    let createdAt: Date

    /// Timestamp when the last command started executing (OSC 133 ;B).
    var lastCommandStartedAt: Date?

    /// Duration of the last completed command in seconds.
    var lastCommandDuration: TimeInterval?

    /// Exit code of the last completed command (0 = success).
    var lastCommandExitCode: Int?

    /// Per-project config overrides loaded from `.cocxy.toml`.
    /// When present, these values override the global config for this tab.
    var projectConfig: ProjectConfig?

    /// Cumulative tool call count from the running agent (fed by hook events).
    var agentToolCount: Int = 0

    /// Cumulative error count from the running agent (fed by hook events).
    var agentErrorCount: Int = 0

    /// Whether a command is currently executing.
    var isCommandRunning: Bool {
        lastCommandStartedAt != nil && lastCommandDuration == nil
    }

    init(
        id: TabID = TabID(),
        title: String = "Terminal",
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        gitBranch: String? = nil,
        agentState: AgentState = .idle,
        detectedAgent: DetectedAgent? = nil,
        hasUnreadNotification: Bool = false,
        lastActivityAt: Date = Date(),
        isActive: Bool = false,
        processName: String? = nil,
        customTitle: String? = nil,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastCommandStartedAt: Date? = nil,
        lastCommandDuration: TimeInterval? = nil,
        lastCommandExitCode: Int? = nil,
        projectConfig: ProjectConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.agentState = agentState
        self.detectedAgent = detectedAgent
        self.hasUnreadNotification = hasUnreadNotification
        self.lastActivityAt = lastActivityAt
        self.isActive = isActive
        self.processName = processName
        self.customTitle = customTitle
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.lastCommandStartedAt = lastCommandStartedAt
        self.lastCommandDuration = lastCommandDuration
        self.lastCommandExitCode = lastCommandExitCode
        self.projectConfig = projectConfig
    }
}

// MARK: - Tab Display Helpers

extension Tab {
    /// The display name shown in the tab bar.
    ///
    /// Format: "directory-name (branch)" if git info is available,
    /// otherwise just "directory-name".
    var displayTitle: String {
        if let custom = customTitle, !custom.trimmingCharacters(in: .whitespaces).isEmpty {
            return custom
        }
        let directoryName = workingDirectory.lastPathComponent
        if let branch = gitBranch {
            return "\(directoryName) (\(branch))"
        }
        return directoryName
    }
}
