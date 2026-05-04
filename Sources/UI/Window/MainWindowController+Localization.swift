// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Localization.swift - Localized copy for window alerts.

import Foundation

extension MainWindowController {
    static func localizedCloseTabConfirmationCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("window.closeTab.title", fallback: "Close Tab?"),
            informativeText: localizer.string(
                "window.closeTab.message",
                fallback: "Running processes in this tab will be terminated."
            ),
            primaryButton: localizer.string("common.close", fallback: "Close"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    static func localizedCloseWorktreeTabCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("window.closeWorktreeTab.title", fallback: "Close Worktree Tab?"),
            informativeText: localizer.string(
                "window.closeWorktreeTab.message",
                fallback: """
                This tab is attached to a cocxy-managed git worktree. Keep the worktree on disk, \
                or remove it only if it has no uncommitted changes.
                """
            ),
            primaryButton: localizer.string("window.closeWorktreeTab.keepWorktree", fallback: "Keep Worktree"),
            secondaryButton: localizer.string("window.closeWorktreeTab.removeIfClean", fallback: "Remove if Clean"),
            tertiaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    static func localizedFocusedPaneCloseCopy(
        localizer: AppLocalizer,
        paneType: PanelType,
        remainingPaneCount: Int
    ) -> AppAlertCopy {
        let paneName = localizedPaneName(paneType, localizer: localizer)
        let messageKey = remainingPaneCount == 1
            ? "window.closePane.message.one"
            : "window.closePane.message.many"
        let fallback = remainingPaneCount == 1
            ? "This will close the focused %@. The workspace tab stays open with %d pane remaining."
            : "This will close the focused %@. The workspace tab stays open with %d panes remaining."

        return AppAlertCopy(
            messageText: localizer.string("window.closePane.title", fallback: "Close Focused Pane?"),
            informativeText: String(
                format: localizer.string(messageKey, fallback: fallback),
                paneName,
                remainingPaneCount
            ),
            primaryButton: localizer.string("window.closePane.button", fallback: "Close Pane"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    static func localizedSaveTabConfigCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string(
                "window.tabConfig.save.title",
                fallback: "Save Current Tab as Config"
            ),
            informativeText: localizer.string(
                "window.tabConfig.save.message",
                fallback: "Saved configs live locally as TOML and can be edited before opening."
            ),
            primaryButton: localizer.string("common.save", fallback: "Save"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    static func localizedOpenTabConfigCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("window.tabConfig.open.title", fallback: "Open Tab from Config"),
            informativeText: localizer.string(
                "window.tabConfig.open.message",
                fallback: "The TOML file is reloaded from disk before the tab opens."
            ),
            primaryButton: localizer.string("common.open", fallback: "Open"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }

    static func localizedTabConfigSaveFailureMessage(localizer: AppLocalizer) -> String {
        localizer.string("window.tabConfig.save.error", fallback: "Unable to save tab config.")
    }

    static func localizedTabConfigOpenFailureMessage(localizer: AppLocalizer) -> String {
        localizer.string("window.tabConfig.open.error", fallback: "Unable to open tab config.")
    }

    static func localizedSSHUploadCompleteTitle(localizer: AppLocalizer) -> String {
        localizer.string("window.sshUpload.complete.title", fallback: "Upload Complete")
    }

    static func localizedSSHUploadFailedTitle(localizer: AppLocalizer) -> String {
        localizer.string("window.sshUpload.failed.title", fallback: "Upload Failed")
    }

    static func localizedSSHUploadUnknownError(localizer: AppLocalizer) -> String {
        localizer.string("window.sshUpload.unknownError", fallback: "Unknown error")
    }

    static func localizedOpenInDefaultEditorTitle(localizer: AppLocalizer) -> String {
        localizer.string("codeReview.externalEditor.openDefault", fallback: "Open in Default Editor")
    }

    static func localizedOpenInEditorTitle(_ editorName: String, localizer: AppLocalizer) -> String {
        String(
            format: localizer.string("codeReview.externalEditor.openNamed", fallback: "Open in %@"),
            editorName
        )
    }

    private static func localizedPaneName(_ paneType: PanelType, localizer: AppLocalizer) -> String {
        switch paneType {
        case .terminal:
            return localizer.string("window.pane.terminalSplit", fallback: "terminal split")
        case .browser:
            return localizer.string("window.pane.browserPanel", fallback: "browser panel")
        case .markdown:
            return localizer.string("window.pane.markdownPanel", fallback: "markdown panel")
        case .editor:
            return localizer.string("window.pane.editorPanel", fallback: "editor panel")
        case .notebook:
            return localizer.string("window.pane.notebookPanel", fallback: "notebook panel")
        case .workflow:
            return localizer.string("window.pane.workflowPanel", fallback: "workflow panel")
        case .sessionReplay:
            return localizer.string("window.pane.sessionReplayPanel", fallback: "session replay panel")
        case .aiEditHistory:
            return localizer.string("window.pane.editHistoryPanel", fallback: "edit history panel")
        case .templates:
            return localizer.string("window.pane.templatesPanel", fallback: "templates panel")
        case .macros:
            return localizer.string("window.pane.macrosPanel", fallback: "macros panel")
        case .dbCloud:
            return localizer.string("window.pane.dbCloudPanel", fallback: "DB/cloud helpers panel")
        case .subagent:
            return localizer.string("window.pane.subagentPanel", fallback: "subagent panel")
        }
    }
}
