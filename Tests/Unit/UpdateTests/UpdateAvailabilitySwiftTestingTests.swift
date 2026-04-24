// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// UpdateAvailabilitySwiftTestingTests.swift - Sidebar update badge model tests.

import Testing
@testable import CocxyTerminal

@Suite("Cocxy update availability")
struct UpdateAvailabilitySwiftTestingTests {

    @Test("Sidebar version label adds a v prefix only when missing")
    func sidebarVersionLabelNormalizesPrefix() {
        let plain = CocxyUpdateAvailability(
            displayVersion: "0.1.83",
            buildVersion: "0.1.83"
        )
        let prefixed = CocxyUpdateAvailability(
            displayVersion: "v0.1.83",
            buildVersion: "0.1.83"
        )

        #expect(plain.sidebarVersionLabel == "v0.1.83")
        #expect(prefixed.sidebarVersionLabel == "v0.1.83")
    }

    @Test("Critical updates use urgent sidebar copy")
    func criticalUpdatesUseUrgentSidebarTitle() {
        let normal = CocxyUpdateAvailability(
            displayVersion: "0.1.83",
            buildVersion: "0.1.83"
        )
        let critical = CocxyUpdateAvailability(
            displayVersion: "0.1.84",
            buildVersion: "0.1.84",
            isCritical: true
        )

        #expect(normal.sidebarTitle == "Update available")
        #expect(critical.sidebarTitle == "Critical update")
        #expect(critical.sidebarAccessibilityLabel == "Critical update: v0.1.84")
    }
}
