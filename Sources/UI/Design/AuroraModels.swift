// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraModels.swift - Minimal mock models for the Aurora chrome views.
//
// These structs mirror the state shapes in the design-reference
// prototype (`src/data.jsx` — `INITIAL_WORKSPACES`, `SESSION_LOGS`).
// They are used by `AuroraSidebarView` and `AuroraStatusBarView` so the
// redesigned chrome can render from either previews/tests or the live
// adapter layer. Production mapping from `TabManager` +
// `AgentStatePerSurfaceStore` happens in `AuroraSourceBuilder` and
// `AuroraWorkspaceAdapter`, keeping these models zero-dependency on
// AppKit and decoupled from the current domain objects.

import Foundation

extension Design {

    /// A single pane inside a session. In production this maps to a
    /// `SurfaceID` and its per-surface agent state, but the view only
    /// needs the display data.
    struct AuroraPane: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let name: String
        let agent: AgentAccent
        let state: AgentStateRole
        let activity: String?
        let toolCount: Int
        let errorCount: Int

        init(
            id: String,
            name: String,
            agent: AgentAccent,
            state: AgentStateRole,
            activity: String? = nil,
            toolCount: Int = 0,
            errorCount: Int = 0
        ) {
            self.id = id
            self.name = name
            self.agent = agent
            self.state = state
            self.activity = activity
            self.toolCount = toolCount
            self.errorCount = errorCount
        }

        /// Computed hint used by the mini-matrix. Surfaces in the
        /// `.finished` state stay visible because the panel groups
        /// them alongside live agents — we still need to show the
        /// user what just completed.
        var contributesToMatrix: Bool {
            switch state {
            case .idle: return false
            case .launched, .working, .waiting, .finished, .error: return true
            }
        }

        /// Compact but information-rich line used by Aurora tooltips.
        /// It intentionally mirrors live per-surface state instead of
        /// tab-level fallbacks so split panes running different agents
        /// remain independently inspectable.
        var diagnosticLine: String {
            var parts = ["\(name) — \(state.rawValue)"]
            if let activity = activity?.trimmingCharacters(in: .whitespacesAndNewlines),
               !activity.isEmpty {
                parts.append(activity)
            }
            if toolCount > 0 || errorCount > 0 {
                parts.append("tools \(toolCount)")
                parts.append("errors \(errorCount)")
            }
            return "• " + parts.joined(separator: " · ")
        }
    }

    /// A session groups one or more panes working on the same task.
    /// In the current product this maps to a tab's primary surface +
    /// its split children.
    struct AuroraSession: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let name: String
        let agent: AgentAccent
        let state: AgentStateRole
        let isPinned: Bool
        let panes: [AuroraPane]
        let workingDirectory: String?
        let foregroundProcessName: String?
        let lastCommandSummary: String?
        /// Whether the underlying tab is attached to a cocxy-managed git
        /// worktree. Drives the sidebar worktree badge in
        /// `AuroraSidebarView`; wired from
        /// the tab's effective `config.worktree.showBadge` gating the
        /// source tab input.
        let hasWorktree: Bool

        init(
            id: String,
            name: String,
            agent: AgentAccent,
            state: AgentStateRole,
            isPinned: Bool = false,
            panes: [AuroraPane],
            workingDirectory: String? = nil,
            foregroundProcessName: String? = nil,
            lastCommandSummary: String? = nil,
            hasWorktree: Bool = false
        ) {
            self.id = id
            self.name = name
            self.agent = agent
            self.state = state
            self.isPinned = isPinned
            self.panes = panes
            self.workingDirectory = workingDirectory
            self.foregroundProcessName = foregroundProcessName
            self.lastCommandSummary = lastCommandSummary
            self.hasWorktree = hasWorktree
        }

        /// Human-readable pane count used by the sidebar metadata
        /// line ("3 panes").
        var paneCountLabel: String {
            panes.count == 1 ? "1 pane" : "\(panes.count) panes"
        }

        /// Panes that should populate the sidebar mini-matrix. Idle
        /// panes are excluded per `AuroraPane.contributesToMatrix` so
        /// the sidebar only surfaces live / just-finished activity and
        /// stays aligned with the model contract the tests pin.
        var matrixPanes: [AuroraPane] {
            panes.filter(\.contributesToMatrix)
        }

        /// Number of panes with visible recent or active agent work.
        var activePaneCount: Int {
            matrixPanes.count
        }

        /// Total tool calls reported by every pane in the session.
        var totalToolCount: Int {
            panes.reduce(0) { $0 + $1.toolCount }
        }

        /// Total agent errors reported by every pane in the session.
        var totalErrorCount: Int {
            panes.reduce(0) { $0 + $1.errorCount }
        }

        /// Multiline tooltip for hovering a sidebar session. This is the
        /// fast "what is happening in this tab?" surface: workspace,
        /// foreground process, command state, and every live split pane
        /// without requiring the user to focus the tab first.
        func diagnosticTooltip(workspaceName: String, branch: String?) -> String {
            var lines: [String] = [name]

            var workspace = "Workspace: \(workspaceName)"
            if let branch, !branch.isEmpty {
                workspace += " · \(branch)"
            }
            lines.append(workspace)
            lines.append("State: \(state.rawValue) · \(paneCountLabel)")

            if let foregroundProcessName = foregroundProcessName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !foregroundProcessName.isEmpty {
                lines.append("Foreground process: \(foregroundProcessName)")
            }

            if let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
               !workingDirectory.isEmpty {
                lines.append("Directory: \(Self.prettyDirectory(workingDirectory))")
            }

            if let lastCommandSummary = lastCommandSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !lastCommandSummary.isEmpty {
                lines.append(lastCommandSummary)
            }

            let livePanes = matrixPanes
            if livePanes.isEmpty {
                lines.append("Panes: all idle")
            } else {
                lines.append("Live panes:")
                lines.append(contentsOf: livePanes.map(\.diagnosticLine))
            }

            lines.append("Click to focus. Use the × button to close this tab.")
            return lines.joined(separator: "\n")
        }

        private static func prettyDirectory(_ path: String) -> String {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            if path == home { return "~" }
            if path.hasPrefix(home + "/") {
                return "~" + path.dropFirst(home.count)
            }
            return path
        }
    }

    /// Hover payload emitted by the Aurora sidebar and rendered by the
    /// window-level tooltip overlay. Keeping the row frame in sidebar
    /// coordinates lets the AppKit integration place the tooltip outside
    /// the sidebar without making the design view know about windows.
    struct AuroraSidebarTooltipSnapshot: Equatable {
        let session: AuroraSession
        let workspaceName: String
        let workspaceBranch: String?
        let rowFrame: CGRect
    }

    /// A workspace is the top-level node in the sidebar tree. It
    /// usually maps to a working directory that contains one or more
    /// related sessions (for example `~/code/cocxy` with an API
    /// refactor session and a web landing session running in
    /// parallel).
    struct AuroraWorkspace: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let name: String
        let branch: String?
        var isCollapsed: Bool
        let sessions: [AuroraSession]

        /// Filters the session list by a case-insensitive substring
        /// against the session name. An empty query returns every
        /// session; this mirrors the CSS prototype's filter box.
        func filteringSessions(by query: String) -> AuroraWorkspace {
            guard !query.isEmpty else { return self }
            let needle = query.lowercased()
            let filtered = sessions.filter { $0.name.lowercased().contains(needle) }
            return AuroraWorkspace(
                id: id,
                name: name,
                branch: branch,
                isCollapsed: isCollapsed,
                sessions: filtered
            )
        }
    }

    /// Presentation-only disclosure overrides for the Aurora sidebar.
    ///
    /// Live workspace snapshots are rebuilt as tabs, branches, panes, and
    /// agent states change. Keeping the user's expanded/collapsed choice in
    /// this small view-state helper prevents those refreshes from reopening a
    /// workspace immediately after the user closes it.
    struct AuroraWorkspaceDisclosureOverrides: Equatable, Sendable {
        private var collapsedByWorkspaceID: [String: Bool]

        init(collapsedByWorkspaceID: [String: Bool] = [:]) {
            self.collapsedByWorkspaceID = collapsedByWorkspaceID
        }

        func isCollapsed(_ workspace: AuroraWorkspace) -> Bool {
            collapsedByWorkspaceID[workspace.id] ?? workspace.isCollapsed
        }

        mutating func toggle(_ workspace: AuroraWorkspace) {
            collapsedByWorkspaceID[workspace.id] = !isCollapsed(workspace)
        }

        mutating func prune(validWorkspaceIDs: [String]) {
            let validIDs = Set(validWorkspaceIDs)
            collapsedByWorkspaceID = collapsedByWorkspaceID.filter { validIDs.contains($0.key) }
        }
    }
}

// MARK: - Status bar models

extension Design {

    /// Lightweight representation of a bound local port surfaced in
    /// the Aurora status bar. Matches the `ports` array in the design
    /// reference (`statusbar.jsx`).
    struct AuroraPortBinding: Identifiable, Equatable, Hashable, Sendable {
        enum Health: String, Sendable {
            case ok
            case idle
            case error
        }

        let id: Int
        let name: String
        let health: Health

        /// Port number used as the identity — two bindings to the same
        /// port would be nonsensical in the matrix.
        init(port: Int, name: String, health: Health) {
            self.id = port
            self.name = name
            self.health = health
        }

        /// Convenience accessor for the view layer, kept as a
        /// dedicated property so a future change to the identity
        /// (for example adding a PID dimension) does not force every
        /// adopter to follow the rename.
        var port: Int { id }

        /// Localhost URL used by the status-bar popover for Copy/Open.
        var localhostURLString: String { "http://localhost:\(port)" }

        /// State role used for the dot colour. `.ok` maps to
        /// `finished` (green), `.idle` to `idle`, `.error` to `error`.
        var stateRole: AgentStateRole {
            switch health {
            case .ok: return .finished
            case .idle: return .idle
            case .error: return .error
            }
        }
    }

    /// Timeline scrubber position + metadata.
    struct AuroraTimelineState: Equatable, Sendable {
        /// Playhead in the [0, 1] range where 1 means "live / now"
        /// and 0 means "60 seconds ago" (matching the CSS prototype).
        let progress: Double
        /// Window length in seconds. Default 60 matches the reference
        /// `Replay last 60s` command.
        let windowSeconds: Double

        init(progress: Double, windowSeconds: Double = 60) {
            self.progress = max(0, min(1, progress))
            self.windowSeconds = max(1, windowSeconds)
        }

        /// Formatted "Xs ago" label used under the scrubber. Rounds
        /// to the nearest integer second so the label never flickers
        /// between 13 and 14 within the same frame.
        var agoLabel: String {
            let seconds = Int((1.0 - progress) * windowSeconds)
            return "\(seconds)s ago"
        }
    }
}

// MARK: - Shipping sample data

extension Design {

    /// Canonical sample workspaces used by previews, the demo
    /// inspector, and the unit tests. Mirrors the `INITIAL_WORKSPACES`
    /// catalogue in the HTML reference so the Swift views render the
    /// same snapshot at parity with the prototype.
    static let sampleWorkspaces: [AuroraWorkspace] = [
        AuroraWorkspace(
            id: "ws-cocxy",
            name: "cocxy",
            branch: "main",
            isCollapsed: false,
            sessions: [
                AuroraSession(
                    id: "s-api",
                    name: "api refactor",
                    agent: .claude,
                    state: .working,
                    panes: [
                        AuroraPane(id: "p-server", name: "server", agent: .claude, state: .working),
                        AuroraPane(id: "p-tests", name: "tests", agent: .shell, state: .finished),
                    ]
                ),
                AuroraSession(
                    id: "s-web",
                    name: "web · landing",
                    agent: .codex,
                    state: .waiting,
                    panes: [
                        AuroraPane(id: "p-dev", name: "dev", agent: .codex, state: .waiting),
                    ]
                ),
            ]
        ),
        AuroraWorkspace(
            id: "ws-research",
            name: "terminal-research",
            branch: "2026-04",
            isCollapsed: false,
            sessions: [
                AuroraSession(
                    id: "s-competitors",
                    name: "competitor audit",
                    agent: .gemini,
                    state: .finished,
                    panes: [
                        AuroraPane(id: "p-audit", name: "audit.md", agent: .gemini, state: .finished),
                    ]
                ),
            ]
        ),
        AuroraWorkspace(
            id: "ws-dotfiles",
            name: "dotfiles",
            branch: "main",
            isCollapsed: true,
            sessions: [
                AuroraSession(
                    id: "s-nvim",
                    name: "nvim",
                    agent: .shell,
                    state: .idle,
                    panes: [
                        AuroraPane(id: "p-nvim", name: "nvim", agent: .shell, state: .idle),
                    ]
                ),
            ]
        ),
    ]

    /// Canonical sample ports used by the Aurora status bar preview +
    /// tests. Matches the reference ports block (3000 / 4001 / 9000).
    static let samplePortBindings: [AuroraPortBinding] = [
        AuroraPortBinding(port: 3000, name: "web", health: .ok),
        AuroraPortBinding(port: 4001, name: "api", health: .ok),
        AuroraPortBinding(port: 9000, name: "db", health: .idle),
    ]
}
