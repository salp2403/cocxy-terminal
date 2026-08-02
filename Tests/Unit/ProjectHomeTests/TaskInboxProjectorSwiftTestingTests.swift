// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskInboxProjectorSwiftTestingTests.swift - Unified project inbox projection coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task inbox projector")
struct TaskInboxProjectorSwiftTestingTests {
    @Test("projects fan-outs, queue items, cross-window agents, and pending handoffs")
    func projectsEveryLiveSourceDeterministically() throws {
        let project = ProjectID(rawValue: "/tmp/inbox-project")
        let otherProject = ProjectID(rawValue: "/tmp/inbox-other")
        let run = try makeRun(project: project, now: Date(timeIntervalSince1970: 40))
        let queued = try makeQueueItem(project: project, now: Date(timeIntervalSince1970: 30))
        let ownerWindow = WindowID()
        let agentTab = TabID()
        let liveSession = SessionEntry(
            createdAt: Date(timeIntervalSince1970: 10),
            ownerWindowID: ownerWindow,
            tabID: agentTab,
            title: "Implementation",
            workingDirectory: URL(fileURLWithPath: project.rawValue),
            agentState: .working,
            detectedAgentName: "Codex"
        )
        let liveDashboard = dashboardSession(
            id: "live-session",
            project: project,
            windowID: ownerWindow,
            tabID: agentTab,
            state: .waitingForInput,
            updatedAt: Date(timeIntervalSince1970: 20),
            files: ["Sources/App.swift"]
        )
        let handoff = dashboardSession(
            id: "handoff-review",
            project: project,
            windowID: WindowID(),
            tabID: TabID(),
            state: .launching,
            updatedAt: Date(timeIntervalSince1970: 50),
            files: ["Sources/Review.swift"]
        )
        let unrelated = SessionEntry(
            ownerWindowID: WindowID(),
            tabID: TabID(),
            title: "Other",
            workingDirectory: URL(fileURLWithPath: otherProject.rawValue),
            agentState: .working,
            detectedAgentName: "Other"
        )

        let entries = TaskInboxProjector.project(
            taskRuns: [run],
            queueItems: [queued],
            sessions: [unrelated, liveSession],
            dashboardSessions: [liveDashboard, handoff],
            resolveProjectID: { ProjectID(rootURL: $0) }
        )
        let projectEntries = entries.filter { $0.projectID == project }

        #expect(projectEntries.map(\.kind) == [.handoff, .fanOut, .queuedTask, .liveAgent])
        #expect(Set(projectEntries.map(\.id)).count == projectEntries.count)
        let fanOut = try #require(projectEntries.first { $0.kind == .fanOut })
        #expect(fanOut.navigation?.sessionID == run.id)
        let agent = try #require(projectEntries.first { $0.kind == .liveAgent })
        #expect(agent.status == AgentDashboardState.waitingForInput.rawValue)
        #expect(agent.touchedFiles == ["Sources/App.swift"])
        #expect(agent.navigation?.windowID == ownerWindow)
        #expect(agent.navigation?.tabID == agentTab)
        let handoffEntry = try #require(projectEntries.first { $0.kind == .handoff })
        #expect(handoffEntry.touchedFiles == ["Sources/Review.swift"])
        #expect(entries.contains { $0.projectID == otherProject && $0.kind == .liveAgent })
    }

    @Test("task inbox JSON excludes local routing and tolerates additive fields")
    func codableContractExcludesNavigationAndDefaultsCollections() throws {
        let entry = TaskInboxEntry(
            id: "queue:build",
            kind: .queuedTask,
            projectID: ProjectID(rawValue: "/tmp/inbox-project"),
            title: "Build",
            status: "scheduled",
            agents: ["Codex"],
            updatedAt: Date(timeIntervalSince1970: 100),
            navigation: TaskInboxNavigation(windowID: WindowID(), tabID: TabID(), sessionID: "private")
        )
        let data = try JSONEncoder().encode(entry)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["navigation"] == nil)
        #expect(object["windowID"] == nil)
        #expect(object["tabID"] == nil)
        #expect(object["sessionID"] == nil)

        let minimal = Data(
            #"{"id":"queue:legacy","kind":"queue","projectID":"/tmp/inbox-project"}"#.utf8
        )
        let decoded = try JSONDecoder().decode(TaskInboxEntry.self, from: minimal)
        #expect(decoded.title == "queue:legacy")
        #expect(decoded.status == "unknown")
        #expect(decoded.agents.isEmpty)
        #expect(decoded.worktreePaths.isEmpty)
        #expect(decoded.touchedFiles.isEmpty)
        #expect(decoded.navigation == nil)
    }

    private func makeRun(project: ProjectID, now: Date) throws -> TaskRun {
        let request = try TaskRunRequest.make(
            prompt: "Compare implementations",
            agents: "codex,gemini"
        )
        var run = TaskRun(
            id: "comparison",
            request: request,
            originRepoPath: URL(fileURLWithPath: project.rawValue),
            baseCommit: "abc123",
            now: now
        )
        run.markRunning(now: now)
        return run
    }

    private func makeQueueItem(project: ProjectID, now: Date) throws -> TaskQueueItem {
        try TaskQueueItem(
            id: "nightly",
            pipeline: AgentPipeline(
                id: "nightly-pipeline",
                name: "Nightly checks",
                steps: [AgentPipelineStep(
                    id: "checks",
                    provider: .codex,
                    prompt: "Run checks",
                    worktree: project.rawValue,
                    project: project.rawValue
                )]
            ),
            project: project.rawValue,
            trigger: .event(.tabCreated),
            now: now
        )
    }

    private func dashboardSession(
        id: String,
        project: ProjectID,
        windowID: WindowID,
        tabID: TabID,
        state: AgentDashboardState,
        updatedAt: Date,
        files: [String]
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: "Project",
            projectIdentity: project,
            windowID: windowID,
            gitBranch: "main",
            agentName: "Codex",
            state: state,
            lastActivity: "Review task",
            lastActivityTime: updatedAt,
            tabId: tabID.rawValue,
            subagents: [],
            priority: .standard,
            model: nil,
            filesTouched: files.map { FileImpact(path: $0) }
        )
    }
}
