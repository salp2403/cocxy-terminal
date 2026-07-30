// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+RemoteSessions.swift - Opens persistent remote sessions in terminal tabs.

import AppKit
import Foundation

enum RemoteDaemonTerminalOpenAction: Equatable {
    case attach(sessionID: String)
    case create(title: String)
}

extension MainWindowController {
    @discardableResult
    func openRemoteDaemonSession(
        profileID: UUID,
        session: DaemonSessionInfo
    ) async throws -> TabID {
        guard let daemonManager = remoteConnectionManager?.daemonManager else {
            throw remoteSessionError(
                key: "remoteWorkspace.daemon.session.connectionUnavailable",
                fallback: "Reconnect this profile before opening a remote session."
            )
        }
        let connection = try daemonManager.connection(for: profileID)
        let viewModel = RemoteDaemonTerminalViewModel(
            sessionBridge: DaemonSessionBridge(connection: connection)
        )
        return try await openRemoteDaemonTerminal(
            viewModel: viewModel,
            action: .attach(sessionID: session.id),
            title: session.title
        )
    }

    @discardableResult
    func createRemoteDaemonSession(
        profileID: UUID,
        title: String
    ) async throws -> TabID {
        guard let daemonManager = remoteConnectionManager?.daemonManager else {
            throw remoteSessionError(
                key: "remoteWorkspace.daemon.session.connectionUnavailable",
                fallback: "Reconnect this profile before opening a remote session."
            )
        }
        let connection = try daemonManager.connection(for: profileID)
        let viewModel = RemoteDaemonTerminalViewModel(
            sessionBridge: DaemonSessionBridge(connection: connection)
        )
        return try await openRemoteDaemonTerminal(
            viewModel: viewModel,
            action: .create(title: title),
            title: title
        )
    }

    @discardableResult
    func openRemoteDaemonTerminal(
        viewModel: RemoteDaemonTerminalViewModel,
        action: RemoteDaemonTerminalOpenAction,
        title: String
    ) async throws -> TabID {
        let validatedAction: RemoteDaemonTerminalOpenAction
        switch action {
        case .attach:
            validatedAction = action
        case .create(let sessionTitle):
            let normalizedTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard DaemonSessionBridge.isValidSessionIdentifier(normalizedTitle) else {
                throw remoteSessionError(
                    key: "remoteWorkspace.daemon.session.invalidTitle",
                    fallback: "Use 1-128 characters: A-Z, a-z, 0-9, . _ @ $ or -; the name cannot start with -."
                )
            }
            validatedAction = .create(title: normalizedTitle)
        }
        let disconnectMessage = appLocalizer().string(
            "remoteWorkspace.daemon.session.disconnected",
            fallback: "Remote session disconnected. Reconnect from Remote Workspaces."
        )
        let workingDirectory = FileManager.default.homeDirectoryForCurrentUser
        let tabID = createTab(
            workingDirectory: workingDirectory,
            terminalEnginePreference: .inProcess,
            surfaceCreator: { engine, surfaceView, directory in
                guard let terminalBridge = engine.cocxyCoreBridge else {
                    throw self.remoteSessionError(
                        key: "remoteWorkspace.daemon.session.surfaceUnavailable",
                        fallback: "A terminal surface is not available for this remote session."
                    )
                }
                let surfaceID = try terminalBridge.createExternalSurface(
                    in: surfaceView,
                    workingDirectory: directory,
                    transport: viewModel.makeTransport()
                )
                viewModel.bind(
                    terminalBridge: terminalBridge,
                    surfaceID: surfaceID,
                    disconnectMessage: disconnectMessage
                )
                self.remoteDaemonTerminalViewModels[surfaceID] = viewModel
                return surfaceID
            }
        )

        guard let surfaceID = tabSurfaceMap[tabID],
              remoteDaemonTerminalViewModels[surfaceID] === viewModel else {
            performCloseTab(tabID)
            throw remoteSessionError(
                key: "remoteWorkspace.daemon.session.surfaceUnavailable",
                fallback: "A terminal surface is not available for this remote session."
            )
        }

        do {
            switch validatedAction {
            case .attach(let sessionID):
                try await viewModel.attach(sessionID: sessionID)
            case .create(let sessionTitle):
                _ = try await viewModel.createAndAttach(title: sessionTitle)
            }
        } catch {
            performCloseTab(tabID)
            throw error
        }

        tabSurfaceViews[tabID]?.syncSizeWithTerminal()
        applyRemoteSessionTitle(title, to: tabID)
        presentRemoteSessionTab()
        return tabID
    }

    @discardableResult
    func openRemoteTmuxSession(profileID: UUID, session: TmuxSessionInfo) -> Bool {
        guard session.profileID == profileID,
              let command = remoteConnectionManager?.attachCommand(
                  sessionName: session.name,
                  profileID: profileID
              ) else {
            return false
        }
        return openRemoteTmuxAttachTab(command: command, title: session.name) != nil
    }

    @discardableResult
    func openRemoteTmuxAttachTab(
        command: String,
        title: String,
        delayNanoseconds: UInt64 = 500_000_000
    ) -> TabID? {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let tabID = createTab(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            terminalEnginePreference: .inProcess
        )
        guard tabSurfaceMap[tabID] != nil else {
            performCloseTab(tabID)
            return nil
        }

        applyRemoteSessionTitle(title, to: tabID)
        Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard let self, let surfaceID = self.tabSurfaceMap[tabID] else { return }
            self.terminalEngine(for: surfaceID).sendText(command + "\r", to: surfaceID)
        }
        presentRemoteSessionTab()
        return tabID
    }

    private func applyRemoteSessionTitle(_ title: String, to tabID: TabID) {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = normalized.isEmpty
            ? appLocalizer().string("remoteWorkspace.sessions.tabTitle", fallback: "Remote Session")
            : normalized
        applyAuroraSessionRename(tabID: tabID, newTitle: resolvedTitle)
        sessionRegistry?.updateTitle(sessionIDForTab(tabID), title: resolvedTitle)
    }

    private func presentRemoteSessionTab() {
        window?.makeKeyAndOrderFront(nil)
        if isRemoteWorkspaceVisible {
            dismissRemoteWorkspacePanel()
        } else {
            focusActiveTerminalSurface()
        }
    }

    private func remoteSessionError(key: String, fallback: String) -> NSError {
        NSError(
            domain: "dev.cocxy.remote-session",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: appLocalizer().string(key, fallback: fallback)]
        )
    }
}
