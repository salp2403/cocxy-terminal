// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamViews.swift - Real terminal surfaces for local agent teams.

import Foundation

struct AgentTeamTerminalContext: Sendable, Equatable {
    let teamID: String
    let teammateID: String
}

enum AgentTeamTerminalEndReason: Sendable, Equatable {
    case processExited
    case tabClosed
}

struct AgentTeamTerminalEnd: Sendable, Equatable {
    let context: AgentTeamTerminalContext
    let tabID: TabID
    let remainingTabCount: Int
    let reason: AgentTeamTerminalEndReason
}

extension MainWindowController: AgentTeamPaneLaunching {
    private static let multilinePromptReadyAttempts = 150
    private static let multilinePromptReadyDelay = Duration.milliseconds(100)

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
        targetTabID: UUID?,
        excludesTaskQueueLifecycleEvents: Bool = false
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
            terminalEnginePreference: .inProcess,
            triggersTaskQueueLifecycleEvents: !excludesTaskQueueLifecycleEvents
        )
        let title = "\(launchSpec.teammateName) - \(launchSpec.provider.displayName)"
        tabManager.renameTab(id: tabID, newTitle: title)

        guard let surfaceID = tabSurfaceMap[tabID] else {
            performCloseTab(tabID)
            return nil
        }

        let teamID = AgentTeamConfig.slug(launchSpec.teamID)
        agentTeamTabIDsByTeamID[teamID, default: []].insert(tabID)
        agentTeamTabContextByTabID[tabID] = AgentTeamTerminalContext(
            teamID: teamID,
            teammateID: launchSpec.teammateID
        )
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
            agentTeamTabContextByTabID.removeValue(forKey: tabID)
            if tabManager.tab(for: tabID) != nil {
                performCloseTab(
                    tabID,
                    worktreeClosePolicyOverride: worktreeClosePolicyOverride
                )
            }
        }
        removeSubagentPanels(forSession: normalizedTeamID)
    }

    @discardableResult
    func unregisterAgentTeamTab(
        _ tabID: TabID,
        reason: AgentTeamTerminalEndReason
    ) -> AgentTeamTerminalEnd? {
        guard let context = agentTeamTabContextByTabID.removeValue(forKey: tabID) else {
            return nil
        }
        agentTeamTabIDsByTeamID[context.teamID]?.remove(tabID)
        let remainingTabCount = agentTeamTabIDsByTeamID[context.teamID]?.count ?? 0
        if remainingTabCount == 0 {
            agentTeamTabIDsByTeamID.removeValue(forKey: context.teamID)
        }
        return AgentTeamTerminalEnd(
            context: context,
            tabID: tabID,
            remainingTabCount: remainingTabCount,
            reason: reason
        )
    }

    func notifyAgentTeamTerminalEnded(_ terminalEnd: AgentTeamTerminalEnd) {
        DispatchQueue.main.async { [weak self] in
            self?.onAgentTeamTerminalEnded?(terminalEnd)
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
        guard let prompt,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let normalizedPrompt = CocxyCoreView.normalizedTerminalPasteText(prompt)
        guard !normalizedPrompt.isEmpty else { return }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            let requiresBracketedPaste = normalizedPrompt.contains("\n")
            for attempt in 0..<Self.multilinePromptReadyAttempts {
                guard let self,
                      self.agentTeamTabIDsByTeamID[teamID]?.contains(tabID) == true,
                      let surfaceID = self.tabSurfaceMap[tabID] else {
                    return
                }
                if !requiresBracketedPaste {
                    self.terminalEngine(for: surfaceID).sendText(
                        Self.agentTeamPromptPayload(
                            normalizedPrompt,
                            usesBracketedPaste: false
                        ),
                        to: surfaceID
                    )
                    return
                }
                if let bridge = self.cocxyCoreBridge(forSurface: surfaceID),
                   bridge.modeDiagnostics(for: surfaceID)?.bracketedPasteMode == true {
                    bridge.sendText(
                        Self.agentTeamPromptPayload(
                            normalizedPrompt,
                            usesBracketedPaste: true
                        ),
                        to: surfaceID
                    )
                    return
                }
                guard attempt + 1 < Self.multilinePromptReadyAttempts else {
                    self.terminalEngine(for: surfaceID).sendText(
                        Self.agentTeamPromptPayload(
                            normalizedPrompt,
                            usesBracketedPaste: false
                        ),
                        to: surfaceID
                    )
                    return
                }
                try? await Task.sleep(for: Self.multilinePromptReadyDelay)
            }
        }
    }

    nonisolated static func agentTeamPromptPayload(
        _ normalizedPrompt: String,
        usesBracketedPaste: Bool
    ) -> String {
        if usesBracketedPaste {
            return "\u{1B}[200~" + normalizedPrompt + "\u{1B}[201~\r"
        }
        guard normalizedPrompt.contains("\n") else {
            return normalizedPrompt + "\r"
        }
        let encoded = normalizedPrompt
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "Task context with encoded newlines: " + encoded + "\r"
    }
}
