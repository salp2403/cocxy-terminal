// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+CrashRecovery.swift - Local crash recovery lifecycle wiring.

import AppKit
import Foundation

extension AppDelegate {
    private static let crashRecoverySnapshotInterval: TimeInterval = 5 * 60
    private static let crashRecoverySnapshotRetention = 24

    func initializeCrashRecovery(manager: CrashRecoveryManager = CrashRecoveryManager()) {
        crashRecoveryManager = manager
        do {
            let result = try manager.beginLaunch()
            pendingCrashRecoverySnapshot = result.suspectedCrash ? result.latestSnapshot : nil
        } catch {
            pendingCrashRecoverySnapshot = nil
            NSLog("[AppDelegate] Crash recovery launch check failed")
        }
    }

    func startCrashRecoverySnapshotsIfNeeded() {
        guard crashRecoveryManager != nil else { return }
        stopCrashRecoverySnapshots()
        writeCrashRecoverySnapshot()

        let timer = Timer(timeInterval: Self.crashRecoverySnapshotInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.writeCrashRecoverySnapshot()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        crashRecoverySnapshotTimer = timer
    }

    func stopCrashRecoverySnapshots() {
        crashRecoverySnapshotTimer?.invalidate()
        crashRecoverySnapshotTimer = nil
    }

    func writeCrashRecoverySnapshot() {
        guard let crashRecoveryManager else { return }
        do {
            _ = try crashRecoveryManager.saveSnapshot(captureCurrentSession())
            _ = try crashRecoveryManager.pruneSnapshots(keepNewest: Self.crashRecoverySnapshotRetention)
        } catch {
            NSLog("[AppDelegate] Crash recovery snapshot failed")
        }
    }

    func markCrashRecoveryCleanShutdown() {
        do {
            try crashRecoveryManager?.markCleanShutdown()
        } catch {
            NSLog("[AppDelegate] Crash recovery shutdown marker failed")
        }
    }

    func presentCrashRecoveryOfferIfNeeded() {
        guard let snapshot = pendingCrashRecoverySnapshot else { return }
        guard let controller = windowController else { return }
        pendingCrashRecoverySnapshot = nil

        let alert = NSAlert()
        let copy = Self.localizedCrashRecoveryOfferCopy(localizer: appLocalizer())
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        if alert.runModal() == .alertFirstButtonReturn {
            _ = restoreSession(snapshot.session, into: controller)
        }
    }
}
