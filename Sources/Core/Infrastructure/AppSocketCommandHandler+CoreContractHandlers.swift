// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandler+CoreContractHandlers.swift - CocxyCore contract commands.

import Darwin
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

    func handleCoreReset(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreResetProvider else {
            return .failure(id: request.id, error: "CocxyCore reset is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to reset the active terminal")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreSignal(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreSignalProvider else {
            return .failure(id: request.id, error: "CocxyCore signal forwarding is not available")
        }
        guard let rawSignal = request.params?["signal"],
              let signal = parseSignal(rawSignal) else {
            return .failure(id: request.id, error: "Missing or invalid signal")
        }
        guard let data = provider(signal) else {
            return .failure(id: request.id, error: "Failed to send signal")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreProcess(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreProcessProvider else {
            return .failure(id: request.id, error: "CocxyCore process diagnostics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query process diagnostics")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreModes(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreModesProvider else {
            return .failure(id: request.id, error: "CocxyCore mode diagnostics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query mode diagnostics")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreSearch(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreSearchProvider else {
            return .failure(id: request.id, error: "CocxyCore search diagnostics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query search diagnostics")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreLigatures(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreLigaturesProvider else {
            return .failure(id: request.id, error: "CocxyCore ligature diagnostics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query ligature diagnostics")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreProtocol(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreProtocolProvider else {
            return .failure(id: request.id, error: "CocxyCore protocol diagnostics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query protocol diagnostics")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreSelection(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreSelectionProvider else {
            return .failure(id: request.id, error: "CocxyCore selection snapshot is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query selection snapshot")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreFontMetrics(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreFontMetricsProvider else {
            return .failure(id: request.id, error: "CocxyCore font metrics are not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query font metrics")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCorePreedit(_ request: SocketRequest) -> SocketResponse {
        guard let provider = corePreeditProvider else {
            return .failure(id: request.id, error: "CocxyCore preedit snapshot is not available")
        }
        guard let data = provider() else {
            return .failure(id: request.id, error: "Failed to query preedit snapshot")
        }
        return .ok(id: request.id, data: data)
    }

    func handleCoreSemantic(_ request: SocketRequest) -> SocketResponse {
        guard let provider = coreSemanticProvider else {
            return .failure(id: request.id, error: "CocxyCore semantic diagnostics are not available")
        }

        let requestedLimit = request.params?["limit"].flatMap(UInt32.init) ?? 10
        let limit = min(max(requestedLimit, 1), 64)
        guard let data = provider(limit) else {
            return .failure(id: request.id, error: "Failed to query semantic diagnostics")
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

    private func parseSignal(_ value: String) -> Int32? {
        if let numeric = Int32(value) {
            return numeric
        }

        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hup", "sighup":
            return SIGHUP
        case "int", "sigint":
            return SIGINT
        case "quit", "sigquit":
            return SIGQUIT
        case "kill", "sigkill":
            return SIGKILL
        case "term", "sigterm":
            return SIGTERM
        case "stop", "sigstop":
            return SIGSTOP
        case "tstp", "sigtstp":
            return SIGTSTP
        case "cont", "sigcont":
            return SIGCONT
        case "usr1", "sigusr1":
            return SIGUSR1
        case "usr2", "sigusr2":
            return SIGUSR2
        case "winch", "sigwinch":
            return SIGWINCH
        default:
            return nil
        }
    }
}
