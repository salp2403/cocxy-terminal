// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraModelsSwiftTestingTests.swift - Pure coverage for the Aurora
// sidebar + status-bar data model.
//
// Every helper that mutates or derives something from
// `AuroraWorkspace` / `AuroraSession` / `AuroraPane` /
// `AuroraTimelineState` / `AuroraPortBinding` is exposed as a pure
// value so tests can diff structs directly. These suites pin those
// contracts plus the shipping sample catalogue.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Aurora workspace model helpers")
struct AuroraWorkspaceModelTests {

    // MARK: - Pane count label

    @Test("paneCountLabel uses singular copy when the session holds a single pane")
    func paneCountLabelSingular() {
        let session = Design.AuroraSession(
            id: "s",
            name: "one",
            agent: .claude,
            state: .idle,
            panes: [
                Design.AuroraPane(id: "p", name: "solo", agent: .claude, state: .idle),
            ]
        )
        #expect(session.paneCountLabel == "1 pane")
    }

    @Test("paneCountLabel uses plural copy for multi-pane sessions")
    func paneCountLabelPlural() {
        let session = Design.AuroraSession(
            id: "s",
            name: "many",
            agent: .claude,
            state: .working,
            panes: (0..<3).map { idx in
                Design.AuroraPane(id: "p\(idx)", name: "n\(idx)", agent: .claude, state: .working)
            }
        )
        #expect(session.paneCountLabel == "3 panes")
    }

    // MARK: - Collapsed state

    @Test("togglingCollapsed flips the boolean and leaves the rest of the workspace intact")
    func togglingCollapsedPreservesFields() {
        let workspace = Design.sampleWorkspaces[0]
        let toggled = workspace.togglingCollapsed()
        #expect(toggled.isCollapsed != workspace.isCollapsed)
        #expect(toggled.id == workspace.id)
        #expect(toggled.sessions == workspace.sessions)
    }

    // MARK: - Filter

    @Test("filteringSessions passes through when the query is empty")
    func filterEmptyQueryReturnsSelf() {
        let workspace = Design.sampleWorkspaces[0]
        #expect(workspace.filteringSessions(by: "") == workspace)
    }

    @Test("filteringSessions matches case-insensitive substrings against session names")
    func filterMatchesCaseInsensitively() {
        let workspace = Design.sampleWorkspaces[0]
        let filtered = workspace.filteringSessions(by: "API")
        #expect(filtered.sessions.count == 1)
        #expect(filtered.sessions.first?.id == "s-api")
    }

    @Test("filteringSessions returns an empty session list when nothing matches")
    func filterNoMatchEmpties() {
        let workspace = Design.sampleWorkspaces[0]
        let filtered = workspace.filteringSessions(by: "nothing-here")
        #expect(filtered.sessions.isEmpty)
    }

    // MARK: - Pane matrix contribution

    @Test("Only non-idle panes contribute to the sidebar mini-matrix")
    func matrixContributionRespectsState() {
        let idle = Design.AuroraPane(id: "p", name: "a", agent: .claude, state: .idle)
        let working = Design.AuroraPane(id: "p2", name: "b", agent: .claude, state: .working)
        let finished = Design.AuroraPane(id: "p3", name: "c", agent: .claude, state: .finished)
        #expect(idle.contributesToMatrix == false)
        #expect(working.contributesToMatrix == true)
        #expect(finished.contributesToMatrix == true)
    }

    @Test("AuroraSession.matrixPanes filters idle panes so the sidebar matrix honours the contract")
    func matrixPanesFiltersIdleStates() {
        let idlePane = Design.AuroraPane(id: "p-idle", name: "idle", agent: .claude, state: .idle)
        let workingPane = Design.AuroraPane(id: "p-work", name: "work", agent: .claude, state: .working)
        let finishedPane = Design.AuroraPane(id: "p-done", name: "done", agent: .claude, state: .finished)
        let session = Design.AuroraSession(
            id: "s",
            name: "mixed",
            agent: .claude,
            state: .working,
            panes: [idlePane, workingPane, finishedPane]
        )
        let matrixIDs = session.matrixPanes.map(\.id)
        #expect(matrixIDs == ["p-work", "p-done"])
        #expect(session.matrixPanes.allSatisfy { $0.state != .idle })
    }

    @Test("AuroraSession.matrixPanes returns an empty list when every pane is idle")
    func matrixPanesEmptyWhenAllIdle() {
        let session = Design.AuroraSession(
            id: "s",
            name: "dormant",
            agent: .shell,
            state: .idle,
            panes: [
                Design.AuroraPane(id: "a", name: "a", agent: .shell, state: .idle),
                Design.AuroraPane(id: "b", name: "b", agent: .shell, state: .idle),
            ]
        )
        #expect(session.matrixPanes.isEmpty)
    }

    @Test("AuroraPane diagnostic line includes activity and counters")
    func paneDiagnosticLineIncludesActivityAndCounters() {
        let pane = Design.AuroraPane(
            id: "claude",
            name: "Claude Code",
            agent: .claude,
            state: .working,
            activity: "Editing AppDelegate.swift",
            toolCount: 7,
            errorCount: 1
        )

        #expect(pane.diagnosticLine.contains("Claude Code"))
        #expect(pane.diagnosticLine.contains("working"))
        #expect(pane.diagnosticLine.contains("Editing AppDelegate.swift"))
        #expect(pane.diagnosticLine.contains("tools 7"))
        #expect(pane.diagnosticLine.contains("errors 1"))
    }

    @Test("AuroraSession diagnostic tooltip summarizes workspace, process, commands, and active panes")
    func sessionDiagnosticTooltipIncludesUsefulHoverContext() {
        let session = Design.AuroraSession(
            id: "s",
            name: "sisocs-v3 (main)",
            agent: .claude,
            state: .working,
            panes: [
                Design.AuroraPane(
                    id: "claude",
                    name: "Claude Code",
                    agent: .claude,
                    state: .working,
                    activity: "Waiting for approval",
                    toolCount: 3
                ),
                Design.AuroraPane(id: "shell", name: "zsh", agent: .shell, state: .idle),
            ],
            workingDirectory: "/Users/Galf/sisocs-v3",
            foregroundProcessName: "claude",
            lastCommandSummary: "Command: running"
        )

        let tooltip = session.diagnosticTooltip(workspaceName: "sisocs-v3", branch: "main")

        #expect(tooltip.contains("Workspace: sisocs-v3 · main"))
        #expect(tooltip.contains("Foreground process: claude"))
        #expect(tooltip.contains("Directory: ~/sisocs-v3"))
        #expect(tooltip.contains("Command: running"))
        #expect(tooltip.contains("Claude Code"))
        #expect(tooltip.contains("Waiting for approval"))
        #expect(!tooltip.contains("zsh — idle"))
    }

    @Test("AuroraSession aggregates live pane and diagnostic counters")
    func sessionAggregatesPaneDiagnostics() {
        let session = Design.AuroraSession(
            id: "s",
            name: "mixed",
            agent: .claude,
            state: .working,
            panes: [
                Design.AuroraPane(id: "idle", name: "zsh", agent: .shell, state: .idle),
                Design.AuroraPane(id: "claude", name: "Claude", agent: .claude, state: .working, toolCount: 4),
                Design.AuroraPane(id: "codex", name: "Codex", agent: .codex, state: .waiting, toolCount: 2, errorCount: 1),
            ]
        )

        #expect(session.activePaneCount == 2)
        #expect(session.totalToolCount == 6)
        #expect(session.totalErrorCount == 1)
    }

    // MARK: - Sample catalogue

    @Test("Shipping sample workspaces cover at least three distinct agent accents")
    func sampleWorkspacesVariety() {
        let allAgents = Set(Design.sampleWorkspaces
            .flatMap { $0.sessions }
            .map(\.agent))
        #expect(allAgents.count >= 3)
    }

    @Test("Shipping sample workspaces expose one collapsed and at least one expanded entry")
    func sampleWorkspacesContainsCollapsedAndExpanded() {
        #expect(Design.sampleWorkspaces.contains(where: { $0.isCollapsed }))
        #expect(Design.sampleWorkspaces.contains(where: { !$0.isCollapsed }))
    }
}

@Suite("Aurora status-bar model helpers")
struct AuroraStatusBarModelTests {

    // MARK: - Timeline state

    @Test("AuroraTimelineState clamps progress to the unit interval")
    func timelineProgressClamps() {
        let below = Design.AuroraTimelineState(progress: -0.2)
        let above = Design.AuroraTimelineState(progress: 1.4)
        #expect(below.progress == 0)
        #expect(above.progress == 1)
    }

    @Test("AuroraTimelineState ago label rounds to the nearest second within the window")
    func timelineAgoLabel() {
        let live = Design.AuroraTimelineState(progress: 1, windowSeconds: 60)
        let halfway = Design.AuroraTimelineState(progress: 0.5, windowSeconds: 60)
        let origin = Design.AuroraTimelineState(progress: 0, windowSeconds: 60)
        #expect(live.agoLabel == "0s ago")
        #expect(halfway.agoLabel == "30s ago")
        #expect(origin.agoLabel == "60s ago")
    }

    @Test("AuroraTimelineState rejects windows below one second")
    func timelineWindowMinimum() {
        let zero = Design.AuroraTimelineState(progress: 0.5, windowSeconds: 0)
        let negative = Design.AuroraTimelineState(progress: 0.5, windowSeconds: -12)
        #expect(zero.windowSeconds == 1)
        #expect(negative.windowSeconds == 1)
    }

    // MARK: - Port binding

    @Test("AuroraPortBinding maps ok health to the finished state role")
    func portHealthMapping() {
        let ok = Design.AuroraPortBinding(port: 3000, name: "web", health: .ok)
        let idle = Design.AuroraPortBinding(port: 4001, name: "api", health: .idle)
        let error = Design.AuroraPortBinding(port: 9000, name: "db", health: .error)
        #expect(ok.stateRole == .finished)
        #expect(idle.stateRole == .idle)
        #expect(error.stateRole == .error)
    }

    @Test("AuroraPortBinding exposes a localhost URL string for status-bar actions")
    func portLocalhostURLString() {
        let port = Design.AuroraPortBinding(port: 4321, name: "dev server", health: .ok)
        #expect(port.localhostURLString == "http://localhost:4321")
    }

    // MARK: - Flatten helper used by the agent matrix

    @Test("AuroraStatusBarView.allPanes flattens every pane across workspaces")
    func allPanesFlattensWorkspaces() {
        let flat = Design.AuroraStatusBarView.allPanes(in: Design.sampleWorkspaces)
        let expected = Design.sampleWorkspaces
            .flatMap { $0.sessions }
            .flatMap { $0.panes }
        #expect(flat == expected)
    }

    @Test("Agent matrix summary counts every non-idle pane")
    func agentMatrixSummaryCountsEveryActivePane() {
        let panes = [
            Design.AuroraPane(id: "idle", name: "Shell", agent: .shell, state: .idle),
            Design.AuroraPane(id: "claude", name: "Claude Code", agent: .claude, state: .working),
            Design.AuroraPane(id: "codex", name: "Codex", agent: .codex, state: .working),
            Design.AuroraPane(id: "gemini", name: "Gemini", agent: .gemini, state: .waiting),
        ]

        #expect(Design.AgentMatrixView.summaryText(for: panes) == "2 working · 1 waiting")
    }

    @Test("Agent matrix tooltip lists active agent names and excludes idle panes")
    func agentMatrixTooltipListsActiveAgentNames() {
        let panes = [
            Design.AuroraPane(id: "idle", name: "Shell", agent: .shell, state: .idle),
            Design.AuroraPane(id: "claude", name: "Claude Code", agent: .claude, state: .working),
            Design.AuroraPane(id: "codex", name: "Codex", agent: .codex, state: .waiting),
        ]

        let tooltip = Design.AgentMatrixView.agentTooltip(for: panes)

        #expect(tooltip.contains("Claude Code — working"))
        #expect(tooltip.contains("Codex — waiting"))
        #expect(!tooltip.contains("Shell"))
    }

    @Test("Sample port bindings always expose at least one port in the ok state")
    func samplePortsContainsHealthyPort() {
        #expect(Design.samplePortBindings.contains(where: { $0.health == .ok }))
    }
}
