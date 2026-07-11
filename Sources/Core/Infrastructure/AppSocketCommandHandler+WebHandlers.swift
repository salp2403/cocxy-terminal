// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+WebHandlers.swift - Web terminal socket commands.

import Foundation

extension AppSocketCommandHandler {

    func handleWebStart(_ request: SocketRequest) -> SocketResponse {
        guard let provider = webStartProvider else {
            return .failure(id: request.id, error: "Web terminal is not available")
        }

        let requestedBind = request.params?["bind"] ?? WebTerminalConfiguration.defaultBindAddress
        guard let bind = WebTerminalConfiguration.normalizedLoopbackBindAddress(requestedBind) else {
            return .failure(id: request.id, error: "Web terminal must bind to an explicit loopback address")
        }
        guard request.params?.keys.contains(where: Self.isWebTerminalCredentialField) != true else {
            return .failure(id: request.id, error: "Cocxy manages web terminal credentials")
        }

        let port: UInt16
        if let rawPort = request.params?["port"] {
            guard let parsedPort = UInt16(rawPort) else {
                return .failure(id: request.id, error: "Invalid web terminal port")
            }
            port = parsedPort
        } else {
            port = WebTerminalConfiguration.defaultPort
        }

        let fps: UInt32
        if let rawFPS = request.params?["fps"] {
            guard let parsedFPS = UInt32(rawFPS) else {
                return .failure(id: request.id, error: "Invalid web terminal frame rate")
            }
            fps = parsedFPS
        } else {
            fps = WebTerminalConfiguration.defaultMaxFrameRate
        }

        let token: String
        do {
            token = try SocketAuthenticationTokenGenerator.generate()
        } catch {
            return .failure(id: request.id, error: "Failed to generate web terminal credentials")
        }

        guard var data = provider(
            bind,
            port,
            token,
            WebTerminalConfiguration.defaultMaxConnections,
            fps
        ) else {
            return .failure(id: request.id, error: "Failed to start web terminal")
        }
        data = Self.redactingWebTerminalCredentials(from: data)
        data["authorization"] = "Bearer \(token)"
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
        return .ok(
            id: request.id,
            data: Self.redactingWebTerminalCredentials(from: data)
        )
    }

    private static func redactingWebTerminalCredentials(
        from data: [String: String]
    ) -> [String: String] {
        data.filter { !isWebTerminalCredentialField($0.key) }
    }

    private static func isWebTerminalCredentialField(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("token")
            || normalized.contains("credential")
            || normalized.contains("authorization")
    }
}
