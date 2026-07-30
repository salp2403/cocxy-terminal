// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TaskQueueCLI.swift - App-side persistent task queue CLI commands.

import Foundation

extension AppDelegate {
    nonisolated func handleTaskQueueCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext? = nil
    ) -> (success: Bool, data: [String: String]) {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedBox<(Bool, [String: String])>((
            false,
            ["error": "Task queue dispatch did not complete"]
        ))

        Task.detached { [self] in
            let value = await performTaskQueueCLIRequest(
                kind: kind,
                params: params,
                approvedContext: approvedContext
            )
            result.withValue { $0 = value }
            semaphore.signal()
        }
        semaphore.wait()
        return result.withValue { $0 }
    }

    nonisolated private func performTaskQueueCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext?
    ) async -> (Bool, [String: String]) {
        let queue = await MainActor.run { taskQueueIsReady ? taskQueue : nil }
        guard let queue else {
            return (false, ["error": "Task queue is still starting or unavailable"])
        }

        do {
            switch kind {
            case "enqueue":
                guard let approvedContext,
                      approvedContext.scope == .localExecution,
                      approvedContext.authorityDetails == TaskQueueSocketAuthority.details(
                        operation: "enqueue",
                        params: params
                      ),
                      let boundParams = approvedContext.bindingLocalResourcePaths(
                        in: params,
                        keys: ["input", "cwd"],
                        requiredScope: .localExecution
                      ) else {
                    return (false, ["error": "Approved task enqueue context is unavailable"])
                }
                let item = try Self.makeTaskQueueItem(
                    params: boundParams,
                    approvedContext: approvedContext
                )
                let enqueued = try await queue.enqueue(item)
                var data: [String: String] = [
                    "status": "enqueued",
                    "task-id": enqueued.id,
                    "pipeline-id": enqueued.pipeline.id,
                    "task-status": enqueued.status.rawValue,
                    "trigger": Self.taskQueueTriggerLabel(enqueued.trigger),
                    "steps": String(enqueued.pipeline.steps.count),
                    "retries": String(enqueued.maximumRetries),
                    "concurrency": String(enqueued.maximumParallelSteps),
                ]
                if let nextRunAt = enqueued.nextRunAt {
                    data["next-run-at"] = Self.taskQueueDateString(nextRunAt)
                }
                return (true, data)

            case "list":
                let limit = Int(params["limit"] ?? "50") ?? 50
                let offset = Int(params["offset"] ?? "0") ?? 0
                let items = await queue.list()
                let page = Array(items.dropFirst(offset).prefix(limit))
                var data: [String: String] = [
                    "status": "listed",
                    "total": String(items.count),
                    "active": String(items.filter { !$0.status.isFinished }.count),
                    "terminal": String(items.filter { $0.status.isFinished }.count),
                    "returned": String(page.count),
                    "offset": String(offset),
                    "has-more": String(offset + page.count < items.count),
                ]
                for (index, item) in page.enumerated() {
                    let prefix = "task_\(index)_"
                    data[prefix + "id"] = item.id
                    data[prefix + "status"] = item.status.rawValue
                    data[prefix + "trigger"] = Self.taskQueueTriggerLabel(item.trigger)
                    data[prefix + "steps"] = String(item.pipeline.steps.count)
                    data[prefix + "retries"] = String(item.maximumRetries)
                    data[prefix + "attempt"] = String(item.retryAttempt)
                    data[prefix + "runs"] = String(item.totalRunCount)
                    data[prefix + "has-error"] = String(item.lastError != nil)
                    if let nextRunAt = item.nextRunAt {
                        data[prefix + "next-run-at"] = Self.taskQueueDateString(nextRunAt)
                    }
                }
                return (true, data)

            case "cancel":
                guard let approvedContext,
                      approvedContext.scope == .localExecution,
                      approvedContext.authorityDetails == TaskQueueSocketAuthority.details(
                        operation: "cancel",
                        params: params
                      ),
                      let taskID = params["task-id"] else {
                    return (false, ["error": "Approved task cancellation context is unavailable"])
                }
                let cancelled = try await queue.cancel(id: taskID)
                return (true, [
                    "status": "cancelled",
                    "task-id": cancelled.id,
                    "task-status": cancelled.status.rawValue,
                ])

            case "rerun", "remove":
                guard let approvedContext,
                      approvedContext.scope == .localExecution,
                      approvedContext.authorityDetails == TaskQueueSocketAuthority.details(
                        operation: kind,
                        params: params
                      ),
                      let taskID = params["task-id"] else {
                    return (false, ["error": "Approved task \(kind) context is unavailable"])
                }
                if kind == "rerun" {
                    let rerun = try await queue.rerun(id: taskID)
                    return (true, [
                        "status": "re-enqueued",
                        "task-id": rerun.id,
                        "task-status": rerun.status.rawValue,
                    ])
                }
                let removed = try await queue.remove(id: taskID)
                return (true, [
                    "status": "removed",
                    "task-id": removed.id,
                    "task-status": removed.status.rawValue,
                ])

            default:
                return (false, ["error": "Unknown task queue action: \(kind)"])
            }
        } catch {
            return (false, ["error": String(describing: error)])
        }
    }

    nonisolated private static func makeTaskQueueItem(
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext
    ) throws -> TaskQueueItem {
        guard let rawTaskID = params["task-id"],
              let rawWorkingDirectory = params["cwd"] else {
            throw TaskQueueCLIRequestError.missingApprovedResource
        }
        let workingDirectory = try canonicalTaskQueueWorktree(rawWorkingDirectory)
        guard workingDirectory == approvedContext.workingDirectory else {
            throw TaskQueueCLIRequestError.approvedResourceChanged
        }

        let pipeline: AgentPipeline
        if let inputPath = params["input"] {
            guard approvedContext.localResourcePaths["input"] == inputPath,
                  let expectedDigest = approvedContext.localResourceDigests["input"],
                  let data = SocketPrivilegedCommandSecurity.boundedFileData(
                    at: URL(fileURLWithPath: inputPath)
                  ),
                  SocketPrivilegedCommandSecurity.digest(data: data) == expectedDigest else {
                throw TaskQueueCLIRequestError.approvedResourceChanged
            }
            do {
                pipeline = try JSONDecoder().decode(AgentPipeline.self, from: data)
            } catch {
                throw TaskQueueCLIRequestError.invalidPipeline(String(describing: error))
            }
        } else {
            let providerName = params["provider"] ?? AgentTeamProvider.claudeCode.rawValue
            guard let provider = AgentTeamProvider.resolve(named: providerName),
                  let prompt = params["prompt"] else {
                throw TaskQueueCLIRequestError.invalidInlineStep
            }
            pipeline = try AgentPipeline(
                id: rawTaskID,
                steps: [AgentPipelineStep(
                    id: "run",
                    provider: provider,
                    prompt: prompt,
                    worktree: workingDirectory
                )]
            )
        }

        let normalizedPipeline = try normalizedTaskQueuePipeline(
            pipeline,
            defaultWorktree: workingDirectory
        )
        let trigger = try AppSocketCommandHandler.taskQueueTrigger(params: params)
        return try TaskQueueItem(
            id: rawTaskID,
            pipeline: normalizedPipeline,
            trigger: trigger,
            maximumRetries: Int(params["retries"] ?? "0") ?? 0,
            maximumParallelSteps: Int(params["concurrency"] ?? "2") ?? 2
        )
    }

    nonisolated static func normalizedTaskQueuePipeline(
        _ pipeline: AgentPipeline,
        defaultWorktree: String
    ) throws -> AgentPipeline {
        let baseURL = URL(fileURLWithPath: defaultWorktree, isDirectory: true)
        let steps = try pipeline.steps.map { step in
            let rawPath = step.worktree ?? defaultWorktree
            let expanded = (rawPath as NSString).expandingTildeInPath
            let candidate: URL
            if NSString(string: expanded).isAbsolutePath {
                candidate = URL(fileURLWithPath: expanded, isDirectory: true)
            } else {
                candidate = baseURL.appendingPathComponent(expanded, isDirectory: true)
            }
            let worktree = try canonicalTaskQueueWorktree(candidate.path)
            return AgentPipelineStep(
                id: step.id,
                provider: step.provider,
                prompt: step.prompt,
                worktree: worktree,
                dependsOn: step.dependsOn
            )
        }
        return try AgentPipeline(id: pipeline.id, name: pipeline.name, steps: steps)
    }

    nonisolated private static func taskQueueTriggerLabel(_ trigger: TaskQueueTrigger) -> String {
        switch trigger {
        case .manual:
            return "manual"
        case .cron:
            return "cron"
        case .event(let event):
            return "on-event:\(event.rawValue)"
        }
    }

    nonisolated private static func taskQueueDateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private enum TaskQueueCLIRequestError: Error, CustomStringConvertible {
    case missingApprovedResource
    case approvedResourceChanged
    case invalidPipeline(String)
    case invalidInlineStep

    var description: String {
        switch self {
        case .missingApprovedResource:
            return "Approved task queue resource is missing"
        case .approvedResourceChanged:
            return "Approved task queue resource changed before execution"
        case .invalidPipeline(let reason):
            return "Invalid agent pipeline JSON: \(reason)"
        case .invalidInlineStep:
            return "Inline task provider or prompt is invalid"
        }
    }
}
