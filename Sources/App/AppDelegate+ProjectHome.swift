// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+ProjectHome.swift - App-scoped project home navigation and team launch.

import Foundation

extension AppDelegate {
    @discardableResult
    func showProjectHome(_ projectID: ProjectID) throws -> TabID {
        let root = URL(fileURLWithPath: projectID.rawValue, isDirectory: true)
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL

        for controller in allWindowControllers {
            for tab in controller.tabManager.tabs {
                let splitManager = controller.tabSplitCoordinator.splitManager(for: tab.id)
                let hasHome = splitManager.panelTypes.values.contains { info in
                    info.type == .projectHome
                        && info.filePath?.resolvingSymlinksInPath().standardizedFileURL
                            == canonicalRoot
                }
                guard hasHome else { continue }
                if let windowTabRouter {
                    windowTabRouter.activateTab(id: tab.id)
                } else {
                    _ = controller.focusTab(id: tab.id)
                }
                guard controller.openProjectHome(projectRoot: canonicalRoot, in: tab.id) else {
                    throw ProjectActivationError.projectHomeUnavailable
                }
                return tab.id
            }
        }

        let tabID = try activateProject(projectID)
        guard let controller = controllerContainingTab(tabID) else {
            throw ProjectActivationError.noWindow
        }
        if controller.openProjectHome(projectRoot: canonicalRoot, in: tabID) {
            return tabID
        }

        let dedicatedTabID = controller.createTab(workingDirectory: canonicalRoot)
        _ = controller.focusTab(id: dedicatedTabID)
        guard controller.openProjectHome(projectRoot: canonicalRoot, in: dedicatedTabID) else {
            throw ProjectActivationError.projectHomeUnavailable
        }
        return dedicatedTabID
    }

    func launchProjectTeam(
        _ request: ProjectTeamLaunchRequest,
        projectRoot: URL
    ) async throws {
        guard await agentTeamProviderAdapterRegistry.prepareExecutableForLaunch(
            for: request.provider
        ) != nil else {
            throw ProjectHomeActionFailure.providerUnavailable
        }

        let projectID = projectResolver.resolveProject(for: projectRoot).groupingID
        let tabID = try activateProject(projectID)
        guard let controller = controllerContainingTab(tabID),
              let tab = controller.tabManager.tab(for: tabID),
              projectResolver.resolveProject(for: tab.workingDirectory).groupingID == projectID else {
            throw ProjectHomeActionFailure.projectSessionChanged
        }

        var usedIDs: [String: Int] = [:]
        let teammates = request.teammateNames.map { name -> AgentTeammateConfig in
            let baseID = "\(request.teamID)-\(AgentTeamConfig.slug(name))"
            let sequence = usedIDs[baseID, default: 0] + 1
            usedIDs[baseID] = sequence
            return AgentTeammateConfig(
                id: sequence == 1 ? baseID : "\(baseID)-\(sequence)",
                name: name,
                prompt: request.prompt
            )
        }
        let config = AgentTeamConfig(
            id: request.teamID,
            provider: request.provider,
            teammates: teammates
        )
        do {
            _ = try launchAgentTeamConfig(
                config,
                controller: controller,
                targetTabID: tabID.rawValue,
                workingDirectory: projectID.rawValue
            )
        } catch AgentTeamError.alreadyRunning {
            throw ProjectHomeActionFailure.teamAlreadyRunning
        } catch {
            throw ProjectHomeActionFailure.teamLaunchFailed
        }
    }
}
