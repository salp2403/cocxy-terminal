// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+WebHandlers.swift - Web terminal socket commands.

import Foundation

extension AppSocketCommandHandler {

    func handleWebStart(_ request: SocketRequest) -> SocketResponse {
        guard let provider = webStartProvider else {
            return .failure(id: request.id, error: "Web terminal is not available")
        }

        let bind = request.params?["bind"] ?? WebTerminalConfiguration.default.bindAddress
        let port = UInt16(request.params?["port"] ?? "") ?? WebTerminalConfiguration.default.port
        let token = request.params?["token"] ?? ""
        let fps = UInt32(request.params?["fps"] ?? "") ?? WebTerminalConfiguration.default.maxFrameRate

        guard let data = provider(bind, port, token, WebTerminalConfiguration.default.maxConnections, fps) else {
            return .failure(id: request.id, error: "Failed to start web terminal")
        }
        return .ok(id: request.id, data: data)
    }

    func handleWebStop(_ request: SocketRequest) -> SocketResponse {
        guard let provider = webStopProvider else {
            return .failure(id: request.id, error: "Web terminal is not available")
        }
        guard provider() else {
            return .failure(id: request.id, error: "Web terminal is not running")
        }
        return .ok(id: request.id, data: ["status": "stopped"])
    }

    func handleWebStatus(_ request: SocketRequest) -> SocketResponse {
        guard let provider = webStatusProvider else {
            return .failure(id: request.id, error: "Web terminal is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "No active terminal surface")
        }
        return .ok(id: request.id, data: data)
    }
}
