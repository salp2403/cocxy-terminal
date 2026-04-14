// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+CwdChangedHandler.swift
// Phase 4: keep `Tab.workingDirectory` in sync when Claude Code 2.1.83+
// emits a CwdChanged lifecycle event. Complements (does not replace) the
// existing OSC 7 path; the two converge on the same final value with no
// double-write side effects thanks to exact previous-CWD matching and
// no-op deduplication when the candidate already equals the new CWD.

import AppKit
import Foundation

extension AppDelegate {

    /// Reacts to a Claude Code `CwdChanged` lifecycle event by routing it
    /// through the pure resolver and, on a hit, mutating the tab and
    /// refreshing the dependent UI surfaces.
    ///
    /// Invariants enforced by `CwdChangedResolver`:
    /// - `event.type == .cwdChanged`.
    /// - Both `event.cwd` and `data.previousCwd` are non-empty.
    /// - `previousCwd != cwd` (no-op when nothing changed).
    /// - The matched tab's current CWD differs from the new CWD (race-free
    ///   dedup against OSC 7).
    /// - Tab matching is exact, never a parent-directory fallback.
    func handleCwdChangedHook(_ event: HookEvent) {
        let snapshots = allWindowControllers.map(TabManagerSnapshot.init)
        guard let resolution = CwdChangedResolver.resolve(
            event: event,
            controllers: snapshots
        ) else {
            return
        }

        let controller = allWindowControllers[resolution.controllerIndex]
        controller.tabManager.updateTab(id: resolution.tabID) { mutated in
            mutated.workingDirectory = resolution.newWorkingDirectory
            mutated.lastActivityAt = Date()
        }
        controller.tabBarViewModel?.syncWithManager()
        controller.refreshStatusBar()
    }
}

// MARK: - Pure resolver (test-friendly)

/// Snapshot of a controller's tabs at the moment the hook arrives. Captured
/// once so the resolver can stay free of MainActor-only operations.
struct TabManagerSnapshot: Sendable {
    let tabs: [Tab]

    @MainActor
    init(controller: MainWindowController) {
        self.tabs = controller.tabManager.tabs
    }

    init(tabs: [Tab]) {
        self.tabs = tabs
    }
}

/// Pure resolution of a CwdChanged hook against a list of tab snapshots.
///
/// Extracted so unit tests can validate the routing logic without booting
/// AppKit or the MainWindowController stack.
enum CwdChangedResolver {

    struct Resolution: Equatable {
        let controllerIndex: Int
        let tabID: TabID
        let newWorkingDirectory: URL
    }

    /// Returns the tab to update, or `nil` when the event must be dropped.
    static func resolve(
        event: HookEvent,
        controllers: [TabManagerSnapshot]
    ) -> Resolution? {
        guard event.type == .cwdChanged else { return nil }
        guard case .cwdChanged(let data) = event.data,
              let previousCwd = data.previousCwd, !previousCwd.isEmpty,
              let newCwd = event.cwd, !newCwd.isEmpty else {
            return nil
        }

        let previousPath = URL(fileURLWithPath: previousCwd).standardizedFileURL.path
        let newPath = URL(fileURLWithPath: newCwd).standardizedFileURL.path
        guard previousPath != newPath else { return nil }

        for (index, snapshot) in controllers.enumerated() {
            guard let tab = snapshot.tabs.first(where: {
                $0.workingDirectory.standardizedFileURL.path == previousPath
            }) else {
                continue
            }
            // Race-free dedup: if OSC 7 already wrote the new CWD, don't
            // re-fire UI refreshes.
            let currentPath = tab.workingDirectory.standardizedFileURL.path
            guard currentPath != newPath else { return nil }

            return Resolution(
                controllerIndex: index,
                tabID: tab.id,
                newWorkingDirectory: URL(fileURLWithPath: newCwd, isDirectory: true)
            )
        }

        return nil
    }
}
