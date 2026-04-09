// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+CoreContractHandlers.swift - CocxyCore contract commands.

import Foundation

extension AppSocketCommandHandler {

    func handleStreamList(_ request: SocketRequest) -> SocketResponse {
        guard let provider = streamListProvider else {
            return .failure(id: request.id, error: "CocxyCore stream diagnostics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "No active terminal surface")
        }
        return .ok(id: request.id, data: data)
    }

    func handleStreamCurrent(_ request: SocketRequest) -> SocketResponse {
        guard let provider = streamCurrentProvider else {
            return .failure(id: request.id, error: "CocxyCore stream selection is not available")
        }
        guard let rawID = request.params?["id"], let streamID = UInt32(rawID) else {
            return .failure(id: request.id, error: "Missing or invalid stream id")
        }
        guard let data = provider(streamID) else {
            return .failure(id: request.id, error: "Failed to select stream")
        }
        return .ok(id: request.id, data: data)
    }

    func handleProtocolCapabilities(_ request: SocketRequest) -> SocketResponse {
        guard let provider = protocolCapabilitiesProvider else {
            return .failure(id: request.id, error: "Protocol v2 exchange is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to request protocol capabilities")
        }
        return .ok(id: request.id, data: data)
    }

    func handleProtocolViewport(_ request: SocketRequest) -> SocketResponse {
        guard let provider = protocolViewportProvider else {
            return .failure(id: request.id, error: "Protocol v2 viewport is not available")
        }
        let requestID = request.params?["request_id"]
        guard let data = provider(requestID) else {
            return .failure(id: request.id, error: "Failed to send protocol viewport")
        }
        return .ok(id: request.id, data: data)
    }

    func handleProtocolSend(_ request: SocketRequest) -> SocketResponse {
        guard let provider = protocolSendProvider else {
            return .failure(id: request.id, error: "Protocol v2 send is not available")
        }
        guard let type = request.params?["type"], !type.isEmpty else {
            return .failure(id: request.id, error: "Missing protocol message type")
        }
        guard let payload = request.params?["json"], !payload.isEmpty else {
            return .failure(id: request.id, error: "Missing protocol JSON payload")
        }
        guard let data = provider(type, payload) else {
            return .failure(id: request.id, error: "Failed to send protocol message")
        }
        return .ok(id: request.id, data: data)
    }

    func handleImageList(_ request: SocketRequest) -> SocketResponse {
        guard let provider = imageListProvider else {
            return .failure(id: request.id, error: "Image management is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to list inline images")
        }
        return .ok(id: request.id, data: data)
    }

    func handleImageDelete(_ request: SocketRequest) -> SocketResponse {
        guard let provider = imageDeleteProvider else {
            return .failure(id: request.id, error: "Image management is not available")
        }
        guard let rawID = request.params?["id"], let imageID = UInt32(rawID) else {
            return .failure(id: request.id, error: "Missing or invalid image id")
        }
        guard let data = provider(imageID) else {
            return .failure(id: request.id, error: "Failed to delete inline image")
        }
        return .ok(id: request.id, data: data)
    }

    func handleImageClear(_ request: SocketRequest) -> SocketResponse {
        guard let provider = imageClearProvider else {
            return .failure(id: request.id, error: "Image management is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to clear inline images")
        }
        return .ok(id: request.id, data: data)
    }
}
