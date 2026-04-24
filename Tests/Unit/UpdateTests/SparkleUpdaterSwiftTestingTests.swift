// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SparkleUpdaterSwiftTestingTests.swift - Sparkle update metadata bridge tests.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("Sparkle updater availability bridge")
@MainActor
struct SparkleUpdaterSwiftTestingTests {

    @Test("Maps Sparkle appcast metadata into sidebar update availability")
    func mapsSparkleAppcastMetadata() throws {
        let item = AppcastMetadataStub(
            displayVersionString: "0.1.83",
            versionString: "0.1.83-build.7",
            title: "Version 0.1.83",
            isCriticalUpdate: true
        )

        let availability = SparkleUpdater.availability(from: item)

        #expect(availability.displayVersion == "0.1.83")
        #expect(availability.buildVersion == "0.1.83-build.7")
        #expect(availability.title == "Version 0.1.83")
        #expect(availability.isCritical)
        #expect(availability.sidebarTitle == "Critical update")
        #expect(availability.sidebarVersionLabel == "v0.1.83")
    }

    @Test("Uses Sparkle build version when display version is absent")
    func usesBuildVersionWhenDisplayVersionIsAbsent() throws {
        let item = AppcastMetadataStub(
            displayVersionString: "0.1.84-build.2",
            versionString: "0.1.84-build.2",
            title: "Version 0.1.84",
            isCriticalUpdate: false
        )

        let availability = SparkleUpdater.availability(from: item)

        #expect(availability.displayVersion == "0.1.84-build.2")
        #expect(availability.buildVersion == "0.1.84-build.2")
        #expect(availability.title == "Version 0.1.84")
        #expect(!availability.isCritical)
        #expect(availability.sidebarTitle == "Update available")
        #expect(availability.sidebarVersionLabel == "v0.1.84-build.2")
    }

    @Test("Stale activation probe respects the minimum refresh interval")
    func staleActivationProbeRespectsMinimumRefreshInterval() {
        let firstProbe = Date(timeIntervalSince1970: 1_000)

        #expect(
            SparkleUpdater.shouldProbeForUpdateInformation(
                lastProbeStartedAt: nil,
                now: firstProbe,
                minimumInterval: 600
            )
        )
        #expect(
            !SparkleUpdater.shouldProbeForUpdateInformation(
                lastProbeStartedAt: firstProbe,
                now: firstProbe.addingTimeInterval(599),
                minimumInterval: 600
            )
        )
        #expect(
            SparkleUpdater.shouldProbeForUpdateInformation(
                lastProbeStartedAt: firstProbe,
                now: firstProbe.addingTimeInterval(600),
                minimumInterval: 600
            )
        )
    }
}

private struct AppcastMetadataStub: SparkleUpdateMetadataProviding {
    let displayVersionString: String
    let versionString: String
    let title: String?
    let isCriticalUpdate: Bool
}
