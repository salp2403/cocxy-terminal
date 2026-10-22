// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+ProjectAlias.swift - Canonical project rename flow.

import Foundation

extension MainWindowController {
    func renameActiveWorkspaceFromPalette() {
        guard let tabID = tabManager.activeTabID,
              let tab = tabManager.tab(for: tabID) else {
            return
        }
        if isAuroraChromeActive, let controller = auroraChromeController {
            controller.refreshSources()
            _ = controller.requestRenameWorkspace(containing: tabID)
            return
        }
        let workspace = AuroraWorkspacePlanner.descriptor(
            for: tab,
            projectResolver: projectResolver
        )
        presentAuroraWorkspaceRename(
            workspaceID: workspace.identity,
            currentName: currentProjectAliasName(for: workspace, tab: tab)
        )
    }

    func applyAuroraWorkspaceRename(workspaceID: String, newTitle: String?) {
        if let projectAliasHandler {
            projectAliasHandler(ProjectID(rawValue: workspaceID), newTitle)
            return
        }
        let matchingIDs = AuroraWorkspacePlanner.matchingTabIDs(
            projectID: workspaceID,
            in: tabManager.tabs,
            projectResolver: projectResolver
        )
        guard !matchingIDs.isEmpty else { return }
        let legacyIdentities = Set(matchingIDs.compactMap { tabID in
            tabManager.tab(for: tabID).map {
                AuroraWorkspacePlanner.descriptor(
                    for: $0,
                    projectResolver: projectResolver
                ).unfoldedIdentity
            }
        })
        auroraWorkspaceTitleStore.setTitle(
            newTitle,
            for: workspaceID,
            migrating: legacyIdentities
        )
    }

    private func currentProjectAliasName(
        for workspace: AuroraWorkspaceDescriptor,
        tab: Tab
    ) -> String {
        let storedValues = auroraWorkspaceTitleStore.snapshot
        if let storedValue = storedValues[workspace.identity] {
            return AuroraWorkspacePlanner.normalizedTitle(storedValue)
                ?? workspace.automaticName
        }
        if workspace.unfoldedIdentity != workspace.identity,
           let storedValue = storedValues[workspace.unfoldedIdentity] {
            return AuroraWorkspacePlanner.normalizedTitle(storedValue)
                ?? workspace.automaticName
        }
        return AuroraWorkspacePlanner.normalizedTitle(tab.workspaceCustomTitle)
            ?? workspace.automaticName
    }

    private func presentAuroraWorkspaceRename(workspaceID: String, currentName: String) {
        guard let parentWindow = window else { return }
        let localizer = appLocalizer()
        RenameSheetController.present(
            on: parentWindow,
            currentName: currentName,
            placeholder: localizer.string(
                "auroraSidebar.workspace.rename.placeholder",
                fallback: "Workspace name"
            ),
            icon: "square.stack.3d.up",
            localizer: localizer,
            onComplete: { [weak self] result in
                guard case .confirmed(let newTitle) = result, let self else { return }
                let trimmed = (newTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                applyAuroraWorkspaceRename(
                    workspaceID: workspaceID,
                    newTitle: trimmed.isEmpty ? nil : trimmed
                )
            }
        )
    }
}
