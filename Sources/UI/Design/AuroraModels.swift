// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraModels.swift - Minimal mock models for the Aurora chrome views.
//
// These structs mirror the state shapes in the design-reference
// prototype (`src/data.jsx` — `INITIAL_WORKSPACES`, `SESSION_LOGS`).
// They are used by the standalone `AuroraSidebarView` and
// `AuroraStatusBarView` so the redesigned chrome can render in
// isolation (previews, tests, the eventual demo inspector) without
// touching the production `TabManager` / `SplitManager` / per-surface
// store.
//
// The integration work that follows this commit will add adapters
// that map the real `TabManager` + `AgentStatePerSurfaceStore` state
// into these structs, but that plumbing lives in a dedicated commit
// so this file can stay zero-dependency on AppKit and zero-coupled
// to the current domain.

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
    }

    /// A session groups one or more panes working on the same task.
    /// In the current product this maps to a tab's primary surface +
    /// its split children.
    struct AuroraSession: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let name: String
        let agent: AgentAccent
        let state: AgentStateRole
        let panes: [AuroraPane]

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

        /// Returns a new workspace with `isCollapsed` toggled. Pure
        /// helper used by the view to keep mutation testable without
        /// booting SwiftUI state.
        func togglingCollapsed() -> AuroraWorkspace {
            var copy = self
            copy.isCollapsed.toggle()
            return copy
        }

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
