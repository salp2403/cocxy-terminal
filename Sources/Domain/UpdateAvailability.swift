// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UpdateAvailability.swift - Presentation-safe update availability model.

import Foundation

/// Lightweight update snapshot published by the Sparkle integration.
///
/// The UI deliberately consumes this value type instead of `SUAppcastItem`
/// so sidebar rendering stays independent from Sparkle's Objective-C model
/// and only the updater bridge owns update-session details.
struct CocxyUpdateAvailability: Equatable, Sendable {
    let displayVersion: String
    let buildVersion: String
    let title: String?
    let isCritical: Bool

    init(
        displayVersion: String,
        buildVersion: String,
        title: String? = nil,
        isCritical: Bool = false
    ) {
        self.displayVersion = displayVersion
        self.buildVersion = buildVersion
        self.title = title
        self.isCritical = isCritical
    }

    var sidebarTitle: String {
        isCritical ? "Critical update" : "Update available"
    }

    var sidebarVersionLabel: String {
        displayVersion.hasPrefix("v") ? displayVersion : "v\(displayVersion)"
    }

    var sidebarAccessibilityLabel: String {
        "\(sidebarTitle): \(sidebarVersionLabel)"
    }
}
