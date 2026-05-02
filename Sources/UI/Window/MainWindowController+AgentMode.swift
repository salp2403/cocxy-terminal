// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+AgentMode.swift - Built-in Agent Mode panel wiring.

import AppKit
import SwiftUI

@MainActor
extension MainWindowController {

    func toggleAgentMode() {
        if isAgentModeVisible {
            dismissAgentMode()
        } else {
            showAgentModePanel()
        }
    }

    @objc func toggleAgentModeAction(_ sender: Any?) {
        toggleAgentMode()
    }

    func showAgentModePanel() {
        guard let overlayContainer = overlayContainerView else { return }

        let viewModel = resolveAgentPanelViewModel()
        agentModeHostingView?.removeFromSuperview()

        let swiftUIView = AgentPanelView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissAgentMode() }
        )
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelY = statusBarHostingView?.frame.height ?? 24
        hostingView.frame = NSRect(
            x: overlayContainer.bounds.width - AgentPanelView.panelWidth,
            y: panelY,
            width: AgentPanelView.panelWidth,
            height: max(0, overlayContainer.bounds.height - panelY)
        )
        hostingView.autoresizingMask = [.height, .minXMargin]

        agentModeHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        isAgentModeVisible = true
        layoutRightDockedAgentPanels()
    }

    func dismissAgentMode() {
        guard let hostingView = agentModeHostingView,
              let overlayContainer = overlayContainerView else {
            agentModeHostingView?.removeFromSuperview()
            agentModeHostingView = nil
            isAgentModeVisible = false
            return
        }

        isAgentModeVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.agentModeHostingView?.removeFromSuperview()
                self?.agentModeHostingView = nil
                self?.layoutRightDockedAgentPanels()
                self?.focusActiveTerminalSurface()
            }
        })
    }

    func resolveAgentPanelViewModel() -> AgentPanelViewModel {
        let configuration = configService?.current.agent ?? .defaults
        if let agentPanelViewModel {
            agentPanelViewModel.updateConfiguration(configuration)
            return agentPanelViewModel
        }

        let runner = injectedAgentPromptRunner ?? AgentSessionRunner(
            workspaceRootProvider: { [weak self] in
                self?.currentAgentModeWorkingDirectory()
            },
            conversationID: "window-\(windowID.rawValue.uuidString)",
            terminalOutputProvider: MainActorAgentTerminalOutputProvider { [weak self] limit in
                self?.latestAgentModeTerminalOutput(limit: limit) ?? ""
            },
            mcpManager: MCPConfiguredManager()
        )
        let viewModel = AgentPanelViewModel(
            configuration: configuration,
            runner: runner
        )
        agentPanelViewModel = viewModel
        return viewModel
    }

    func currentAgentModeWorkingDirectory() -> URL? {
        if let surfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID,
           let surfaceDirectory = surfaceWorkingDirectories[surfaceID] {
            return surfaceDirectory
        }

        if let surfaceID = activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
           let surfaceDirectory = surfaceWorkingDirectories[surfaceID] {
            return surfaceDirectory
        }

        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return nil }
        return tabManager.tab(for: tabID)?.workingDirectory
    }

    func latestAgentModeTerminalOutput(limit: Int) -> String {
        let boundedLimit = UInt32(min(max(limit, 1), 64))
        guard let surfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID
                ?? activeTerminalSurfaceView?.terminalViewModel?.surfaceID,
              let cocxyBridge = terminalEngine(for: surfaceID).cocxyCoreBridge else {
            return ""
        }

        return cocxyBridge.latestCommandBlockOutputs(
            for: surfaceID,
            limit: boundedLimit,
            stripANSI: true
        )
    }
}
