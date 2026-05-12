// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+GitAssistant.swift - Local Git Assistant UI actions.

import AppKit
import Foundation

extension MainWindowController {
    @MainActor
    func generateGitAssistantCommitMessageFromPalette() async {
        let settings = configService?.current.gitAssistant ?? .defaults
        guard settings.enabled else {
            notifyGitAssistantPaletteResult(
                title: "Git Assistant is disabled",
                body: "Enable Git Assistant in Preferences > GitHub before generating commit messages.",
                type: .custom("git-assistant-disabled")
            )
            return
        }
        guard let workingDirectory = currentGitHubPaneWorkingDirectory() else {
            notifyGitAssistantPaletteResult(
                title: "Open a git repository",
                body: "Git Assistant needs the active tab to be inside a git repository.",
                type: .custom("git-assistant-no-repository")
            )
            return
        }

        do {
            let diff = try AppDelegate.gitOutput(
                at: workingDirectory,
                arguments: ["diff", "--cached", "--no-color", "--no-ext-diff"]
            )
            guard !diff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                notifyGitAssistantPaletteResult(
                    title: "No staged changes",
                    body: "Stage files before generating a commit message.",
                    type: .custom("git-assistant-empty-diff")
                )
                return
            }

            let client = try AgentProviderClientFactory().makeClient(
                configuration: AgentModeConfig(
                    enabled: true,
                    preferredProvider: settings.defaultProvider,
                    foundationModelsFallback: .requireExplicitChoice,
                    autoMode: false,
                    computerUseConfirm: true,
                    maxIterations: 1
                )
            )
            let draft = try await DefaultGitAssistantService(client: client)
                .generateCommitMessage(diff: diff, settings: settings)
            let text = [draft.subject, draft.body]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            guard !text.isEmpty else {
                notifyGitAssistantPaletteResult(
                    title: "Git Assistant returned an empty draft",
                    body: "Try again with a smaller staged diff or another provider.",
                    type: .custom("git-assistant-empty-response")
                )
                return
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            notifyGitAssistantPaletteResult(
                title: "Commit message copied",
                body: draft.subject,
                type: .custom("git-assistant-commit-message")
            )
        } catch {
            notifyGitAssistantPaletteResult(
                title: "Git Assistant failed",
                body: error.localizedDescription,
                type: .agentError
            )
        }
    }

    private func notifyGitAssistantPaletteResult(
        title: String,
        body: String,
        type: NotificationType
    ) {
        let notification = CocxyNotification(
            type: type,
            tabId: tabManager.activeTabID ?? TabID(),
            title: title,
            body: body
        )
        injectedNotificationManager?.notify(notification)
    }
}
