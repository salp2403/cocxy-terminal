// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TimelineProjectIdentity.swift - Exact project attribution for timeline events.

import Foundation

@MainActor
extension AppDelegate {
    func timelineProjectIdentity(
        cwd: String?,
        resolved: (controller: MainWindowController, tabID: TabID)?
    ) -> ProjectID? {
        let directory = cwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? resolved.flatMap { $0.controller.tabManager.tab(for: $0.tabID)?.workingDirectory }
        return directory.map { projectResolver.resolveProject(for: $0).groupingID }
    }

    func timelineProjectIdentity(forSessionID sessionID: String) -> ProjectID? {
        let tabID = hookSessionTabBindings[sessionID]
            ?? UUID(uuidString: sessionID)
                .flatMap { sessionRegistry?.session(for: SessionID(rawValue: $0))?.tabID }
        guard let tabID,
              let controller = controllerContainingTab(tabID),
              let directory = controller.tabManager.tab(for: tabID)?.workingDirectory else {
            return nil
        }
        return projectResolver.resolveProject(for: directory).groupingID
    }
}
