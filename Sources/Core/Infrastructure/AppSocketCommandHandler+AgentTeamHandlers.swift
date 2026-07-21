// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+AgentTeamHandlers.swift - Local agent team CLI bridge.

import Foundation

extension AppSocketCommandHandler {
    func handleAgentTeam(kind: String, request: SocketRequest) -> SocketResponse {
        let params = request.params ?? [:]
        if let validationError = agentTeamValidationError(kind: kind, params: params) {
            return .failure(id: request.id, error: validationError)
        }
        guard let provider = agentTeamCLIProvider else {
            return .failure(id: request.id, error: "Agent teams not available")
        }
        let result = provider(kind, params)
        guard result.success else {
            return .failure(id: request.id, error: result.data["error"] ?? "Agent team command failed")
        }
        return .ok(id: request.id, data: result.data)
    }

    private func agentTeamValidationError(
        kind: String,
        params: [String: String]
    ) -> String? {
        func unexpectedParameter(allowed: Set<String>) -> String? {
            params.keys.sorted().first(where: { !allowed.contains($0) })
                .map { "Unsupported parameter for agent team \(kind): \($0)" }
        }

        switch kind {
        case "launch":
            if params["config"] != nil {
                return "Agent team config files are not supported by the local socket"
            }
            if let error = unexpectedParameter(
                allowed: ["provider", "teammates", "team-id", "template"]
            ) {
                return error
            }
            let rawProvider = params["provider"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerName = rawProvider.flatMap { $0.isEmpty ? nil : $0 }
                ?? AgentTeamProvider.claudeCode.rawValue
            guard let provider = AgentTeamProvider(rawValue: providerName) else {
                return "Unsupported agent team provider: \(providerName)"
            }

            let templateID = params["template"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let teammates = params["teammates"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if templateID?.isEmpty == false, teammates?.isEmpty == false {
                return "Use either template or teammates, not both"
            }
            if let templateID, !templateID.isEmpty {
                guard AgentTeamTemplateCatalog.builtin.template(id: templateID) != nil else {
                    return "Unknown agent team template: \(AgentTeamConfig.slug(templateID))"
                }
                return nil
            }

            guard let teammates, !teammates.isEmpty else {
                return "Missing required param: teammates"
            }
            do {
                _ = try AgentTeamConfig.from(
                    teammates: teammates,
                    teamID: params["team-id"],
                    provider: provider
                )
                return nil
            } catch {
                return "Invalid agent team configuration: \(error)"
            }

        case "list":
            return unexpectedParameter(allowed: [])

        case "stop":
            if let error = unexpectedParameter(allowed: ["team-id"]) {
                return error
            }
            guard let teamID = params["team-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !teamID.isEmpty else {
                return "Missing required param: team-id"
            }
            return nil

        default:
            return "Unknown agent team action: \(kind)"
        }
    }
}
