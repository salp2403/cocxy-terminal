// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Handoff.swift - macOS Handoff activity lifecycle.

import AppKit

extension MainWindowController {
    private static let handoffActivityProvider = HandoffActivityProvider()

    @discardableResult
    func installPrivacyPreservingHandoffActivity(makeCurrent: Bool) -> NSUserActivity? {
        guard let window else { return nil }

        let activity = Self.handoffActivityProvider.makeActivity(localizer: appLocalizer())
        window.userActivity?.invalidate()
        window.userActivity = activity
        if makeCurrent {
            activity.becomeCurrent()
        }
        return activity
    }

    func resignPrivacyPreservingHandoffActivity() {
        window?.userActivity?.resignCurrent()
    }

    func invalidatePrivacyPreservingHandoffActivity() {
        window?.userActivity?.invalidate()
        window?.userActivity = nil
    }
}
