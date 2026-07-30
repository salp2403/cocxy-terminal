// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Task queue app CLI")
struct TaskQueueCLISwiftTestingTests {
    @Test("approved pipeline persists, lists without private content, and cancels")
    func approvedPipelineLifecycle() async throws {
        let fixture = try await makeFixture(taskID: "scheduled-review")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let enqueue = await Task.detached {
            fixture.delegate.handleTaskQueueCLIRequest(
                kind: "enqueue",
                params: fixture.params,
                approvedContext: fixture.context
            )
        }.value
        #expect(enqueue.success)
        #expect(enqueue.data["task-id"] == "scheduled-review")

        let item = try #require(await fixture.queue.item(id: "scheduled-review"))
        #expect(item.status == .scheduled)
        #expect(item.pipeline.steps.first?.worktree == fixture.root.path)

        let listed = await Task.detached {
            fixture.delegate.handleTaskQueueCLIRequest(
                kind: "list",
                params: ["limit": "50", "offset": "0"]
            )
        }.value
        #expect(listed.success)
        #expect(listed.data["total"] == "1")
        #expect(listed.data["task_0_id"] == "scheduled-review")
        #expect(!listed.data.values.contains(where: { value in
            value.contains("Audit private changes") || value.contains(fixture.root.path)
        }))

        let cancelParams = ["task-id": "scheduled-review"]
        let cancelContext = Self.context(
            operation: "cancel",
            params: cancelParams,
            workingDirectory: fixture.root.path
        )
        let cancelled = await Task.detached {
            fixture.delegate.handleTaskQueueCLIRequest(
                kind: "cancel",
                params: cancelParams,
                approvedContext: cancelContext
            )
        }.value
        #expect(cancelled.success)
        #expect(await fixture.queue.item(id: "scheduled-review")?.status == .cancelled)
        await fixture.queue.shutdown()
    }

    @Test("pipeline bytes changed after approval are rejected")
    func pipelineTOCTOUIsRejected() async throws {
        let fixture = try await makeFixture(taskID: "immutable-review")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try Data("{}".utf8).write(to: fixture.pipelineURL, options: .atomic)

        let result = await Task.detached {
            fixture.delegate.handleTaskQueueCLIRequest(
                kind: "enqueue",
                params: fixture.params,
                approvedContext: fixture.context
            )
        }.value

        #expect(!result.success)
        #expect(result.data["error"]?.contains("changed before execution") == true)
        #expect(await fixture.queue.item(id: "immutable-review") == nil)
        await fixture.queue.shutdown()
    }

    private func makeFixture(taskID: String) async throws -> TaskQueueCLIFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-cli-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let pipelineURL = root.appendingPathComponent("pipeline.json")
        let pipeline = try AgentPipeline(
            id: "review-pipeline",
            steps: [AgentPipelineStep(
                id: "audit",
                provider: .codex,
                prompt: "Audit private changes"
            )]
        )
        let pipelineData = try JSONEncoder().encode(pipeline)
        try pipelineData.write(to: pipelineURL, options: .atomic)

        let queue = try TaskQueue(
            store: TaskQueueStore(rootDirectory: root.appendingPathComponent("queue")),
            runHandler: { item in
                let now = Date()
                return AgentPipelineRunSummary(
                    pipelineID: item.pipeline.id,
                    status: .failed,
                    stepResults: [],
                    startedAt: now,
                    finishedAt: now
                )
            }
        )
        _ = try await queue.start()
        let delegate = AppDelegate()
        delegate.taskQueue = queue
        delegate.taskQueueIsReady = true

        let params = [
            "task-id": taskID,
            "input": pipelineURL.path,
            "cwd": root.path,
            "trigger": "on-event",
            "event": "command-complete",
            "retries": "1",
            "concurrency": "2",
        ]
        let context = Self.context(
            operation: "enqueue",
            params: params,
            workingDirectory: root.path,
            pipelineURL: pipelineURL,
            pipelineData: pipelineData
        )
        return TaskQueueCLIFixture(
            root: root,
            pipelineURL: pipelineURL,
            params: params,
            context: context,
            queue: queue,
            delegate: delegate
        )
    }

    private static func context(
        operation: String,
        params: [String: String],
        workingDirectory: String,
        pipelineURL: URL? = nil,
        pipelineData: Data? = nil
    ) -> SocketPrivilegedCommandContext {
        var paths = ["cwd": workingDirectory]
        var digests: [String: String] = [:]
        if let pipelineURL, let pipelineData {
            paths["input"] = pipelineURL.path
            digests["input"] = SocketPrivilegedCommandSecurity.digest(data: pipelineData)
        }
        return SocketPrivilegedCommandContext(
            scope: .localExecution,
            windowControllerIdentifier: nil,
            tabID: nil,
            workingDirectory: workingDirectory,
            localResourcePaths: paths,
            localResourceDigests: digests,
            authorityDetails: TaskQueueSocketAuthority.details(
                operation: operation,
                params: params
            ) ?? [:],
            surfaceID: nil,
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: taskID(from: params)
        )
    }

    private static func taskID(from params: [String: String]) -> String {
        params["task-id"] ?? "task"
    }
}

private struct TaskQueueCLIFixture: @unchecked Sendable {
    let root: URL
    let pipelineURL: URL
    let params: [String: String]
    let context: SocketPrivilegedCommandContext
    let queue: TaskQueue
    let delegate: AppDelegate
}
