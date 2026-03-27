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
        let swiftUIView = BrowserHistoryView(
            historyStore: historyStore,
            activeProfileID: activeProfileID,
            onNavigate: { [weak self] url in
                self?.dismissBrowserHistory()
                self?.browserViewModel?.navigate(to: url)
            },
            onDismiss: { [weak self] in self?.dismissBrowserHistory() }
        )
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
        let swiftUIView = BrowserBookmarksView(
            bookmarkStore: bookmarkStore,
            onNavigate: { [weak self] url in
                self?.dismissBrowserBookmarks()
                self?.browserViewModel?.navigate(to: url)
            },
            onAddBookmark: { [weak self] in
                guard let vm = self?.browserViewModel,
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
