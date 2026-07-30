// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteDaemonTerminalViewModel.swift - Owns one attached daemon terminal transport.

import Foundation

@MainActor
final class RemoteDaemonTerminalViewModel: ObservableObject {
    let sessionBridge: DaemonSessionBridge

    private weak var terminalBridge: CocxyCoreBridge?
    private var surfaceID: SurfaceID?

    init(sessionBridge: DaemonSessionBridge) {
        self.sessionBridge = sessionBridge
    }

    func bind(
        terminalBridge: CocxyCoreBridge,
        surfaceID: SurfaceID,
        disconnectMessage: String
    ) {
        self.terminalBridge = terminalBridge
        self.surfaceID = surfaceID
        sessionBridge.onOutput = { [weak terminalBridge] data in
            _ = terminalBridge?.feedExternalOutput(data, to: surfaceID)
        }
        sessionBridge.onDisconnect = { [weak terminalBridge] in
            let message = Data("\r\n\u{1B}[33m\(disconnectMessage)\u{1B}[0m\r\n".utf8)
            _ = terminalBridge?.feedExternalOutput(message, to: surfaceID)
        }
    }

    func attach(sessionID: String) async throws {
        try await sessionBridge.attach(sessionID: sessionID)
    }

    @discardableResult
    func createAndAttach(title: String) async throws -> String {
        try await sessionBridge.createAndAttach(title: title)
    }

    func makeTransport() -> CocxyCoreBridge.SurfaceState.ExternalTransport {
        .init(
            write: { [self] data in
                sessionBridge.enqueueInput(data)
            },
            resize: { [self] size in
                sessionBridge.enqueueResize(size)
            },
            close: { [self] in
                sessionBridge.beginDetach()
            }
        )
    }
}
