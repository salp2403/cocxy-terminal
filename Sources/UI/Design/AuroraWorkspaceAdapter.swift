// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraWorkspaceAdapter.swift - Maps domain snapshots into the
// presentation-only `AuroraWorkspace` tree.
//
// The adapter is the seam between the production domain
// (`TabManager`, `AgentStatePerSurfaceStore`, `SplitManager`) and the
// redesigned Aurora chrome. To keep the design module free of AppKit
// or domain imports, the boundary is a pair of value types
// (`AuroraSourceTab` / `AuroraSourceSurface`) that the integration
// layer fills from whatever the app currently exposes. The adapter
// itself is a pure function with no SwiftUI, no global state, and no
// side effects — every edge case is unit-testable in isolation.

import Foundation

extension Design {

    // MARK: - Source snapshots

    /// Snapshot of a single pane / split surface inside a tab.
    ///
    /// The integration layer fills every field from the live domain so
    /// the adapter can work with pure value types:
    ///   * `id` comes from `SurfaceID.rawValue.uuidString`.
    ///   * `name` is a caller-controlled label (first command,
    ///     detected agent's name, or "pane N" as fallback).
    ///   * `agent` / `state` are resolved from
    ///     `AgentStatePerSurfaceStore` through
    ///     `SurfaceAgentStateResolver`.
    struct AuroraSourceSurface: Hashable, Sendable {
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
    }

    /// Snapshot of a single tab used as the adapter's input.
    ///
    /// `workspaceGroup` is the identifier the adapter groups tabs by.
    /// The integration layer typically populates it with the git root
    /// or the first path component under `~`, mirroring how Aurora's
    /// sidebar groups sessions in the reference design. When the caller
    /// cannot resolve a group (SSH session, detached tab), passing the
    /// tab's own identifier keeps that tab in its own one-session
    /// workspace instead of dropping it.
    struct AuroraSourceTab: Hashable, Sendable {
        let id: String
        let name: String
        let workspaceGroup: String
        let branch: String?
        let isPinned: Bool
        let surfaces: [AuroraSourceSurface]
        let workingDirectory: String?
        let foregroundProcessName: String?
        let lastCommandSummary: String?

        init(
            id: String,
            name: String,
            workspaceGroup: String,
            branch: String? = nil,
            isPinned: Bool = false,
            surfaces: [AuroraSourceSurface],
            workingDirectory: String? = nil,
            foregroundProcessName: String? = nil,
            lastCommandSummary: String? = nil
        ) {
            self.id = id
            self.name = name
            self.workspaceGroup = workspaceGroup
            self.branch = branch
            self.isPinned = isPinned
            self.surfaces = surfaces
            self.workingDirectory = workingDirectory
            self.foregroundProcessName = foregroundProcessName
            self.lastCommandSummary = lastCommandSummary
        }
    }

    // MARK: - Adapter

    /// Pure adapter that groups source tabs into Aurora workspaces.
    ///
    /// ## Invariants pinned by the tests
    ///
    /// 1. Empty input produces an empty workspace list — callers can
    ///    feed a fresh app startup without branching.
    /// 2. Tabs keep their insertion order inside each workspace so
    ///    sidebars render stably across refreshes.
    /// 3. `workspaceGroup` values are compared verbatim; two tabs with
    ///    the same value end up in the same workspace regardless of
    ///    case. This mirrors how the live chrome groups paths.
    /// 4. The first tab's `branch` wins when several tabs in the same
    ///    workspace carry different values — matches "primary branch"
    ///    semantics in the reference prototype.
    /// 5. A tab without surfaces degrades to a single synthetic pane
    ///    named "shell" so the sidebar still has something to render
    ///    (prevents the first tab from disappearing during bootstrap).
    /// 6. A tab's primary agent / state is sourced from its **first**
    ///    non-idle surface, falling back to the first surface overall
    ///    when every pane is idle. Keeps the pill in sync with whatever
    ///    live pane dominates the user's attention.
    enum AuroraWorkspaceAdapter {

        static func workspaces(from sources: [AuroraSourceTab]) -> [AuroraWorkspace] {
            guard !sources.isEmpty else { return [] }

            // Preserve insertion order across groups by tracking the
            // order in which each workspaceGroup was first seen.
            var order: [String] = []
            var grouped: [String: [AuroraSourceTab]] = [:]

            for tab in sources {
                if grouped[tab.workspaceGroup] == nil {
                    order.append(tab.workspaceGroup)
                }
                grouped[tab.workspaceGroup, default: []].append(tab)
            }

            return order.map { group -> AuroraWorkspace in
                let tabs = grouped[group] ?? []
                let branch = tabs.lazy.compactMap(\.branch).first
                let sessions = tabs.map(session(from:))
                return AuroraWorkspace(
                    id: group,
                    name: group,
                    branch: branch,
                    isCollapsed: false,
                    sessions: sessions
                )
            }
        }

        /// Builds a session from a source tab, deriving the primary
        /// agent / state from the most-active surface so the sidebar
        /// header reflects live activity.
        private static func session(from tab: AuroraSourceTab) -> AuroraSession {
            let panes = panes(for: tab)
            let primary = primarySurface(in: panes)
            return AuroraSession(
                id: tab.id,
                name: tab.name,
                agent: primary.agent,
                state: primary.state,
                isPinned: tab.isPinned,
                panes: panes,
                workingDirectory: tab.workingDirectory,
                foregroundProcessName: tab.foregroundProcessName,
                lastCommandSummary: tab.lastCommandSummary
            )
        }

        /// Returns the Aurora panes for the tab's surfaces. When the
        /// source carries no surfaces we synthesize a single "shell"
        /// pane so the sidebar row stays well-formed during bootstrap
        /// or any transient teardown / restore cycle.
        private static func panes(for tab: AuroraSourceTab) -> [AuroraPane] {
            if tab.surfaces.isEmpty {
                return [
                AuroraPane(
                    id: tab.id + "-shell",
                    name: "shell",
                    agent: .shell,
                    state: .idle
                ),
            ]
        }
        return tab.surfaces.map { surface in
            AuroraPane(
                id: surface.id,
                name: surface.name,
                agent: surface.agent,
                state: surface.state,
                activity: surface.activity,
                toolCount: surface.toolCount,
                errorCount: surface.errorCount
            )
        }
        }

        /// Picks the surface that should drive the session's primary
        /// indicator (agent + state). Prefers non-idle panes; falls
        /// back to the first pane overall when every surface is idle.
        /// Keeps a deterministic answer for all-empty or all-idle
        /// inputs so snapshots stay stable between renders.
        private static func primarySurface(in panes: [AuroraPane]) -> AuroraPane {
            if let active = panes.first(where: { $0.state != .idle }) {
                return active
            }
            // `panes(for:)` always returns at least one pane, so this
            // unwrap is safe — the cascade (active → first → shell)
            // covers every legitimate input.
            return panes.first ?? AuroraPane(
                id: "fallback",
                name: "shell",
                agent: .shell,
                state: .idle
            )
        }
    }
}
