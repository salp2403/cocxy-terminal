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
    let exitCode: Int32?
}

extension MainWindowController: AgentTeamPaneLaunching {
    private static let promptReadyAttempts = 150
    private static let promptReadyDelay = Duration.milliseconds(100)
    private static let promptFinalRetryDelay = Duration.milliseconds(250)

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
        reason: AgentTeamTerminalEndReason,
        exitCode: Int32? = nil
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
            reason: reason,
            exitCode: exitCode
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
            guard let self else { return }
            try? await Task.sleep(for: self.agentTeamPromptMinimumDelay)
            guard !Task.isCancelled else { return }
            for attempt in 0..<Self.promptReadyAttempts {
                guard let surfaceID = self.activeAgentTeamPromptSurface(
                        teamID: teamID,
                        tabID: tabID
                      ) else {
                    return
                }
                let readiness = self.agentTeamPromptReadiness(for: surfaceID)
                if readiness.isReady {
                    self.terminalEngine(for: surfaceID).sendText(
                        Self.agentTeamPromptPayload(
                            normalizedPrompt,
                            usesBracketedPaste: readiness.usesBracketedPaste
                        ),
                        to: surfaceID
                    )
                    return
                }
                guard attempt + 1 < Self.promptReadyAttempts else {
                    break
                }
                try? await Task.sleep(for: Self.promptReadyDelay)
            }

            try? await Task.sleep(for: Self.promptFinalRetryDelay)
            guard let surfaceID = self.activeAgentTeamPromptSurface(
                    teamID: teamID,
                    tabID: tabID
                  ) else {
                return
            }
            let finalReadiness = self.agentTeamPromptReadiness(for: surfaceID)
            self.terminalEngine(for: surfaceID).sendText(
                Self.agentTeamPromptPayload(
                    normalizedPrompt,
                    usesBracketedPaste: finalReadiness.usesBracketedPaste
                ),
                to: surfaceID
            )
        }
    }

    private func activeAgentTeamPromptSurface(
        teamID: String,
        tabID: TabID
    ) -> SurfaceID? {
        guard agentTeamTabIDsByTeamID[teamID]?.contains(tabID) == true else {
            return nil
        }
        return tabSurfaceMap[tabID]
    }

    private func agentTeamPromptReadiness(
        for surfaceID: SurfaceID
    ) -> (isReady: Bool, usesBracketedPaste: Bool) {
        let usesBracketedPaste = cocxyCoreBridge(forSurface: surfaceID)?
            .modeDiagnostics(for: surfaceID)?
            .bracketedPasteMode == true
        let detectedPrompt = injectedPerSurfaceStore?
            .state(for: surfaceID)
            .agentState == .waitingInput
        let isReady = agentTeamPromptReadinessOverride?(surfaceID)
            ?? (usesBracketedPaste || detectedPrompt)
        return (isReady, usesBracketedPaste)
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
