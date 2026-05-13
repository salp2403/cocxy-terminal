// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SOCKS5BrokerOverRPC.swift - SOCKS5 request parsing and proxy RPC adapter.

import Foundation

enum SOCKS5BrokerParser {
    struct ConnectRequest: Equatable, Sendable {
        let host: String
        let port: Int
    }

    enum ParseError: Error, Equatable {
        case truncated
        case unsupportedVersion
        case unsupportedCommand
        case unsupportedAddressType
    }

    static func parseConnectRequest(_ data: Data) throws -> ConnectRequest {
        let bytes = Array(data)
        guard bytes.count >= 7 else { throw ParseError.truncated }
        guard bytes[0] == 0x05 else { throw ParseError.unsupportedVersion }
        guard bytes[1] == 0x01 else { throw ParseError.unsupportedCommand }

        var index = 4
        let host: String
        switch bytes[3] {
        case 0x01:
            guard bytes.count >= index + 4 + 2 else { throw ParseError.truncated }
            host = "\(bytes[index]).\(bytes[index + 1]).\(bytes[index + 2]).\(bytes[index + 3])"
            index += 4
        case 0x03:
            let length = Int(bytes[index])
            index += 1
            guard bytes.count >= index + length + 2 else { throw ParseError.truncated }
            host = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
            index += length
        default:
            throw ParseError.unsupportedAddressType
        }

        let port = (Int(bytes[index]) << 8) | Int(bytes[index + 1])
        return ConnectRequest(host: host, port: port)
    }
}
@MainActor
final class SOCKS5BrokerOverRPC {
    private let proxy: CocxyDRemoteProxyRPC

    init(proxy: CocxyDRemoteProxyRPC) {
        self.proxy = proxy
    }

    func openChannel(for request: SOCKS5BrokerParser.ConnectRequest) async throws -> String {
        let result = try await proxy.open(host: request.host, port: request.port, kind: .tcp)
        return result.channelID
    }
}
