// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Handoff activity provider")
struct HandoffActivityProviderSwiftTestingTests {

    @Test("app Info.plist declares the Cocxy Handoff activity type")
    func appInfoPlistDeclaresHandoffActivityType() throws {
        let plistURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        let activityTypes = try #require(plist["NSUserActivityTypes"] as? [String])

        #expect(activityTypes.contains(HandoffActivityProvider.activityType))
    }

    @Test("provider creates a Handoff-only activity without terminal data")
    func providerCreatesPrivacyPreservingActivity() throws {
        let provider = HandoffActivityProvider()
        let activity = provider.makeActivity(localizer: AppLocalizer(languagePreference: .english))

        #expect(activity.activityType == HandoffActivityProvider.activityType)
        #expect(activity.title == "Continue Cocxy Terminal")
        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch == false)
        #expect(activity.isEligibleForPublicIndexing == false)
        #expect(activity.userInfo?.isEmpty ?? true)
        #expect(activity.keywords.isEmpty)
    }

    @Test("main window installs the privacy preserving Handoff activity")
    func mainWindowInstallsHandoffActivity() throws {
        let controller = MainWindowController(bridge: MockTerminalEngine(), deferContentSetup: true)
        let window = try #require(controller.window)
        let activity = try #require(window.userActivity)

        #expect(activity.activityType == HandoffActivityProvider.activityType)
        #expect(activity.isEligibleForHandoff)
        #expect(activity.isEligibleForSearch == false)
        #expect(activity.isEligibleForPublicIndexing == false)
        #expect(activity.userInfo?.isEmpty ?? true)
    }
}
