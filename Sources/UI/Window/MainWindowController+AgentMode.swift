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
            onDismiss: { [weak self] in self?.dismissAgentMode() },
            localizer: appLocalizer()
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

    func refreshVisibleAgentModeLocalizer() {
        guard let hostingView = agentModeHostingView,
              let agentPanelViewModel else { return }
        hostingView.rootView = AgentPanelView(
            viewModel: agentPanelViewModel,
            onDismiss: { [weak self] in self?.dismissAgentMode() },
            localizer: appLocalizer()
        )
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
            agentPanelViewModel.updateSkillRegistry(currentAgentModeSkillRegistry())
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
            lspDiagnosticsProvider: MainActorAgentLSPDiagnosticsProvider { [weak self] limit in
                self?.currentAgentModeLSPDiagnostics(limit: limit) ?? []
            },
            mcpManager: MCPConfiguredManager(),
            usageRecorder: { [weak self] usage in
                await self?.recordCurrentAgentModeTokenUsage(usage)
            }
        )
        let viewModel = AgentPanelViewModel(
            configuration: configuration,
            runner: runner,
            skillRegistry: currentAgentModeSkillRegistry()
        )
        agentPanelViewModel = viewModel
        return viewModel
    }

    func currentAgentModeSkillRegistry() -> SkillRegistry {
        SkillRegistry.localDefault(projectRoot: currentAgentModeWorkingDirectory())
    }

    func recordCurrentAgentModeTokenUsage(_ usage: AgentLLMUsage) {
        guard let tabID = visibleTabID ?? tabManager.activeTabID else { return }
        let surfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID
            ?? activeTerminalSurfaceView?.terminalViewModel?.surfaceID
        recordAgentTokenUsage(usage, tabID: tabID, surfaceID: surfaceID)
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

        let blocks = availableCommandBlocks(
            surfaceID: surfaceID,
            liveBlocks: cocxyBridge.commandBlocks(for: surfaceID, limit: boundedLimit),
            limit: boundedLimit
        )
        return TerminalBlockOutputContextFormatter.text(for: blocks)
    }

    func currentAgentModeLSPDiagnostics(limit: Int) -> [AgentLSPDiagnostic] {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0,
              let tabID = visibleTabID ?? tabManager.activeTabID else {
            return []
        }

        let workspaceURL = tabManager.tab(for: tabID)?.workingDirectory
        let diagnostics = lspDocumentTabIDs
            .filter { _, ownerTabID in ownerTabID == tabID }
            .flatMap { uri, _ -> [AgentLSPDiagnostic] in
                guard lspEditorViewsByDocumentURI[uri]?.value != nil,
                      let coordinator = lspWorkspaceCoordinators[tabID],
                      let currentDiagnostics = try? coordinator.diagnostics(forURI: uri) else {
                    return []
                }

                return currentDiagnostics.map { diagnostic in
                    AgentLSPDiagnostic(
                        path: agentModePath(forDocumentURI: uri, workspaceURL: workspaceURL),
                        line: diagnostic.range.start.line + 1,
                        column: diagnostic.range.start.character + 1,
                        severity: agentModeSeverity(for: diagnostic.severity),
                        message: diagnostic.message,
                        source: diagnostic.source
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.path != rhs.path { return lhs.path < rhs.path }
                if lhs.line != rhs.line { return lhs.line < rhs.line }
                if lhs.column != rhs.column { return lhs.column < rhs.column }
                if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
                return lhs.message < rhs.message
            }

        return Array(diagnostics.prefix(boundedLimit))
    }

    private func agentModePath(forDocumentURI uri: String, workspaceURL: URL?) -> String {
        guard let documentURL = URL(string: uri), documentURL.isFileURL else {
            return uri
        }

        let documentPath = documentURL.standardizedFileURL.path
        guard let workspaceURL else {
            return documentPath
        }

        let workspacePath = workspaceURL.standardizedFileURL.path
        if documentPath == workspacePath {
            return "."
        }

        let workspacePrefix = workspacePath.hasSuffix("/") ? workspacePath : "\(workspacePath)/"
        guard documentPath.hasPrefix(workspacePrefix) else {
            return documentPath
        }

        return String(documentPath.dropFirst(workspacePrefix.count))
    }

    private func agentModeSeverity(for severity: LSPDiagnosticSeverity) -> String {
        switch severity {
        case .error:
            return "error"
        case .warning:
            return "warning"
        case .information:
            return "information"
        case .hint:
            return "hint"
        }
    }
}
