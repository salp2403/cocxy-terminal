// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SparkleUpdater.swift - Auto-update integration via Sparkle framework.

import Foundation
import Sparkle

/// Manages automatic update checks and user-initiated update actions
/// using the Sparkle framework.
@MainActor
final class SparkleUpdater: ObservableObject {

    // MARK: - Properties

    private let updaterController: SPUStandardUpdaterController

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    // MARK: - Initialization

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController.updater.sendsSystemProfile = false

        // Don't show update UI on first launch — only on manual check.
        // Sparkle will still check silently in background.
        updaterController.updater.automaticallyDownloadsUpdates = false
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    // MARK: - Actions

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
