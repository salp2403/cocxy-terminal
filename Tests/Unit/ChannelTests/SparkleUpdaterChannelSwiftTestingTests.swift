// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Sparkle updater channels")
@MainActor
struct SparkleUpdaterChannelSwiftTestingTests {

    @Test("updater starts with injected channel")
    func updaterStartsWithInjectedChannel() {
        let updater = SparkleUpdater(channel: .preview)

        #expect(updater.channel == .preview)
        #expect(updater.updateChannel == "preview")
        #expect(updater.currentFeedURLString == "https://cocxy.dev/appcast-preview.xml")
    }

    @Test("set channel updates feed and clears stale availability")
    func setChannelUpdatesFeedAndClearsStaleAvailability() {
        let updater = SparkleUpdater(channel: .stable)
        updater.availableUpdate = CocxyUpdateAvailability(
            displayVersion: "9.9.9",
            buildVersion: "999",
            title: "Old",
            isCritical: false
        )

        updater.setChannel(.nightly)

        #expect(updater.channel == .nightly)
        #expect(updater.currentFeedURLString == "https://cocxy.dev/appcast-nightly.xml")
        #expect(updater.availableUpdate == nil)
    }
}
