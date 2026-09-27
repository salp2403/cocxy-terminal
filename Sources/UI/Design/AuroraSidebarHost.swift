// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraSidebarHost.swift - Binds Aurora sidebar state and actions.

import SwiftUI

struct AuroraSidebarHost: View {
    @ObservedObject var controller: AuroraChromeController

    var body: some View {
        makeSidebarView()
            .designThemePalette(Design.palette(for: controller.themeIdentity))
    }

    func makeSidebarView() -> Design.AuroraSidebarView {
        Design.AuroraSidebarView(
            workspaces: controller.workspaces,
            projects: controller.projects,
            projectTaskCounts: controller.projectTaskCounts,
            projectRegistryAvailable: controller.projectRegistryErrorDescription == nil,
            projectRegistryRecoveryMessage: controller.projectRegistryRecoveryDiagnostic.map {
                Design.AuroraProjectRegistrySection.localizedRecoveryMessage(
                    for: $0,
                    using: controller.localizer
                )
            },
            activeSessionID: controller.activeSessionID,
            notesByWorkspace: controller.notesByWorkspace,
            onTogglePalette: { controller.onTogglePalette?() },
            onCreateTab: { controller.onCreateTab?() },
            onActivateSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onActivateSession?(tabID)
                }
            },
            onCloseSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onCloseSession?(tabID)
                }
            },
            onTogglePinSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onTogglePinSession?(tabID)
                }
            },
            onRenameSession: { sessionID, title in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onRenameSession?(tabID, title)
                }
            },
            onRenameWorkspace: { workspaceID, title in
                controller.onRenameWorkspace?(workspaceID, title)
            },
            onSetWorkspaceCollapsed: controller.projectRegistryWritable
                ? controller.onSetWorkspaceCollapsed
                : nil,
            onActivateProject: controller.projectRegistryWritable
                ? controller.onActivateProject
                : nil,
            onSetProjectPinned: controller.projectRegistryWritable
                ? controller.onSetProjectPinned
                : nil,
            renameRequest: controller.sidebarRenameRequest,
            onCloseOtherSessions: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onCloseOtherSessions?(tabID)
                }
            },
            onMoveSessionUp: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onMoveSessionUp?(tabID)
                }
            },
            onMoveSessionDown: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onMoveSessionDown?(tabID)
                }
            },
            onMoveSessionBefore: { sourceSessionID, targetSessionID in
                _ = controller.moveSession(sourceSessionID, before: targetSessionID)
            },
            onMovePaneToSession: { paneID, targetSessionID in
                _ = controller.movePane(paneID, toSessionID: targetSessionID)
            },
            onToggleNotifications: controller.onToggleNotifications.map { handler in
                { handler() }
            },
            onToggleNotes: controller.onToggleNotes.map { handler in
                { handler() }
            },
            onOpenNote: controller.onOpenNoteInWorkspace.map { handler in
                { workspaceID, noteID in handler(workspaceID, noteID) }
            },
            onInstallUpdate: controller.availableUpdate.map { _ in
                { controller.onInstallUpdate?() }
            },
            onHoverSession: { snapshot in
                controller.sidebarTooltip = snapshot
            },
            availableUpdate: controller.availableUpdate,
            displayMode: controller.sidebarDisplayMode,
            primaryInfo: controller.sidebarPrimaryInfo,
            onDisplayModeChange: { mode in
                controller.updateSidebarDisplayMode(mode)
            },
            onPrimaryInfoChange: { info in
                controller.updateSidebarPrimaryInfo(info)
            },
            paletteShortcutLabel: controller.paletteShortcutLabel,
            newTabShortcutLabel: controller.newTabShortcutLabel,
            localizer: controller.localizer
        )
    }
}
