// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+AgentTeamsCLI.swift - App-side local agent team CLI commands.

import Foundation

@MainActor
struct AgentTeamAppLaunchResult {
    let launchResult: AgentTeamLaunchResult
    let tabIDs: [TabID]
}

extension AppDelegate {
    nonisolated func handleAgentTeamCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext? = nil
    ) -> (success: Bool, data: [String: String]) {
        syncOnMainActor {
            switch kind {
            case "launch":
                guard let approvedContext,
                      approvedContext.scope == .localExecution else {
                    return (false, ["error": "Approved agent team launch context is unavailable"])
                }
                return self.launchAgentTeam(
                    params: params,
                    approvedContext: approvedContext
                )
            case "list":
                return self.listAgentTeams()
            case "stop":
                guard approvedContext?.scope == .localExecution else {
                    return (false, ["error": "Approved agent team stop context is unavailable"])
                }
                return self.stopAgentTeam(params: params)
            default:
                return (false, ["error": "Unknown agent team action: \(kind)"])
            }
        }
    }

    private func launchAgentTeam(
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext
    ) -> (Bool, [String: String]) {
        guard let rawTabID = approvedContext.tabID,
              let controller = privilegedSocketController(for: approvedContext),
              let tab = controller.tabManager.tab(for: TabID(rawValue: rawTabID)),
              (tab.worktreeRoot ?? tab.workingDirectory)
                .resolvingSymlinksInPath()
                .standardizedFileURL.path == approvedContext.workingDirectory else {
            return (false, ["error": "Approved agent team target is no longer available"])
        }
        let rawProvider = params["provider"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerName: String
        if let rawProvider, !rawProvider.isEmpty {
            providerName = rawProvider
        } else {
            providerName = AgentTeamProvider.claudeCode.rawValue
        }
        guard let provider = AgentTeamProvider(rawValue: providerName) else {
            return (false, ["error": "Unsupported agent team provider: \(providerName)"])
        }

        do {
            let config: AgentTeamConfig
            if let templateID = params["template"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !templateID.isEmpty {
                config = try AgentTeamTemplateCatalog.builtin.makeConfig(
                    templateID: templateID,
                    teamID: params["team-id"],
                    provider: provider
                )
            } else if let teammates = params["teammates"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !teammates.isEmpty {
                config = try AgentTeamConfig.from(
                    teammates: teammates,
                    teamID: params["team-id"],
                    provider: provider
                )
            } else {
                return (false, ["error": "Missing required param: teammates"])
            }
            guard activeAgentTeamCoordinators[config.id] == nil else {
                return (false, ["error": "Agent team is already running: \(config.id)"])
            }
            let appResult = try launchAgentTeamConfig(
                config,
                controller: controller,
                targetTabID: rawTabID,
                workingDirectory: approvedContext.workingDirectory
            )
            let result = appResult.launchResult

            var data: [String: String] = [
                "status": "launched",
                "team-id": result.teamID,
                "provider": config.provider.rawValue,
                "teammates": "\(result.launchedCount)",
                "launch-specs": "\(result.launchSpecs.count)",
                "surfaces": "\(result.launchedCount)",
                "provider-preflight": "passed",
                "runtime-handoff": "provider-process",
                "notifications-isolated": "\(config.notificationsIsolated)",
            ]
            if let templateID = params["template"], !templateID.isEmpty {
                data["template"] = templateID
            }
            for (index, teammateID) in result.teammateIDs.enumerated() {
                data["teammate_\(index)"] = teammateID
            }
            for (index, tabID) in appResult.tabIDs.enumerated() {
                data["tab_\(index)_id"] = tabID.rawValue.uuidString
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
            if let run = activeAgentTeamRuns[coordinator.config.id] {
                data["team_\(index)_graph_nodes"] = "\(run.graph.nodes.count)"
                data["team_\(index)_review_requests"] = "\(run.reviewBeforeShipRequests.count)"
            }
        }
        return (true, data)
    }

    private func stopAgentTeam(params: [String: String]) -> (Bool, [String: String]) {
        guard let rawTeamID = params["team-id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTeamID.isEmpty else {
            return (false, ["error": "Missing required param: team-id"])
        }
        let teamID = AgentTeamConfig.slug(rawTeamID)
        guard activeAgentTeamCoordinators[teamID] != nil else {
            return (false, ["error": "Agent team not found: \(teamID)"])
        }
        let taskRunID = taskRunIDByTeamID[teamID]
        _ = removeAgentTeamRuntime(
            teamID: teamID,
            worktreeClosePolicyOverride: taskRunID == nil ? nil : .keep,
            removeDashboardRow: taskRunID == nil
        )
        if let taskRunID {
            markTaskRunCandidateStopped(
                taskRunID: taskRunID,
                teamID: teamID,
                reason: "Provider process stopped"
            )
        }

        return (true, [
            "status": "stopped",
            "team-id": teamID,
        ])
    }

    func applyAgentTeamHookEvent(_ event: HookEvent) {
        let candidateTeamIDs = Array(Set([
            event.teamID.map(AgentTeamConfig.slug),
            event.sessionId,
        ].compactMap { $0 }))

        for teamID in candidateTeamIDs {
            guard var run = activeAgentTeamRuns[teamID] else { continue }
            do {
                let result = try run.apply(event)
                guard result.accepted else { continue }
                activeAgentTeamRuns[teamID] = run
                activeAgentTeamCoordinators[teamID] = run.coordinator
                if let taskRunID = taskRunIDByTeamID[teamID] {
                    updateTaskRunCandidate(
                        taskRunID: taskRunID,
                        teamID: teamID,
                        from: run
                    )
                } else {
                    let tabID = agentDashboardViewModel?.tabIdForSession(teamID)
                        ?? focusedWindowController()?.visibleTabID?.rawValue
                        ?? focusedWindowController()?.tabManager.activeTabID?.rawValue
                    syncAgentTeamRunToDashboard(run, tabID: tabID)
                    try? AgentTeamSessionSnapshotStore().save(run.snapshot())
                }
                if let request = result.reviewBeforeShipRequest {
                    requestAgentTeamReviewBeforeShip(request)
                }
            } catch {
                continue
            }
        }
    }

    @MainActor
    func launchAgentTeamConfig(
        _ config: AgentTeamConfig,
        controller: MainWindowController,
        targetTabID: UUID,
        workingDirectory: String,
        persist: Bool = true,
        syncDashboard: Bool = true
    ) throws -> AgentTeamAppLaunchResult {
        guard activeAgentTeamCoordinators[config.id] == nil else {
            throw AgentTeamError.alreadyRunning(config.id)
        }

        let paneLauncher = SocketBoundAgentTeamPaneLauncher(
            controller: controller,
            targetTabID: targetTabID
        )
        let launcher = AgentTeamLauncher(
            paneLauncher: paneLauncher,
            launchProfileProvider: { _ in
                AgentTeamLaunchProfile(workingDirectory: workingDirectory)
            }
        )
        let result = try launcher.launch(config: config)
        guard paneLauncher.launchedTabIDs.count == result.launchedCount else {
            paneLauncher.closeAgentTeamPanes(teamID: config.id)
            throw AgentTeamError.paneLaunchFailed(config.id)
        }

        activeAgentTeamCoordinators[config.id] = AgentTeamCoordinator(config: config)
        activeAgentTeamRuns[config.id] = AgentTeamRunState(
            config: config,
            launchSpecs: result.launchSpecs
        )
        if syncDashboard, let run = activeAgentTeamRuns[config.id] {
            syncAgentTeamRunToDashboard(
                run,
                tabID: paneLauncher.launchedTabIDs.first?.rawValue ?? targetTabID
            )
        }
        if persist {
            try? AgentTeamPersistence().save(config)
            if let snapshot = activeAgentTeamRuns[config.id]?.snapshot() {
                try? AgentTeamSessionSnapshotStore().save(snapshot)
            }
        }

        return AgentTeamAppLaunchResult(
            launchResult: result,
            tabIDs: paneLauncher.launchedTabIDs
        )
    }

    @MainActor
    @discardableResult
    func removeAgentTeamRuntime(
        teamID rawTeamID: String,
        worktreeClosePolicyOverride: WorktreeOnClose?,
        removeDashboardRow: Bool
    ) -> Bool {
        let teamID = AgentTeamConfig.slug(rawTeamID)
        let removedCoordinator = activeAgentTeamCoordinators.removeValue(forKey: teamID)
        let removedRun = activeAgentTeamRuns.removeValue(forKey: teamID)
        let existed = removedCoordinator != nil || removedRun != nil
        taskRunIDByTeamID.removeValue(forKey: teamID)

        if removeDashboardRow {
            agentDashboardViewModel?.removeAgentTeamRun(teamID: teamID)
        }
        for controller in allWindowControllers {
            if removeDashboardRow {
                controller.dashboardViewModel?.removeAgentTeamRun(teamID: teamID)
            }
            controller.closeAgentTeamPanes(
                teamID: teamID,
                worktreeClosePolicyOverride: worktreeClosePolicyOverride
            )
        }
        return existed
    }

    private func requestAgentTeamReviewBeforeShip(_ request: AgentTeamReviewBeforeShipRequest) {
        guard !request.touchedFiles.isEmpty else { return }
        let targetControllers: [MainWindowController]
        if let resolved = resolvedControllerAndTab(
            forHookSessionID: request.sessionID,
            cwd: request.workingDirectory
        ) {
            targetControllers = [resolved.controller]
        } else {
            targetControllers = allWindowControllers
        }

        for controller in targetControllers {
            let viewModel = controller.resolveCodeReviewViewModel()
            viewModel.requestReviewSuggestionIfNeeded(key: request.id)
        }
    }

    @MainActor
    private func syncAgentTeamRunToDashboard(_ run: AgentTeamRunState, tabID: UUID?) {
        let resolvedTabID = tabID
            ?? agentDashboardViewModel?.tabIdForSession(run.config.id)
            ?? UUID()
        agentDashboardViewModel?.syncAgentTeamRun(run, tabId: resolvedTabID)
        for controller in allWindowControllers {
            guard controller.dashboardViewModel !== agentDashboardViewModel else { continue }
            controller.dashboardViewModel?.syncAgentTeamRun(run, tabId: resolvedTabID)
        }
    }
}

@MainActor
private final class SocketBoundAgentTeamPaneLauncher: AgentTeamPaneLaunching {
    private weak var controller: MainWindowController?
    private let targetTabID: UUID
    private(set) var launchedTabIDs: [TabID] = []

    init(controller: MainWindowController, targetTabID: UUID) {
        self.controller = controller
        self.targetTabID = targetTabID
    }

    func spawnAgentTeamPane(
        launchSpec: AgentTeamProviderLaunchSpec,
        initialPrompt: String?
    ) -> Bool {
        guard let tabID = controller?.spawnAgentTeamTerminal(
            launchSpec: launchSpec,
            initialPrompt: initialPrompt,
            targetTabID: targetTabID
        ) else {
            return false
        }
        launchedTabIDs.append(tabID)
        return true
    }

    func closeAgentTeamPanes(teamID: String) {
        controller?.closeAgentTeamPanes(teamID: teamID)
    }
}
