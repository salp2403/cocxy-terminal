// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+ProjectHandlers.swift - Project CLI validation and routing.

import Foundation

extension AppSocketCommandHandler {
    static func projectKind(_ command: CLICommandName) -> String {
        switch command {
        case .projectOpen: return "open"
        case .projectList: return "list"
        case .projectPin: return "pin"
        case .projectUnpin: return "unpin"
        case .projectAlias: return "alias"
        case .projectForget: return "forget"
        case .projectClone: return "clone"
        case .projectTasks: return "tasks"
        default: preconditionFailure("Project command routing drifted")
        }
    }

    func handleProject(kind: String, request: SocketRequest) -> SocketResponse {
        let params = request.params ?? [:]
        if let error = projectValidationError(kind: kind, params: params) {
            return .failure(id: request.id, error: error)
        }
        guard let projectCLIProvider else {
            return .failure(id: request.id, error: "Project commands are unavailable")
        }
        let result = projectCLIProvider(kind, params)
        guard result.success else {
            return .failure(
                id: request.id,
                error: result.data["error"] ?? "Project command failed"
            )
        }
        return .ok(id: request.id, data: result.data)
    }

    private func projectValidationError(
        kind: String,
        params: [String: String]
    ) -> String? {
        let allowed: Set<String>
        let required: Set<String>
        switch kind {
        case "open":
            allowed = ["path"]
            required = allowed
        case "list":
            allowed = []
            required = []
        case "pin", "unpin", "forget":
            allowed = ["project"]
            required = allowed
        case "alias":
            allowed = ["project", "alias"]
            required = allowed
        case "clone":
            allowed = ["remote", "parent"]
            required = allowed
        case "tasks":
            allowed = ["project"]
            required = []
        default:
            return "Unknown project action: \(kind)"
        }

        if let key = params.keys.sorted().first(where: { !allowed.contains($0) }) {
            return "Unsupported parameter for project \(kind): \(key)"
        }
        for key in required.sorted() {
            guard params[key]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return "Missing required param: \(key)"
            }
        }
        if let alias = params["alias"],
           AuroraWorkspacePlanner.normalizedTitle(alias) == nil {
            return "Project alias cannot be empty"
        }
        if let remote = params["remote"] {
            do {
                _ = try ProjectCloneService.validatedRemote(remote)
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }
}
