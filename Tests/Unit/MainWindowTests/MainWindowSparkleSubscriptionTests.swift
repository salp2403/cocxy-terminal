// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowSparkleSubscriptionTests.swift - Pin the wiring between
// `MainWindowController.sparkleUpdater` and the chrome surfaces that
// surface update availability (`AuroraChromeController.availableUpdate`,
// the classic `tabBarView` is built lazily on `showWindow` so this
// suite asserts the chrome-controller path which is observable
// without a window boot).

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("MainWindowController — Sparkle subscription", .serialized)
struct MainWindowSparkleSubscriptionTests {

    // MARK: - Fixtures

    /// Builds a fresh controller pair (`MainWindowController` +
    /// `AuroraChromeController`) wired the way production does it. The
    /// Aurora controller is exposed so each test can observe the
    /// `availableUpdate` published value without booting a real window.
    private func makeWiredControllers() -> (MainWindowController, AuroraChromeController) {
        let mainController = MainWindowController(bridge: MockTerminalEngine())
        let aurora = AuroraChromeController(
            tabManager: TabManager(),
            store: AgentStatePerSurfaceStore()
        )
        mainController.auroraChromeController = aurora
        return (mainController, aurora)
    }

    /// Convenience constructor for a non-critical update snapshot.
    private func makeAvailability(
        displayVersion: String,
        isCritical: Bool = false
    ) -> CocxyUpdateAvailability {
        CocxyUpdateAvailability(
            displayVersion: displayVersion,
            buildVersion: displayVersion,
            title: nil,
            isCritical: isCritical
        )
    }

    /// Drains pending main-actor hops from the
    /// `.receive(on: DispatchQueue.main)` operator the subscription
    /// uses. Sleep length stays generous because the operator does not
    /// re-emit synchronously even for the current thread.
    private func waitForMainHop() async {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    // MARK: - Initial wiring

    @Test("Setting sparkleUpdater forwards the initial availability synchronously so the sidebar is correct on the first frame")
    func subscribesAndForwardsInitialAvailability() {
        let (mainController, aurora) = makeWiredControllers()
        let updater = SparkleUpdater()
        let initial = makeAvailability(displayVersion: "0.1.91")
        updater.availableUpdate = initial

        mainController.sparkleUpdater = updater

        #expect(aurora.availableUpdate == initial)
    }

    @Test("Setting sparkleUpdater with a nil availability resets the chrome so a sparkle bridge with no detected update never surfaces a stale value")
    func initialNilAvailabilityResetsChrome() {
        let (mainController, aurora) = makeWiredControllers()
        // Pre-populate the chrome with a stale value so we can observe
        // the reset taking effect (in production this would come from a
        // previous sparkle session that was already torn down).
        aurora.availableUpdate = makeAvailability(displayVersion: "0.0.0")

        let updater = SparkleUpdater()
        // updater.availableUpdate stays at its default (nil) so the
        // subscription should propagate that value verbatim.
        mainController.sparkleUpdater = updater

        #expect(aurora.availableUpdate == nil)
    }

    // MARK: - Live updates

    @Test("Updates emitted by sparkleUpdater after the subscription propagate to the chrome so a Sparkle delegate callback reaches the sidebar without manual re-wire")
    func propagatesSubsequentUpdates() async {
        let (mainController, aurora) = makeWiredControllers()
        let updater = SparkleUpdater()
        mainController.sparkleUpdater = updater

        let stub = makeAvailability(displayVersion: "0.1.92")
        updater.availableUpdate = stub
        await waitForMainHop()

        #expect(aurora.availableUpdate == stub)
    }

    @Test("Critical updates propagate the isCritical flag so the sidebar can switch its title to Critical update")
    func propagatesCriticalFlag() async {
        let (mainController, aurora) = makeWiredControllers()
        let updater = SparkleUpdater()
        mainController.sparkleUpdater = updater

        let critical = makeAvailability(displayVersion: "0.1.93", isCritical: true)
        updater.availableUpdate = critical
        await waitForMainHop()

        #expect(aurora.availableUpdate == critical)
        #expect(aurora.availableUpdate?.isCritical == true)
    }

    // MARK: - Subscription lifecycle

    @Test("Setting sparkleUpdater = nil cancels the subscription and clears the chrome immediately so torn-down sessions do not linger as available updates")
    func clearsAvailabilityWhenSparkleUpdaterIsNil() async {
        let (mainController, aurora) = makeWiredControllers()
        let updater = SparkleUpdater()
        mainController.sparkleUpdater = updater
        let stub = makeAvailability(displayVersion: "0.1.94")
        updater.availableUpdate = stub
        await waitForMainHop()
        #expect(aurora.availableUpdate == stub) // baseline

        mainController.sparkleUpdater = nil

        #expect(aurora.availableUpdate == nil)
    }

    @Test("Replacing sparkleUpdater cancels the previous subscription so updates emitted by the replaced instance no longer reach the chrome")
    func replacingSparkleUpdaterCancelsPreviousSubscription() async {
        let (mainController, aurora) = makeWiredControllers()
        let firstUpdater = SparkleUpdater()
        let secondUpdater = SparkleUpdater()

        mainController.sparkleUpdater = firstUpdater
        mainController.sparkleUpdater = secondUpdater

        // Mutating the FIRST updater after the swap must NOT propagate.
        let stalePayload = makeAvailability(displayVersion: "0.1.90-stale")
        firstUpdater.availableUpdate = stalePayload
        await waitForMainHop()
        #expect(aurora.availableUpdate == nil)

        // Mutating the SECOND updater (the active one) must propagate.
        let livePayload = makeAvailability(displayVersion: "0.1.95")
        secondUpdater.availableUpdate = livePayload
        await waitForMainHop()
        #expect(aurora.availableUpdate == livePayload)
    }

    @Test("Toggling sparkleUpdater off and back on rebinds the subscription so the chrome receives the new instance's value cleanly")
    func toggleOffAndOnRebindsSubscription() async {
        let (mainController, aurora) = makeWiredControllers()
        let firstUpdater = SparkleUpdater()
        firstUpdater.availableUpdate = makeAvailability(displayVersion: "0.1.96")
        mainController.sparkleUpdater = firstUpdater

        mainController.sparkleUpdater = nil
        #expect(aurora.availableUpdate == nil)

        let secondUpdater = SparkleUpdater()
        let payload = makeAvailability(displayVersion: "0.1.97")
        secondUpdater.availableUpdate = payload
        mainController.sparkleUpdater = secondUpdater

        #expect(aurora.availableUpdate == payload)
    }
}
