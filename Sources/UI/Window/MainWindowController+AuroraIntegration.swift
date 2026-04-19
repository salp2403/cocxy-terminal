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

    /// Fallback height for the Aurora status bar used only when the
    /// classic `statusBarHostingView` has not been built yet (extremely
    /// rare — essentially tests without a full window boot). Matches
    /// the classic `statusBarHeight` so both chromes share the same
    /// vertical budget and the split view never shifts when the user
    /// toggles the feature flag at runtime.
    private static var auroraStatusBarFallbackHeight: CGFloat { 24 }

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
            refreshAuroraShortcutLabels()
            applyAuroraChromeVisibility(true)
        } else if auroraChromeController != nil {
            applyAuroraChromeVisibility(false)
        }

        // Re-apply the tab position so the Aurora override inside
        // `applyTabPosition` (`.left` while the flag is on) takes
        // effect even if the user's config persists `.top`/`.hidden`.
        // On deactivation this same call restores the user's chosen
        // layout immediately.
        if let sidebar = tabBarView, let strip = horizontalTabStripView {
            applyTabPosition(appearance.tabPosition, sidebar: sidebar, strip: strip)
        }
    }

    /// Resolves the command-palette and new-tab pretty shortcut labels
    /// from the live `[keybindings]` config so the Aurora sidebar tray
    /// mirrors the user's current bindings. Safe no-op when the Aurora
    /// controller is not installed yet.
    ///
    /// Invoked both on install and on every `applyConfig(...)` call so
    /// a rebinding flows to the new chrome without waiting for the next
    /// toggle-on cycle.
    func refreshAuroraShortcutLabels() {
        guard let controller = auroraChromeController else { return }
        let keybindings = configService?.current.keybindings ?? .defaults
        // `MenuKeybindingsBinder.prettyShortcut` returns nil when the
        // user has intentionally cleared the binding. The classic
        // menu-bar glyphs disappear in that case and the palette rows
        // drop the hint. Mirror that contract here: show the catalog
        // default only when the user has NOT edited the binding (i.e.
        // the raw string matches the default). When the user cleared
        // it explicitly, surface an "unbound" glyph (`—`) so the
        // Aurora tray never lies about what the shortcut is.
        let paletteLabel = resolveShortcutLabel(
            for: KeybindingActionCatalog.windowCommandPalette,
            in: keybindings
        )
        let newTabLabel = resolveShortcutLabel(
            for: KeybindingActionCatalog.tabNew,
            in: keybindings
        )
        if controller.paletteShortcutLabel != paletteLabel {
            controller.paletteShortcutLabel = paletteLabel
        }
        if controller.newTabShortcutLabel != newTabLabel {
            controller.newTabShortcutLabel = newTabLabel
        }
    }

    /// Label the Aurora tray should show for `action` given `config`.
    ///
    /// - Returns `prettyShortcut` when the user has a live binding.
    /// - Returns the catalog default's pretty label when the stored
    ///   string matches the catalog default (legacy configs that
    ///   never edited the action — preserves the out-of-box look).
    /// - Returns `"—"` (en-dash) when the user cleared the binding
    ///   explicitly. The classic palette / menu bar render no glyph
    ///   in that case; the Aurora tray has a fixed slot so a
    ///   single-character placeholder is the closest equivalent.
    /// Internal (not private) so the Aurora unit test suite can pin
    /// the label-resolution behaviour without booting the window
    /// controller. The helper has no dependency on the live instance
    /// and could be free-standing; living on the extension keeps the
    /// call site readable inside `refreshAuroraShortcutLabels`.
    static func auroraShortcutLabel(
        for action: KeybindingAction,
        in config: KeybindingsConfig
    ) -> String {
        if let pretty = MenuKeybindingsBinder.prettyShortcut(for: action.id, in: config) {
            return pretty
        }
        let raw = config.shortcutString(for: action.id)
        if raw.isEmpty {
            return "—"
        }
        return action.defaultShortcut.prettyLabel
    }

    private func resolveShortcutLabel(
        for action: KeybindingAction,
        in config: KeybindingsConfig
    ) -> String {
        Self.auroraShortcutLabel(for: action, in: config)
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
            self?.toggleAuroraPalette()
        }
        controller.onExecutePaletteAction = { [weak self] actionID in
            self?.executeAuroraPaletteAction(withID: actionID)
        }
        controller.onDismissPalette = { [weak self] in
            // The Aurora palette closes itself via the host binding; all
            // the host needs to do here is restore first responder on
            // whatever surface had keyboard focus. The classic
            // `dismissCommandPalette` is NOT called — that path operates
            // on `commandPaletteHostingView`, which is never mounted
            // while the Aurora chrome is active.
            self?.restoreFirstResponderAfterAuroraPalette()
        }
        controller.onToggleNotifications = { [weak self] in
            self?.toggleNotificationPanel()
        }
        // Mirror the live port scanner onto the Aurora status bar.
        // The status bar's `PortListView` renders whatever the
        // controller publishes, so this single subscription keeps the
        // new chrome aligned with the classic `activePorts` display.
        controller.wirePortScanner(portScanner)

        auroraChromeController = controller

        // Sidebar — mounted as an overlay **inside** `tabBarView`, not
        // as a sibling of the split view. Adding a third subview to
        // `mainSplitView` turned `sidebarHost` into a split pane and
        // NSSplitView pushed it to the far right of the window. Living
        // inside `tabBarView` pins Aurora to the same rect as the
        // classic sidebar (autoresizing handles width+height growth)
        // and keeps `mainSplitView`'s two-pane topology untouched, so
        // the autosave frame, the split-view delegate contract and
        // every classic layout path stay identical.
        //
        // The hosting view is given an opaque background layer so the
        // classic sidebar's vibrancy and subviews, which stay mounted
        // underneath, do not bleed through Aurora's rounded corners.
        let sidebarHost = controller.makeSidebarHost()
        if let sidebar = tabBarView {
            sidebarHost.frame = sidebar.bounds
            sidebarHost.autoresizingMask = [.width, .height]
            sidebarHost.wantsLayer = true
            sidebarHost.layer?.backgroundColor = CocxyColors.base.cgColor
            sidebarHost.isHidden = true
            sidebar.addSubview(sidebarHost)
        } else {
            // Fallback path for the rare case when `tabBarView` is
            // unavailable (tab position `.top` skips building it).
            // Aurora still mounts as a split pane so the feature is
            // reachable, although the layout will not match the left
            // sidebar look until the user switches back to `.left`.
            sidebarHost.frame = NSRect(
                x: 0, y: 0,
                width: Self.sidebarWidth,
                height: splitView.bounds.height
            )
            sidebarHost.autoresizingMask = [.height]
            sidebarHost.isHidden = true
            splitView.addSubview(sidebarHost)
        }

        // Status bar — sibling of `statusBarHostingView` inside the
        // root window view. Aurora overlays the classic one at the
        // exact same rectangle so we only flip `isHidden` to pick the
        // renderer — no splitView frame adjustment, no layout shift.
        // `AuroraStatusBarView` no longer pins a hardcoded 32pt
        // height; it adapts to whatever rectangle the host supplies,
        // which keeps the window's overall layout identical between
        // chromes.
        let statusBarHost = controller.makeStatusBarHost()
        let classicStatusFrame = statusBarHostingView?.frame ?? NSRect(
            x: 0, y: 0,
            width: rootView.bounds.width,
            height: Self.auroraStatusBarFallbackHeight
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
    ///   - Aurora on  → Aurora sidebar (mounted as overlay inside
    ///     `tabBarView`) and status bar visible; classic status bar
    ///     hidden. The classic `tabBarView` itself STAYS visible so
    ///     the split view's pane is preserved — Aurora tapes over it
    ///     via its opaque background layer. Hiding `tabBarView` would
    ///     also hide the Aurora overlay because it is a child view.
    ///   - Aurora off → Aurora hosting views hidden, classic chrome
    ///     intact. Aurora siblings stay mounted but hidden so they
    ///     keep receiving source updates in the background and
    ///     re-show instantly on the next toggle.
    private func applyAuroraChromeVisibility(_ active: Bool) {
        if active {
            // Symmetric cleanup on the opposite flip: if the classic
            // palette overlay is open when Aurora turns on, dismiss
            // it so only one overlay can be visible at a time.
            // `toggleCommandPalette()` now routes to the Aurora helper
            // once the sidebar host is visible, so forgetting to
            // dismiss the classic overlay here would leave it floating
            // above the new chrome until the user clicked elsewhere.
            if isCommandPaletteVisible {
                dismissCommandPalette()
            }
            auroraChromeController?.sidebarHost?.isHidden = false
            auroraChromeController?.statusBarHost?.isHidden = false
            statusBarHostingView?.isHidden = true
        } else {
            // Dismiss the Aurora palette before hiding the chrome so a
            // user flipping the flag off mid-open does not leave the
            // overlay floating above the classic chrome. `hidePalette`
            // clears `isPaletteVisible` and re-hides `paletteHost`, and
            // `toggleCommandPalette()` routes to the classic path once
            // `isAuroraChromeActive` flips to false (the sidebar host
            // is hidden immediately afterwards).
            if auroraChromeController?.isPaletteVisible == true {
                auroraChromeController?.hidePalette()
            }
            auroraChromeController?.sidebarHost?.isHidden = true
            auroraChromeController?.statusBarHost?.isHidden = true
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

    // MARK: - Palette routing

    /// Returns `true` when the Aurora chrome is currently the active
    /// chrome — i.e. the feature flag is on and the controller has
    /// been installed. Routing helpers use this to decide whether to
    /// forward palette shortcuts to the Aurora overlay or leave them
    /// for the classic path.
    var isAuroraChromeActive: Bool {
        guard let controller = auroraChromeController else { return false }
        return controller.sidebarHost?.isHidden == false
    }

    /// Shows or hides the Aurora palette overlay. Refreshes the action
    /// catalogue from the live engine before presenting so the user
    /// always sees the current shortcuts (e.g. after a keybindings
    /// edit that rebuilt the pretty labels).
    func toggleAuroraPalette() {
        guard let controller = auroraChromeController else { return }
        if !controller.isPaletteVisible {
            controller.setPaletteActions(buildAuroraPaletteActions())
        }
        controller.togglePalette()
        if controller.isPaletteVisible {
            if let host = controller.paletteHost {
                window?.makeFirstResponder(host)
            }
        } else {
            restoreFirstResponderAfterAuroraPalette()
        }
    }

    /// Restores keyboard focus to the terminal surface after the
    /// Aurora palette dismisses. Mirrors the behaviour the classic
    /// palette achieves through `dismissCommandPalette` +
    /// `window?.makeFirstResponder(tabBarView)` but targets whichever
    /// terminal the user was driving before opening the palette. In
    /// split layouts the palette may have been invoked from a
    /// non-primary pane, so focusing `terminalSurfaceView` blindly
    /// would send keystrokes to the wrong split after dismiss.
    /// `activeTerminalSurfaceView` already models the right target
    /// (focused split -> primary surface -> any surviving split), so
    /// we delegate to it and fall back to `focusActiveTerminalSurface`
    /// which performs the same `makeFirstResponder` work on our
    /// behalf.
    func restoreFirstResponderAfterAuroraPalette() {
        focusActiveTerminalSurface()
    }

    // MARK: - Palette action translation

    /// Builds the Aurora palette action list from the live
    /// `CommandPaletteEngine`. Falls back to an empty list when the
    /// engine has not been initialised yet so the overlay can still
    /// render a quiet "no actions" state without crashing.
    ///
    /// When an existing engine is reused we rebuild its built-in
    /// shortcut labels from the live `[keybindings]` config — the
    /// classic overlay does this in `showCommandPaletteOverlay()`, so
    /// Aurora has to replicate the refresh or rows would show stale
    /// glyphs after the user edited a binding.
    private func buildAuroraPaletteActions() -> [Design.AuroraPaletteAction] {
        let engine: CommandPaletteEngineImpl
        if let existing = commandPaletteEngine {
            engine = existing
            let keybindings = configService?.current.keybindings ?? .defaults
            engine.rebuildBuiltInShortcuts(using: keybindings)
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
