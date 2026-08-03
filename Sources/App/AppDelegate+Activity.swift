// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Activity.swift - App-scoped activity store configuration.

import Foundation

@MainActor
extension AppDelegate {
    func configuredActivityStore() -> ActivityStoreCoordinator {
        activityStoreCoordinator.configure(for: configService?.current.activity ?? .defaults)
        return activityStoreCoordinator
    }

    func activityWorkingDirectoriesSnapshot() -> [URL] {
        let windowDirectories = allWindowControllers.flatMap { controller in
            controller.tabManager.tabs.map(\.workingDirectory)
                + Array(controller.surfaceWorkingDirectories.values)
        }
        let sessionDirectories = sessionRegistry?.allSessions.map(\.workingDirectory) ?? []
        return windowDirectories + sessionDirectories
    }
}
