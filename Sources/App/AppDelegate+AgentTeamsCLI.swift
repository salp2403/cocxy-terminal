// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+AgentTeamsCLI.swift - App-side local agent team CLI commands.

import Foundation

extension AppDelegate {
    nonisolated func handleAgentTeamCLIRequest(
        kind: String,
        params: [String: String]
    ) -> (success: Bool, data: [String: String]) {
        syncOnMainActor {
            switch kind {
            case "launch":
                return self.launchAgentTeam(params: params)
            case "list":
                return self.listAgentTeams()
            case "stop":
                return self.stopAgentTeam(params: params)
            default:
                return (false, ["error": "Unknown agent team action: \(kind)"])
            }
        }
    }

    private func launchAgentTeam(params: [String: String]) -> (Bool, [String: String]) {
        guard let teammates = params["teammates"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !teammates.isEmpty else {
            return (false, ["error": "Missing required param: teammates"])
        }
        guard let controller = focusedWindowController() ?? windowController else {
            return (false, ["error": "No focused window available"])
        }

        do {
            let config = try AgentTeamConfig.from(
                teammates: teammates,
                teamID: params["team-id"],
                provider: .claudeCode
            )
            let launcher = AgentTeamLauncher(paneLauncher: controller)
            let result = try launcher.launch(config: config)
            activeAgentTeamCoordinators[config.id] = AgentTeamCoordinator(config: config)
            try? AgentTeamPersistence().save(config)

            var data: [String: String] = [
                "status": "launched",
                "team-id": result.teamID,
                "provider": config.provider.rawValue,
                "teammates": "\(result.launchedCount)",
                "notifications-isolated": "\(config.notificationsIsolated)",
            ]
            for (index, teammateID) in result.teammateIDs.enumerated() {
                data["teammate_\(index)"] = teammateID
            }
            return (true, data)
        } catch {
            return (false, ["error": "Failed to launch agent team: \(error)"])
        }
    }

    private func listAgentTeams() -> (Bool, [String: String]) {
        var data: [String: String] = [
            "status": "listed",
            "teams": "\(activeAgentTeamCoordinators.count)",
        ]
        for (index, coordinator) in activeAgentTeamCoordinators.values.sorted(by: { $0.config.id < $1.config.id }).enumerated() {
            data["team_\(index)_id"] = coordinator.config.id
            data["team_\(index)_teammates"] = "\(coordinator.config.teammates.count)"
        }
        return (true, data)
    }

    private func stopAgentTeam(params: [String: String]) -> (Bool, [String: String]) {
        guard let rawTeamID = params["team-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTeamID.isEmpty else {
            return (false, ["error": "Missing required param: team-id"])
        }
        let teamID = AgentTeamConfig.slug(rawTeamID)
        guard activeAgentTeamCoordinators.removeValue(forKey: teamID) != nil else {
            return (false, ["error": "Agent team not found: \(teamID)"])
        }

        for controller in allWindowControllers {
            controller.removeSubagentPanels(forSession: teamID)
        }

        return (true, [
            "status": "stopped",
            "team-id": teamID,
        ])
    }
}
