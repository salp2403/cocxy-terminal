// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SparkleUpdater.swift - Auto-update integration via Sparkle framework.

import AppKit
import Combine
@preconcurrency import Sparkle

protocol SparkleUpdateMetadataProviding {
    var displayVersionString: String { get }
    var versionString: String { get }
    var title: String? { get }
    var isCriticalUpdate: Bool { get }
}

extension SUAppcastItem: SparkleUpdateMetadataProviding {}

/// Manages update checks using the Sparkle framework.
/// Sparkle owns installation and release-note UI; Cocxy only performs a
/// silent availability probe so the sidebar can surface a focused Update
/// button when a valid appcast item exists.
@MainActor
final class SparkleUpdater: NSObject, ObservableObject {

    // MARK: - Properties

    private static let automaticProbeInterval: TimeInterval = 15 * 60
    private static let activeProbeMinimumInterval: TimeInterval = 10 * 60

    private var updaterController: SPUStandardUpdaterController?
    private var automaticProbeTimer: Timer?
    private var lastProbeStartedAt: Date?
    private var hasStarted = false
    private var hasStartedAutomaticDetection = false

    @Published var automaticallyChecksForUpdates: Bool = true {
        didSet {
            updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @Published private(set) var availableUpdate: CocxyUpdateAvailability?
    @Published private(set) var lastProbeErrorDescription: String?

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

    /// Starts Sparkle and performs a silent update-information check.
    ///
    /// `checkForUpdateInformation()` does not offer the update by itself;
    /// it only drives the delegate callbacks Cocxy needs to update sidebar
    /// state. Users still install through Sparkle's standard UI after
    /// clicking the sidebar/menu/preferences button.
    func startAutomaticUpdateDetection() {
        guard !hasStartedAutomaticDetection else { return }
        hasStartedAutomaticDetection = true
        startUpdaterIfNeeded()
        probeForUpdateInformation()
        scheduleAutomaticProbeTimer()
    }

    /// Performs a silent availability refresh without presenting Sparkle UI.
    func probeForUpdateInformation(now: Date = Date()) {
        startUpdaterIfNeeded()
        guard let updater = updaterController?.updater,
              !updater.sessionInProgress else {
            return
        }
        lastProbeStartedAt = now
        updater.checkForUpdateInformation()
    }

    /// Refreshes availability when the app becomes active, without hammering
    /// the appcast if the user is switching between apps frequently.
    func probeForUpdateInformationIfStale(now: Date = Date()) {
        guard Self.shouldProbeForUpdateInformation(
            lastProbeStartedAt: lastProbeStartedAt,
            now: now,
            minimumInterval: Self.activeProbeMinimumInterval
        ) else {
            return
        }
        probeForUpdateInformation(now: now)
    }

    /// Triggers a user-initiated update check.
    /// Initializes Sparkle on first call. If initialization fails,
    /// shows a simple alert instead of Sparkle's cryptic error.
    func checkForUpdates() {
        startUpdaterIfNeeded()
        updaterController?.checkForUpdates(nil)
    }

    func stopAutomaticUpdateDetection() {
        automaticProbeTimer?.invalidate()
        automaticProbeTimer = nil
        hasStartedAutomaticDetection = false
    }

    // MARK: - Private

    private func startUpdaterIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        controller.updater.sendsSystemProfile = false
        controller.updater.automaticallyDownloadsUpdates = false
        updaterController = controller
    }

    private func scheduleAutomaticProbeTimer() {
        automaticProbeTimer?.invalidate()
        let timer = Timer(timeInterval: Self.automaticProbeInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.probeForUpdateInformation()
            }
        }
        automaticProbeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    static func availability(from item: SUAppcastItem) -> CocxyUpdateAvailability {
        availability(from: item as SparkleUpdateMetadataProviding)
    }

    static func availability(from metadata: SparkleUpdateMetadataProviding) -> CocxyUpdateAvailability {
        CocxyUpdateAvailability(
            displayVersion: metadata.displayVersionString,
            buildVersion: metadata.versionString,
            title: metadata.title,
            isCritical: metadata.isCriticalUpdate
        )
    }

    static func shouldProbeForUpdateInformation(
        lastProbeStartedAt: Date?,
        now: Date,
        minimumInterval: TimeInterval
    ) -> Bool {
        guard let lastProbeStartedAt else { return true }
        return now.timeIntervalSince(lastProbeStartedAt) >= minimumInterval
    }

    private func updateAvailability(from item: SUAppcastItem) {
        availableUpdate = Self.availability(from: item)
        lastProbeErrorDescription = nil
    }
}

// MARK: - Sparkle Delegates

@MainActor
extension SparkleUpdater: SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateAvailability(from: item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableUpdate = nil
        lastProbeErrorDescription = nil
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        lastProbeErrorDescription = error.localizedDescription
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        return false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        updateAvailability(from: update)
    }
}
