// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteProxyRPC.swift - Typed proxy RPC wrapper for cocxyd-remote.

import Foundation

enum CocxyDRemoteProxyKind: String, Codable, Equatable, Sendable {
    case tcp
}

struct CocxyDRemoteProxyOpenResult: Equatable, Sendable {
    let channelID: String
}

struct CocxyDRemoteProxyChannel: Equatable, Sendable {
    let channelID: String
    let host: String
    let port: Int
    let kind: CocxyDRemoteProxyKind
}

struct CocxyDRemoteProxyReconnectPlan: Equatable, Sendable {
    private(set) var channels: [CocxyDRemoteProxyChannel] = []

    init() {}

    mutating func record(channelID: String, host: String, port: Int, kind: CocxyDRemoteProxyKind) {
        channels.append(CocxyDRemoteProxyChannel(
            channelID: channelID,
            host: host,
            port: port,
            kind: kind
        ))
    }
}
@MainActor
final class CocxyDRemoteProxyRPC {
    private let sender: any CocxyDRemoteRPCSending

    init(sender: any CocxyDRemoteRPCSending) {
        self.sender = sender
    }

    func open(host: String, port: Int, kind: CocxyDRemoteProxyKind) async throws -> CocxyDRemoteProxyOpenResult {
        let data = try await sender.sendRemoteRPC(
            method: "proxy.open",
            params: ["host": host, "port": "\(port)", "kind": kind.rawValue]
        )
        guard let channelID = data["channelID"] else { throw DaemonProtocolError.invalidResponse }
        return CocxyDRemoteProxyOpenResult(channelID: channelID)
    }

    func write(channelID: String, data: Data) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "proxy.write",
            params: ["channelID": channelID, "data": data.base64EncodedString()]
        )
    }

    func close(channelID: String) async throws {
        _ = try await sender.sendRemoteRPC(
            method: "proxy.close",
            params: ["channelID": channelID]
        )
    }

    func subscribe(channelID: String, after cursor: String?) async throws -> String {
        var params = ["channelID": channelID]
        if let cursor {
            params["after"] = cursor
        }
        let data = try await sender.sendRemoteRPC(
            method: "proxy.stream.subscribe",
            params: params
        )
        guard let streamID = data["streamID"] else { throw DaemonProtocolError.invalidResponse }
        return streamID
    }
}
