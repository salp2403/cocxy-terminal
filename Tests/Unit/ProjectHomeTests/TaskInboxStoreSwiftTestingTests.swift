// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskInboxStoreSwiftTestingTests.swift - App-scoped task inbox snapshot coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task inbox store")
@MainActor
struct TaskInboxStoreSwiftTestingTests {
    @Test("publishes one atomic ready snapshot and active task badges")
    func publishesReadySnapshotAndBadges() throws {
        let project = ProjectID(rawValue: "/tmp/store-project")
        let resolver = FixedProjectResolver(projectID: project)
        let store = TaskInboxStore(projectResolver: resolver)
        #expect(store.snapshot == .loading)

        let request = try TaskRunRequest.make(prompt: "Compare", agents: "codex,gemini")
        var run = TaskRun(
            id: "compare",
            request: request,
            originRepoPath: URL(fileURLWithPath: project.rawValue),
            baseCommit: "abc123",
            now: Date(timeIntervalSince1970: 20)
        )
        run.markRunning(now: Date(timeIntervalSince1970: 21))
        let queueItem = try TaskQueueItem(
            id: "queued",
            pipeline: AgentPipeline(
                id: "pipeline",
                steps: [AgentPipelineStep(
                    id: "run",
                    provider: .codex,
                    prompt: "Run",
                    project: project.rawValue
                )]
            ),
            project: project.rawValue,
            trigger: .event(.tabCreated)
        )

        store.updateSessions([])
        store.updateDashboardSessions([])
        store.updateTaskRuns([run])
        store.updateQueueItems([queueItem])

        #expect(store.snapshot.availability == .ready)
        #expect(store.entries(for: project).count == 2)
        #expect(store.snapshot.badgeCounts[project.rawValue] == 2)

        store.markFailed(.queue, message: "Queue unavailable")
        guard case .partial(let issues) = store.snapshot.availability else {
            Issue.record("Expected a partial snapshot after one source failed")
            return
        }
        #expect(issues == [TaskInboxIssue(source: .queue, message: "Queue unavailable")])
        #expect(store.entries(for: project).count == 2)
    }
}

@MainActor
private final class FixedProjectResolver: ProjectResolving {
    private let projectID: ProjectID

    init(projectID: ProjectID) {
        self.projectID = projectID
    }

    func resolveProject(for directory: URL) -> ProjectDescriptor {
        ProjectDescriptor(
            id: projectID,
            rootURL: URL(fileURLWithPath: projectID.rawValue, isDirectory: true),
            automaticName: "Project",
            displayName: "Project",
            parent: nil
        )
    }

    func invalidate(directory: URL) {}
    func invalidateAll() {}
}
