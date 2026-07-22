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
                await self?.openRemoteBrowser(profile: profile, suggestion: suggestion) ?? false
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
    ) async -> Bool {
        guard let remoteConnectionManager,
              case .connected = remoteConnectionManager.connections[profile.id],
              let remotePortScanner,
              remotePortScanner.scanningProfileID == profile.id,
              suggestion.profileID == profile.id,
              suggestion.browserURL.port == suggestion.remotePort,
              remotePortScanner.detectedPorts.contains(where: {
                  $0.port == suggestion.remotePort
              }) else {
            return false
        }
        guard let viewModel = browserViewModelForExternalNavigation() else { return false }

        let openingID = UUID()
        remoteBrowserOpeningID = openingID
        remoteBrowserOpeningViewModel = viewModel
        defer {
            if remoteBrowserOpeningID == openingID {
                remoteBrowserOpeningID = nil
                remoteBrowserOpeningViewModel = nil
            }
        }
        remoteBrowserOpenGeneration &+= 1
        let generation = remoteBrowserOpenGeneration
        let session = makeRemoteBrowserProxySession(
            profileID: profile.id,
            remotePort: suggestion.remotePort,
            connectionManager: remoteConnectionManager
        )
        let capability: RemoteBrowserProxyCapability
        do {
            capability = try await session.start()
            try await BrowserWebsiteDataStoreFactory.prepareRemoteNetworkIsolation(
                for: capability
            )
        } catch {
            session.stop()
            return false
        }

        guard generation == remoteBrowserOpenGeneration,
              session.capability?.id == capability.id,
              remotePortScanner.scanningProfileID == profile.id,
              remotePortScanner.detectedPorts.contains(where: {
                  $0.port == suggestion.remotePort
              }),
              case .connected = remoteConnectionManager.connections[profile.id] else {
            session.stop()
            return false
        }

        let remoteProfile = RemoteBrowserProfile(
            remoteConnectionProfile: profile,
            socksPort: capability.localProxyPort,
            proxyHealth: .active
        )
        let previousSession = remoteBrowserProxySession
        let previousViewModel = remoteBrowserRouteViewModel
        let previousCapability = previousSession?.capability
            ?? previousViewModel?.activeRemoteBrowserProxyCapability

        guard viewModel.openRemoteBrokeredRoute(
            remoteProfile,
            capability: capability,
            scheme: suggestion.browserURL.scheme ?? "http",
            path: suggestion.browserURL.path.isEmpty ? "/" : suggestion.browserURL.path
        ) != nil else {
            session.stop()
            return false
        }

        remoteBrowserProxySession = session
        remoteBrowserRouteViewModel = viewModel
        remoteBrowserRouteProfile = profile
        remoteBrowserRouteSuggestion = suggestion
        installRemoteBrowserSessionCallbacks(session, viewModel: viewModel)
        scheduleRemoteBrowserProxyRenewal(
            sessionID: capability.id,
            expiresAt: capability.expiresAt
        )
        previousSession?.stop()
        if let previousCapability,
           !BrowserWebsiteDataStoreFactory.sharesRemoteDataStoreScope(
               previousCapability,
               capability
           ) {
            BrowserWebsiteDataStoreFactory.releaseRemoteDataStore(
                for: previousCapability
            )
        }
        if let previousViewModel, previousViewModel !== viewModel {
            previousViewModel.onRetryRemoteBrowserRoute = nil
            previousViewModel.clearRemoteBrowserProfile()
        }

        let activeProfileIDs = Set(remoteConnectionManager.connections.compactMap { profileID, state in
            if case .connected = state { return profileID }
            return nil
        })
        viewModel.updateInitScriptRemoteConnectionAvailability(
            activeConnectionProfileIDs: activeProfileIDs
        )
        return true
    }

    func revokeRemoteBrowserRoute(profileID: UUID, reason: String) {
        guard remoteBrowserProxySession?.profileID == profileID
                || remoteBrowserRouteProfile?.id == profileID
        else { return }
        remoteBrowserOpenGeneration &+= 1
        remoteBrowserProxyRenewalTask?.cancel()
        remoteBrowserProxyRenewalTask = nil
        remoteBrowserProxySession?.stop()
        remoteBrowserProxySession = nil
        remoteBrowserRouteViewModel?.markRemoteBrowserProxyFailed(reason)
    }

    /// Revokes a route when its concrete browser surface leaves this window.
    /// Hidden overlay browsers intentionally keep their state; split close,
    /// tab close, transfer, and window teardown call this ownership boundary.
    func revokeRemoteBrowserRouteOwnership(of viewModel: BrowserViewModel) {
        let ownsOpening = remoteBrowserOpeningViewModel === viewModel
        let ownsActiveRoute = remoteBrowserRouteViewModel === viewModel
        guard ownsOpening || ownsActiveRoute else { return }

        remoteBrowserOpenGeneration &+= 1
        if ownsOpening {
            remoteBrowserOpeningID = nil
            remoteBrowserOpeningViewModel = nil
        }
        guard ownsActiveRoute else { return }

        remoteBrowserProxyStateCancellable?.cancel()
        remoteBrowserProxyStateCancellable = nil
        remoteBrowserProxyRenewalTask?.cancel()
        remoteBrowserProxyRenewalTask = nil
        let capability = remoteBrowserProxySession?.capability
            ?? viewModel.activeRemoteBrowserProxyCapability
        remoteBrowserProxySession?.stop()
        remoteBrowserProxySession = nil
        remoteBrowserRouteViewModel = nil
        remoteBrowserRouteProfile = nil
        remoteBrowserRouteSuggestion = nil
        viewModel.onRetryRemoteBrowserRoute = nil
        if let capability {
            BrowserWebsiteDataStoreFactory.releaseRemoteDataStore(for: capability)
        }
        viewModel.clearRemoteBrowserProfile()
    }

    private func makeRemoteBrowserProxySession(
        profileID: UUID,
        remotePort: Int,
        connectionManager: RemoteConnectionManager
    ) -> RemoteBrowserProxySession {
        RemoteBrowserProxySession(
            ownerWindowID: windowID,
            profileID: profileID,
            remotePort: remotePort,
            forwarder: connectionManager
        )
    }

    private func installRemoteBrowserSessionCallbacks(
        _ session: RemoteBrowserProxySession,
        viewModel: BrowserViewModel
    ) {
        session.invalidationHandler = { [weak self, weak session, weak viewModel] invalidation in
            guard let self, let session, let viewModel,
                  self.remoteBrowserProxySession === session else { return }
            self.remoteBrowserProxyRenewalTask?.cancel()
            self.remoteBrowserProxyRenewalTask = nil
            self.remoteBrowserProxySession = nil
            switch invalidation {
            case .expired:
                viewModel.markRemoteBrowserProxyFailed("The protected browser route expired")
            case .listenerFailed:
                viewModel.markRemoteBrowserProxyFailed("The protected browser route stopped")
            }
        }

        viewModel.onRetryRemoteBrowserRoute = { [weak self, weak viewModel] request in
            guard let self, let viewModel,
                  self.remoteBrowserRouteViewModel === viewModel,
                  let profile = self.remoteBrowserRouteProfile,
                  let suggestion = self.remoteBrowserRouteSuggestion,
                  suggestion.remotePort == request.remotePort else { return }
            Task { @MainActor [weak self] in
                guard let self, let scanner = self.remotePortScanner else { return }
                guard let freshSuggestion = try? scanner.beginBrowserOpen(request.remotePort) else {
                    return
                }
                defer { scanner.finishBrowserOpen(request.remotePort) }
                var components = URLComponents(
                    url: freshSuggestion.browserURL,
                    resolvingAgainstBaseURL: false
                )
                components?.scheme = request.scheme
                components?.path = request.path
                let reopenedSuggestion = RemoteBrowserOpenSuggestion(
                    profileID: freshSuggestion.profileID,
                    remotePort: freshSuggestion.remotePort,
                    process: freshSuggestion.process,
                    remoteAddress: freshSuggestion.remoteAddress,
                    browserURL: components?.url ?? suggestion.browserURL
                )
                _ = await self.openRemoteBrowser(
                    profile: profile,
                    suggestion: reopenedSuggestion
                )
            }
        }

        remoteBrowserProxyStateCancellable?.cancel()
        remoteBrowserProxyStateCancellable = viewModel.$activeRemoteBrowserProfile
            .dropFirst()
            .sink { [weak self, weak viewModel] remoteProfile in
                guard let self, let viewModel,
                      self.remoteBrowserRouteViewModel === viewModel,
                      remoteProfile?.connectionProfileID != self.remoteBrowserRouteProfile?.id
                else { return }
                self.remoteBrowserOpenGeneration &+= 1
                self.remoteBrowserProxyRenewalTask?.cancel()
                self.remoteBrowserProxyRenewalTask = nil
                if let capability = self.remoteBrowserProxySession?.capability
                    ?? viewModel.activeRemoteBrowserProxyCapability {
                    BrowserWebsiteDataStoreFactory.releaseRemoteDataStore(for: capability)
                }
                self.remoteBrowserProxySession?.stop()
                self.remoteBrowserProxySession = nil
                viewModel.onRetryRemoteBrowserRoute = nil
                self.remoteBrowserRouteViewModel = nil
                self.remoteBrowserRouteProfile = nil
                self.remoteBrowserRouteSuggestion = nil
            }
    }

    private func scheduleRemoteBrowserProxyRenewal(
        sessionID: UUID,
        expiresAt: Date
    ) {
        let delay = max(
            1,
            expiresAt.timeIntervalSinceNow - RemoteBrowserProxySession.renewalLeadTime
        )
        scheduleRemoteBrowserProxyRenewalAttempt(
            sessionID: sessionID,
            delay: delay
        )
    }

    private func scheduleRemoteBrowserProxyRenewalAttempt(
        sessionID: UUID,
        delay: TimeInterval
    ) {
        remoteBrowserProxyRenewalTask?.cancel()
        remoteBrowserProxyRenewalTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(1, delay) * 1_000_000_000)
                )
            } catch {
                return
            }
            await self?.renewRemoteBrowserProxySession(expectedSessionID: sessionID)
        }
    }

    private func renewRemoteBrowserProxySession(expectedSessionID: UUID) async {
        guard let currentSession = remoteBrowserProxySession,
              currentSession.capability?.id == expectedSessionID,
              let profile = remoteBrowserRouteProfile,
              let suggestion = remoteBrowserRouteSuggestion,
              let viewModel = remoteBrowserRouteViewModel,
              let remoteConnectionManager,
              let remotePortScanner,
              remotePortScanner.scanningProfileID == profile.id,
              remotePortScanner.detectedPorts.contains(where: {
                  $0.port == suggestion.remotePort
              }),
              case .connected = remoteConnectionManager.connections[profile.id] else {
            return
        }

        let replacement = makeRemoteBrowserProxySession(
            profileID: profile.id,
            remotePort: suggestion.remotePort,
            connectionManager: remoteConnectionManager
        )
        let capability: RemoteBrowserProxyCapability
        do {
            capability = try await replacement.start()
            try await BrowserWebsiteDataStoreFactory.prepareRemoteNetworkIsolation(
                for: capability
            )
        } catch {
            replacement.stop()
            guard remoteBrowserProxySession === currentSession,
                  currentSession.capability?.id == expectedSessionID
            else { return }
            let remainingLifetime = currentSession.capability?.expiresAt
                .timeIntervalSinceNow ?? 0
            if remainingLifetime > 1 {
                scheduleRemoteBrowserProxyRenewalAttempt(
                    sessionID: expectedSessionID,
                    delay: min(30, max(1, remainingLifetime / 2))
                )
            }
            return
        }

        guard remoteBrowserProxySession === currentSession,
              viewModel.refreshRemoteBrowserProxyCapability(capability) else {
            replacement.stop()
            return
        }

        remoteBrowserProxySession = replacement
        installRemoteBrowserSessionCallbacks(replacement, viewModel: viewModel)
        scheduleRemoteBrowserProxyRenewal(
            sessionID: capability.id,
            expiresAt: capability.expiresAt
        )
        currentSession.stop()
    }
}
