// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+NotificationPanel.swift - Notification panel lifecycle.

import AppKit
import QuartzCore

@MainActor
extension MainWindowController {
    func toggleNotificationPanel() {
        if isNotificationPanelVisible {
            dismissNotificationPanel()
        } else {
            showNotificationPanel()
        }
    }

    @objc func toggleNotificationPanelAction(_ sender: Any?) {
        toggleNotificationPanel()
    }

    func showNotificationPanel() {
        guard let overlayContainer = overlayContainerView else { return }

        if notificationPanelViewModel == nil {
            notificationPanelViewModel = NotificationPanelViewModel(
                notificationManager: injectedNotificationManager
            )
            notificationPanelViewModel?.onNavigateToTab = { [weak self] tabId in
                self?.dismissNotificationPanel()
                self?.tabManager.setActive(id: tabId)
            }
        }

        guard let viewModel = notificationPanelViewModel else { return }

        notificationPanelHostingView?.removeFromSuperview()
        var swiftUIView = NotificationPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissNotificationPanel() },
            localizer: appLocalizer()
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = makeShellHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelWidth: CGFloat = NotificationPanelView.panelWidth
        let containerBounds = overlayContainer.bounds

        let targetX = trailingPanelOrigin(
            containerWidth: containerBounds.width,
            panelWidth: panelWidth
        )
        hostingView.frame = NSRect(
            x: targetX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
        hostingView.autoresizingMask = trailingPanelAutoresizingMask(including: .height)
        self.notificationPanelHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isNotificationPanelVisible = true
        layoutTrailingDockedPanels()
    }

    func dismissNotificationPanel() {
        guard let hostingView = notificationPanelHostingView,
              let overlayContainer = overlayContainerView else {
            notificationPanelHostingView?.removeFromSuperview()
            notificationPanelHostingView = nil
            isNotificationPanelVisible = false
            return
        }

        isNotificationPanelVisible = false
        let targetX = trailingPanelExitOrigin(
            containerWidth: overlayContainer.bounds.width,
            panelWidth: hostingView.frame.width
        )
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.notificationPanelHostingView?.removeFromSuperview()
                self?.notificationPanelHostingView = nil
                self?.layoutTrailingDockedPanels()
            }
        })

        focusActiveTerminalSurface()
    }
}
