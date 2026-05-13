// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("ConnectProxyOverRPC")
struct ConnectProxyOverRPCSwiftTestingTests {

    @Test("opens RPC proxy channel from CONNECT request line")
    @MainActor func opensRPCProxyChannelFromConnectRequestLine() async throws {
        let sender = RecordingRemoteRPCSender()
        sender.responses = [["channelID": "p1"]]
        let proxy = ConnectProxyOverRPC(proxy: CocxyDRemoteProxyRPC(sender: sender))

        let channelID = try await proxy.openChannel(requestLine: "CONNECT example.com:443 HTTP/1.1")

        #expect(channelID == "p1")
        #expect(sender.calls.last == .init(
            method: "proxy.open",
            params: ["host": "example.com", "port": "443", "kind": "tcp"]
        ))
    }

    @Test("reuses HTTP CONNECT success response")
    func reusesHTTPConnectSuccessResponse() {
        #expect(ConnectProxyOverRPC.connectionEstablishedResponse == HTTPConnectParser.connectionEstablishedResponse)
    }

    @Test("rejects malformed CONNECT request line")
    @MainActor func rejectsMalformedConnectRequestLine() async {
        let proxy = ConnectProxyOverRPC(proxy: CocxyDRemoteProxyRPC(sender: RecordingRemoteRPCSender()))

        await #expect(throws: HTTPConnectParser.ParseError.missingPort) {
            _ = try await proxy.openChannel(requestLine: "CONNECT example.com HTTP/1.1")
        }
    }
}
