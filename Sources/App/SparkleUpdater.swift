// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SparkleUpdater.swift - Auto-update integration via Sparkle framework.

import Foundation
import Sparkle

/// Manages automatic update checks and user-initiated update actions
/// using the Sparkle framework.
///
/// Sparkle verifies EdDSA signatures on every update, ensuring that only
/// releases signed with the project's private key are accepted. The appcast
/// feed URL and public key are embedded in Info.plist at build time.
///
/// ## Zero Telemetry
///
/// Sparkle is configured with `sendsSystemProfile = false` and no anonymous
/// data collection. The only network request is a plain HTTP GET to the
/// appcast URL.
@MainActor
final class SparkleUpdater: ObservableObject {

    // MARK: - Properties

    /// The Sparkle updater controller. Nil if Sparkle initialization fails.
    private let updaterController: SPUStandardUpdaterController?

    /// Whether automatic update checks are enabled.
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    /// Whether an update check can be performed right now.
    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? false
    }

    // MARK: - Initialization

    init() {
        // SPUStandardUpdaterController reads SUFeedURL and SUPublicEDKey
        // from the app's Info.plist automatically.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Disable system profile sending — zero telemetry.
        controller.updater.sendsSystemProfile = false

        self.updaterController = controller
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    // MARK: - Actions

    /// Triggers a user-initiated update check. Shows UI if an update is found.
    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}
