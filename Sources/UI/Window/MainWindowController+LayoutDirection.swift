// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+LayoutDirection.swift - Logical shell geometry and host creation.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {
    var shellLayoutDirection: NSUserInterfaceLayoutDirection {
        ApplicationLayoutDirectionCoordinator.resolvedDirection(for: appLocalizer())
    }

    func applyShellLayoutDirection(to view: NSView) {
        ApplicationLayoutDirectionCoordinator.apply(shellLayoutDirection, to: view)
    }

    func markAsApplicationManaged(_ window: NSWindow) {
        ApplicationLayoutDirectionCoordinator.markAsApplicationManaged(window)
        if let contentView = window.contentView {
            applyShellLayoutDirection(to: contentView)
        }
    }

    func makeShellHostingView<Content: View>(rootView: Content) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        applyShellLayoutDirection(to: hostingView)
        return hostingView
    }

    func makeShellHostingController<Content: View>(
        rootView: Content
    ) -> NSHostingController<Content> {
        let hostingController = NSHostingController(rootView: rootView)
        applyShellLayoutDirection(to: hostingController.view)
        return hostingController
    }

    func trailingPanelOrigin(containerWidth: CGFloat, panelWidth: CGFloat) -> CGFloat {
        DirectionalPanelGeometry.trailingOrigin(
            containerWidth: containerWidth,
            panelWidth: panelWidth,
            direction: shellLayoutDirection
        )
    }

    func trailingPanelExitOrigin(containerWidth: CGFloat, panelWidth: CGFloat) -> CGFloat {
        DirectionalPanelGeometry.trailingExitOrigin(
            containerWidth: containerWidth,
            panelWidth: panelWidth,
            direction: shellLayoutDirection
        )
    }

    func trailingPanelAutoresizingMask(
        including base: NSView.AutoresizingMask = []
    ) -> NSView.AutoresizingMask {
        var mask = base
        mask.insert(shellLayoutDirection == .rightToLeft ? .maxXMargin : .minXMargin)
        return mask
    }
}
