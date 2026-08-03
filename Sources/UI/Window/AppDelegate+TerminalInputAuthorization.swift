// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TerminalInputAuthorization.swift - Exact terminal input target binding.

import CocxyShared
import Foundation

extension AppDelegate {
    @MainActor
    func terminalInputPresentationTarget(
        tabID rawTabID: String,
        fallbackController: MainWindowController,
        authorityDetails: [String: String] = [:],
        requiredSurfaceID rawSurfaceID: String? = nil
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard let uuid = UUID(uuidString: rawTabID) else { return nil }
        let requiredSurfaceID: SurfaceID?
        if let rawSurfaceID {
            guard let surfaceUUID = UUID(uuidString: rawSurfaceID) else { return nil }
            requiredSurfaceID = SurfaceID(rawValue: surfaceUUID)
        } else {
            requiredSurfaceID = nil
        }
        let tabID = TabID(rawValue: uuid)
        guard let controller = controllerContainingTab(tabID)
                ?? (fallbackController.tabManager.tab(for: tabID) == nil
                    ? nil
                    : fallbackController),
              let tab = controller.tabManager.tab(for: tabID) else {
            return nil
        }
        let workingDirectory = (tab.worktreeRoot ?? tab.workingDirectory)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        return terminalInputPresentationTarget(
            tabID: tabID,
            tab: tab,
            controller: controller,
            workingDirectory: workingDirectory,
            authorityDetails: authorityDetails,
            requiredSurfaceID: requiredSurfaceID
        )
    }

    @MainActor
    func terminalInputPresentationTarget(
        tabID: TabID,
        tab: Tab,
        controller: MainWindowController,
        workingDirectory: String,
        authorityDetails: [String: String] = [:],
        requiredSurfaceID: SurfaceID? = nil
    ) -> SocketPrivilegedCommandPresentationTarget? {
        let availableSurfaceIDs = controller.surfaceIDs(for: tabID)
        let isVisible = (controller.visibleTabID ?? controller.tabManager.activeTabID) == tabID
        let visibleSurfaceID = isVisible
            ? controller.focusedSplitSurfaceView?.terminalViewModel?.surfaceID
                ?? controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID
            : nil
        let surfaceID = requiredSurfaceID.flatMap {
            availableSurfaceIDs.contains($0) ? $0 : nil
        } ?? (requiredSurfaceID == nil
            ? visibleSurfaceID.flatMap { availableSurfaceIDs.contains($0) ? $0 : nil }
                ?? controller.tabSurfaceMap[tabID].flatMap {
                    availableSurfaceIDs.contains($0) ? $0 : nil
                }
                ?? availableSurfaceIDs.sorted {
                    $0.rawValue.uuidString < $1.rawValue.uuidString
                }.first
            : nil)
        guard let surfaceID else { return nil }

        return SocketPrivilegedCommandPresentationTarget(
            context: SocketPrivilegedCommandContext(
                scope: .terminalSurface,
                windowControllerIdentifier: ObjectIdentifier(controller),
                tabID: tabID.rawValue,
                workingDirectory: workingDirectory,
                authorityDetails: authorityDetails,
                surfaceID: surfaceID.rawValue,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                targetDisplayName: "Terminal tab \(tab.displayTitle) (\(tabID.rawValue.uuidString))"
            ),
            controller: controller
        )
    }
}
