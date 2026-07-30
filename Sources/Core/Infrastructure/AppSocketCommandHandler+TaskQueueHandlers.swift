// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+TaskQueueHandlers.swift - Persistent task queue CLI bridge.

import Foundation

extension AppSocketCommandHandler {
    func handleTaskQueue(kind: String, request: SocketRequest) -> SocketResponse {
        let params = request.params ?? [:]
        if let validationError = taskQueueValidationError(kind: kind, params: params) {
            return .failure(id: request.id, error: validationError)
        }
        guard let provider = taskQueueCLIProvider else {
            return .failure(id: request.id, error: "Task queue is not available")
        }
        let result = provider(kind, params)
        guard result.success else {
            return .failure(
                id: request.id,
                error: result.data["error"] ?? "Task queue command failed"
            )
        }
        return .ok(id: request.id, data: result.data)
    }

    private func taskQueueValidationError(
        kind: String,
        params: [String: String]
    ) -> String? {
        func unexpectedParameter(allowed: Set<String>) -> String? {
            params.keys.sorted().first(where: { !allowed.contains($0) })
                .map { "Unsupported parameter for task queue \(kind): \($0)" }
        }
        func integerError(
            key: String,
            default defaultValue: Int,
            range: ClosedRange<Int>
        ) -> String? {
            guard let rawValue = params[key] else {
                return range.contains(defaultValue) ? nil : "Invalid default for \(key)"
            }
            guard let value = Int(rawValue), range.contains(value) else {
                return "\(key) must be an integer from \(range.lowerBound) through \(range.upperBound)"
            }
            return nil
        }

        switch kind {
        case "enqueue":
            if let error = unexpectedParameter(allowed: [
                "task-id", "input", "provider", "prompt", "cwd", "trigger",
                "cron", "timezone", "event", "retries", "concurrency",
            ]) {
                return error
            }
            guard let taskID = params["task-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskID.isEmpty else {
                return "Missing required param: task-id"
            }
            guard TaskQueueSocketAuthority.details(
                operation: "enqueue",
                params: params
            ) != nil else {
                return "Invalid task-id"
            }
            guard params["cwd"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Missing required param: cwd"
            }
            let hasInput = params["input"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasPrompt = params["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasInput != hasPrompt else {
                return "Use exactly one pipeline input or inline prompt"
            }
            if hasInput, params["provider"] != nil {
                return "Pipeline input defines each step provider"
            }
            if hasPrompt {
                let providerName = params["provider"] ?? AgentTeamProvider.claudeCode.rawValue
                guard let provider = AgentTeamProvider.resolve(named: providerName) else {
                    return "Unsupported agent provider: \(providerName)"
                }
                do {
                    _ = try AgentPipeline(
                        id: taskID,
                        steps: [AgentPipelineStep(
                            id: "run",
                            provider: provider,
                            prompt: params["prompt"] ?? ""
                        )]
                    )
                } catch {
                    return String(describing: error)
                }
            }
            if let error = integerError(key: "retries", default: 0, range: 0...5) {
                return error
            }
            if let error = integerError(key: "concurrency", default: 2, range: 1...8) {
                return error
            }
            do {
                _ = try Self.taskQueueTrigger(params: params)
            } catch {
                return String(describing: error)
            }
            return nil

        case "list":
            if let error = unexpectedParameter(allowed: ["limit", "offset"]) {
                return error
            }
            if let error = integerError(key: "limit", default: 50, range: 1...100) {
                return error
            }
            let rawOffset = params["offset"] ?? "0"
            guard let offset = Int(rawOffset),
                  offset >= 0 else {
                return "offset must be a non-negative integer"
            }
            return nil

        case "cancel":
            if let error = unexpectedParameter(allowed: ["task-id"]) {
                return error
            }
            guard params["task-id"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Missing required param: task-id"
            }
            guard TaskQueueSocketAuthority.details(
                operation: "cancel",
                params: params
            ) != nil else {
                return "Invalid task-id"
            }
            return nil

        default:
            return "Unknown task queue action: \(kind)"
        }
    }

    static func taskQueueTrigger(params: [String: String]) throws -> TaskQueueTrigger {
        switch params["trigger"] ?? "manual" {
        case "manual":
            guard params["cron"] == nil,
                  params["timezone"] == nil,
                  params["event"] == nil else {
                throw TaskQueueSocketRequestError.inconsistentTrigger("manual")
            }
            return .manual
        case "cron":
            guard let expression = params["cron"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !expression.isEmpty,
                  params["event"] == nil else {
                throw TaskQueueSocketRequestError.inconsistentTrigger("cron")
            }
            return .cron(try CronSchedule(
                expression: expression,
                timeZoneIdentifier: params["timezone"] ?? TimeZone.current.identifier
            ))
        case "on-event":
            guard let eventName = params["event"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let event = PluginEvent(rawValue: eventName),
                  params["cron"] == nil,
                  params["timezone"] == nil else {
                throw TaskQueueSocketRequestError.inconsistentTrigger("on-event")
            }
            return try TaskQueueTrigger.eventTrigger(event)
        default:
            throw TaskQueueSocketRequestError.invalidTrigger(params["trigger"] ?? "")
        }
    }
}

private enum TaskQueueSocketRequestError: Error, CustomStringConvertible {
    case invalidTrigger(String)
    case inconsistentTrigger(String)

    var description: String {
        switch self {
        case .invalidTrigger(let trigger):
            return "Unknown task trigger: \(trigger)"
        case .inconsistentTrigger(let trigger):
            return "Task trigger parameters are inconsistent for \(trigger)"
        }
    }
}
