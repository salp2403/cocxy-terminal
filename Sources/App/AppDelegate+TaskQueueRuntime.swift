// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskQueueRuntime.swift - Persistent agent-pipeline runtime wiring.

import Foundation
import os.log

struct TaskQueueAgentTeamContext: Sendable, Equatable {
    let taskID: String
    let pipelineID: String
    let stepID: String
}

extension AppDelegate {
    nonisolated private static let taskQueueLogger = Logger(
        subsystem: "dev.cocxy.terminal",
        category: "TaskQueue"
    )

    func setupTaskQueueRuntime() {
        guard taskQueue == nil else { return }
        taskQueueIsReady = false

        do {
            let queue = try TaskQueue(
                runHandler: { [weak self] item in
                    guard let self else {
                        return Self.taskQueueFailureSummary(
                            item: item,
                            error: AgentPipelineRuntimeError.runtimeUnavailable
                        )
                    }
                    return await self.executeQueuedAgentPipeline(item)
                },
                lifecycleHandler: { [weak self] event in
                    await self?.dispatchTaskQueueLifecycleEvent(event)
                }
            )
            taskQueue = queue

            Task { [weak self] in
                do {
                    let report = try await queue.start()
                    self?.finishTaskQueueStartup(queue: queue, report: report)
                } catch {
                    self?.failTaskQueueStartup(queue: queue, error: error)
                }
            }
        } catch {
            Self.taskQueueLogger.error(
                "Task queue initialization failed: \(String(describing: error), privacy: .private)"
            )
        }
    }

    private func finishTaskQueueStartup(
        queue: TaskQueue,
        report: TaskQueueStoreLoadReport
    ) {
        guard taskQueue === queue else { return }
        taskQueueIsReady = true
        if !report.rejectedFiles.isEmpty {
            Self.taskQueueLogger.warning(
                "Task queue ignored \(report.rejectedFiles.count, privacy: .public) invalid persisted file(s)"
            )
        }

        taskQueueTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak queue] _ in
            guard let queue else { return }
            Task { await queue.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        taskQueueTimer = timer
    }

    private func failTaskQueueStartup(queue: TaskQueue, error: Error) {
        guard taskQueue === queue else { return }
        taskQueue = nil
        taskQueueIsReady = false
        taskQueueTimer?.invalidate()
        taskQueueTimer = nil
        Self.taskQueueLogger.error(
            "Task queue startup failed: \(String(describing: error), privacy: .private)"
        )
    }

    private func executeQueuedAgentPipeline(
        _ item: TaskQueueItem
    ) async -> AgentPipelineRunSummary {
        let executor: AgentPipelineExecutor
        do {
            executor = try AgentPipelineExecutor(
                maximumConcurrency: item.maximumParallelSteps
            )
        } catch {
            return Self.taskQueueFailureSummary(item: item, error: error)
        }

        return await executor.execute(item.pipeline) { [weak self] step in
            guard let self else {
                throw AgentPipelineRuntimeError.runtimeUnavailable
            }
            return try await self.executeQueuedAgentStep(item: item, step: step)
        }
    }

    private func executeQueuedAgentStep(
        item: TaskQueueItem,
        step: AgentPipelineStep
    ) async throws -> AgentPipelineStepExecutionOutput {
        let worktree = try Self.canonicalTaskQueueWorktree(step.worktree)
        let teamID = "queue-\(UUID().uuidString.lowercased())"
        let context = TaskQueueAgentTeamContext(
            taskID: item.id,
            pipelineID: item.pipeline.id,
            stepID: step.id
        )
        let teammateID = "\(teamID)-agent"
        let config = AgentTeamConfig(
            id: teamID,
            provider: step.provider,
            teammates: [AgentTeammateConfig(
                id: teammateID,
                name: String(step.id.prefix(80)),
                prompt: step.prompt
            )]
        )
        guard await agentTeamProviderAdapterRegistry.prepareExecutableForLaunch(
            for: config.provider
        ) != nil else {
            throw AgentTeamProviderAdapterError.executableUnavailable(
                provider: config.provider,
                candidates: config.provider.executableCandidates
            )
        }

        return try await withTaskCancellationHandler {
            try await agentPipelineCompletionBroker.launchAndWait(
                teamID: teamID,
                launch: { [weak self] in
                    guard let self else {
                        throw AgentPipelineRuntimeError.runtimeUnavailable
                    }
                    try self.launchQueuedAgentTeam(
                        config: config,
                        context: context,
                        workingDirectory: worktree
                    )
                },
                onTimeout: { [weak self] in
                    self?.cleanupQueuedAgentTeamRuntime(teamID: teamID)
                }
            )
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelQueuedAgentTeam(teamID: teamID)
            }
        }
    }

    private func launchQueuedAgentTeam(
        config: AgentTeamConfig,
        context: TaskQueueAgentTeamContext,
        workingDirectory: String
    ) throws {
        guard let controller = focusedWindowController() ?? windowController,
              let targetTabID = controller.visibleTabID?.rawValue else {
            throw AgentPipelineRuntimeError.runtimeUnavailable
        }
        guard taskQueueAgentTeamContexts[config.id] == nil else {
            throw AgentPipelineRuntimeError.launchAlreadyPending(config.id)
        }

        _ = try launchAgentTeamConfig(
            config,
            controller: controller,
            targetTabID: targetTabID,
            workingDirectory: workingDirectory,
            persistSnapshot: false,
            syncDashboard: true,
            excludesTaskQueueLifecycleEvents: true
        )
        taskQueueAgentTeamContexts[config.id] = context
    }

    func completeQueuedAgentTeam(
        teamID rawTeamID: String,
        outcome: AgentPipelineHookOutcome
    ) {
        let teamID = AgentTeamConfig.slug(rawTeamID)
        guard taskQueueAgentTeamContexts[teamID] != nil else { return }

        _ = removeAgentTeamRuntime(
            teamID: teamID,
            worktreeClosePolicyOverride: .keep,
            removeDashboardRow: true
        )
        Task { [agentPipelineCompletionBroker] in
            switch outcome {
            case .succeeded(let summary):
                _ = await agentPipelineCompletionBroker.complete(
                    teamID: teamID,
                    output: AgentPipelineStepExecutionOutput(summary: summary)
                )
            case .failed(let message):
                _ = await agentPipelineCompletionBroker.fail(
                    teamID: teamID,
                    message: message
                )
            }
        }
    }

    func cancelQueuedAgentTeam(teamID rawTeamID: String) {
        let teamID = AgentTeamConfig.slug(rawTeamID)
        cleanupQueuedAgentTeamRuntime(teamID: teamID)
        Task { [agentPipelineCompletionBroker] in
            _ = await agentPipelineCompletionBroker.cancel(teamID: teamID)
        }
    }

    private func cleanupQueuedAgentTeamRuntime(teamID rawTeamID: String) {
        let teamID = AgentTeamConfig.slug(rawTeamID)
        guard taskQueueAgentTeamContexts[teamID] != nil else { return }
        _ = removeAgentTeamRuntime(
            teamID: teamID,
            worktreeClosePolicyOverride: .keep,
            removeDashboardRow: true
        )
    }

    func dispatchApplicationPluginEvent(
        _ event: PluginEvent,
        environment: [String: String],
        triggersTaskQueue: Bool = true
    ) {
        if triggersTaskQueue,
           event != .taskRunStarted,
           event != .taskRunFinished,
           taskQueueIsReady,
           let taskQueue {
            Task { await taskQueue.handlePluginEvent(event) }
        }
        pluginManager?.dispatchEvent(event, environment: environment)
    }

    private func dispatchTaskQueueLifecycleEvent(
        _ event: TaskQueueLifecycleEvent
    ) {
        let pluginEvent: PluginEvent = event.kind == .started
            ? .taskRunStarted
            : .taskRunFinished
        pluginManager?.dispatchEvent(pluginEvent, environment: [
            "COCXY_TASK_ID": event.taskID,
            "COCXY_PIPELINE_ID": event.pipelineID,
            "COCXY_TASK_STATUS": event.status.rawValue,
            "COCXY_TASK_ATTEMPT": String(event.attempt),
        ])
    }

    nonisolated static func canonicalTaskQueueWorktree(_ rawPath: String?) throws -> String {
        guard let rawPath = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty,
              NSString(string: rawPath).isAbsolutePath else {
            throw AgentPipelineRuntimeError.worktreeUnavailable(rawPath ?? "")
        }

        let resolved = URL(fileURLWithPath: rawPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AgentPipelineRuntimeError.worktreeUnavailable(rawPath)
        }
        return resolved.path
    }

    nonisolated private static func taskQueueFailureSummary(
        item: TaskQueueItem,
        error: Error
    ) -> AgentPipelineRunSummary {
        let now = Date()
        let message = String(describing: error)
        return AgentPipelineRunSummary(
            pipelineID: item.pipeline.id,
            status: .failed,
            stepResults: item.pipeline.steps.map { step in
                AgentPipelineStepResult(
                    stepID: step.id,
                    status: .failed,
                    output: nil,
                    error: message,
                    startedAt: nil,
                    finishedAt: now
                )
            },
            startedAt: now,
            finishedAt: now
        )
    }
}
