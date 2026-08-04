// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task collision app integration")
@MainActor
struct TaskCollisionAppIntegrationSwiftTestingTests {
    @Test("launch analysis crosses the app queue and active task runs")
    func launchAnalysisCrossesAppWorkloads() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try Data("struct App {}\n".utf8).write(
            to: sourceDirectory.appendingPathComponent("App.swift")
        )

        let pipeline = try AgentPipeline(
            id: "queued-work",
            name: "Queued work",
            steps: [AgentPipelineStep(
                id: "edit",
                provider: .codex,
                prompt: "Update Sources/App.swift",
                project: root.path
            )]
        )
        let queued = try TaskQueueItem(
            id: "queued-work",
            pipeline: pipeline,
            project: root.path,
            trigger: .event(.tabCreated)
        )
        let queue = try TaskQueue(
            store: TaskQueueStore(
                rootDirectory: root.appendingPathComponent("queue", isDirectory: true)
            ),
            runHandler: { _ in
                AgentPipelineRunSummary(
                    pipelineID: "queued-work",
                    status: .succeeded,
                    stepResults: [],
                    startedAt: Date(),
                    finishedAt: Date()
                )
            }
        )
        _ = try await queue.start()
        _ = try await queue.enqueue(queued)

        let request = try TaskRunRequest.make(
            prompt: "Review Sources/App.swift",
            agents: "codex,claude"
        )
        let activeRun = TaskRun(
            id: "active-run",
            request: request,
            originRepoPath: root,
            baseCommit: "base"
        )
        let appDelegate = AppDelegate()
        appDelegate.taskQueue = queue
        appDelegate.activeTaskRuns[activeRun.id] = activeRun

        let analysis = await appDelegate.taskLaunchCollisionAnalysis(
            prompt: "Implement Sources/App.swift",
            seedPaths: [],
            projectID: activeRun.projectID,
            projectRoot: root
        )

        #expect(analysis.inferredPaths == ["Sources/App.swift"])
        #expect(analysis.report.paths == ["Sources/App.swift"])
        #expect(Set(analysis.report.collisions.flatMap { collision in
            collision.participants.map(\.kind)
        }) == [.plannedTask, .queuedTask, .taskRun])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-collision-\(UUID().uuidString)", isDirectory: true)
    }
}
