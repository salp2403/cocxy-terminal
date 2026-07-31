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
        var didCleanRuntime = false

        await #expect(throws: AgentPipelineRuntimeError.stepTimedOut("queue-timeout")) {
            _ = try await broker.launchAndWait(
                teamID: "queue-timeout",
                launch: {},
                onTimeout: { didCleanRuntime = true }
            )
        }
        #expect(didCleanRuntime)
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

    @Test("handoff hook events never persist resumable team snapshots")
    func handoffHooksDoNotPersistSnapshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-handoff-snapshots-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let teamID = "handoff-\(UUID().uuidString.lowercased())"
        let teammateID = "\(teamID)-agent"
        let config = AgentTeamConfig(
            id: teamID,
            provider: .codex,
            teammates: [AgentTeammateConfig(
                id: teammateID,
                name: "handoff",
                prompt: "Continue"
            )]
        )
        let delegate = AppDelegate()
        delegate.agentTeamSessionSnapshotStore = AgentTeamSessionSnapshotStore(directory: root)
        delegate.activeAgentTeamCoordinators[teamID] = AgentTeamCoordinator(config: config)
        delegate.activeAgentTeamRuns[teamID] = AgentTeamRunState(
            config: config,
            launchSpecs: []
        )

        delegate.applyAgentTeamHookEvent(HookEvent(
            type: .sessionStart,
            sessionId: teamID,
            teamID: teamID,
            teammateID: teammateID,
            teammateName: "handoff"
        ))

        #expect(delegate.activeAgentTeamRuns[teamID]?.graph.node(id: teammateID)?.status == .working)
        #expect(!FileManager.default.fileExists(
            atPath: delegate.agentTeamSessionSnapshotStore.fileURL(teamID: teamID).path
        ))
    }

    @Test("provider exit completes queued work without hook infrastructure")
    func providerExitCompletesQueuedWorkWithoutHooks() async throws {
        let fixture = try launchRealQueuedProvider(teamID: "queue-process-exit", exitCode: 0)
        defer { fixture.controller.close() }
        #expect(fixture.delegate.hookEventReceiver == nil)
        #expect(await waitUntil(attempts: 1_000) {
            fixture.tabID.withValue { $0 != nil }
        })
        let completedBeforeWatchdog = await waitUntil(attempts: 1_000) {
            await fixture.delegate.agentPipelineCompletionBroker.pendingTeamIDs.isEmpty
        }
        guard completedBeforeWatchdog else {
            fixture.waiter.cancel()
            Issue.record("Provider exit 0 did not complete before the production watchdog")
            return
        }

        #expect(try await fixture.waiter.value == AgentPipelineStepExecutionOutput(
            summary: "Provider process exited"
        ))
        let didCleanQueueRuntime = await waitUntilOnMainActor {
            fixture.delegate.taskQueueAgentTeamContexts[fixture.teamID] == nil
                && fixture.delegate.activeAgentTeamRuns[fixture.teamID] == nil
                && fixture.tabID.withValue {
                    $0.map { fixture.controller.tabManager.tab(for: $0) == nil } ?? false
                }
        }
        #expect(didCleanQueueRuntime)
    }

    @Test("nonzero provider exit fails queued work and clears runtime state")
    func nonzeroProviderExitFailsQueuedWork() async throws {
        let fixture = try launchRealQueuedProvider(teamID: "queue-process-failure", exitCode: 3)
        defer { fixture.controller.close() }
        #expect(await waitUntil(attempts: 1_000) {
            fixture.tabID.withValue { $0 != nil }
        })
        let completedBeforeWatchdog = await waitUntil(attempts: 1_000) {
            await fixture.delegate.agentPipelineCompletionBroker.pendingTeamIDs.isEmpty
        }
        guard completedBeforeWatchdog else {
            fixture.waiter.cancel()
            Issue.record("Provider exit 3 did not fail before the production watchdog")
            return
        }

        await #expect(throws: AgentPipelineRuntimeError.agentFailed(
            "Provider process exited with status 3"
        )) {
            _ = try await fixture.waiter.value
        }
        #expect(await waitUntilOnMainActor {
            fixture.delegate.taskQueueAgentTeamContexts[fixture.teamID] == nil
                && fixture.delegate.activeAgentTeamRuns[fixture.teamID] == nil
                && fixture.tabID.withValue {
                    $0.map { fixture.controller.tabManager.tab(for: $0) == nil } ?? false
                }
        })
    }

    @Test("unknown provider exit status fails queued work")
    func unknownProviderExitStatusFailsQueuedWork() async throws {
        _ = NSApplication.shared
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        defer { controller.close() }
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        delegate.configureSharedServices(for: controller, registerWindow: false)
        let fixture = try installTeamRuntime(
            teamID: "queue-process-unknown",
            bridge: bridge,
            controller: controller,
            delegate: delegate,
            queued: true
        )
        let waiter = Task {
            try await delegate.agentPipelineCompletionBroker.launchAndWait(teamID: fixture.teamID) {}
        }
        #expect(await waitUntil {
            await delegate.agentPipelineCompletionBroker.pendingTeamIDs == [fixture.teamID]
        })

        controller.handleOSCNotification(
            .processExited(exitCode: nil),
            fromTabID: fixture.tabID,
            surfaceID: fixture.surfaceID
        )

        await #expect(throws: AgentPipelineRuntimeError.agentFailed(
            "Provider process exited without a status"
        )) {
            _ = try await waiter.value
        }
    }

    @Test("closing a queued provider tab fails its step and clears runtime state")
    func closingQueuedProviderTabFailsStep() async throws {
        _ = NSApplication.shared
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        delegate.configureSharedServices(for: controller, registerWindow: false)
        let fixture = try installTeamRuntime(
            teamID: "queue-tab-close",
            bridge: bridge,
            controller: controller,
            delegate: delegate,
            queued: true
        )
        let waiter = Task {
            try await delegate.agentPipelineCompletionBroker.launchAndWait(
                teamID: fixture.teamID
            ) {}
        }
        #expect(await waitUntil {
            await delegate.agentPipelineCompletionBroker.pendingTeamIDs == [fixture.teamID]
        })

        controller.performCloseTab(fixture.tabID)

        await #expect(throws: AgentPipelineRuntimeError.agentFailed(
            "Provider terminal tab closed"
        )) {
            _ = try await waiter.value
        }
        #expect(delegate.taskQueueAgentTeamContexts[fixture.teamID] == nil)
        #expect(delegate.activeAgentTeamRuns[fixture.teamID] == nil)
    }

    @Test("closing a provider window fails its queued step and clears runtime state")
    func closingQueuedProviderWindowFailsStep() async throws {
        _ = NSApplication.shared
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        delegate.configureSharedServices(for: controller, registerWindow: false)
        let fixture = try installTeamRuntime(
            teamID: "queue-window-close",
            bridge: bridge,
            controller: controller,
            delegate: delegate,
            queued: true
        )
        let waiter = Task {
            try await delegate.agentPipelineCompletionBroker.launchAndWait(
                teamID: fixture.teamID
            ) {}
        }
        #expect(await waitUntil {
            await delegate.agentPipelineCompletionBroker.pendingTeamIDs == [fixture.teamID]
        })

        controller.window?.close()

        await #expect(throws: AgentPipelineRuntimeError.agentFailed(
            "Provider terminal tab closed"
        )) {
            _ = try await waiter.value
        }
        #expect(delegate.taskQueueAgentTeamContexts[fixture.teamID] == nil)
        #expect(delegate.activeAgentTeamRuns[fixture.teamID] == nil)
        #expect(delegate.activeAgentTeamCoordinators[fixture.teamID] == nil)
        #expect(!controller.taskQueueLifecycleExcludedTabIDs.contains(fixture.tabID))
    }

    @Test("queue-origin plugin events cannot retrigger event tasks")
    func queueOriginPluginEventsAreSuppressed() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-queue-plugin-events-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runCount = LockedBox(0)
        let queue = try TaskQueue(
            store: TaskQueueStore(rootDirectory: root.appendingPathComponent("queue")),
            runHandler: { item in
                runCount.withValue { $0 += 1 }
                let now = Date()
                return AgentPipelineRunSummary(
                    pipelineID: item.pipeline.id,
                    status: .succeeded,
                    stepResults: [],
                    startedAt: now,
                    finishedAt: now
                )
            }
        )
        _ = try await queue.start()
        let item = try TaskQueueItem(
            id: "on-tab-created",
            pipeline: AgentPipeline(
                id: "event-pipeline",
                steps: [AgentPipelineStep(id: "run", provider: .codex, prompt: "Run")]
            ),
            trigger: .event(.tabCreated)
        )
        _ = try await queue.enqueue(item)
        let delegate = AppDelegate()
        delegate.taskQueue = queue
        delegate.taskQueueIsReady = true

        delegate.dispatchApplicationPluginEvent(
            .tabCreated,
            environment: [:],
            triggersTaskQueue: false
        )
        try await Task.sleep(for: .milliseconds(30))
        #expect(runCount.withValue { $0 } == 0)
        #expect(await queue.item(id: item.id)?.status == .scheduled)

        delegate.dispatchApplicationPluginEvent(.tabCreated, environment: [:])
        #expect(await waitUntil { runCount.withValue { $0 } == 1 })
        await queue.shutdown()
    }

    @Test("last provider exit cleans a normal team while preserving terminal output")
    func providerExitCleansNormalTeamRuntime() async throws {
        _ = NSApplication.shared
        let bridge = MockTerminalEngine()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        delegate.configureSharedServices(for: controller, registerWindow: false)
        let fixture = try installTeamRuntime(
            teamID: "normal-process-exit",
            bridge: bridge,
            controller: controller,
            delegate: delegate,
            queued: false
        )

        controller.handleOSCNotification(
            .processExited(exitCode: 0),
            fromTabID: fixture.tabID,
            surfaceID: fixture.surfaceID
        )

        let didCleanNormalRuntime = await waitUntilOnMainActor {
            delegate.activeAgentTeamRuns[fixture.teamID] == nil
                && delegate.activeAgentTeamCoordinators[fixture.teamID] == nil
        }
        #expect(didCleanNormalRuntime)
        #expect(controller.tabManager.tab(for: fixture.tabID) != nil)
        #expect(!controller.taskQueueLifecycleExcludedTabIDs.contains(fixture.tabID))
        controller.performCloseTab(fixture.tabID)
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

    private func launchRealQueuedProvider(
        teamID: String,
        exitCode: Int32
    ) throws -> (
        teamID: String,
        controller: MainWindowController,
        delegate: AppDelegate,
        tabID: LockedBox<TabID?>,
        waiter: Task<AgentPipelineStepExecutionOutput, Error>
    ) {
        _ = NSApplication.shared
        let bridge = try makeBridge()
        let controller = MainWindowController(bridge: bridge)
        controller.showWindow(nil)
        let delegate = AppDelegate()
        delegate.installWindowControllerForTesting(controller)
        delegate.configureSharedServices(for: controller, registerWindow: false)

        let teammateID = "\(teamID)-agent"
        let config = AgentTeamConfig(
            id: teamID,
            provider: .codex,
            teammates: [AgentTeammateConfig(
                id: teammateID,
                name: "agent",
                prompt: "Run"
            )]
        )
        let launchSpec = AgentTeamProviderLaunchSpec(
            provider: .codex,
            teamID: teamID,
            teammateID: teammateID,
            teammateName: "agent",
            executable: "/bin/sh",
            arguments: ["-c", "exit \(exitCode)"],
            environment: ["COCXY_AGENT_TEAM_ID": teamID],
            workingDirectory: NSTemporaryDirectory()
        )
        delegate.activeAgentTeamCoordinators[teamID] = AgentTeamCoordinator(config: config)
        delegate.activeAgentTeamRuns[teamID] = AgentTeamRunState(
            config: config,
            launchSpecs: [launchSpec]
        )
        delegate.taskQueueAgentTeamContexts[teamID] = TaskQueueAgentTeamContext(
            taskID: "scheduled-task",
            pipelineID: "pipeline",
            stepID: "step"
        )

        let tabID = LockedBox<TabID?>(nil)
        let waiter = Task {
            try await delegate.agentPipelineCompletionBroker.launchAndWait(teamID: teamID) {
                guard let launchedTabID = controller.spawnAgentTeamTerminal(
                    launchSpec: launchSpec,
                    targetTabID: nil,
                    excludesTaskQueueLifecycleEvents: true
                ) else {
                    throw RuntimeTestError.launch
                }
                tabID.withValue { $0 = launchedTabID }
            }
        }
        return (teamID, controller, delegate, tabID, waiter)
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

    private func waitUntilOnMainActor(
        attempts: Int = 200,
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private func installTeamRuntime(
        teamID: String,
        bridge: MockTerminalEngine,
        controller: MainWindowController,
        delegate: AppDelegate,
        queued: Bool
    ) throws -> (teamID: String, tabID: TabID, surfaceID: SurfaceID) {
        let teammateID = "\(teamID)-agent"
        let config = AgentTeamConfig(
            id: teamID,
            provider: .codex,
            teammates: [AgentTeammateConfig(
                id: teammateID,
                name: "agent",
                prompt: "Run"
            )]
        )
        let launchSpec = AgentTeamProviderLaunchSpec(
            provider: .codex,
            teamID: teamID,
            teammateID: teammateID,
            teammateName: "agent",
            executable: "/usr/local/bin/codex",
            arguments: [],
            environment: ["COCXY_AGENT_TEAM_ID": teamID],
            workingDirectory: NSTemporaryDirectory()
        )
        let tabID = try #require(controller.spawnAgentTeamTerminal(
            launchSpec: launchSpec,
            targetTabID: nil,
            excludesTaskQueueLifecycleEvents: queued
        ))
        let surfaceID = try #require(controller.tabSurfaceMap[tabID])
        delegate.activeAgentTeamCoordinators[teamID] = AgentTeamCoordinator(config: config)
        delegate.activeAgentTeamRuns[teamID] = AgentTeamRunState(
            config: config,
            launchSpecs: [launchSpec]
        )
        if queued {
            delegate.taskQueueAgentTeamContexts[teamID] = TaskQueueAgentTeamContext(
                taskID: "scheduled-task",
                pipelineID: "pipeline",
                stepID: "step"
            )
        }
        #expect(bridge.sentTexts.last?.text.contains("codex") == true)
        return (teamID, tabID, surfaceID)
    }
}

private enum RuntimeTestError: Error, CustomStringConvertible {
    case launch

    var description: String { "expected launch failure" }
}
