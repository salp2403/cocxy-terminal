// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SOCKS5BrokerOverRPC")
struct SOCKS5BrokerOverRPCSwiftTestingTests {

    @Test("parses domain CONNECT request")
    func parsesDomainConnectRequest() throws {
        let data = Data([0x05, 0x01, 0x00, 0x03, 0x0b])
            + Data("example.com".utf8)
            + Data([0x01, 0xbb])

        let request = try SOCKS5BrokerParser.parseConnectRequest(data)

        #expect(request.host == "example.com")
        #expect(request.port == 443)
    }

    @Test("parses IPv4 CONNECT request")
    func parsesIPv4ConnectRequest() throws {
        let data = Data([0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, 0x1f, 0x90])

        let request = try SOCKS5BrokerParser.parseConnectRequest(data)

        #expect(request.host == "127.0.0.1")
        #expect(request.port == 8080)
    }

    @Test("rejects unsupported command")
    func rejectsUnsupportedCommand() {
        let data = Data([0x05, 0x02, 0x00, 0x03, 0x01, 0x61, 0x00, 0x50])

        #expect(throws: SOCKS5BrokerParser.ParseError.unsupportedCommand) {
            _ = try SOCKS5BrokerParser.parseConnectRequest(data)
        }
    }

    @Test("opens RPC proxy channel from parsed request")
    @MainActor func opensRPCProxyChannelFromParsedRequest() async throws {
        let sender = RecordingRemoteRPCSender()
        sender.responses = [["channelID": "p1"]]
        let broker = SOCKS5BrokerOverRPC(proxy: CocxyDRemoteProxyRPC(sender: sender))

        let channelID = try await broker.openChannel(
            for: .init(host: "example.com", port: 443)
        )

        #expect(channelID == "p1")
        #expect(sender.calls.last?.method == "proxy.open")
    }
}
