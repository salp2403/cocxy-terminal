// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraSourceBuilder.swift - Pure bridge between the live domain and the
// Aurora presentation module.
//
// The builder takes domain snapshots (TabManager.tabs, a surface-IDs-per-tab
// map and the per-surface agent-state store) and emits
// `[Design.AuroraSourceTab]`, the input contract of
// `Design.AuroraWorkspaceAdapter.workspaces(from:)`. It contains no AppKit,
// no SwiftUI and no global state; every input is a value type or a small
// closure so the builder is trivially unit-testable in isolation.
//
// Lives in `Domain/Aurora/` because the inputs come from domain types,
// while the output types belong to the UI/Design module. Both sides are
// part of the main `CocxyTerminal` target, so the import graph stays
// clean without adding package products.

import Foundation

// MARK: - Workspace Root Resolver

/// Resolves the workspace root URL a tab belongs to, so that sibling tabs
/// editing different subdirectories of the same project land in the same
/// Aurora workspace.
///
/// Implementations are expected to be fast and side-effect free — Aurora
/// rebuilds the source list on every domain change (tab add/close/switch,
/// agent state transition, split spawn/close). The default implementation
/// walks the ancestor chain of the tab's working directory looking for a
/// `.git` entry, stopping at the user's home directory or after a small
/// depth budget.
protocol AuroraWorkspaceRootResolver: Sendable {

    /// Returns the root URL of the workspace containing `directory`, or
    /// `nil` when no resolvable root exists (detached tab, SSH session,
    /// ephemeral `/tmp` path). Callers fall back to the tab's own
    /// directory when the result is `nil`.
    func workspaceRoot(for directory: URL) -> URL?
}

/// Production resolver that treats the nearest ancestor containing a `.git`
/// directory as the workspace root. Capped at 12 levels of ascent to keep
/// worst-case behavior bounded when the tab lives deep inside a giant
/// monorepo. Stops at the user's home directory so a stray `~/.git` doesn't
/// collapse every local tab into a single pseudo-workspace.
struct GitAncestorWorkspaceRootResolver: AuroraWorkspaceRootResolver {

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let maxDepth: Int

    init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        maxDepth: Int = 12
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.maxDepth = maxDepth
    }

    func workspaceRoot(for directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        let home = homeDirectory

        for _ in 0..<maxDepth {
            let dotGit = current.appendingPathComponent(".git", isDirectory: true)
            if fileManager.fileExists(atPath: dotGit.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current { return nil } // hit filesystem root
            if current == home { return nil }   // stop at $HOME boundary
            current = parent
        }
        return nil
    }
}

// MARK: - Aurora Source Builder

/// Pure mapper from domain snapshots to `Design.AuroraSourceTab` values.
///
/// The builder never mutates its inputs. It exists as a namespace so the
/// integration layer can call it once per refresh, pass the resulting
/// `[Design.AuroraSourceTab]` to `Design.AuroraWorkspaceAdapter.workspaces(from:)`,
/// and hand the workspace tree to `AuroraSidebarView` /
/// `AuroraStatusBarView` as `@Binding` inputs.
///
/// ## Invariants (pinned by the test suite)
///
/// 1. Empty `tabs` produces an empty array — the integration layer can
///    call the builder during bootstrap without branching.
/// 2. Tab order is preserved exactly. Adapter grouping happens downstream.
/// 3. Each tab carries the surfaces that `surfaceIDsByTab[tab.id]` lists,
///    in the caller's order. Missing keys translate to zero surfaces so
///    the adapter's "synthetic shell pane" safety net kicks in.
/// 4. `workspaceGroup` is the workspace-root's last path component when
///    the resolver finds one; otherwise the tab's own working-directory
///    last component; otherwise the tab ID's UUID string as last-resort
///    fallback so two tabs without any resolvable path still stay in
///    separate workspaces.
/// 5. `branch` is copied verbatim from `tab.gitBranch`.
/// 6. Surface name is `detectedAgent.name` when an agent is attached,
///    else `"pane N"` using 1-based indexing for user friendliness.
/// 7. Agent / state mapping is a total function — every legitimate
///    domain value maps deterministically, so snapshots stay stable
///    between renders.
@MainActor
enum AuroraSourceBuilder {

    /// Builds the flat `[Design.AuroraSourceTab]` list the adapter groups
    /// into Aurora workspaces. See the invariants above for the exact
    /// contract each field honours.
    ///
    /// - Parameters:
    ///   - tabs: Tab snapshots straight from `TabManager.tabs`. Order is
    ///     preserved end-to-end.
    ///   - surfaceIDsByTab: Map from `TabID` to the surface IDs the tab
    ///     owns (primary + live splits + restored splits), in the UI
    ///     ordering the integration layer wants to show in the sidebar.
    ///   - store: Per-surface agent-state store consulted to resolve the
    ///     agent accent and state role of each pane.
    ///   - workspaceRootResolver: Injectable resolver (defaults to
    ///     ancestor-walk looking for `.git`). Tests pass a stub.
    /// - Returns: One `AuroraSourceTab` per input tab, in order.
    static func buildSources(
        tabs: [Tab],
        surfaceIDsByTab: [TabID: [SurfaceID]],
        store: AgentStatePerSurfaceStore,
        workspaceRootResolver: AuroraWorkspaceRootResolver = GitAncestorWorkspaceRootResolver()
    ) -> [Design.AuroraSourceTab] {
        tabs.map { tab in
            let surfaceIDs = surfaceIDsByTab[tab.id] ?? []
            let surfaces = surfaceIDs.enumerated().map { index, surfaceID -> Design.AuroraSourceSurface in
                let state = store.state(for: surfaceID)
                return Design.AuroraSourceSurface(
                    id: surfaceID.rawValue.uuidString,
                    name: surfaceName(index: index, state: state),
                    agent: accent(for: state.detectedAgent),
                    state: role(for: state.agentState)
                )
            }
            return Design.AuroraSourceTab(
                id: tab.id.rawValue.uuidString,
                name: tab.displayTitle,
                workspaceGroup: workspaceGroup(for: tab, resolver: workspaceRootResolver),
                branch: tab.gitBranch,
                surfaces: surfaces
            )
        }
    }

    // MARK: - Pure helpers

    /// Maps the domain-side `AgentState` lifecycle to the Aurora design
    /// module's `AgentStateRole`. Total function — every case is handled.
    static func role(for agentState: AgentState) -> Design.AgentStateRole {
        switch agentState {
        case .idle: return .idle
        case .launched: return .launched
        case .working: return .working
        case .waitingInput: return .waiting
        case .finished: return .finished
        case .error: return .error
        }
    }

    /// Maps a `DetectedAgent?` to the Aurora design module's `AgentAccent`.
    ///
    /// The match is case-insensitive and uses containment so command-line
    /// variants ("claude-code", "codex-cli", "gemini-cli", "aider-chat")
    /// collapse onto the corresponding accent. Everything else — including
    /// `nil`, an empty name, or an unrecognised agent — falls back to
    /// `.shell`, matching the adapter's synthetic-pane behaviour.
    static func accent(for detectedAgent: DetectedAgent?) -> Design.AgentAccent {
        guard let raw = detectedAgent?.name, !raw.isEmpty else { return .shell }
        let lowered = raw.lowercased()
        if lowered.contains("claude") { return .claude }
        if lowered.contains("codex")  { return .codex }
        if lowered.contains("gemini") { return .gemini }
        if lowered.contains("aider")  { return .aider }
        return .shell
    }

    /// Resolves the `workspaceGroup` string tabs with the same project
    /// share. Priority chain:
    /// 1. Workspace root (last path component) if the resolver finds one.
    /// 2. Tab's own `workingDirectory.lastPathComponent`.
    /// 3. `"home"` for the user's home directory where `lastPathComponent`
    ///    may be empty on some filesystems.
    /// 4. Tab ID UUID string as last resort so two tabs without any
    ///    resolvable path still end up in separate workspaces.
    static func workspaceGroup(
        for tab: Tab,
        resolver: AuroraWorkspaceRootResolver
    ) -> String {
        if let root = resolver.workspaceRoot(for: tab.workingDirectory) {
            let name = root.lastPathComponent
            if !name.isEmpty { return name }
        }
        let folder = tab.workingDirectory.lastPathComponent
        if !folder.isEmpty { return folder }
        if tab.workingDirectory.path == FileManager.default.homeDirectoryForCurrentUser.path {
            return "home"
        }
        return tab.id.rawValue.uuidString
    }

    /// Friendly per-pane label shown in the Aurora sidebar row.
    /// Falls back to a 1-based "pane N" when no agent is attached so the
    /// user sees a stable ordering across renders.
    static func surfaceName(index: Int, state: SurfaceAgentState) -> String {
        if let name = state.detectedAgent?.name, !name.isEmpty {
            return name
        }
        return "pane \(index + 1)"
    }
}
