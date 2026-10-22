// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+TaskHandoffHandlers.swift - Bounded task handoff CLI bridge.

import CocxyShared
import Foundation

extension AppSocketCommandHandler {
    func handleTaskHandoff(kind: String, request: SocketRequest) -> SocketResponse {
        let params = request.params ?? [:]
        if let validationError = taskHandoffValidationError(kind: kind, params: params) {
            return .failure(id: request.id, error: validationError)
        }
        guard let provider = taskHandoffCLIProvider else {
            return .failure(id: request.id, error: "Task handoff is not available")
        }
        let result = provider(kind, params)
        guard result.success else {
            return .failure(
                id: request.id,
                error: result.data["error"] ?? "Task handoff command failed"
            )
        }
        return .ok(id: request.id, data: result.data)
    }

    private func taskHandoffValidationError(
        kind: String,
        params: [String: String]
    ) -> String? {
        func unexpectedParameter(allowed: Set<String>) -> String? {
            params.keys.sorted().first(where: { !allowed.contains($0) })
                .map { "Unsupported parameter for handoff \(kind): \($0)" }
        }

        switch kind {
        case "export":
            if let error = unexpectedParameter(allowed: ["tabId", "limit"]) {
                return error
            }
            guard let rawTabID = params["tabId"], UUID(uuidString: rawTabID) != nil else {
                return "Missing or invalid required param: tabId"
            }
            guard let rawLimit = params["limit"],
                  let limit = Int(rawLimit),
                  (1...CocxyTaskHandoffWireContract.maximumBlockLimit).contains(limit) else {
                return "Handoff block limit must be between 1 and "
                    + "\(CocxyTaskHandoffWireContract.maximumBlockLimit)"
            }
            return nil

        case "import":
            if let error = unexpectedParameter(allowed: ["agent", "artifact"]) {
                return error
            }
            guard params["agent"]?
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Missing required param: agent"
            }
            guard let artifact = params["artifact"],
                  !artifact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "Missing required param: artifact"
            }
            guard artifact.utf8.count <= CocxyTaskHandoffWireContract.maximumArtifactBytes else {
                return "Handoff artifact exceeds the "
                    + "\(CocxyTaskHandoffWireContract.maximumArtifactBytes)-byte limit"
            }
            guard !artifact.contains("\0") else {
                return "Handoff artifact cannot contain NUL bytes"
            }
            return nil

        default:
            return "Unknown task handoff action: \(kind)"
        }
    }
}
