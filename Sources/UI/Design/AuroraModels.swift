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

        /// Always-visible row metadata selected by the user. Falls back
        /// to state + pane count when the chosen signal is unavailable so
        /// every row remains useful even for fresh shells and detached
        /// sessions with no command/process yet.
        func primaryMetadataLine(selection: AuroraSidebarPrimaryInfo) -> String {
            switch selection {
            case .state:
                return stateMetadataLine
            case .directory:
                return Self.cleaned(workingDirectory).map(Self.prettyDirectory) ?? stateMetadataLine
            case .process:
                return Self.cleaned(foregroundProcessName) ?? stateMetadataLine
            case .command:
                return Self.cleaned(lastCommandSummary) ?? stateMetadataLine
            }
        }

        /// Case-insensitive search corpus for the Aurora sidebar filter.
        /// Includes the session, live context, pane labels, and workspace
        /// metadata so users can jump by project path, process, command,
        /// split-pane name, branch, or status without focusing every tab.
        func matchesSearchTokens(
            _ tokens: [String],
            workspaceName: String,
            branch: String?
        ) -> Bool {
            guard !tokens.isEmpty else { return true }
            let corpus = searchCorpus(workspaceName: workspaceName, branch: branch)
            return tokens.allSatisfy { token in
                corpus.contains { $0.contains(token) }
            }
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

        private var stateMetadataLine: String {
            "\(state.rawValue) · \(paneCountLabel)"
        }

        private func searchCorpus(workspaceName: String, branch: String?) -> [String] {
            [
                name,
                state.rawValue,
                paneCountLabel,
                workingDirectory,
                foregroundProcessName,
                lastCommandSummary,
                workspaceName,
                branch,
            ]
            .compactMap(Self.cleaned)
            .map { $0.lowercased() }
            + panes.flatMap { pane in
                [
                    pane.name,
                    pane.agent.rawValue,
                    pane.state.rawValue,
                    pane.activity,
                    pane.diagnosticLine,
                ].compactMap(Self.cleaned).map { $0.lowercased() }
            }
        }

        private static func cleaned(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else {
                return nil
            }
            return trimmed
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
        /// Raw value of the `NoteWorkspaceID` for this workspace, when
        /// resolvable. Computed by the adapter from the workspace root
        /// path so the Aurora sidebar can show a per-workspace notes
        /// section. Stays optional (`nil`) for tabs whose path is not
        /// resolvable — SSH sessions, detached tabs, fallback shells —
        /// so the sidebar simply omits the notes block instead of
        /// surfacing a non-functional affordance.
        let notesWorkspaceID: String?

        init(
            id: String,
            name: String,
            branch: String?,
            isCollapsed: Bool,
            sessions: [AuroraSession],
            notesWorkspaceID: String? = nil
        ) {
            self.id = id
            self.name = name
            self.branch = branch
            self.isCollapsed = isCollapsed
            self.sessions = sessions
            self.notesWorkspaceID = notesWorkspaceID
        }

        /// Filters the session list by case-insensitive tokens across
        /// session name, workspace metadata, directory, foreground
        /// process, last command, pane labels and pane activity. An empty
        /// query returns every session; whitespace is ignored so the
        /// field behaves like a direct jump target rather than a brittle
        /// title-only matcher.
        func filteringSessions(by query: String) -> AuroraWorkspace {
            let tokens = query
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            guard !tokens.isEmpty else { return self }
            let filtered = sessions.filter {
                $0.matchesSearchTokens(tokens, workspaceName: name, branch: branch)
            }
            return AuroraWorkspace(
                id: id,
                name: name,
                branch: branch,
                isCollapsed: isCollapsed,
                sessions: filtered,
                notesWorkspaceID: notesWorkspaceID
            )
        }
    }

    // MARK: - Notes summary models

    /// Compact representation of a single note for the Aurora sidebar
    /// notes section. Pure value type so the controller can publish it
    /// across actor boundaries without any reactive plumbing.
    ///
    /// `id` is the note's UUID rendered as a string so the sidebar can
    /// pass it back to the host as a stable identifier without leaking
    /// the `UUID` type into the design module.
    struct AuroraNoteRow: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let title: String
        let updatedAt: Date

        init(id: String, title: String, updatedAt: Date) {
            self.id = id
            self.title = title
            self.updatedAt = updatedAt
        }
    }

    /// Aggregated notes state for a single workspace.
    ///
    /// The Aurora sidebar shows the workspace's note count plus a
    /// truncated list of the most recently edited notes. This summary
    /// captures both pieces in a single value so the published map on
    /// `AuroraChromeController` remains a flat dictionary keyed by the
    /// workspace's `NoteWorkspaceID.rawValue`.
    struct AuroraWorkspaceNotesSummary: Equatable, Hashable, Sendable {
        let workspaceID: String
        let count: Int
        let recentNotes: [AuroraNoteRow]

        init(workspaceID: String, count: Int, recentNotes: [AuroraNoteRow]) {
            self.workspaceID = workspaceID
            self.count = count
            self.recentNotes = recentNotes
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
