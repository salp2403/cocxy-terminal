// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorStaticAssetServer.swift - App-scoped compiled mobile shell host.

import CocxyCoreKit
import Foundation

struct MobileMirrorStaticAssetEndpoint: Equatable, Sendable {
    let port: UInt16
    let bearerToken: String
}

enum MobileMirrorStaticAssetServerError: Error, LocalizedError {
    case creationFailed
    case startFailed

    var errorDescription: String? {
        switch self {
        case .creationFailed:
            return "The compiled mobile interface could not be initialized."
        case .startFailed:
            return "The compiled mobile interface could not be started."
        }
    }
}

@MainActor
final class MobileMirrorStaticAssetServer {
    private var handle: OpaquePointer?
    private(set) var endpoint: MobileMirrorStaticAssetEndpoint?

    func start() throws -> MobileMirrorStaticAssetEndpoint {
        if let handle, cocxycore_web_is_running(handle), let endpoint {
            return endpoint
        }
        stop()

        let bindAddress = WebTerminalConfiguration.defaultBindAddress
        let token = MobileMirrorPairingAuthority.base64URL(RelayToken.generate().secret)
        var configuration = cocxycore_web_config()
        Self.writeCString(bindAddress, into: &configuration.bind_address, maxBytes: 64)
        configuration.bind_address_len = UInt32(bindAddress.utf8.count)
        configuration.port = 0
        Self.writeCString(token, into: &configuration.auth_token, maxBytes: 128)
        configuration.auth_token_len = UInt32(token.utf8.count)
        configuration.max_connections = UInt16(MobileMirrorGateway.maximumConnections)
        configuration.max_frame_rate = 1
        configuration.read_only = 1

        guard let server = cocxycore_web_create(&configuration) else {
            throw MobileMirrorStaticAssetServerError.creationFailed
        }
        guard cocxycore_web_start(server) else {
            cocxycore_web_destroy(server)
            throw MobileMirrorStaticAssetServerError.startFailed
        }
        let port = cocxycore_web_port(server)
        guard port > 0 else {
            cocxycore_web_destroy(server)
            throw MobileMirrorStaticAssetServerError.startFailed
        }
        let endpoint = MobileMirrorStaticAssetEndpoint(
            port: port,
            bearerToken: token
        )
        handle = server
        self.endpoint = endpoint
        return endpoint
    }

    func stop() {
        guard let handle else {
            endpoint = nil
            return
        }
        cocxycore_web_stop(handle)
        cocxycore_web_destroy(handle)
        self.handle = nil
        endpoint = nil
    }

    private static func writeCString<T>(
        _ string: String,
        into buffer: inout T,
        maxBytes: Int
    ) {
        withUnsafeMutableBytes(of: &buffer) { rawBuffer in
            guard rawBuffer.count > 0 else { return }
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            let capacity = min(rawBuffer.count, maxBytes)
            let bytes = Array(string.utf8.prefix(max(0, capacity - 1)))
            rawBuffer.copyBytes(from: bytes)
        }
    }
}
