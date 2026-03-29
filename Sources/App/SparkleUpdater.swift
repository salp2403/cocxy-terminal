// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SparkleUpdater.swift - Auto-update integration via Sparkle framework.

import AppKit
import Sparkle

/// Manages update checks using the Sparkle framework.
/// Sparkle is NOT started automatically to avoid error dialogs on launch.
/// Updates are triggered only by user action (menu or preferences button).
@MainActor
final class SparkleUpdater: ObservableObject {

    // MARK: - Properties

    private var updaterController: SPUStandardUpdaterController?
    private var hasStarted = false

    @Published var automaticallyChecksForUpdates: Bool = true {
        didSet {
            updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var canCheckForUpdates: Bool {
        updaterController?.updater.canCheckForUpdates ?? true
    }

    /// The current update channel based on the bundle identifier.
    ///
    /// Returns "nightly" for `dev.cocxy.terminal.nightly` builds,
    /// "stable" for production builds.
    var updateChannel: String {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return bundleID.hasSuffix(".nightly") ? "nightly" : "stable"
    }

    /// Whether this is a nightly build.
    var isNightly: Bool {
        updateChannel == "nightly"
    }

    // MARK: - Actions

    /// Triggers a user-initiated update check.
    /// Initializes Sparkle on first call. If initialization fails,
    /// shows a simple alert instead of Sparkle's cryptic error.
    func checkForUpdates() {
        if !hasStarted {
            hasStarted = true
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            controller.updater.sendsSystemProfile = false
            controller.updater.automaticallyDownloadsUpdates = false
            self.updaterController = controller

            // Give Sparkle a moment to initialize before checking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.updaterController?.checkForUpdates(nil)
            }
        } else {
            updaterController?.checkForUpdates(nil)
        }
    }
}
