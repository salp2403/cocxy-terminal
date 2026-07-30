// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamViews.swift - Real terminal surfaces for local agent teams.

import Foundation

extension MainWindowController: AgentTeamPaneLaunching {
    func spawnAgentTeamPane(launchSpec: AgentTeamProviderLaunchSpec) -> Bool {
        spawnAgentTeamPane(
            launchSpec: launchSpec,
            initialPrompt: nil,
            targetTabID: nil
        )
    }

    func spawnAgentTeamPane(
        launchSpec: AgentTeamProviderLaunchSpec,
        initialPrompt: String?
    ) -> Bool {
        spawnAgentTeamPane(
            launchSpec: launchSpec,
            initialPrompt: initialPrompt,
            targetTabID: nil
        )
    }

    func spawnAgentTeamPane(
        launchSpec: AgentTeamProviderLaunchSpec,
        initialPrompt: String? = nil,
        targetTabID: UUID?
    ) -> Bool {
        spawnAgentTeamTerminal(
            launchSpec: launchSpec,
            initialPrompt: initialPrompt,
            targetTabID: targetTabID
        ) != nil
    }

    @discardableResult
    func spawnAgentTeamTerminal(
        launchSpec: AgentTeamProviderLaunchSpec,
        initialPrompt: String? = nil,
        targetTabID: UUID?
    ) -> TabID? {
        guard let command = AgentTeamLaunchCommand.makeShellCommand(for: launchSpec),
              let workingDirectory = agentTeamWorkingDirectory(
                launchSpec: launchSpec,
                targetTabID: targetTabID
              ) else {
            return nil
        }

        let tabID = createTab(
            workingDirectory: workingDirectory,
            terminalEnginePreference: .inProcess
        )
        let title = "\(launchSpec.teammateName) - \(launchSpec.provider.displayName)"
        tabManager.renameTab(id: tabID, newTitle: title)

        guard let surfaceID = tabSurfaceMap[tabID] else {
            performCloseTab(tabID)
            return nil
        }

        let teamID = AgentTeamConfig.slug(launchSpec.teamID)
        agentTeamTabIDsByTeamID[teamID, default: []].insert(tabID)
        terminalEngine(for: surfaceID).sendText(command + "\r", to: surfaceID)
        scheduleAgentTeamPrompt(
            initialPrompt,
            teamID: teamID,
            tabID: tabID
        )
        refreshTabStrip()
        return tabID
    }

    func closeAgentTeamPanes(teamID: String) {
        closeAgentTeamPanes(
            teamID: teamID,
            worktreeClosePolicyOverride: nil
        )
    }

    func closeAgentTeamPanes(
        teamID: String,
        worktreeClosePolicyOverride: WorktreeOnClose?
    ) {
        let normalizedTeamID = AgentTeamConfig.slug(teamID)
        let tabIDs = agentTeamTabIDsByTeamID.removeValue(forKey: normalizedTeamID) ?? []
        for tabID in tabIDs.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            if tabManager.tab(for: tabID) != nil {
                performCloseTab(
                    tabID,
                    worktreeClosePolicyOverride: worktreeClosePolicyOverride
                )
            }
        }
        removeSubagentPanels(forSession: normalizedTeamID)
    }

    func unregisterAgentTeamTab(_ tabID: TabID) {
        for teamID in Array(agentTeamTabIDsByTeamID.keys) {
            agentTeamTabIDsByTeamID[teamID]?.remove(tabID)
            if agentTeamTabIDsByTeamID[teamID]?.isEmpty == true {
                agentTeamTabIDsByTeamID.removeValue(forKey: teamID)
            }
        }
    }

    private func agentTeamWorkingDirectory(
        launchSpec: AgentTeamProviderLaunchSpec,
        targetTabID: UUID?
    ) -> URL? {
        let directory: URL
        if let path = launchSpec.workingDirectory {
            directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        } else if let targetTabID,
                  let tab = tabManager.tab(for: TabID(rawValue: targetTabID)) {
            directory = (tab.worktreeRoot ?? tab.workingDirectory).standardizedFileURL
        } else {
            directory = (tabManager.activeTab?.worktreeRoot
                ?? tabManager.activeTab?.workingDirectory
                ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return directory
    }

    private func scheduleAgentTeamPrompt(
        _ prompt: String?,
        teamID: String,
        tabID: TabID
    ) {
        guard let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else {
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self,
                  self.agentTeamTabIDsByTeamID[teamID]?.contains(tabID) == true,
                  let surfaceID = self.tabSurfaceMap[tabID] else {
                return
            }
            self.terminalEngine(for: surfaceID).sendText(prompt + "\r", to: surfaceID)
        }
    }
}
