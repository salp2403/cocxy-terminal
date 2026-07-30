// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+TaskRunHandlers.swift - Parallel task CLI bridge.

import Foundation

extension AppSocketCommandHandler {
    func handleTaskRun(kind: String, request: SocketRequest) -> SocketResponse {
        let params = request.params ?? [:]
        if let validationError = taskRunValidationError(kind: kind, params: params) {
            return .failure(id: request.id, error: validationError)
        }
        guard let provider = taskRunCLIProvider else {
            return .failure(id: request.id, error: "Parallel tasks are not available")
        }
        let result = provider(kind, params)
        guard result.success else {
            return .failure(
                id: request.id,
                error: result.data["error"] ?? "Parallel task command failed"
            )
        }
        return .ok(id: request.id, data: result.data)
    }

    private func taskRunValidationError(
        kind: String,
        params: [String: String]
    ) -> String? {
        func unexpectedParameter(allowed: Set<String>) -> String? {
            params.keys.sorted().first(where: { !allowed.contains($0) })
                .map { "Unsupported parameter for task run \(kind): \($0)" }
        }

        switch kind {
        case "launch":
            if let error = unexpectedParameter(
                allowed: ["prompt", "agents", "count", "base-ref"]
            ) {
                return error
            }
            guard let prompt = params["prompt"] else {
                return "Missing required param: prompt"
            }
            guard let agents = params["agents"] else {
                return "Missing required param: agents"
            }
            let count: Int?
            if let rawCount = params["count"] {
                guard let parsedCount = Int(rawCount) else {
                    return "Task candidate count must be an integer"
                }
                count = parsedCount
            } else {
                count = nil
            }
            do {
                _ = try TaskRunRequest.make(
                    prompt: prompt,
                    agents: agents,
                    count: count,
                    baseRef: params["base-ref"]
                )
                return nil
            } catch {
                return String(describing: error)
            }

        case "list":
            return unexpectedParameter(allowed: [])

        case "promote":
            if let error = unexpectedParameter(allowed: ["run-id", "candidate-id"]) {
                return error
            }
            guard params["run-id"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Missing required param: run-id"
            }
            guard params["candidate-id"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Missing required param: candidate-id"
            }
            return nil

        default:
            return "Unknown task run action: \(kind)"
        }
    }
}
