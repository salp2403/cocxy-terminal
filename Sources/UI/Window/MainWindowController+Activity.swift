// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Activity.swift - Local Activity dashboard panel wiring.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {

    func toggleActivityDashboard() {
        if isActivityDashboardVisible {
            dismissActivityDashboard()
        } else {
            showActivityDashboardPanel()
        }
    }

    @objc func toggleActivityDashboardAction(_ sender: Any?) {
        toggleActivityDashboard()
    }

    func showActivityDashboardPanel() {
        guard let overlayContainer = overlayContainerView,
              let viewModel = resolveActivityDashboardViewModel() else {
            return
        }

        activityDashboardHostingView?.removeFromSuperview()
        let swiftUIView = ActivityDashboardView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissActivityDashboard() }
        )
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true

        let panelY = statusBarHostingView?.frame.height ?? 24
        hostingView.frame = NSRect(
            x: overlayContainer.bounds.width - ActivityDashboardView.panelWidth,
            y: panelY,
            width: ActivityDashboardView.panelWidth,
            height: max(0, overlayContainer.bounds.height - panelY)
        )
        hostingView.autoresizingMask = [.height, .minXMargin]

        activityDashboardHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        isActivityDashboardVisible = true
        layoutRightDockedAgentPanels()
    }

    func dismissActivityDashboard() {
        guard let hostingView = activityDashboardHostingView,
              let overlayContainer = overlayContainerView else {
            activityDashboardHostingView?.removeFromSuperview()
            activityDashboardHostingView = nil
            isActivityDashboardVisible = false
            return
        }

        isActivityDashboardVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.activityDashboardHostingView?.removeFromSuperview()
                self?.activityDashboardHostingView = nil
                self?.layoutRightDockedAgentPanels()
                self?.focusActiveTerminalSurface()
            }
        })
    }

    func resolveActivityDashboardViewModel() -> ActivityDashboardViewModel? {
        let policy = configService?.current.activity.privacyPolicy ?? .disabled
        if let activityDashboardViewModel {
            activityDashboardViewModel.setPrivacyPolicy(policy)
            activityDashboardViewModel.refresh()
            return activityDashboardViewModel
        }

        do {
            let store = try resolveActivityStore()
            let viewModel = ActivityDashboardViewModel(
                store: store,
                privacyPolicy: policy
            )
            activityDashboardViewModel = viewModel
            return viewModel
        } catch {
            return nil
        }
    }

    func refreshActivityDashboardPrivacyState(_ config: ActivityConfig) {
        activityDashboardViewModel?.setPrivacyPolicy(config.privacyPolicy)
    }

    private func resolveActivityStore() throws -> ActivityStoring {
        if let injectedActivityStore {
            return injectedActivityStore
        }
        return try SQLiteActivityStore(databasePath: activityDatabaseURL().path)
    }

    private func activityDatabaseURL() -> URL {
        let configuredDirectory = configService?.current.activity.storageDirectory
            ?? ActivityConfig.defaults.storageDirectory
        let expandedDirectory = (configuredDirectory as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedDirectory, isDirectory: true)
            .appendingPathComponent("activity.sqlite")
    }
}
