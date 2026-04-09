// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketProtocolTests.swift - Tests for the socket wire protocol types.

import XCTest
@testable import CocxyTerminal

// MARK: - Socket Protocol Tests

/// Tests for the wire protocol types: `SocketRequest`, `SocketResponse`,
/// and `SocketMessageFraming`.
///
/// Covers:
/// - Codable round-trip for SocketRequest and SocketResponse.
/// - All CLICommandName enum cases.
/// - Length prefix encoding and decoding.
/// - Max message size rejection.
/// - Framing of valid messages.
/// - Edge cases: empty params, nil data, etc.
final class SocketProtocolTests: XCTestCase {

    // MARK: - 1. SocketRequest Codable round-trip

    func testSocketRequestCodableRoundTripWithParams() throws {
        let request = SocketRequest(
            id: "test-123",
            command: "notify",
            params: ["message": "Hello"]
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SocketRequest.self, from: encoded)

        XCTAssertEqual(decoded.id, "test-123")
        XCTAssertEqual(decoded.command, "notify")
        XCTAssertEqual(decoded.params?["message"], "Hello")
    }

    func testSocketRequestCodableRoundTripWithoutParams() throws {
        let request = SocketRequest(
            id: "test-456",
            command: "status",
            params: nil
        )

        let encoded = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(SocketRequest.self, from: encoded)

        XCTAssertEqual(decoded.id, "test-456")
        XCTAssertEqual(decoded.command, "status")
        XCTAssertNil(decoded.params)
    }

    func testSocketRequestDecodesFromRawJSON() throws {
        let json = """
        {
            "id": "raw-1",
            "command": "new-tab",
            "params": { "dir": "/tmp" }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SocketRequest.self, from: json)

        XCTAssertEqual(decoded.id, "raw-1")
        XCTAssertEqual(decoded.command, "new-tab")
        XCTAssertEqual(decoded.params?["dir"], "/tmp")
    }

    // MARK: - 2. SocketResponse Codable round-trip

    func testSocketResponseSuccessCodableRoundTrip() throws {
        let response = SocketResponse.ok(
            id: "resp-1",
            data: ["tabCount": "3"]
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SocketResponse.self, from: encoded)

        XCTAssertEqual(decoded.id, "resp-1")
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.data?["tabCount"], "3")
        XCTAssertNil(decoded.error)
    }

    func testSocketResponseFailureCodableRoundTrip() throws {
        let response = SocketResponse.failure(
            id: "resp-2",
            error: "Unknown command: foo"
        )

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SocketResponse.self, from: encoded)

        XCTAssertEqual(decoded.id, "resp-2")
        XCTAssertFalse(decoded.success)
        XCTAssertNil(decoded.data)
        XCTAssertEqual(decoded.error, "Unknown command: foo")
    }

    func testSocketResponseOkWithoutData() throws {
        let response = SocketResponse.ok(id: "resp-3")

        let encoded = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(SocketResponse.self, from: encoded)

        XCTAssertTrue(decoded.success)
        XCTAssertNil(decoded.data)
        XCTAssertNil(decoded.error)
    }

    // MARK: - 3. CLICommandName enum cases

    func testCLICommandNameAllCasesExist() {
        let allCases = CLICommandName.allCases
        XCTAssertTrue(allCases.contains(.notify))
        XCTAssertTrue(allCases.contains(.newTab))
        XCTAssertTrue(allCases.contains(.listTabs))
        XCTAssertTrue(allCases.contains(.focusTab))
        XCTAssertTrue(allCases.contains(.closeTab))
        XCTAssertTrue(allCases.contains(.split))
        XCTAssertTrue(allCases.contains(.status))
    }

    func testCLICommandNameRawValues() {
        XCTAssertEqual(CLICommandName.notify.rawValue, "notify")
        XCTAssertEqual(CLICommandName.newTab.rawValue, "new-tab")
        XCTAssertEqual(CLICommandName.listTabs.rawValue, "list-tabs")
        XCTAssertEqual(CLICommandName.focusTab.rawValue, "focus-tab")
        XCTAssertEqual(CLICommandName.closeTab.rawValue, "close-tab")
        XCTAssertEqual(CLICommandName.split.rawValue, "split")
        XCTAssertEqual(CLICommandName.status.rawValue, "status")
    }

    func testCLICommandNameInitFromRawValue() {
        XCTAssertEqual(CLICommandName(rawValue: "notify"), .notify)
        XCTAssertEqual(CLICommandName(rawValue: "new-tab"), .newTab)
        XCTAssertEqual(CLICommandName(rawValue: "list-tabs"), .listTabs)
        XCTAssertNil(CLICommandName(rawValue: "unknown-command"))
        XCTAssertNil(CLICommandName(rawValue: ""))
    }

    // MARK: - 4. Length prefix encoding/decoding

    func testEncodeLengthProducesFourBytes() {
        let encoded = SocketMessageFraming.encodeLength(42)
        XCTAssertEqual(encoded.count, 4)
    }

    func testEncodeLengthBigEndianFormat() {
        // 256 in big-endian: 0x00 0x00 0x01 0x00
        let encoded = SocketMessageFraming.encodeLength(256)
        XCTAssertEqual(encoded[0], 0x00)
        XCTAssertEqual(encoded[1], 0x00)
        XCTAssertEqual(encoded[2], 0x01)
        XCTAssertEqual(encoded[3], 0x00)
    }

    func testDecodeLengthRoundTrip() {
        let originalLength: UInt32 = 12345
        let encoded = SocketMessageFraming.encodeLength(originalLength)
        let decoded = SocketMessageFraming.decodeLength(encoded)

        XCTAssertEqual(decoded, originalLength)
    }

    func testDecodeLengthZero() {
        let encoded = SocketMessageFraming.encodeLength(0)
        let decoded = SocketMessageFraming.decodeLength(encoded)
        XCTAssertEqual(decoded, 0)
    }

    func testDecodeLengthMaxUInt32() {
        let encoded = SocketMessageFraming.encodeLength(UInt32.max)
        let decoded = SocketMessageFraming.decodeLength(encoded)
        XCTAssertEqual(decoded, UInt32.max)
    }

    func testDecodeLengthRejectsInvalidDataSize() {
        let tooShort = Data([0x00, 0x00])
        XCTAssertNil(SocketMessageFraming.decodeLength(tooShort))

        let tooLong = Data([0x00, 0x00, 0x00, 0x00, 0x01])
        XCTAssertNil(SocketMessageFraming.decodeLength(tooLong))

        let empty = Data()
        XCTAssertNil(SocketMessageFraming.decodeLength(empty))
    }

    // MARK: - 5. Framing valid messages

    func testFrameProducesHeaderPlusPayload() throws {
        let request = SocketRequest(id: "f-1", command: "status", params: nil)
        let framed = try SocketMessageFraming.frame(request)

        // First 4 bytes are the length header.
        let headerData = framed.prefix(4)
        let payloadLength = SocketMessageFraming.decodeLength(headerData)!

        // Remaining bytes are the JSON payload.
        let payload = framed.dropFirst(4)
        XCTAssertEqual(UInt32(payload.count), payloadLength)

        // Payload is valid JSON that decodes back.
        let decoded = try JSONDecoder().decode(SocketRequest.self, from: Data(payload))
        XCTAssertEqual(decoded.id, "f-1")
        XCTAssertEqual(decoded.command, "status")
    }

    func testFrameResponseRoundTrip() throws {
        let response = SocketResponse.ok(id: "f-2", data: ["key": "value"])
        let framed = try SocketMessageFraming.frame(response)

        let headerData = framed.prefix(4)
        let payloadLength = SocketMessageFraming.decodeLength(headerData)!
        let payload = Data(framed.dropFirst(4))

        XCTAssertEqual(UInt32(payload.count), payloadLength)

        let decoded = try JSONDecoder().decode(SocketResponse.self, from: payload)
        XCTAssertEqual(decoded.id, "f-2")
        XCTAssertTrue(decoded.success)
        XCTAssertEqual(decoded.data?["key"], "value")
    }

    // MARK: - 6. Max message size rejection

    func testFrameRejectsOversizedPayload() {
        // Create a request with a huge params dictionary that exceeds 64KB.
        var hugeParams: [String: String] = [:]
        for i in 0..<5000 {
            hugeParams["key_\(i)"] = String(repeating: "x", count: 20)
        }
        let request = SocketRequest(id: "huge", command: "notify", params: hugeParams)

        XCTAssertThrowsError(try SocketMessageFraming.frame(request)) { error in
            guard case CLISocketError.malformedMessage(let reason) = error else {
                XCTFail("Expected CLISocketError.malformedMessage, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("exceeds maximum"), "Reason: \(reason)")
        }
    }

    // MARK: - 7. SocketServerConstants

    func testSocketPathContainsCocxySock() {
        XCTAssertTrue(
            SocketServerConstants.socketPath.hasSuffix("/.config/cocxy/cocxy.sock"),
            "Socket path should end with /.config/cocxy/cocxy.sock, got: \(SocketServerConstants.socketPath)"
        )
    }

    func testSocketPermissionsAreOwnerOnly() {
        // 0o600 = owner read+write, no group, no other.
        XCTAssertEqual(SocketServerConstants.socketPermissions, 0o600)
    }

    func testMaxConcurrentConnectionsIsReasonable() {
        XCTAssertEqual(SocketServerConstants.maxConcurrentConnections, 10)
    }

    func testConnectionTimeoutIsThirtySeconds() {
        XCTAssertEqual(SocketServerConstants.connectionTimeoutSeconds, 30.0)
    }

    // MARK: - 8. SocketRequest Equatable

    func testSocketRequestEquality() {
        let a = SocketRequest(id: "eq-1", command: "status", params: nil)
        let b = SocketRequest(id: "eq-1", command: "status", params: nil)
        let c = SocketRequest(id: "eq-2", command: "status", params: nil)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - 9. SocketResponse Equatable

    func testSocketResponseEquality() {
        let a = SocketResponse.ok(id: "eq-r1", data: ["k": "v"])
        let b = SocketResponse.ok(id: "eq-r1", data: ["k": "v"])
        let c = SocketResponse.failure(id: "eq-r1", error: "nope")

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - 10. Header size constant

    func testHeaderSizeIsFour() {
        XCTAssertEqual(SocketMessageFraming.headerSize, 4)
    }

    func testMaxPayloadSizeIs64KB() {
        XCTAssertEqual(SocketMessageFraming.maxPayloadSize, 65_536)
    }
}
