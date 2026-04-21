// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for the Aurora workspace adapter.
///
/// The adapter is the single seam between the production domain and
/// the redesigned chrome; every invariant the sidebar / status-bar
/// views depend on is pinned here so refactors on either side surface
/// regressions in isolation.
@Suite("Aurora workspace adapter")
struct AuroraWorkspaceAdapterTests {

    // MARK: - Fixture helpers

    private func surface(
        id: String = "s",
        name: String = "pane",
        agent: Design.AgentAccent = .claude,
        state: Design.AgentStateRole = .working,
        activity: String? = nil,
        toolCount: Int = 0,
        errorCount: Int = 0
    ) -> Design.AuroraSourceSurface {
        Design.AuroraSourceSurface(
            id: id,
            name: name,
            agent: agent,
            state: state,
            activity: activity,
            toolCount: toolCount,
            errorCount: errorCount
        )
    }

    private func tab(
        id: String = "t",
        name: String = "tab",
        workspaceGroup: String = "cocxy",
        branch: String? = nil,
        isPinned: Bool = false,
        surfaces: [Design.AuroraSourceSurface] = [],
        workingDirectory: String? = nil,
        foregroundProcessName: String? = nil,
        lastCommandSummary: String? = nil
    ) -> Design.AuroraSourceTab {
        Design.AuroraSourceTab(
            id: id,
            name: name,
            workspaceGroup: workspaceGroup,
            branch: branch,
            isPinned: isPinned,
            surfaces: surfaces,
            workingDirectory: workingDirectory,
            foregroundProcessName: foregroundProcessName,
            lastCommandSummary: lastCommandSummary
        )
    }

    // MARK: - Empty input

    @Test("Empty source list produces no workspaces")
    func emptyInputProducesNoWorkspaces() {
        #expect(Design.AuroraWorkspaceAdapter.workspaces(from: []).isEmpty)
    }

    // MARK: - Grouping

    @Test("Tabs sharing a workspace group collapse into a single workspace")
    func tabsShareWorkspace() {
        let sources = [
            tab(id: "a", name: "api", workspaceGroup: "cocxy", surfaces: [surface(id: "sa")]),
            tab(id: "b", name: "web", workspaceGroup: "cocxy", surfaces: [surface(id: "sb")]),
        ]
        let result = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        #expect(result.count == 1)
        #expect(result[0].id == "cocxy")
        #expect(result[0].sessions.map(\.id) == ["a", "b"])
    }

    @Test("Distinct workspace groups produce distinct workspaces in source order")
    func groupsProduceOrderedWorkspaces() {
        let sources = [
            tab(id: "a", workspaceGroup: "alpha"),
            tab(id: "b", workspaceGroup: "beta"),
            tab(id: "c", workspaceGroup: "alpha"),
        ]
        let result = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        #expect(result.map(\.id) == ["alpha", "beta"])
        #expect(result[0].sessions.map(\.id) == ["a", "c"])
        #expect(result[1].sessions.map(\.id) == ["b"])
    }

    // MARK: - Branch propagation

    @Test("First non-nil branch in a workspace wins")
    func firstBranchWins() {
        let sources = [
            tab(id: "a", workspaceGroup: "cocxy", branch: nil),
            tab(id: "b", workspaceGroup: "cocxy", branch: "feat/foo"),
            tab(id: "c", workspaceGroup: "cocxy", branch: "feat/bar"),
        ]
        let result = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        #expect(result.first?.branch == "feat/foo")
    }

    @Test("Workspace with no branches keeps the nil value")
    func noBranchesStaysNil() {
        let sources = [tab(id: "a", workspaceGroup: "lonely")]
        let result = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        #expect(result.first?.branch == nil)
    }

    // MARK: - Pane derivation

    @Test("Panes map 1:1 from source surfaces")
    func panesMapFromSurfaces() {
        let sources = [
            tab(id: "a", surfaces: [
                surface(id: "s1", name: "server", agent: .claude, state: .working),
                surface(id: "s2", name: "tests", agent: .shell, state: .finished),
            ]),
        ]
        let result = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        let panes = result[0].sessions[0].panes
        #expect(panes.map(\.id) == ["s1", "s2"])
        #expect(panes.map(\.name) == ["server", "tests"])
        #expect(panes.map(\.agent) == [.claude, .shell])
        #expect(panes.map(\.state) == [.working, .finished])
    }

    @Test("Panes preserve activity and counter metadata for tooltips")
    func panesPreserveDiagnosticMetadata() {
        let sources = [
            tab(id: "a", surfaces: [
                surface(
                    id: "s1",
                    name: "Claude Code",
                    agent: .claude,
                    state: .working,
                    activity: "Editing files",
                    toolCount: 5,
                    errorCount: 1
                ),
            ]),
        ]
        let pane = Design.AuroraWorkspaceAdapter.workspaces(from: sources)[0].sessions[0].panes[0]
        #expect(pane.activity == "Editing files")
        #expect(pane.toolCount == 5)
        #expect(pane.errorCount == 1)
    }

    @Test("Sessions preserve tab-level metadata for sidebar hover diagnostics")
    func sessionsPreserveTabMetadata() {
        let sources = [
            tab(
                id: "a",
                isPinned: true,
                surfaces: [surface()],
                workingDirectory: "/Users/user/cocxy",
                foregroundProcessName: "claude",
                lastCommandSummary: "Command: running"
            ),
        ]
        let session = Design.AuroraWorkspaceAdapter.workspaces(from: sources)[0].sessions[0]
        #expect(session.workingDirectory == "/Users/user/cocxy")
        #expect(session.foregroundProcessName == "claude")
        #expect(session.lastCommandSummary == "Command: running")
        #expect(session.isPinned == true)
    }

    @Test("A surface-less tab gets a synthetic shell pane so the sidebar never empties")
    func surfacelessTabGetsSyntheticPane() {
        let sources = [tab(id: "bootstrap", surfaces: [])]
        let result = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        let panes = result[0].sessions[0].panes
        #expect(panes.count == 1)
        #expect(panes[0].agent == .shell)
        #expect(panes[0].state == .idle)
        #expect(panes[0].id == "bootstrap-shell")
    }

    // MARK: - Session primary resolution

    @Test("Session primary uses the first non-idle surface for agent/state")
    func primaryUsesFirstActive() {
        let sources = [
            tab(id: "a", surfaces: [
                surface(id: "s1", agent: .shell, state: .idle),
                surface(id: "s2", agent: .claude, state: .working),
                surface(id: "s3", agent: .codex, state: .error),
            ]),
        ]
        let session = Design.AuroraWorkspaceAdapter.workspaces(from: sources)[0].sessions[0]
        #expect(session.agent == .claude)
        #expect(session.state == .working)
    }

    @Test("Session primary falls back to first surface when every pane is idle")
    func primaryFallsBackToFirstSurfaceWhenIdle() {
        let sources = [
            tab(id: "a", surfaces: [
                surface(id: "s1", agent: .gemini, state: .idle),
                surface(id: "s2", agent: .shell, state: .idle),
            ]),
        ]
        let session = Design.AuroraWorkspaceAdapter.workspaces(from: sources)[0].sessions[0]
        #expect(session.agent == .gemini)
        #expect(session.state == .idle)
    }

    @Test("Session primary degrades gracefully when the tab has no surfaces")
    func primaryHandlesSurfaceLessTab() {
        let sources = [tab(id: "a", surfaces: [])]
        let session = Design.AuroraWorkspaceAdapter.workspaces(from: sources)[0].sessions[0]
        #expect(session.agent == .shell)
        #expect(session.state == .idle)
    }
}
