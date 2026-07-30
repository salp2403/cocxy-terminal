// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TaskHandoff.swift - Command palette task handoff flow.

import AppKit
import Foundation

@MainActor
extension MainWindowController {
    func commandPaletteTaskHandoffAction() -> CommandAction {
        CommandAction(
            id: "handoff.passTask",
            name: "Pass This Task To...",
            description: "Continue the active task in another local agent",
            shortcut: nil,
            category: .agent,
            handler: { [weak self] in
                self?.dismissCommandPalette()
                Task { @MainActor in
                    self?.showTaskHandoffProviderPicker()
                }
            }
        )
    }

    func showTaskHandoffProviderPicker() {
        guard let sourceTabID = visibleTabID,
              tabManager.tab(for: sourceTabID) != nil else {
            presentTaskHandoffAlert(
                message: localizedTaskHandoffString(
                    "handoff.error.noSource",
                    fallback: "No active terminal task is available to pass."
                )
            )
            return
        }

        let currentProvider = currentTaskHandoffProvider(sourceTabID: sourceTabID)
        let availableProviders = availableTaskHandoffProviders()
        let actions = taskHandoffProviderActions(
            sourceTabID: sourceTabID,
            currentProvider: currentProvider,
            availableProviders: availableProviders
        )
        guard !actions.isEmpty else {
            presentTaskHandoffAlert(
                message: localizedTaskHandoffString(
                    "handoff.error.noDestination",
                    fallback: "No other supported local agent executable is available."
                )
            )
            return
        }
        showTransientCommandPaletteOverlay(
            engine: StaticCommandPaletteEngine(actions: actions)
        )
    }

    func taskHandoffProviderActions(
        sourceTabID: TabID,
        currentProvider: AgentTeamProvider?,
        availableProviders: [AgentTeamProvider]
    ) -> [CommandAction] {
        let localizer = appLocalizer()
        return TaskHandoffProviderCatalog.destinations(
            currentProvider: currentProvider,
            availableProviders: availableProviders
        ).map { provider in
            let description = String(
                format: localizer.string(
                    "handoff.destination.description",
                    fallback: "Open %@ in a new tab with this task's bounded context"
                ),
                provider.displayName
            )
            return CommandAction(
                id: "handoff.destination.\(provider.rawValue)",
                name: provider.displayName,
                description: description,
                shortcut: nil,
                category: .agent,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.performTaskHandoff(
                            to: provider,
                            sourceTabID: sourceTabID
                        )
                    }
                }
            )
        }
    }

    func currentTaskHandoffProvider(
        sourceTabID: TabID
    ) -> AgentTeamProvider? {
        let focusedSurfaceID: SurfaceID?
        if visibleTabID == sourceTabID {
            focusedSurfaceID = activeTerminalSurfaceView?
                .terminalViewModel?
                .surfaceID
        } else {
            focusedSurfaceID = nil
        }
        let state = SurfaceAgentStateResolver.resolve(
            focusedSurfaceID: focusedSurfaceID,
            primarySurfaceID: tabSurfaceMap[sourceTabID],
            allSurfaceIDs: surfaceIDs(for: sourceTabID),
            store: injectedPerSurfaceStore
        )
        return TaskHandoffProviderCatalog.resolveCurrentProvider(
            detectedAgent: state.detectedAgent
        )
    }

    func availableTaskHandoffProviders(
        executableResolver: AgentTeamExecutableResolver =
            AgentTeamProviderAdapterRegistry.defaultExecutableResolver
    ) -> [AgentTeamProvider] {
        AgentTeamProvider.allCases.filter { provider in
            provider.executableCandidates.contains { candidate in
                executableResolver(candidate) != nil
            }
        }
    }

    private func performTaskHandoff(
        to provider: AgentTeamProvider,
        sourceTabID: TabID
    ) {
        guard let delegate = NSApp.delegate as? AppDelegate else {
            presentTaskHandoffAlert(
                message: localizedTaskHandoffString(
                    "handoff.error.unavailable",
                    fallback: "Task handoff is unavailable in the current app context."
                )
            )
            return
        }

        do {
            let artifact = try delegate.exportTaskHandoffArtifact(
                controller: self,
                tabID: sourceTabID
            )
            let destination = try TaskHandoffDestination.make(
                agent: provider.rawValue,
                artifact: artifact.markdown
            )
            _ = try delegate.launchTaskHandoff(
                destination,
                sourceController: self,
                sourceTabID: sourceTabID
            )
        } catch {
            presentTaskHandoffAlert(message: String(describing: error))
        }
    }

    private func localizedTaskHandoffString(
        _ key: String,
        fallback: String
    ) -> String {
        appLocalizer().string(key, fallback: fallback)
    }

    private func presentTaskHandoffAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizedTaskHandoffString(
            "handoff.error.title",
            fallback: "Task Handoff Failed"
        )
        alert.informativeText = message
        alert.addButton(withTitle: localizedTaskHandoffString(
            "common.ok",
            fallback: "OK"
        ))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            NSSound.beep()
        }
    }
}
