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

    @Test("default protocol hello stays IPC-only unless a helper opts into terminal capabilities")
    func defaultProtocolHelloIsIPCOnly() {
        let hello = PTYDaemonHello(version: "dev", pid: 42)

        #expect(hello.protocolVersion == PTYDaemonProtocol.protocolVersion)
        #expect(hello.capabilities == [PTYDaemonProtocol.jsonLinesCapability])
        #expect(hello.supportsTerminalSurfaces == false)
        #expect(hello.supportsTerminalHostRenderer == false)
        #expect(hello.supportsTerminalEngineAdapter == false)
    }

    @Test("terminal engine adapter requires surface frames, engine transport and host renderer")
    func terminalEngineAdapterRequiresCompleteCapabilitySet() {
        let framesOnly = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
            ]
        )
        let engineOnly = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
            ]
        )
        let complete = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
                PTYDaemonProtocol.terminalHostRendererCapability,
            ]
        )

        #expect(framesOnly.supportsTerminalSurfaces == true)
        #expect(framesOnly.supportsTerminalEngineAdapter == false)
        #expect(engineOnly.supportsTerminalSurfaces == true)
        #expect(engineOnly.supportsTerminalHostRenderer == false)
        #expect(engineOnly.supportsTerminalEngineAdapter == false)
        #expect(complete.supportsTerminalHostRenderer == true)
        #expect(complete.supportsTerminalEngineAdapter == true)
    }

    @Test("surface frame response round-trips through newline codec")
    func surfaceFrameResponseRoundTrips() throws {
        let frame = PTYDaemonSurfaceFrame(
            surfaceID: "11111111-1111-1111-1111-111111111111",
            revision: 7,
            timestamp: 1_776_000_000,
            columns: 2,
            rows: 1,
            cells: [
                PTYDaemonGridCell(
                    row: 0,
                    column: 0,
                    glyph: 65,
                    foregroundRGBA: 0xFFFFFFFF,
                    backgroundRGBA: 0x000000FF
                ),
                PTYDaemonGridCell(
                    row: 0,
                    column: 1,
                    glyph: 66,
                    foregroundRGBA: 0xEEEEEEFF,
                    backgroundRGBA: 0x111111FF,
                    attributes: 1
                ),
            ],
            cursor: PTYDaemonCursor(row: 0, column: 1),
            scrollbackTop: 3,
            images: [
                PTYDaemonImageReference(id: "img-1", row: 0, column: 1, width: 4, height: 2)
            ]
        )
        let response = PTYDaemonResponse(id: "frame-1", ok: true, frame: frame)
        let data = try PTYDaemonLineCodec.encode(response)

        #expect(try PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: data) == response)
    }

    @Test("surface output and OSC events round-trip through newline codec")
    func surfaceEventsRoundTrip() throws {
        let output = PTYDaemonEvent(
            event: .surfaceOutput,
            surfaceID: "11111111-1111-1111-1111-111111111111",
            bytesBase64: Data("daemon bytes".utf8).base64EncodedString()
        )
        let osc = PTYDaemonEvent(
            event: .surfaceOSC,
            surfaceID: "11111111-1111-1111-1111-111111111111",
            osc: PTYDaemonOSCNotification(kind: .currentDirectory, url: "/tmp/project")
        )

        let outputData = try PTYDaemonLineCodec.encode(output)
        let oscData = try PTYDaemonLineCodec.encode(osc)

        #expect(try PTYDaemonLineCodec.decode(PTYDaemonEvent.self, fromLine: outputData) == output)
        #expect(try PTYDaemonLineCodec.decode(PTYDaemonEvent.self, fromLine: oscData) == osc)
    }

    @Test("surface requests carry command payloads for daemon adapter calls")
    func surfaceRequestsCarryPayloads() throws {
        let request = PTYDaemonRequest(
            id: "surface-create-1",
            command: .surfaceCreate,
            payload: [
                "workingDirectory": "/tmp/project",
                "command": "/bin/zsh",
            ]
        )
        let data = try PTYDaemonLineCodec.encode(request)

        #expect(try PTYDaemonLineCodec.decode(PTYDaemonRequest.self, fromLine: data) == request)
    }
}
