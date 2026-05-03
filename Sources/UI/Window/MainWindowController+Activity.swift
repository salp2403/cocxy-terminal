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
        let currentStorePath = currentActivityStorePath()
        if let activityDashboardViewModel,
           injectedActivityStore != nil || activityDashboardStorePath == currentStorePath {
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
            activityDashboardStorePath = currentStorePath
            refreshVisibleActivityDashboardRootIfNeeded(viewModel)
            return viewModel
        } catch {
            return nil
        }
    }

    func refreshActivityDashboardPrivacyState(_ config: ActivityConfig) {
        if injectedActivityStore == nil,
           let activityStorePath,
           activityStorePath != activityDatabaseURL(for: config).path {
            activityStore = nil
            self.activityStorePath = nil
            activityDashboardViewModel = nil
            activityDashboardStorePath = nil
        }
        activityDashboardViewModel?.setPrivacyPolicy(config.privacyPolicy)
        if isActivityDashboardVisible {
            _ = resolveActivityDashboardViewModel()
        }
    }

    func recordLocalActivity(
        kind: ActivityEventKind,
        summary: String,
        workingDirectory: URL? = nil,
        sessionID: String? = nil,
        metadata: [String: String] = [:]
    ) {
        let policy = configService?.current.activity.privacyPolicy ?? .disabled
        guard policy.activityTrackingEnabled else { return }

        do {
            let store = try resolveActivityStore()
            let recorder = ActivityRecorder(
                store: store,
                policyProvider: { policy }
            )
            let event = ActivityEvent(
                kind: kind,
                sessionID: sessionID,
                project: workingDirectory.map(ActivityProjectRef.workingDirectory(_:)),
                summary: summary,
                metadata: metadata
            )
            try recorder.record(event)
            if activityDashboardViewModel != nil {
                _ = resolveActivityDashboardViewModel()
            }
            activityDashboardViewModel?.refresh()
        } catch {
            return
        }
    }

    func recordCommandBlockActivity(
        _ block: TerminalCommandBlock,
        tabID: TabID,
        surfaceID: SurfaceID?
    ) {
        var metadata = [
            "block_id": "\(block.id)",
            "duration_ms": "\(block.durationNs / 1_000_000)",
        ]
        if let exitCode = block.exitCode {
            metadata["exit_code"] = "\(exitCode)"
        }
        if let surfaceID {
            metadata["surface_id"] = surfaceID.rawValue.uuidString
        }

        let workingDirectory = block.pwd.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? tabManager.tab(for: tabID)?.workingDirectory
        recordLocalActivity(
            kind: .commandExecuted,
            summary: commandActivitySummary(block.command),
            workingDirectory: workingDirectory,
            sessionID: sessionIDForTab(tabID).rawValue.uuidString,
            metadata: metadata
        )
    }

    private func resolveActivityStore() throws -> ActivityStoring {
        if let injectedActivityStore {
            return injectedActivityStore
        }
        let databasePath = currentActivityStorePath()
        if let activityStore, activityStorePath == databasePath {
            return activityStore
        }
        let store = try SQLiteActivityStore(databasePath: databasePath)
        activityStore = store
        activityStorePath = databasePath
        return store
    }

    private func currentActivityStorePath() -> String {
        activityDatabaseURL().path
    }

    private func activityDatabaseURL() -> URL {
        activityDatabaseURL(for: configService?.current.activity ?? .defaults)
    }

    private func activityDatabaseURL(for config: ActivityConfig) -> URL {
        let configuredDirectory = config.storageDirectory
        let expandedDirectory = (configuredDirectory as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedDirectory, isDirectory: true)
            .appendingPathComponent("activity.sqlite")
    }

    private func commandActivitySummary(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Command finished" }
        if trimmed.count <= 240 { return trimmed }
        return String(trimmed.prefix(237)) + "..."
    }

    func projectSwitchActivitySummary(_ directory: URL) -> String {
        let name = directory.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? directory.path : name
    }

    private func refreshVisibleActivityDashboardRootIfNeeded(_ viewModel: ActivityDashboardViewModel) {
        guard let hostingView = activityDashboardHostingView else { return }
        hostingView.rootView = ActivityDashboardView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissActivityDashboard() }
        )
    }
}
