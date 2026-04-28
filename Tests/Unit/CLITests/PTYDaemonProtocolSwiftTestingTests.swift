// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonProtocolSwiftTestingTests.swift - Local daemon JSONL contract tests.

import Foundation
import Testing
import CocxyShared

@Suite("PTY daemon JSONL protocol")
struct PTYDaemonProtocolSwiftTestingTests {

    @Test("codec emits and requires newline-delimited JSON")
    func codecRoundTripsNewlineDelimitedJSON() throws {
        let request = PTYDaemonRequest(id: "req-1", command: .hello)
        let data = try PTYDaemonLineCodec.encode(request)

        #expect(data.last == 0x0A)
        #expect(try PTYDaemonLineCodec.decode(PTYDaemonRequest.self, fromLine: data) == request)
    }

    @Test("codec rejects partial records without newline")
    func codecRejectsPartialRecords() throws {
        let request = PTYDaemonRequest(id: "req-2", command: .shutdown)
        var data = try PTYDaemonLineCodec.encode(request)
        data.removeLast()

        #expect(throws: PTYDaemonLineCodec.CodecError.missingNewline) {
            _ = try PTYDaemonLineCodec.decode(PTYDaemonRequest.self, fromLine: data)
        }
    }

    @Test("default helper hello is IPC-only until terminal surface bridge ships")
    func defaultHelloIsIPCOnly() {
        let hello = PTYDaemonHello(version: "dev", pid: 42)

        #expect(hello.protocolVersion == PTYDaemonProtocol.protocolVersion)
        #expect(hello.capabilities == [PTYDaemonProtocol.jsonLinesCapability])
        #expect(hello.supportsTerminalSurfaces == false)
    }
}
