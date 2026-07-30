// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Agent pipeline runtime")
struct AgentPipelineRuntimeSwiftTestingTests {
    @Test("registers completion before launching and returns hook output")
    func registersBeforeLaunch() async throws {
        let broker = AgentPipelineCompletionBroker()
        let launched = LockedBox(false)
        let waiter = Task {
            try await broker.launchAndWait(teamID: "queue-one") {
                launched.withValue { $0 = true }
            }
        }

        #expect(await waitUntil {
            let pendingTeamIDs = await broker.pendingTeamIDs
            return launched.withValue { $0 } && pendingTeamIDs == ["queue-one"]
        })
        #expect(await broker.complete(
            teamID: "queue-one",
            output: AgentPipelineStepExecutionOutput(summary: "finished")
        ))

        #expect(try await waiter.value == AgentPipelineStepExecutionOutput(summary: "finished"))
        let pendingAfterCompletion = await broker.pendingTeamIDs
        #expect(pendingAfterCompletion.isEmpty)
    }

    @Test("surfaces launch failures and removes the pending continuation")
    func launchFailure() async {
        let broker = AgentPipelineCompletionBroker()

        await #expect(throws: AgentPipelineRuntimeError.launchFailed("expected launch failure")) {
            _ = try await broker.launchAndWait(teamID: "queue-failure") {
                throw RuntimeTestError.launch
            }
        }
        let pendingAfterFailure = await broker.pendingTeamIDs
        #expect(pendingAfterFailure.isEmpty)
    }

    @Test("cancellation resumes the waiter and clears broker state")
    func cancellation() async throws {
        let broker = AgentPipelineCompletionBroker()
        let launched = LockedBox(false)
        let waiter = Task {
            try await broker.launchAndWait(teamID: "queue-cancel") {
                launched.withValue { $0 = true }
            }
        }
        #expect(await waitUntil {
            let pendingTeamIDs = await broker.pendingTeamIDs
            return launched.withValue { $0 } && pendingTeamIDs == ["queue-cancel"]
        })

        waiter.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await waiter.value
        }
        #expect(await waitUntil { await broker.pendingTeamIDs.isEmpty })
    }

    @Test("watchdog fails a stalled step and releases broker state")
    func watchdogTimeout() async {
        let broker = AgentPipelineCompletionBroker(stepTimeout: .milliseconds(20))

        await #expect(throws: AgentPipelineRuntimeError.stepTimedOut("queue-timeout")) {
            _ = try await broker.launchAndWait(teamID: "queue-timeout") {}
        }
        #expect(await broker.pendingTeamIDs.isEmpty)
    }

    @Test("classifies only terminal lifecycle hooks")
    func hookOutcomeClassification() {
        let taskCompleted = HookEvent(
            type: .taskCompleted,
            sessionId: "session",
            data: .taskCompleted(TaskCompletedData(taskDescription: "Reviewed and tested"))
        )
        let completedStop = HookEvent(
            type: .stop,
            sessionId: "session",
            data: .stop(StopData(lastMessage: "Done", reason: "completed"))
        )
        let cancelledStop = HookEvent(
            type: .stop,
            sessionId: "session",
            data: .stop(StopData(reason: "cancelled by provider"))
        )
        let sessionEnd = HookEvent(type: .sessionEnd, sessionId: "session")
        let toolUse = HookEvent(type: .postToolUse, sessionId: "session")

        #expect(AgentPipelineHookOutcome.resolve(taskCompleted) == .succeeded("Reviewed and tested"))
        #expect(AgentPipelineHookOutcome.resolve(completedStop) == .succeeded("Done"))
        #expect(AgentPipelineHookOutcome.resolve(cancelledStop) == .failed("cancelled by provider"))
        #expect(AgentPipelineHookOutcome.resolve(sessionEnd) == .succeeded(nil))
        #expect(AgentPipelineHookOutcome.resolve(toolUse) == nil)
    }

    @Test("accepted completion hooks retire queue teams and resume their pipeline step")
    func acceptedHookCompletesQueuedAgentStep() async throws {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let teamID = "queue-hook-runtime"
        let teammateID = "\(teamID)-agent"
        let config = AgentTeamConfig(
            id: teamID,
            provider: .codex,
            teammates: [AgentTeammateConfig(
                id: teammateID,
                name: "audit",
                prompt: "Audit"
            )]
        )
        delegate.activeAgentTeamCoordinators[teamID] = AgentTeamCoordinator(config: config)
        delegate.activeAgentTeamRuns[teamID] = AgentTeamRunState(
            config: config,
            launchSpecs: []
        )
        delegate.taskQueueAgentTeamContexts[teamID] = TaskQueueAgentTeamContext(
            taskID: "scheduled-audit",
            pipelineID: "audit-pipeline",
            stepID: "audit"
        )

        let waiter = Task {
            try await delegate.agentPipelineCompletionBroker.launchAndWait(teamID: teamID) {}
        }
        #expect(await waitUntil {
            await delegate.agentPipelineCompletionBroker.pendingTeamIDs == [teamID]
        })

        delegate.applyAgentTeamHookEvent(HookEvent(
            type: .taskCompleted,
            sessionId: "provider-session",
            data: .taskCompleted(TaskCompletedData(taskDescription: "Audit complete")),
            teamID: teamID,
            teammateID: teammateID,
            teammateName: "audit"
        ))

        #expect(try await waiter.value == AgentPipelineStepExecutionOutput(summary: "Audit complete"))
        #expect(delegate.taskQueueAgentTeamContexts[teamID] == nil)
        #expect(delegate.activeAgentTeamCoordinators[teamID] == nil)
        #expect(delegate.activeAgentTeamRuns[teamID] == nil)
    }

    @Test("bounds terminal hook summaries by UTF-8 bytes")
    func boundsHookSummary() throws {
        let event = HookEvent(
            type: .taskCompleted,
            sessionId: "session",
            data: .taskCompleted(TaskCompletedData(
                taskDescription: String(repeating: "\u{00E1}", count: 2_000)
            ))
        )
        let outcome = try #require(AgentPipelineHookOutcome.resolve(event))
        guard case .succeeded(let summary) = outcome else {
            Issue.record("Expected a successful task completion outcome")
            return
        }
        #expect(try #require(summary).utf8.count <= 2_048)
    }

    @Test("requires an existing absolute worktree directory")
    func canonicalWorktreeValidation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-task-queue-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(try AppDelegate.canonicalTaskQueueWorktree(directory.path) == directory.path)
        #expect(throws: AgentPipelineRuntimeError.worktreeUnavailable("relative/path")) {
            _ = try AppDelegate.canonicalTaskQueueWorktree("relative/path")
        }
        let missing = directory.appendingPathComponent("missing", isDirectory: true).path
        #expect(throws: AgentPipelineRuntimeError.worktreeUnavailable(missing)) {
            _ = try AppDelegate.canonicalTaskQueueWorktree(missing)
        }
    }

    private func waitUntil(
        attempts: Int = 200,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private enum RuntimeTestError: Error, CustomStringConvertible {
    case launch

    var description: String { "expected launch failure" }
}
