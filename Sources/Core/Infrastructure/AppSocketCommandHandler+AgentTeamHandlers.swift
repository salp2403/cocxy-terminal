// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+AgentTeamHandlers.swift - Local agent team CLI bridge.

import Foundation

extension AppSocketCommandHandler {
    func handleAgentTeam(kind: String, request: SocketRequest) -> SocketResponse {
        guard let provider = agentTeamCLIProvider else {
            return .failure(id: request.id, error: "Agent teams not available")
        }
        let result = provider(kind, request.params ?? [:])
        guard result.success else {
            return .failure(id: request.id, error: result.data["error"] ?? "Agent team command failed")
        }
        return .ok(id: request.id, data: result.data)
    }
}
