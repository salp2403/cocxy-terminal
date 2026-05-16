// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+VaultSidebar.swift - Visual Vault sidebar wiring.

import AppKit
import CocxyVault
import Foundation
import SwiftUI

@MainActor
extension MainWindowController {
    func toggleVaultSidebar() {
        if isVaultSidebarVisible {
            dismissVaultSidebar()
        } else {
            showVaultSidebar()
        }
    }

    @objc func toggleVaultSidebarAction(_ sender: Any?) {
        toggleVaultSidebar()
    }

    func showVaultSidebar() {
        guard let overlayContainer = overlayContainerView else { return }
        let viewModel = resolveVaultSidebarViewModel()
        viewModel.setActiveWorkspacePath(currentVaultWorkingDirectory()?.path)

        vaultSidebarHostingView?.removeFromSuperview()
        vaultSidebarPanelWidth = clampedVaultSidebarPanelWidth(
            viewModel.widthMode.panelWidth,
            containerWidth: overlayContainer.bounds.width
        )

        var swiftUIView = makeVaultSidebarView(viewModel: viewModel, panelWidth: vaultSidebarPanelWidth)
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelY = statusBarHostingView?.frame.height ?? 24
        hostingView.frame = NSRect(
            x: overlayContainer.bounds.width - vaultSidebarPanelWidth,
            y: panelY,
            width: vaultSidebarPanelWidth,
            height: max(0, overlayContainer.bounds.height - panelY)
        )
        hostingView.autoresizingMask = [.height, .minXMargin]

        vaultSidebarHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        isVaultSidebarVisible = true
        layoutRightDockedAgentPanels()
    }

    func dismissVaultSidebar() {
        guard let hostingView = vaultSidebarHostingView,
              let overlayContainer = overlayContainerView else {
            vaultSidebarHostingView?.removeFromSuperview()
            vaultSidebarHostingView = nil
            isVaultSidebarVisible = false
            return
        }

        isVaultSidebarVisible = false
        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.vaultSidebarHostingView?.removeFromSuperview()
                self?.vaultSidebarHostingView = nil
                self?.layoutRightDockedAgentPanels()
                self?.focusActiveTerminalSurface()
            }
        })
    }

    func resolveVaultSidebarViewModel() -> VaultSidebarViewModel {
        if let vaultSidebarViewModel {
            return vaultSidebarViewModel
        }
        if let injectedVaultSidebarViewModel {
            vaultSidebarViewModel = injectedVaultSidebarViewModel
            return injectedVaultSidebarViewModel
        }

        let store = VaultSessionStore.defaultStore()
        do {
            let index = try VaultSearchIndex()
            let viewModel = VaultSidebarViewModel(store: store, searchIndex: index)
            viewModel.setActiveWorkspacePath(currentVaultWorkingDirectory()?.path)
            vaultSidebarViewModel = viewModel
            return viewModel
        } catch {
            let fallbackIndex = VaultSearchIndexUnavailable(error: error)
            let viewModel = VaultSidebarViewModel(store: store, searchIndex: fallbackIndex)
            viewModel.setActiveWorkspacePath(currentVaultWorkingDirectory()?.path)
            vaultSidebarViewModel = viewModel
            return viewModel
        }
    }

    func syncVaultSidebarRootView(panelWidth: CGFloat? = nil) {
        guard isVaultSidebarVisible,
              let hostingView = vaultSidebarHostingView,
              let viewModel = vaultSidebarViewModel else {
            return
        }
        let width = clampedVaultSidebarPanelWidth(
            panelWidth ?? viewModel.widthMode.panelWidth,
            containerWidth: overlayContainerView?.bounds.width ?? VaultSidebarView.defaultPanelWidth
        )
        vaultSidebarPanelWidth = width
        var view = makeVaultSidebarView(viewModel: viewModel, panelWidth: width)
        view.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        hostingView.rootView = view
    }

    func syncVaultSidebarVibrancyOverride(_ override: NSAppearance?) {
        guard isVaultSidebarVisible,
              let hostingView = vaultSidebarHostingView,
              let viewModel = vaultSidebarViewModel else { return }
        var view = makeVaultSidebarView(viewModel: viewModel, panelWidth: vaultSidebarPanelWidth)
        view.vibrancyAppearanceOverride = override
        hostingView.rootView = view
    }

    func vaultSidebarStatsSnapshot() -> [String: String] {
        let viewModel = resolveVaultSidebarViewModel()
        return [
            "visible": isVaultSidebarVisible ? "true" : "false",
            "session_count": "\(viewModel.sessions.count)",
            "filtered_count": "\(viewModel.filteredSessions.count)",
            "selected_count": "\(viewModel.selectedSessionIDs.count)",
            "pinned_count": "\(viewModel.pinnedSessionIDs.count)",
            "width_mode": viewModel.widthMode.rawValue,
        ]
    }

    func handleVaultSessionDrop(_ payload: VaultSessionDragPayload, surfaceID: SurfaceID) -> Bool {
        do {
            let session = try VaultSessionStore.defaultStore()
                .loadSessions()
                .first { $0.id == payload.sessionID && $0.agentID.rawValue == payload.agentID }
            guard let session else { return false }
            return sendVaultResumeCommand(for: session, to: surfaceID)
        } catch {
            return false
        }
    }

    private func makeVaultSidebarView(
        viewModel: VaultSidebarViewModel,
        panelWidth: CGFloat
    ) -> VaultSidebarView {
        VaultSidebarView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissVaultSidebar() },
            onNewSession: { [weak self] in self?.createTab(workingDirectory: self?.currentVaultWorkingDirectory()) },
            onResume: { [weak self] session in
                self?.resumeVaultSession(session, inNewTab: false)
            },
            onResumeInNewTab: { [weak self] session in
                self?.resumeVaultSession(session, inNewTab: true)
            },
            onExport: { [weak self] sessions, format in
                self?.exportVaultSessions(sessions, format: format)
            },
            onCompare: { [weak self] session in
                self?.compareVaultSession(session)
            },
            onWidthModeChanged: { [weak self] in
                self?.layoutRightDockedAgentPanels()
            },
            panelWidth: panelWidth,
            localizer: appLocalizer()
        )
    }

    func clampedVaultSidebarPanelWidth(
        _ proposed: CGFloat,
        containerWidth: CGFloat
    ) -> CGFloat {
        let absolute = min(max(proposed, VaultSidebarView.minimumPanelWidth), VaultSidebarView.maximumPanelWidth)
        let reservedTerminalWidth: CGFloat = 280
        let siblingWidth: CGFloat = [
            isTimelineVisible ? DashboardPanelView.panelWidth : CGFloat(0),
            isDashboardVisible ? DashboardPanelView.panelWidth : CGFloat(0),
            isActivityDashboardVisible ? ActivityDashboardView.panelWidth : CGFloat(0),
            isAgentModeVisible ? AgentPanelView.panelWidth : CGFloat(0),
            isCodeReviewVisible ? codeReviewPanelWidth : CGFloat(0),
            isGitHubPaneVisible ? gitHubPanePanelWidth : CGFloat(0),
            isNotesVisible ? clampedNotesPanelWidth(containerWidth: containerWidth) : CGFloat(0),
        ].reduce(0, +)
        let maximum = max(
            VaultSidebarView.minimumPanelWidth,
            min(containerWidth * 0.75, containerWidth - siblingWidth - reservedTerminalWidth)
        )
        return min(absolute, maximum)
    }

    private func currentVaultWorkingDirectory() -> URL? {
        if let tabID = visibleTabID ?? tabManager.activeTabID,
           let tab = tabManager.tab(for: tabID) {
            return tab.worktreeRoot ?? tab.workingDirectory
        }
        return nil
    }

    private func resumeVaultSession(_ session: VaultSession, inNewTab: Bool) {
        if inNewTab {
            let tabID = createTab(
                workingDirectory: session.workingDirectory.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                } ?? currentVaultWorkingDirectory()
            )
            guard let surfaceID = tabSurfaceMap[tabID] else { return }
            _ = sendVaultResumeCommand(for: session, to: surfaceID)
            return
        }

        guard let surfaceID = focusedSplitSurfaceView?.terminalViewModel?.surfaceID
            ?? activeTerminalSurfaceView?.terminalViewModel?.surfaceID else { return }
        _ = sendVaultResumeCommand(for: session, to: surfaceID)
    }

    private func sendVaultResumeCommand(for session: VaultSession, to surfaceID: SurfaceID) -> Bool {
        do {
            guard let agent = VaultAgentRegistry.builtIn.agent(matching: session.agentID.rawValue) else {
                return false
            }
            let invocation = try VaultSessionResumer.plan(agent: agent, session: session)
            terminalEngine(for: surfaceID).sendText(
                VaultShellCommandRenderer.commandLine(for: invocation),
                to: surfaceID
            )
            return true
        } catch {
            return false
        }
    }

    private func exportVaultSessions(_ sessions: [VaultSession], format: VaultSessionExportFormat) {
        do {
            let data = try VaultSessionExportFormatter.data(for: sessions, format: format)
            MainWindowController.saveExportedData(
                data,
                suggestedName: VaultSessionExportFormatter.suggestedFilename(for: sessions, format: format),
                localizer: appLocalizer()
            )
        } catch {
            NSLog("[Cocxy] Failed to export Vault session: %@", String(describing: error))
        }
    }

    private func compareVaultSession(_ session: VaultSession) {
        let selectedIDs = vaultSidebarViewModel?.selectedSessionIDs ?? []
        guard selectedIDs.count == 1,
              let otherID = selectedIDs.first,
              otherID != session.id,
              let other = try? VaultSessionStore.defaultStore()
                .loadSessions()
                .first(where: { $0.id == otherID }) else {
            presentVaultSessionSummary(session)
            return
        }

        let alert = NSAlert()
        alert.messageText = appLocalizer().string("vault.compare.title", fallback: "Vault Compare")
        alert.informativeText = """
        \(session.agentDisplayName) \(session.sessionID)
        \(other.agentDisplayName) \(other.sessionID)

        \(appLocalizer().string("vault.compare.workspace", fallback: "Workspace"))
        \(session.workingDirectory ?? "-")
        \(other.workingDirectory ?? "-")

        \(appLocalizer().string("vault.compare.arguments", fallback: "Arguments"))
        \(session.sanitizedArguments.joined(separator: " "))
        \(other.sanitizedArguments.joined(separator: " "))
        """
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func presentVaultSessionSummary(_ session: VaultSession) {
        let alert = NSAlert()
        alert.messageText = appLocalizer().string("vault.preview.title", fallback: "Vault Session")
        alert.informativeText = [
            "\(session.agentDisplayName) \(session.sessionID)",
            session.workingDirectory,
            session.sanitizedArguments.joined(separator: " "),
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private struct VaultSearchIndexUnavailable: VaultSearchIndexing {
    let error: Error

    func indexSession(_ session: VaultSession) throws {
        throw error
    }

    func removeSession(id: String) throws {
        throw error
    }

    func search(query: String, filters: VaultSearchFilters) throws -> [VaultSearchResult] {
        throw error
    }

    func rebuild() throws {
        throw error
    }
}
