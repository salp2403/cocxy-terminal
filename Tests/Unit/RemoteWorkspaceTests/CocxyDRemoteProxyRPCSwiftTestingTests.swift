// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteProxyRPC")
struct CocxyDRemoteProxyRPCSwiftTestingTests {

    @Test("open sends proxy.open for tcp target")
    @MainActor func openSendsProxyOpen() async throws {
        let sender = RecordingRemoteRPCSender()
        sender.responses = [["channelID": "p1"]]
        let rpc = CocxyDRemoteProxyRPC(sender: sender)

        let result = try await rpc.open(host: "example.com", port: 443, kind: .tcp)

        #expect(result.channelID == "p1")
        #expect(sender.calls == [
            .init(method: "proxy.open", params: ["host": "example.com", "port": "443", "kind": "tcp"])
        ])
    }

    @Test("write sends base64 data")
    @MainActor func writeSendsBase64Data() async throws {
        let sender = RecordingRemoteRPCSender()
        let rpc = CocxyDRemoteProxyRPC(sender: sender)

        try await rpc.write(channelID: "p1", data: Data("GET / HTTP/1.1\r\n\r\n".utf8))

        #expect(sender.calls.last?.method == "proxy.write")
        #expect(sender.calls.last?.params["channelID"] == "p1")
        #expect(sender.calls.last?.params["data"] == "R0VUIC8gSFRUUC8xLjENCg0K")
    }

    @Test("close sends proxy.close")
    @MainActor func closeSendsProxyClose() async throws {
        let sender = RecordingRemoteRPCSender()
        let rpc = CocxyDRemoteProxyRPC(sender: sender)

        try await rpc.close(channelID: "p1")

        #expect(sender.calls.last == .init(method: "proxy.close", params: ["channelID": "p1"]))
    }

    @Test("stream subscribe sends channel id and cursor")
    @MainActor func streamSubscribeSendsCursor() async throws {
        let sender = RecordingRemoteRPCSender()
        sender.responses = [["streamID": "stream-1"]]
        let rpc = CocxyDRemoteProxyRPC(sender: sender)

        let streamID = try await rpc.subscribe(channelID: "p1", after: "42")

        #expect(streamID == "stream-1")
        #expect(sender.calls.last == .init(
            method: "proxy.stream.subscribe",
            params: ["channelID": "p1", "after": "42"]
        ))
    }

    @Test("reconnect plan keeps open channel metadata")
    func reconnectPlanKeepsOpenChannelMetadata() {
        var plan = CocxyDRemoteProxyReconnectPlan()
        plan.record(channelID: "p1", host: "example.com", port: 443, kind: .tcp)

        #expect(plan.channels == [
            .init(channelID: "p1", host: "example.com", port: 443, kind: .tcp)
        ])
    }
}
