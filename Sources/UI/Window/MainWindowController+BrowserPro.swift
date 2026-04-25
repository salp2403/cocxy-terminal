// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+BrowserPro.swift - Browser Pro overlay panels.

import AppKit
import SwiftUI

// MARK: - Browser Pro Panels

/// Extension that manages Browser Pro overlay panels: history and bookmarks.
///
/// These panels extend the base browser functionality (in +Overlays.swift)
/// with advanced features. Each panel follows the same slide-in pattern
/// used by Dashboard and Timeline.
extension MainWindowController {

    // MARK: - Active Browser Resolution

    /// Returns the currently active `BrowserViewModel`, checking both the
    /// overlay browser and any split-based browser panels.
    ///
    /// Resolution order:
    /// 1. The overlay browser's ViewModel (`browserViewModel`), if the overlay is open.
    /// 2. The focused split leaf's browser ViewModel, if it's a browser panel.
    /// 3. The first browser split ViewModel found in `panelContentViews`, as a fallback.
    ///
    /// Returns nil when no browser panel is open in any form.
    func activeBrowserViewModel() -> BrowserViewModel? {
        // Prefer the overlay browser when it's visible.
        if isBrowserVisible, let overlayVM = browserViewModel {
            return overlayVM
        }

        // If focus is already inside a browser split panel (URL bar, WKWebView,
        // toolbar button, etc.), prefer that exact panel.
        var currentView: NSView?
        if let firstResponderView = window?.firstResponder as? NSView {
            currentView = firstResponderView
        } else if let firstResponder = window?.firstResponder as? NSResponder {
            currentView = firstResponder.nextResponder as? NSView
        }

        while let view = currentView {
            if let viewModel = browserViewModel(containedIn: view) {
                return viewModel
            }
            currentView = view.superview
        }

        // Check for a split-based browser by looking at the focused leaf.
        syncFocusedLeafSelectionFromFirstResponder()
        if let sm = activeSplitManager, let focusedID = sm.focusedLeafID {
            let leaves = sm.rootNode.allLeafIDs()
            if let focusedLeaf = leaves.first(where: { $0.leafID == focusedID }),
               let panelView = panelContentViews[focusedLeaf.terminalID],
               let viewModel = browserViewModel(containedIn: panelView) {
                return viewModel
            }
        }

        // Fallback: return any open browser split panel.
        for (_, view) in panelContentViews {
            if let viewModel = browserViewModel(containedIn: view) {
                return viewModel
            }
        }

        // Last resort: the overlay ViewModel even if overlay is not visible
        // (it may have been set from a previous session).
        return browserViewModel
    }

    /// Returns a browser model for external URL opens, showing the overlay when
    /// there is no visible browser surface to receive the navigation.
    func browserViewModelForExternalNavigation() -> BrowserViewModel? {
        if let active = activeBrowserViewModel(),
           active !== browserViewModel || isBrowserVisible {
            return active
        }

        showBrowserPanel()
        window?.makeKeyAndOrderFront(nil)
        return browserViewModel
    }

    func browserViewModel(containedIn view: NSView) -> BrowserViewModel? {
        if let browserView = view as? BrowserContentView {
            return browserView.viewModel
        }
        if let hostingView = view as? NSHostingView<BrowserPanelView> {
            return hostingView.rootView.viewModel
        }
        return nil
    }

    func goBackFocusedBrowserPanel() {
        activeBrowserViewModel()?.goBack()
    }

    func goForwardFocusedBrowserPanel() {
        activeBrowserViewModel()?.goForward()
    }

    /// Toggles the browser history panel.
    func toggleBrowserHistory() {
        if isBrowserHistoryVisible {
            dismissBrowserHistory()
        } else {
            showBrowserHistory()
        }
    }

    func showBrowserHistory() {
        guard let overlayContainer = overlayContainerView,
              let historyStore = browserHistoryStore else { return }

        let activeProfileID = browserProfileManager?.activeProfileID

        browserHistoryHostingView?.removeFromSuperview()
        var swiftUIView = BrowserHistoryView(
            historyStore: historyStore,
            activeProfileID: activeProfileID,
            onNavigate: { [weak self] url in
                self?.dismissBrowserHistory()
                self?.activeBrowserViewModel()?.navigate(to: url)
            },
            onDismiss: { [weak self] in self?.dismissBrowserHistory() }
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true

        let panelWidth: CGFloat = 320
        let containerBounds = overlayContainer.bounds
        let targetX = containerBounds.width - panelWidth

        hostingView.frame = NSRect(
            x: targetX, y: 0,
            width: panelWidth, height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.browserHistoryHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isBrowserHistoryVisible = true
    }

    func dismissBrowserHistory() {
        guard let hostingView = browserHistoryHostingView,
              let overlayContainer = overlayContainerView else {
            browserHistoryHostingView?.removeFromSuperview()
            browserHistoryHostingView = nil
            isBrowserHistoryVisible = false
            return
        }

        isBrowserHistoryVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.browserHistoryHostingView?.removeFromSuperview()
                self?.browserHistoryHostingView = nil
            }
        })
    }

    /// Toggles the browser bookmarks panel.
    func toggleBrowserBookmarks() {
        if isBrowserBookmarksVisible {
            dismissBrowserBookmarks()
        } else {
            showBrowserBookmarks()
        }
    }

    func showBrowserBookmarks() {
        guard let overlayContainer = overlayContainerView,
              let bookmarkStore = browserBookmarkStore else { return }

        browserBookmarksHostingView?.removeFromSuperview()
        var swiftUIView = BrowserBookmarksView(
            bookmarkStore: bookmarkStore,
            onNavigate: { [weak self] url in
                self?.dismissBrowserBookmarks()
                self?.activeBrowserViewModel()?.navigate(to: url)
            },
            onAddBookmark: { [weak self] in
                guard let vm = self?.activeBrowserViewModel(),
                      let pageURL = vm.currentURL else { return }
                let urlString = pageURL.absoluteString
                let title = vm.pageTitle.isEmpty ? urlString : vm.pageTitle
                try? bookmarkStore.save(BrowserBookmark(
                    title: title,
                    url: urlString
                ))
            },
            onDismiss: { [weak self] in self?.dismissBrowserBookmarks() }
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true

        let panelWidth: CGFloat = 320
        let containerBounds = overlayContainer.bounds
        let targetX = containerBounds.width - panelWidth

        hostingView.frame = NSRect(
            x: targetX, y: 0,
            width: panelWidth, height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.browserBookmarksHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isBrowserBookmarksVisible = true
    }

    func dismissBrowserBookmarks() {
        guard let hostingView = browserBookmarksHostingView,
              let overlayContainer = overlayContainerView else {
            browserBookmarksHostingView?.removeFromSuperview()
            browserBookmarksHostingView = nil
            isBrowserBookmarksVisible = false
            return
        }

        isBrowserBookmarksVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.browserBookmarksHostingView?.removeFromSuperview()
                self?.browserBookmarksHostingView = nil
            }
        })
    }
}
