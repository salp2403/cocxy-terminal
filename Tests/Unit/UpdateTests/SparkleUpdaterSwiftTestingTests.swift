// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SparkleUpdaterSwiftTestingTests.swift - Sparkle update metadata bridge tests.

import Testing
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
}

private struct AppcastMetadataStub: SparkleUpdateMetadataProviding {
    let displayVersionString: String
    let versionString: String
    let title: String?
    let isCriticalUpdate: Bool
}
