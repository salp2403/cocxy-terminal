// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Activity.swift - App-scoped activity store configuration.

import Foundation

@MainActor
extension AppDelegate {
    func configuredActivityStore() -> ActivityStoreCoordinator {
        activityStoreCoordinator.configure(for: configService?.current.activity ?? .defaults)
        return activityStoreCoordinator
    }
}
