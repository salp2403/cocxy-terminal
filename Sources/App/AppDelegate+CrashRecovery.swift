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
        guard let controller = windowController,
              let window = controller.window else { return }
        pendingCrashRecoverySnapshot = nil

        let copy = Self.localizedCrashRecoveryOfferCopy(localizer: appLocalizer())

        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, weak controller] response in
            self?.crashRecoveryOfferWindowController = nil
            guard response == .alertFirstButtonReturn,
                  let self,
                  let controller else { return }
            _ = self.restoreCrashRecoverySession(snapshot.session, into: controller)
        }

        if let crashRecoveryOfferPresenter {
            crashRecoveryOfferPresenter(copy, window, completion)
            return
        }

        let offerController = CrashRecoveryOfferWindowController(copy: copy, completion: completion)
        crashRecoveryOfferWindowController = offerController
        offerController.show(over: window)
    }

    func restoreCrashRecoverySession(_ session: Session, into controller: MainWindowController) -> Bool {
        return restoreSession(session, into: controller)
    }
}
