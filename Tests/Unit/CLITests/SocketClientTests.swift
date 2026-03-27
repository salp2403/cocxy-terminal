// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketClientTests.swift - Tests for CLI socket client and message framing.

import XCTest
@testable import CocxyCLILib

// MARK: - Message Framing Tests

/// Tests for `CLIMessageFraming`: encode, decode, frame, unframe.
///
/// These tests verify that the CLI's framing implementation is
/// wire-compatible with the app's `SocketMessageFraming`.
final class CLIMessageFramingTests: XCTestCase {

    // MARK: - 1. Encode length produces 4 bytes

    func testEncodeLengthProducesFourBytes() {
        let encoded = CLIMessageFraming.encodeLength(42)
        XCTAssertEqual(encoded.count, 4)
    }

    // MARK: - 2. Encode/decode round-trip

    func testEncodeLengthDecodeLengthRoundTrip() {
        let originalLength: UInt32 = 12345
        let encoded = CLIMessageFraming.encodeLength(originalLength)
        let decoded = CLIMessageFraming.decodeLength(encoded)
        XCTAssertEqual(decoded, originalLength)
    }

    // MARK: - 3. Decode rejects invalid data size

    func testDecodeLengthRejectsInvalidDataSize() {
        XCTAssertNil(CLIMessageFraming.decodeLength(Data([0x00, 0x00])))
        XCTAssertNil(CLIMessageFraming.decodeLength(Data([0x00, 0x00, 0x00, 0x00, 0x01])))
        XCTAssertNil(CLIMessageFraming.decodeLength(Data()))
    }

    // MARK: - 4. Frame request round-trip

    func testFrameRequestProducesHeaderPlusPayload() throws {
        let request = CLISocketRequest(id: "test-1", command: "status", params: nil)
        let framed = try CLIMessageFraming.frame(request)

        // First 4 bytes are the length header.
        let headerData = framed.prefix(4)
        let payloadLength = CLIMessageFraming.decodeLength(headerData)!

        // Remaining bytes are the JSON payload.
        let payload = framed.dropFirst(4)
        XCTAssertEqual(UInt32(payload.count), payloadLength)

        // Payload decodes back to the original request.
        let decoded = try JSONDecoder().decode(CLISocketRequest.self, from: Data(payload))
        XCTAssertEqual(decoded, request)
    }

    // MARK: - 5. Frame response and unframe round-trip

    func testFrameResponseUnframeRoundTrip() throws {
        let response = CLISocketResponse(
            id: "r-1",
            success: true,
            data: ["key": "value"],
            error: nil
        )
        let framed = try CLIMessageFraming.frame(response)
        let unframed = try CLIMessageFraming.unframe(CLISocketResponse.self, from: framed)

        XCTAssertEqual(unframed, response)
    }

    // MARK: - 6. Unframe rejects data too short for header

    func testUnframeRejectsDataTooShortForHeader() {
        let tooShort = Data([0x00, 0x01])
        XCTAssertThrowsError(
            try CLIMessageFraming.unframe(CLISocketResponse.self, from: tooShort)
        ) { error in
            guard let cliError = error as? CLIError,
                  case .malformedResponse = cliError else {
                XCTFail("Expected CLIError.malformedResponse, got \(error)")
                return
            }
        }
    }

    // MARK: - 7. Unframe rejects truncated payload

    func testUnframeRejectsTruncatedPayload() {
        // Header says 100 bytes, but only 4 bytes of header + 5 bytes payload.
        let header = CLIMessageFraming.encodeLength(100)
        let truncated = header + Data([0x01, 0x02, 0x03, 0x04, 0x05])

        XCTAssertThrowsError(
            try CLIMessageFraming.unframe(CLISocketResponse.self, from: truncated)
        ) { error in
            guard let cliError = error as? CLIError,
                  case .malformedResponse = cliError else {
                XCTFail("Expected CLIError.malformedResponse, got \(error)")
                return
            }
        }
    }

    // MARK: - 8. Wire compatibility with app protocol

    func testWireCompatibilityWithAppProtocol() throws {
        // Simulate the app's SocketMessageFraming encoding.
        // The CLI must be able to decode what the app produces.
        let request = CLISocketRequest(id: "compat-1", command: "notify", params: ["message": "hello"])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let payload = try encoder.encode(request)

        var bigEndianLength = UInt32(payload.count).bigEndian
        let header = Data(bytes: &bigEndianLength, count: 4)
        let framedByApp = header + payload

        // The CLI's unframe must decode this.
        let decoded = try CLIMessageFraming.unframe(CLISocketRequest.self, from: framedByApp)
        XCTAssertEqual(decoded.id, "compat-1")
        XCTAssertEqual(decoded.command, "notify")
        XCTAssertEqual(decoded.params?["message"], "hello")
    }
}

// MARK: - Socket Client Tests

/// Tests for `SocketClient` connection error handling.
///
/// These tests verify that the client produces the correct `CLIError`
/// when it cannot connect to the server.
final class SocketClientTests: XCTestCase {

    // MARK: - 9. Connection refused when no server running

    func testConnectionRefusedProducesAppNotRunningError() {
        // Use a path where no socket exists.
        let nonexistentPath = NSTemporaryDirectory()
            .appending("cocxy-test-\(UUID().uuidString.prefix(8))/nonexistent.sock")

        let client = SocketClient(socketPath: nonexistentPath, timeoutSeconds: 1)
        let request = CLISocketRequest(id: "err-1", command: "status", params: nil)

        XCTAssertThrowsError(try client.send(request)) { error in
            guard let cliError = error as? CLIError else {
                XCTFail("Expected CLIError, got \(error)")
                return
            }
            XCTAssertEqual(cliError, .appNotRunning)
        }
    }

    // MARK: - 10. Error message for app not running

    func testAppNotRunningErrorMessage() {
        let error = CLIError.appNotRunning
        XCTAssertEqual(
            error.userMessage,
            "Error: Cocxy Terminal is not running. Start the app first."
        )
    }

    // MARK: - 11. Error message for permission denied

    func testPermissionDeniedErrorMessage() {
        let error = CLIError.permissionDenied
        XCTAssertEqual(
            error.userMessage,
            "Error: Permission denied connecting to Cocxy Terminal socket."
        )
    }

    // MARK: - 12. Default socket path contains cocxy.sock

    func testDefaultSocketPathContainsCocxySock() {
        XCTAssertTrue(
            SocketClient.defaultSocketPath.hasSuffix("/.config/cocxy/cocxy.sock"),
            "Default socket path should end with /.config/cocxy/cocxy.sock"
        )
    }

    // MARK: - 13. Custom socket path and timeout

    func testCustomSocketPathAndTimeout() {
        let client = SocketClient(socketPath: "/tmp/test.sock", timeoutSeconds: 10)
        XCTAssertEqual(client.socketPath, "/tmp/test.sock")
        XCTAssertEqual(client.timeoutSeconds, 10)
    }
}
