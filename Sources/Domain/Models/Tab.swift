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
/// A tab contains one or more terminal surfaces arranged in a split
/// tree. The tab tracks the user-facing metadata (title, working
/// directory, git branch, SSH session, pinned state, last-command
/// timing) and the process name that the foreground PTY advertises.
///
/// Per-surface agent state (agent lifecycle, detected agent metadata,
/// activity label, tool/error counters) is **not** stored on `Tab`: it
/// lives in `AgentStatePerSurfaceStore`, keyed by `SurfaceID`, and the
/// UI reads it through `SurfaceAgentStateResolver`. Keeping agent
/// state off the tab lets splits running different agents display
/// independent indicators.
///
/// Conforms to `Codable` for session persistence and `Equatable` for
/// efficient UI diffing. Legacy session JSONs that still carry the
/// old `agentState`/`detectedAgent`/`agentActivity`/`agentToolCount`/
/// `agentErrorCount` keys remain decodable — Swift's auto-synthesised
/// `Codable` implementation silently ignores unknown keys.
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

    /// Short, stable identifier of the cocxy-managed git worktree attached
    /// to this tab.
    ///
    /// Non-nil means the tab is running inside a linked worktree created
    /// by `WorktreeService`. Matches the final path component at
    /// `<base-path>/<repo-hash>/<worktreeID>/`.
    ///
    /// Kept separate from `worktreeRoot` because consumers frequently need
    /// a short identifier for lookup in the manifest without parsing the
    /// full URL.
    var worktreeID: String?

    /// Immutable anchor pointing to the worktree root on disk.
    ///
    /// `workingDirectory` may drift from this when the shell `cd`'s inside
    /// the worktree (OSC 7 and `CwdChanged` both mutate
    /// `workingDirectory`). Every consumer that needs the physical
    /// worktree path — badge, `git worktree remove`, status queries —
    /// reads `worktreeRoot`, never `workingDirectory`.
    ///
    /// Set once when the worktree is created and only cleared when the
    /// worktree is removed.
    var worktreeRoot: URL?

    /// Path to the origin repository this worktree was created from.
    ///
    /// Required for:
    ///   - `git worktree remove <path>` invoked from within the origin
    ///     repo (git requires operating from one of the repo's worktrees).
    ///   - `ProjectConfigService` fallback when `.cocxy.toml` lives in the
    ///     origin repo but not inside the worktree tree.
    ///   - UI tooltips ("worktree of <origin-repo-name>").
    ///
    /// Nil when `worktreeID` is nil.
    var worktreeOriginRepo: URL?

    /// Cached branch name of the worktree.
    ///
    /// The foreground shell may `cd` outside the worktree root
    /// temporarily, so the badge and tooltip read this cache instead of
    /// shelling out to `git branch --show-current` on each render. Kept
    /// in sync when the worktree is created and when the branch is
    /// explicitly switched via the CLI.
    var worktreeBranch: String?

    /// Whether a command is currently executing.
    var isCommandRunning: Bool {
        lastCommandStartedAt != nil && lastCommandDuration == nil
    }

    /// Marks a new command as started. Resets duration and exit code
    /// to ensure `isCommandRunning` returns true immediately.
    mutating func markCommandStarted(at date: Date = Date()) {
        lastCommandDuration = nil
        lastCommandExitCode = nil
        lastCommandStartedAt = date
    }

    /// Marks the current command as finished with the given duration and exit code.
    mutating func markCommandFinished(duration: TimeInterval, exitCode: Int?) {
        lastCommandDuration = duration
        lastCommandExitCode = exitCode
    }

    init(
        id: TabID = TabID(),
        title: String = "Terminal",
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        gitBranch: String? = nil,
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
        projectConfig: ProjectConfig? = nil,
        worktreeID: String? = nil,
        worktreeRoot: URL? = nil,
        worktreeOriginRepo: URL? = nil,
        worktreeBranch: String? = nil
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
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
        self.worktreeID = worktreeID
        self.worktreeRoot = worktreeRoot
        self.worktreeOriginRepo = worktreeOriginRepo
        self.worktreeBranch = worktreeBranch
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
