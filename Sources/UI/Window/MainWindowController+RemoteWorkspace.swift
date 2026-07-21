// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+RemoteWorkspace.swift - Remote workspace overlay toggle.

import AppKit
import Combine
import SwiftUI

// MARK: - Remote Workspace Panel

/// Extension that manages the Remote Workspace overlay panel.
///
/// The panel slides in from the right edge of the window, following the
/// same pattern as the Dashboard and Timeline panels in +Overlays.swift.
///
/// Triggered by Cmd+Shift+R from the menu bar or Command Palette.
extension MainWindowController {

    /// Toggles the remote workspace panel visibility.
    func toggleRemoteWorkspacePanel() {
        if isRemoteWorkspaceVisible {
            dismissRemoteWorkspacePanel()
        } else {
            showRemoteWorkspacePanel()
        }
    }

    @objc func toggleRemoteWorkspacePanelAction(_ sender: Any?) {
        toggleRemoteWorkspacePanel()
    }

    func showRemoteWorkspacePanel() {
        guard let overlayContainer = overlayContainerView else { return }

        guard let connectionManager = remoteConnectionManager,
              let profileStore = remoteProfileStore,
              let tunnelManager = tunnelManager else {
            NSLog("[MainWindowController] Remote workspace services not initialized")
            return
        }

        if remoteConnectionViewModel == nil {
            remoteConnectionViewModel = RemoteConnectionViewModel(
                profileStore: profileStore,
                connectionManager: connectionManager,
                tunnelManager: tunnelManager,
                localizer: appLocalizer()
            )
            remoteConnectionViewModel?.loadProfiles()
        }

        guard let viewModel = remoteConnectionViewModel else { return }
        viewModel.updateLocalizer(appLocalizer())

        remoteWorkspaceHostingView?.removeFromSuperview()
        var swiftUIView = RemoteConnectionView(
            viewModel: viewModel,
            onDismiss: { [weak self] in self?.dismissRemoteWorkspacePanel() },
            localizer: appLocalizer(),
            sshKeyManager: sshKeyManager,
            sftpExecutor: SystemSFTPExecutor(),
            remotePortScanner: remotePortScanner,
            onOpenRemoteBrowser: { [weak self] profile, suggestion in
                self?.openRemoteBrowser(profile: profile, suggestion: suggestion) ?? false
            }
        )
        swiftUIView.vibrancyAppearanceOverride = resolveVibrancyAppearanceOverride()
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true

        let panelWidth: CGFloat = RemoteConnectionView.panelWidth
        let containerBounds = overlayContainer.bounds

        let targetX = containerBounds.width - panelWidth
        hostingView.frame = NSRect(
            x: targetX,
            y: 0,
            width: panelWidth,
            height: containerBounds.height
        )
        hostingView.autoresizingMask = [.height, .minXMargin]
        self.remoteWorkspaceHostingView = hostingView

        overlayContainer.addSubview(hostingView)
        isRemoteWorkspaceVisible = true
    }

    func dismissRemoteWorkspacePanel() {
        guard let hostingView = remoteWorkspaceHostingView,
              let overlayContainer = overlayContainerView else {
            remoteWorkspaceHostingView?.removeFromSuperview()
            remoteWorkspaceHostingView = nil
            isRemoteWorkspaceVisible = false
            return
        }

        isRemoteWorkspaceVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.remoteWorkspaceHostingView?.removeFromSuperview()
                self?.remoteWorkspaceHostingView = nil
            }
        })

        focusActiveTerminalSurface()
    }

    @discardableResult
    func openRemoteBrowser(
        profile: RemoteConnectionProfile,
        suggestion: RemoteBrowserOpenSuggestion
    ) -> Bool {
        guard let remoteConnectionManager,
              case .connected = remoteConnectionManager.connections[profile.id],
              let remotePortScanner,
              remotePortScanner.scanningProfileID == profile.id,
              suggestion.profileID == profile.id,
              remotePortScanner.forwardedPortMappings[suggestion.remotePort]
                == suggestion.localPort else {
            return false
        }
        guard let viewModel = browserViewModelForExternalNavigation() else { return false }
        let proxyState = remoteConnectionManager.proxyManager?.state ?? .off
        let remoteProfile = remotePortScanner.browserProfile(
            for: profile,
            proxyState: proxyState
        )

        guard viewModel.openRemoteForward(
            remoteProfile,
            remotePort: suggestion.remotePort,
            scheme: suggestion.localURL.scheme ?? "http"
        ) != nil else { return false }
        let activeProfileIDs = Set(remoteConnectionManager.connections.compactMap { profileID, state in
            if case .connected = state { return profileID }
            return nil
        })
        viewModel.updateInitScriptRemoteConnectionAvailability(
            activeConnectionProfileIDs: activeProfileIDs
        )
        viewModel.updateInitScriptRemoteForwardLeaseAvailability(
            scanningProfileID: remotePortScanner.scanningProfileID,
            forwardedPortMappings: remotePortScanner.forwardedPortMappings
        )
        bindRemoteBrowserProxyState(to: viewModel, profileID: profile.id)
        return true
    }

    func bindRemoteBrowserProxyState(to viewModel: BrowserViewModel, profileID: UUID) {
        remoteBrowserProxyStateCancellable?.cancel()
        remoteBrowserProxyStateCancellable = remoteConnectionManager?.proxyManager?.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak viewModel] proxyState in
                guard let viewModel,
                      viewModel.activeRemoteBrowserProfile?.connectionProfileID == profileID else {
                    return
                }
                viewModel.updateRemoteBrowserProxyState(proxyState)
            }
    }
}
