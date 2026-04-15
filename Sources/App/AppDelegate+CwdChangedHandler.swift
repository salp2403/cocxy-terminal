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
        if let resolution = resolutionForCwdChanged(event) {
            let controller = allWindowControllers[resolution.controllerIndex]
            controller.tabManager.updateTab(id: resolution.tabID) { mutated in
                mutated.workingDirectory = resolution.newWorkingDirectory
                mutated.lastActivityAt = Date()
            }
            controller.tabBarViewModel?.syncWithManager()
            controller.refreshStatusBar()
        } else {
            return
        }
    }

    private func resolutionForCwdChanged(_ event: HookEvent) -> CwdChangedResolver.Resolution? {
        guard event.type == .cwdChanged,
              case .cwdChanged(let data) = event.data,
              let previousCwd = data.previousCwd, !previousCwd.isEmpty,
              let newCwd = event.cwd, !newCwd.isEmpty
        else {
            return nil
        }

        let previousPath = HookPathNormalizer.normalize(previousCwd)
        let newPath = HookPathNormalizer.normalize(newCwd)
        guard previousPath != newPath else { return nil }

        if let bound = boundResolutionForCwdChanged(
            sessionID: event.sessionId,
            previousPath: previousPath,
            newCwd: newCwd
        ) {
            return bound
        }

        return CwdChangedResolver.resolve(
            event: event,
            controllers: allWindowControllers.map(TabManagerSnapshot.init(controller:))
        )
    }

    private func boundResolutionForCwdChanged(
        sessionID: String?,
        previousPath: String,
        newCwd: String
    ) -> CwdChangedResolver.Resolution? {
        guard let sessionID,
              let boundTabID = hookSessionTabBindings[sessionID],
              let boundController = controllerContainingTab(boundTabID),
              let controllerIndex = allWindowControllers.firstIndex(where: { $0 === boundController }),
              let tab = boundController.tabManager.tab(for: boundTabID)
        else {
            return nil
        }

        let currentPath = HookPathNormalizer.normalize(tab.workingDirectory.path)
        guard currentPath == previousPath else { return nil }

        return CwdChangedResolver.Resolution(
            controllerIndex: controllerIndex,
            tabID: boundTabID,
            newWorkingDirectory: URL(fileURLWithPath: newCwd, isDirectory: true)
        )
    }
}

// MARK: - Pure resolver shared by production and tests

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
/// Production uses this as the unbound fallback path after attempting an
/// exact session-to-tab binding match. Tests also exercise it directly so
/// the fallback routing stays hermetic and easy to reason about.
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

        let previousPath = HookPathNormalizer.normalize(previousCwd)
        let newPath = HookPathNormalizer.normalize(newCwd)
        guard previousPath != newPath else { return nil }

        var matches: [(index: Int, tab: Tab)] = []
        for (index, snapshot) in controllers.enumerated() {
            for tab in snapshot.tabs where HookPathNormalizer.normalize(tab.workingDirectory.path) == previousPath {
                matches.append((index, tab))
            }
        }

        guard matches.count == 1, let match = matches.first else {
            return nil
        }

        // Race-free dedup: if OSC 7 already wrote the new CWD, don't
        // re-fire UI refreshes.
        let currentPath = HookPathNormalizer.normalize(match.tab.workingDirectory.path)
        guard currentPath != newPath else { return nil }

        return Resolution(
            controllerIndex: match.index,
            tabID: match.tab.id,
            newWorkingDirectory: URL(fileURLWithPath: newCwd, isDirectory: true)
        )
    }
}
