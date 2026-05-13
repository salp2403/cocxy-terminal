// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ConnectProxyOverRPC.swift - HTTP CONNECT parser adapter for remote proxy RPC.

import Foundation

@MainActor
final class ConnectProxyOverRPC {
    nonisolated static let connectionEstablishedResponse = HTTPConnectParser.connectionEstablishedResponse

    private let proxy: CocxyDRemoteProxyRPC

    init(proxy: CocxyDRemoteProxyRPC) {
        self.proxy = proxy
    }

    func openChannel(requestLine: String) async throws -> String {
        let target = try HTTPConnectParser.parse(requestLine: requestLine)
        let result = try await proxy.open(host: target.host, port: target.port, kind: .tcp)
        return result.channelID
    }
}
