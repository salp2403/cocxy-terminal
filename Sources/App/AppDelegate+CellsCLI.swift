// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+CellsCLI.swift - App-side Cocxy Cells CLI commands.

import Foundation

extension AppDelegate {
    nonisolated static let sharedCellCLIService = CellCLICommandService()

    nonisolated func handleCellCLIRequest(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext,
        serviceOverride: CellCLICommandService? = nil,
        cloudInitBroker: CellCloudInitFileBroker = CellCloudInitFileBroker()
    ) -> (success: Bool, data: [String: String]) {
        guard let boundParams = approvedContext.bindingLocalResourcePaths(
            in: params,
            keys: kind == "create" ? CellCLICommandService.createLocalResourcePathKeys : [],
            requiredScope: .computeCell
        ) else {
            return (false, ["error": "Approved cell command context is unavailable"])
        }
        let dispatch: (result: (Bool, [String: String]), params: [String: String])
        let service = serviceOverride ?? Self.sharedCellCLIService
        do {
            dispatch = try cloudInitBroker.withStagedApprovedCloudInit(
                kind: kind,
                params: boundParams,
                approvedContext: approvedContext
            ) { approvedParams in
                let semaphore = DispatchSemaphore(value: 0)
                let box = LockedBox<(Bool, [String: String])>((
                    false,
                    ["error": "Cell dispatch did not complete"]
                ))

                Task.detached {
                    let result = await service.perform(
                        kind: kind,
                        params: approvedParams
                    )
                    box.withValue { $0 = result }
                    semaphore.signal()
                }

                semaphore.wait()
                return (box.withValue { $0 }, approvedParams)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (false, ["error": message])
        }

        let result = dispatch.result
        let approvedParams = dispatch.params
        guard kind == "attach",
              result.0,
              approvedParams["open-tab"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "false",
              let command = result.1["pty-command"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty else {
            return result
        }

        var data = result.1
        let appAttachData = syncOnMainActor {
            self.openCellAttachTab(
                attachData: result.1,
                command: command,
                title: result.1["pty-title"],
                cellID: result.1["cell-id"],
                approvedContext: approvedContext
            )
        }
        if let appAttachData {
            data["app-attach"] = "tab-opened"
            data.merge(appAttachData) { _, new in new }
        } else {
            data["app-attach"] = "command-ready"
        }
        return (true, data)
    }

    @MainActor
    private func openCellAttachTab(
        attachData: [String: String],
        command: String,
        title: String?,
        cellID: String?,
        approvedContext: SocketPrivilegedCommandContext?
    ) -> [String: String]? {
        guard let controller = privilegedSocketController(for: approvedContext) else {
            return nil
        }

        let resolvedTitle = trimmedNonEmpty(title)
            ?? cellID.map { "Cell \($0.prefix(8))" }
            ?? "Cell Attach"
        let tabID = controller.createTab(
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser,
            terminalEnginePreference: .inProcess
        )
        controller.tabManager.renameTab(id: tabID, newTitle: resolvedTitle)

        var appData: [String: String] = [
            "tab-id": tabID.rawValue.uuidString,
            "tab-title": resolvedTitle,
        ]
        if let surfaceID = controller.surfaceIDs(for: tabID).first,
           let cocxyBridge = controller.cocxyCoreBridge(forSurface: surfaceID),
           let token = trimmedNonEmpty(attachData["lease-token"]) {
            let configuration = WebTerminalConfiguration(
                bindAddress: WebTerminalConfiguration.defaultBindAddress,
                port: 0,
                authToken: token,
                maxConnections: 1,
                maxFrameRate: WebTerminalConfiguration.defaultMaxFrameRate,
                stopAfterFirstConnection: true,
                firstConnectionHandler: { [attachData] in
                    _ = Self.sharedCellCLIService.consumeAttachLease(fields: attachData)
                }
            )
            if let status = cocxyBridge.startWebTerminal(for: surfaceID, configuration: configuration) {
                appData["pty-transport"] = "websocket"
                appData["web-bind"] = status.bindAddress
                appData["web-port"] = "\(status.port)"
                appData["web-origin"] = "http://\(status.bindAddress):\(status.port)"
                appData["web-token"] = token
                appData["web-auth-header"] = "Authorization: Bearer \(token)"
                appData["web-one-shot"] = status.oneShot ? "true" : "false"
                appData["web-expires-at"] = attachData["expires-at"]
                scheduleCellAttachWebTerminalExpiry(
                    surfaceID: surfaceID,
                    controller: controller,
                    expiresAtUnixValue: attachData["expires-at-unix"]
                )
            }
        }

        Task { @MainActor [weak controller] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let controller,
                  let surfaceID = controller.surfaceIDs(for: tabID).first else {
                return
            }
            controller.terminalEngine(for: surfaceID).sendText(command + "\r", to: surfaceID)
        }

        return appData
    }

    @MainActor
    private func scheduleCellAttachWebTerminalExpiry(
        surfaceID: SurfaceID,
        controller: MainWindowController,
        expiresAtUnixValue: String?
    ) {
        guard let expiresAtUnixValue,
              let expiresAtSeconds = Double(expiresAtUnixValue),
              let cocxyBridge = controller.cocxyCoreBridge(forSurface: surfaceID) else {
            return
        }
        let expiresAt = Date(timeIntervalSince1970: expiresAtSeconds)

        Task { @MainActor [weak controller, weak cocxyBridge] in
            let delay = max(0, expiresAt.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard controller != nil,
                  let cocxyBridge,
                  cocxyBridge.webTerminalStatus(for: surfaceID)?.oneShot == true else {
                return
            }
            cocxyBridge.stopWebTerminal(for: surfaceID)
        }
    }

    private nonisolated func trimmedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
