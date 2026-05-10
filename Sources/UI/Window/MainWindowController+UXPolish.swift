// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+UXPolish.swift - Context-aware chrome shortcuts.

import AppKit
import SwiftUI

extension MainWindowController {

    private static let shortcutHintOverlaySize = NSSize(width: 280, height: 92)
    private static let shortcutHintDebugOverlaySize = NSSize(width: 200, height: 92)

    func refreshShortcutHintsOverlay(
        config: UXPolishConfig,
        keybindings: KeybindingsConfig
    ) {
        guard config.alwaysShowShortcutHints else {
            removeShortcutHintOverlays()
            return
        }
        guard let overlayContainer = overlayContainerView else { return }

        let registry = ShortcutHintRegistry.defaults
        let placements = ShortcutHintPlacement.allCases.filter { placement in
            !registry.visibleHints(
                placement: placement,
                alwaysShow: config.alwaysShowShortcutHints,
                isDebugOverlayVisible: config.shortcutHintDebugOverlay
            ).isEmpty
        }

        let activePlacements = Set(placements)
        for placement in Array(shortcutHintOverlayHosts.keys) where !activePlacements.contains(placement) {
            shortcutHintOverlayHosts[placement]?.removeFromSuperview()
            shortcutHintOverlayHosts[placement] = nil
        }

        for placement in placements {
            let hints = registry.visibleHints(
                placement: placement,
                alwaysShow: config.alwaysShowShortcutHints,
                isDebugOverlayVisible: config.shortcutHintDebugOverlay
            )
            let rootView = ShortcutHintsOverlayView(
                hints: hints,
                config: config,
                shortcutLabelProvider: { actionId in
                    MenuKeybindingsBinder.prettyShortcut(for: actionId, in: keybindings)
                }
            )

            if let host = shortcutHintOverlayHosts[placement] {
                host.rootView = rootView
            } else {
                let host = ShortcutHintPassthroughHostingView(rootView: rootView)
                host.translatesAutoresizingMaskIntoConstraints = true
                host.autoresizingMask = []
                host.wantsLayer = true
                host.layer?.backgroundColor = NSColor.clear.cgColor
                overlayContainer.addSubview(host)
                shortcutHintOverlayHosts[placement] = host
            }
        }

        layoutShortcutHintOverlays()
    }

    func layoutShortcutHintOverlays() {
        guard let overlayContainer = overlayContainerView else { return }
        for (placement, host) in shortcutHintOverlayHosts {
            host.frame = shortcutHintFrame(for: placement, in: overlayContainer)
        }
    }

    private func removeShortcutHintOverlays() {
        for host in shortcutHintOverlayHosts.values {
            host.removeFromSuperview()
        }
        shortcutHintOverlayHosts.removeAll()
    }

    private func shortcutHintFrame(
        for placement: ShortcutHintPlacement,
        in overlayContainer: NSView
    ) -> NSRect {
        let bounds = overlayContainer.bounds
        let size = placement == .debug
            ? Self.shortcutHintDebugOverlaySize
            : Self.shortcutHintOverlaySize

        switch placement {
        case .sidebar:
            if let tabBarView {
                let sidebarFrame = tabBarView.convert(tabBarView.bounds, to: overlayContainer)
                return NSRect(
                    x: sidebarFrame.minX + 12,
                    y: sidebarFrame.minY + 16,
                    width: min(size.width, max(120, sidebarFrame.width - 24)),
                    height: size.height
                )
            }
            return NSRect(x: 14, y: 16, width: size.width, height: size.height)
        case .titlebar:
            return NSRect(
                x: max(12, (bounds.width - size.width) / 2),
                y: max(12, bounds.height - size.height - 16),
                width: size.width,
                height: size.height
            )
        case .pane:
            let anchor = focusedPaneView() ?? terminalSurfaceView ?? terminalContainerView ?? overlayContainer
            let paneFrame = anchor.convert(anchor.bounds, to: overlayContainer)
            return NSRect(
                x: max(paneFrame.minX + 12, paneFrame.maxX - size.width - 16),
                y: max(paneFrame.minY + 12, paneFrame.maxY - size.height - 16),
                width: min(size.width, max(120, paneFrame.width - 24)),
                height: size.height
            )
        case .debug:
            return NSRect(
                x: 18,
                y: max(12, bounds.height - size.height - 84),
                width: size.width,
                height: size.height
            )
        }
    }

    @objc func focusLocationOrOpenBrowserAction(_ sender: Any?) {
        let action = ContextAwareShortcuts.commandLAction(
            focusedSurface: currentContextAwareShortcutSurface(),
            browserSurfaceAvailable: browserSurfaceAvailable()
        )

        switch action {
        case .focusBrowserAddressField:
            if !focusBrowserAddressField() {
                splitWithBrowserAction(sender)
                DispatchQueue.main.async { [weak self] in
                    _ = self?.focusBrowserAddressField()
                }
            }
        case .openBrowserSplitAndFocusAddressField:
            splitWithBrowserAction(sender)
            DispatchQueue.main.async { [weak self] in
                _ = self?.focusBrowserAddressField()
            }
        }
    }

    @discardableResult
    func focusBrowserAddressField() -> Bool {
        if isBrowserVisible,
           let hostingView = browserHostingView,
           focusFirstBrowserURLField(in: hostingView) {
            return true
        }

        if let focusedBrowserView = browserContentViewContainingFirstResponder() {
            focusedBrowserView.focusAddressField()
            return true
        }

        syncFocusedLeafSelectionFromFirstResponder()
        if let splitManager = activeSplitManager,
           let focusedLeafID = splitManager.focusedLeafID,
           let focusedLeaf = splitManager.rootNode.allLeafIDs().first(where: { $0.leafID == focusedLeafID }),
           let browserView = panelContentViews[focusedLeaf.terminalID] as? BrowserContentView {
            browserView.focusAddressField()
            return true
        }

        for view in panelContentViews.values {
            if let browserView = view as? BrowserContentView {
                browserView.focusAddressField()
                return true
            }
            if focusFirstBrowserURLField(in: view) {
                return true
            }
        }

        return false
    }

    private func currentContextAwareShortcutSurface() -> ContextAwareShortcutSurface {
        guard let responder = window?.firstResponder else { return .other }

        if let view = responder as? NSView {
            if view is BrowserURLTextField || ancestor(of: view, matching: { $0 as? BrowserContentView }) != nil {
                return .browser
            }
            if ancestor(of: view, matching: { $0 as? TerminalHostView }) != nil {
                return .terminal
            }
            if ancestor(of: view, matching: { $0 as? EditorView }) != nil {
                return .editor
            }
        }

        return .other
    }

    private func browserSurfaceAvailable() -> Bool {
        if isBrowserVisible, browserHostingView != nil {
            return true
        }
        return panelContentViews.values.contains { view in
            view is BrowserContentView || containsSubview(in: view, matching: { $0 is BrowserURLTextField })
        }
    }

    private func browserContentViewContainingFirstResponder() -> BrowserContentView? {
        guard let firstResponder = window?.firstResponder as? NSView else { return nil }
        return ancestor(of: firstResponder) { view in
            view as? BrowserContentView
        }
    }

    private func focusFirstBrowserURLField(in root: NSView) -> Bool {
        guard let field = descendant(of: root, matching: { $0 as? BrowserURLTextField }) else {
            return false
        }
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        return true
    }

    private func containsSubview(in root: NSView, matching predicate: (NSView) -> Bool) -> Bool {
        descendant(of: root) { view in
            predicate(view) ? view : nil
        } != nil
    }

    private func ancestor<T>(of view: NSView, matching transform: (NSView) -> T?) -> T? {
        var current: NSView? = view
        while let candidate = current {
            if let matched = transform(candidate) {
                return matched
            }
            current = candidate.superview
        }
        return nil
    }

    private func descendant<T>(of root: NSView, matching transform: (NSView) -> T?) -> T? {
        if let matched = transform(root) {
            return matched
        }
        for subview in root.subviews {
            if let matched: T = descendant(of: subview, matching: transform) {
                return matched
            }
        }
        return nil
    }
}
