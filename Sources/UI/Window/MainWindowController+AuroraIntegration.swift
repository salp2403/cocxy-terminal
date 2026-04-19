// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+AuroraIntegration.swift - Mounts and toggles the
// Aurora chrome side-by-side with the classic chrome based on the
// `appearance.aurora-enabled` feature flag.
//
// Strategy: dual-mount. Aurora's `NSHostingView`s live alongside the
// classic `TabBarView` and `statusBarHostingView` as siblings in the
// same containers. Neither hierarchy is torn down or rebuilt on toggle
// — we only flip `isHidden` so bindings, first responder and scroll
// state survive the switch. While the flag is off, the Aurora hosting
// views are never instantiated so the classic path incurs zero extra
// work.
//
// The Aurora chrome is presentation-only. Every side effect the user
// triggers from an Aurora view (activate session, create tab, toggle
// palette, execute a palette action) is routed back to the controller's
// existing handlers, so behaviour is identical across both chromes.

import AppKit
import Combine
import SwiftUI

// MARK: - Aurora Integration

extension MainWindowController {

    /// Height budget reserved for the Aurora status bar. Matches the
    /// `.frame(height: 32)` that the design module pins in
    /// `AuroraStatusBarView`, plus two points of bottom padding so the
    /// glass material does not hug the window edge.
    private static var auroraStatusBarHeight: CGFloat { 34 }

    /// Idempotent entry point invoked by `applyConfig(...)` whenever the
    /// appearance block changes. Instantiates the Aurora controller and
    /// mounts its hosting views the first time the flag is true, then
    /// keeps toggling visibility on subsequent calls. When the flag is
    /// false the controller stays `nil` so classic chrome consumers do
    /// not pay any overhead.
    func applyAuroraChromeIfNeeded(for appearance: AppearanceConfig) {
        if appearance.auroraEnabled {
            installAuroraChromeIfNeeded()
            auroraChromeController?.setPaletteActions(buildAuroraPaletteActions())
            applyAuroraChromeVisibility(true)
        } else if auroraChromeController != nil {
            applyAuroraChromeVisibility(false)
        }
    }

    /// Applies the Aurora chrome state using the current `ConfigService`
    /// snapshot. Invoked by `AppDelegate.configureSharedServices(...)`
    /// after every service has been injected, which is the earliest
    /// moment the integration has the per-surface store it needs to
    /// build Aurora source data.
    ///
    /// Safe no-op when no config service is wired (tests, fallback
    /// windows) or when the flag is off.
    func applyInitialAuroraChromeStateIfNeeded() {
        guard let appearance = configService?.current.appearance else { return }
        applyAuroraChromeIfNeeded(for: appearance)
    }

    /// Creates the controller, wires its callbacks to the live window
    /// controller state and mounts the hosting views into the existing
    /// containers. Called lazily so zero allocations happen while the
    /// flag is off.
    ///
    /// The function is a no-op after the first successful install so
    /// config reloads that leave `auroraEnabled` true do not rebuild
    /// subviews and lose scroll / focus state.
    private func installAuroraChromeIfNeeded() {
        guard auroraChromeController == nil else { return }
        guard let rootView = window?.contentView else { return }
        guard let splitView = mainSplitView else { return }
        guard let agentStore = injectedPerSurfaceStore else { return }

        let controller = AuroraChromeController(
            tabManager: tabManager,
            store: agentStore
        )

        controller.surfaceIDsByTabProvider = { [weak self] in
            guard let self = self else { return [:] }
            return self.surfaceIDsByTabSnapshot()
        }
        controller.onActivateSession = { [weak self] tabID in
            _ = self?.focusTab(id: tabID)
        }
        controller.onCreateTab = { [weak self] in
            self?.createTab()
        }
        controller.onTogglePalette = { [weak self] in
            self?.toggleCommandPalette()
        }
        controller.onExecutePaletteAction = { [weak self] actionID in
            self?.executeAuroraPaletteAction(withID: actionID)
        }
        controller.onDismissPalette = { [weak self] in
            self?.dismissCommandPalette()
        }

        auroraChromeController = controller

        // Sidebar — sibling of `tabBarView` inside `mainSplitView`. We
        // mount it as a last subview so the split-view delegate still
        // treats `tabBarView` as the canonical first subview; Aurora
        // simply sits on top and renders when visible.
        let sidebarHost = controller.makeSidebarHost()
        if let sidebar = tabBarView {
            sidebarHost.frame = sidebar.frame
            sidebarHost.autoresizingMask = sidebar.autoresizingMask
        } else {
            sidebarHost.frame = NSRect(
                x: 0, y: 0,
                width: Self.sidebarWidth,
                height: splitView.bounds.height
            )
            sidebarHost.autoresizingMask = [.height]
        }
        sidebarHost.isHidden = true
        splitView.addSubview(sidebarHost)

        // Status bar — sibling of `statusBarHostingView` inside the
        // root window view. Aurora overlays the classic one at the same
        // frame so we simply flip `isHidden` to choose which renders.
        let statusBarHost = controller.makeStatusBarHost()
        let classicStatusFrame = statusBarHostingView?.frame ?? NSRect(
            x: 0, y: 0,
            width: rootView.bounds.width,
            height: Self.auroraStatusBarHeight
        )
        statusBarHost.frame = classicStatusFrame
        statusBarHost.autoresizingMask = statusBarHostingView?.autoresizingMask ?? [.width]
        statusBarHost.isHidden = true
        rootView.addSubview(statusBarHost)

        // Palette — lives on the overlay layer so it sits above every
        // split, browser, and markdown panel without disturbing the
        // split-view subview budget.
        if let overlayLayer = overlayContainerView {
            let paletteHost = controller.makePaletteHost()
            paletteHost.frame = overlayLayer.bounds
            paletteHost.autoresizingMask = [.width, .height]
            paletteHost.isHidden = true
            overlayLayer.addSubview(paletteHost)
        }

        controller.beginObservingDomain()
    }

    /// Flips visibility between classic and Aurora chrome. Safe to
    /// call with `auroraEnabled == false` even when the controller was
    /// never installed — the helper simply shows the classic path.
    ///
    /// Visibility rules:
    ///   - Aurora on  → classic sidebar, classic status bar, classic
    ///     palette hosting views hidden. Aurora siblings shown.
    ///   - Aurora off → reverse. Aurora siblings stay mounted but
    ///     hidden so they keep receiving source updates in the
    ///     background and re-show instantly on the next toggle.
    private func applyAuroraChromeVisibility(_ active: Bool) {
        if active {
            auroraChromeController?.sidebarHost?.isHidden = false
            auroraChromeController?.statusBarHost?.isHidden = false
            tabBarView?.isHidden = true
            statusBarHostingView?.isHidden = true
        } else {
            auroraChromeController?.sidebarHost?.isHidden = true
            auroraChromeController?.statusBarHost?.isHidden = true
            tabBarView?.isHidden = false
            statusBarHostingView?.isHidden = false
        }
    }

    /// Snapshots the surface-IDs-per-tab map the Aurora sidebar needs
    /// to render live splits. Walks every tab's split manager so the
    /// snapshot stays consistent with whatever the classic chrome is
    /// drawing.
    private func surfaceIDsByTabSnapshot() -> [TabID: [SurfaceID]] {
        var result: [TabID: [SurfaceID]] = [:]
        for tab in tabManager.tabs {
            result[tab.id] = surfaceIDs(for: tab.id)
        }
        return result
    }

    // MARK: - Palette action translation

    /// Builds the Aurora palette action list from the live
    /// `CommandPaletteEngine`. Falls back to an empty list when the
    /// engine has not been initialised yet so the overlay can still
    /// render a quiet "no actions" state without crashing.
    private func buildAuroraPaletteActions() -> [Design.AuroraPaletteAction] {
        let engine: CommandPaletteEngineImpl
        if let existing = commandPaletteEngine {
            engine = existing
        } else {
            engine = createWiredCommandPaletteEngine()
            commandPaletteEngine = engine
        }
        return engine.allActions.map { action in
            Design.AuroraPaletteAction(
                id: action.id,
                label: action.name,
                category: action.category.rawValue,
                subtitle: action.description,
                shortcut: action.shortcut
            )
        }
    }

    /// Forwards a palette action execution to the shared engine. Keeps
    /// the Aurora overlay's behaviour aligned with the classic palette
    /// by going through the same execute path so side effects (action
    /// analytics, recent-action tracking) stay consistent.
    private func executeAuroraPaletteAction(withID id: String) {
        guard let engine = commandPaletteEngine else { return }
        guard let action = engine.allActions.first(where: { $0.id == id }) else { return }
        engine.execute(action)
    }
}
