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

    /// The Sparkle updater controller. Nil if initialization fails.
    private var updaterController: SPUStandardUpdaterController?

    /// Whether automatic update checks are enabled.
    @Published var automaticallyChecksForUpdates: Bool = false {
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
        // Do not start the updater immediately. We initialize it lazily
        // on the first manual check or after a short delay to avoid
        // showing error dialogs on launch.
    }

    // MARK: - Actions

    /// Starts the updater. Called after the app has fully launched.
    func startIfNeeded() {
        guard updaterController == nil else { return }

        do {
            let controller = try SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.sendsSystemProfile = false
            self.updaterController = controller
            self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        } catch {
            // Sparkle initialization failed (e.g., missing SUFeedURL).
            // Silently ignore — the app works without auto-updates.
        }
    }

    /// Triggers a user-initiated update check. Shows UI if an update is found.
    func checkForUpdates() {
        startIfNeeded()
        updaterController?.checkForUpdates(nil)
    }
}
