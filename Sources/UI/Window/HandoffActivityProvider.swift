// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HandoffActivityProvider.swift - Privacy-preserving macOS Handoff activity.

import Foundation

/// Builds Cocxy's macOS Handoff activity without terminal contents, paths,
/// commands, environment values, or other sensitive session data.
struct HandoffActivityProvider {
    static let activityType = "dev.cocxy.terminal.continue"

    func makeActivity(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) -> NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.title = localizer.string(
            "handoff.activity.title",
            fallback: "Continue Cocxy Terminal"
        )
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false
        activity.isEligibleForPublicIndexing = false
        activity.userInfo = [:]
        activity.keywords = []
        return activity
    }
}
