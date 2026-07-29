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
///
/// Reads `FileManager.default.fileExists(atPath:)` each call — a thread-safe
/// singleton operation — so the resolver stays `Sendable` without needing
/// to store a `FileManager` reference (which is not `Sendable` itself).
struct GitAncestorWorkspaceRootResolver: AuroraWorkspaceRootResolver {

    private let homeDirectory: URL
    private let maxDepth: Int

    init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        maxDepth: Int = 12
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.maxDepth = maxDepth
    }

    func workspaceRoot(for directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        let home = homeDirectory

        for _ in 0..<maxDepth {
            // The home boundary must be evaluated BEFORE the `.git`
            // probe. Otherwise a user whose `$HOME` itself contains a
            // `.git` directory (a common layout for dotfiles repos) would
            // end up with every local tab collapsed into one synthetic
            // "home" workspace — contradicting the doc-comment above.
            if current == home { return nil }
            let dotGit = current.appendingPathComponent(".git", isDirectory: true)
            if FileManager.default.fileExists(atPath: dotGit.path) {
                return current
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current { return nil } // hit filesystem root
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
/// 4. `workspaceGroup` is a non-colliding identity derived from the full,
///    standardized workspace-root path. The automatic visible name remains
///    the root's last path component.
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
    ///   - stateSnapshot: Optional just-emitted store snapshot. Combine's
    ///     `@Published` emits during `willSet`, so callers reacting to
    ///     `store.$states` must pass the emitted dictionary here instead of
    ///     reading `store.state(for:)`, which would still return the old
    ///     state inside that callback.
    ///   - workspaceRootResolver: Injectable resolver (defaults to
    ///     ancestor-walk looking for `.git`). Tests pass a stub.
    ///   - workspaceTitlesByIdentity: Optional persisted title map. An
    ///     empty value is an explicit reset to the automatic folder name.
    /// - Returns: One `AuroraSourceTab` per input tab, in order.
    static func buildSources(
        tabs: [Tab],
        surfaceIDsByTab: [TabID: [SurfaceID]],
        store: AgentStatePerSurfaceStore,
        stateSnapshot: [SurfaceID: SurfaceAgentState]? = nil,
        workspaceRootResolver: AuroraWorkspaceRootResolver = GitAncestorWorkspaceRootResolver(),
        workspaceTitlesByIdentity: [String: String]? = nil,
        worktreeBadgeVisibleProvider: (Tab) -> Bool = { _ in true }
    ) -> [Design.AuroraSourceTab] {
        tabs.map { tab in
            let surfaceIDs = surfaceIDsByTab[tab.id] ?? []
            let surfaces = surfaceIDs.enumerated().map { index, surfaceID -> Design.AuroraSourceSurface in
                let state = stateSnapshot?[surfaceID] ?? store.state(for: surfaceID)
                return Design.AuroraSourceSurface(
                    id: surfaceID.rawValue.uuidString,
                    name: surfaceName(index: index, state: state),
                    agent: accent(for: state.detectedAgent),
                    state: role(for: state.agentState),
                    activity: state.agentActivity,
                    toolCount: state.agentToolCount,
                    errorCount: state.agentErrorCount
                )
            }
            // Apply the config gate at source-build time so the adapter
            // can stay pure and the view layer does not read config.
            let hasWorktree = tab.worktreeID != nil && worktreeBadgeVisibleProvider(tab)
            let workspace = AuroraWorkspacePlanner.descriptor(
                for: tab,
                resolver: workspaceRootResolver
            )
            let workspaceTitle: String?
            if let storedValue = workspaceTitlesByIdentity?[workspace.identity] {
                workspaceTitle = AuroraWorkspacePlanner.normalizedTitle(storedValue)
            } else {
                workspaceTitle = AuroraWorkspacePlanner.normalizedTitle(tab.workspaceCustomTitle)
            }
            // Workspace root path used by the Aurora notes section so
            // the sidebar can compute the same `NoteWorkspaceID` the
            // Notes store uses on disk. Falls back to the tab's own
            // working directory when no git ancestor exists, matching
            // `DefaultNoteWorkspaceResolver`'s contract.
            return Design.AuroraSourceTab(
                id: tab.id.rawValue.uuidString,
                name: tab.displayTitle,
                workspaceGroup: workspace.identity,
                workspaceTitle: workspaceTitle,
                workspaceDefaultName: workspace.automaticName,
                branch: tab.gitBranch,
                isPinned: tab.isPinned,
                surfaces: surfaces,
                workingDirectory: tab.workingDirectory.path,
                foregroundProcessName: tab.processName,
                lastCommandSummary: commandSummary(for: tab),
                hasWorktree: hasWorktree,
                workspaceRootPath: workspace.rootPath
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

    /// Resolves the stable, full-path identity tabs in the same project
    /// share. Kept as a compatibility helper for integration callers.
    static func workspaceGroup(
        for tab: Tab,
        resolver: AuroraWorkspaceRootResolver
    ) -> String {
        AuroraWorkspacePlanner.descriptor(for: tab, resolver: resolver).identity
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

    /// Human-readable command status shown in Aurora's session tooltip.
    /// Kept pure so the sidebar can explain tab-level command activity
    /// without reaching back into `Tab` from the SwiftUI view layer.
    static func commandSummary(for tab: Tab) -> String? {
        if tab.isCommandRunning {
            return "Command: running"
        }
        guard let duration = tab.lastCommandDuration else { return nil }

        var parts = ["Command: last finished in \(formatDuration(duration))"]
        if let exitCode = tab.lastCommandExitCode {
            parts.append("exit \(exitCode)")
        }
        return parts.joined(separator: " · ")
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1000).rounded()))ms"
        }
        if duration < 10 {
            return String(format: "%.1fs", duration)
        }
        return "\(Int(duration.rounded()))s"
    }
}
