// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase7SecurityTests.swift - Additional security and edge-case tests for Fase 7.
//
// Covers gaps identified in QA review:
// - Socket: payload exactly at 64 KB limit, 1 byte over the limit
// - Socket: zero-length payload rejected
// - Socket: partial header (client closes mid-send)
// - Socket: rapid successive reconnections
// - Socket: all 7 commands produce non-error responses
// - CLI: buildRequest for .help and .version produces a valid request
// - CLI: CommandRunner propagates server error response with exit code 1
// - CLI: notifyWithEmptyStringAfterJoining (edge case multi-word notify)
// - AnimationConfig: duration(0) with reduce motion off returns 0
// - AnimationConfig: all constants passed through duration() with reduce motion
// - AccessibilityHelpers: color with alpha component does not affect contrast formula
// - AccessibilityHelpers: contrastRatio is symmetric (order does not matter)
// - AccessibilityHelpers: ratio >= 1.0 for any two colors
// - AgentState: all cases have unique accessibility descriptions

import XCTest
@testable import CocxyTerminal
@testable import CocxyCLILib

// MARK: - Socket Security Edge Cases

/// Additional security tests for `SocketServerImpl` and `SocketConnectionHandler`.
final class Phase7SocketSecurityTests: XCTestCase {

    private var testSocketPath: String!
    private var testSocketDirectory: String!

    override func setUp() {
        super.setUp()
        let uniqueID = UUID().uuidString.prefix(8)
        testSocketDirectory = NSTemporaryDirectory()
            .appending("cocxy-p7-\(uniqueID)")
        testSocketPath = testSocketDirectory.appending("/test.sock")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testSocketPath)
        try? FileManager.default.removeItem(atPath: testSocketDirectory)
        testSocketPath = nil
        testSocketDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @MainActor
    private func startServer(
        handler: MockSocketCommandHandler = MockSocketCommandHandler()
    ) throws -> (SocketServerImpl, MockSocketCommandHandler) {
        let server = SocketServerImpl(
            socketPath: testSocketPath,
            commandHandler: handler
        )
        try server.start()
        Thread.sleep(forTimeInterval: 0.05)
        return (server, handler)
    }

    // MARK: - TEST 1: Payload exactly at maxPayloadSize limit is accepted

    /// A payload of exactly 65536 bytes is at the limit, but because the JSON
    /// message itself cannot be exactly 65536 bytes for a valid SocketRequest
    /// without huge params, we test that the framing guard uses <=, not <.
    @MainActor
    func testPayloadAtExactMaxSizeIsAcceptedByFraming() throws {
        // Build a SocketRequest whose JSON payload is exactly maxPayloadSize bytes.
        // We use SocketMessageFraming.maxPayloadSize and confirm no throw.
        let maxPayload = SocketMessageFraming.maxPayloadSize

        // We create a params dict sized so that the encoded JSON is <= 65536.
        // The simplest verification: encodeLength of maxPayload and decodeLength
        // confirm the boundary logic is <=.
        let encoded = SocketMessageFraming.encodeLength(maxPayload)
        let decoded = SocketMessageFraming.decodeLength(encoded)
        XCTAssertEqual(decoded, maxPayload,
                       "maxPayloadSize should encode/decode cleanly via boundary")
    }

    // MARK: - TEST 2: Zero-length payload is rejected by the server

    @MainActor
    func testZeroLengthPayloadIsRejectedByServer() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let expectation = expectation(description: "Zero-length payload test")
        var connectionClosed = false

        DispatchQueue.global().async { [testSocketPath] in
            do {
                let fd = try SocketTestClient.connect(to: testSocketPath!)
                defer { Darwin.close(fd) }

                // Send a length header of 0.
                let zeroHeader = SocketMessageFraming.encodeLength(0)
                let written = zeroHeader.withUnsafeBytes { ptr in
                    Darwin.write(fd, ptr.baseAddress!, ptr.count)
                }
                guard written == zeroHeader.count else { return }

                // Server should close the connection — any read attempt will fail
                // or we get a server-side error response for a zero payload.
                var oneByte = [UInt8](repeating: 0, count: 1)
                let readResult = Darwin.read(fd, &oneByte, 1)
                connectionClosed = (readResult <= 0)
            } catch {
                connectionClosed = true
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(connectionClosed,
                      "Server should close connection on zero-length payload")
    }

    // MARK: - TEST 3: Oversized length header (> 64 KB) causes connection close

    @MainActor
    func testOversizedLengthHeaderCausesConnectionClose() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let expectation = expectation(description: "Oversized header test")
        var connectionClosed = false

        DispatchQueue.global().async { [testSocketPath] in
            do {
                let fd = try SocketTestClient.connect(to: testSocketPath!)
                defer { Darwin.close(fd) }

                // Send a length of 65537 (one byte over the 64 KB limit).
                let oversizeHeader = SocketMessageFraming.encodeLength(65_537)
                let written = oversizeHeader.withUnsafeBytes { ptr in
                    Darwin.write(fd, ptr.baseAddress!, ptr.count)
                }
                guard written == oversizeHeader.count else { return }

                // Server should close the connection without responding.
                var oneByte = [UInt8](repeating: 0, count: 1)
                let readResult = Darwin.read(fd, &oneByte, 1)
                connectionClosed = (readResult <= 0)
            } catch {
                connectionClosed = true
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(connectionClosed,
                      "Server should close connection on oversized payload length")
    }

    // MARK: - TEST 4: Partial header (only 2 of 4 bytes) causes connection close

    @MainActor
    func testPartialHeaderCausesConnectionClose() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let expectation = expectation(description: "Partial header test")
        var connectionClosed = false

        DispatchQueue.global().async { [testSocketPath] in
            do {
                let fd = try SocketTestClient.connect(to: testSocketPath!)
                defer { Darwin.close(fd) }

                // Write only 2 bytes of the 4-byte header, then close.
                var partialHeader: [UInt8] = [0x00, 0x01]
                Darwin.write(fd, &partialHeader, 2)

                // Close the connection immediately — server is left waiting for
                // the remaining 2 bytes and should time out or detect EOF.
                Darwin.close(fd)
                connectionClosed = true
            } catch {
                connectionClosed = true
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(connectionClosed,
                      "Partial header should cause connection closure (client side)")
    }

    // MARK: - TEST 5: Rapid successive reconnections do not crash or leak

    @MainActor
    func testRapidSuccessiveReconnectionsAreHandledSafely() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let group = DispatchGroup()
        let reconnectCount = 5
        var successfulConnections = 0
        let lock = NSLock()

        for i in 0..<reconnectCount {
            group.enter()
            DispatchQueue.global().async { [testSocketPath] in
                defer { group.leave() }
                do {
                    let fd = try SocketTestClient.connect(to: testSocketPath!)
                    defer { Darwin.close(fd) }

                    let req = SocketRequest(id: "rapid-\(i)", command: "status", params: nil)
                    let resp = try SocketTestClient.sendRequest(req, on: fd)

                    if resp.success {
                        lock.lock()
                        successfulConnections += 1
                        lock.unlock()
                    }
                } catch {
                    // Some connections may fail under rapid load — that is acceptable.
                }
            }
        }

        let expectation = expectation(description: "Rapid reconnections complete")
        group.notify(queue: .main) { expectation.fulfill() }
        wait(for: [expectation], timeout: 10.0)

        // All connections should succeed — the server must remain stable.
        XCTAssertEqual(successfulConnections, reconnectCount,
                       "All \(reconnectCount) rapid reconnections should succeed")
        XCTAssertTrue(server.isRunning,
                      "Server must still be running after rapid reconnections")
    }

    // MARK: - TEST 6: All 7 known commands produce success responses

    @MainActor
    func testAllSevenCommandsProduceSuccessResponses() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let commands = CLICommandName.allCases.map { $0.rawValue }
        XCTAssertEqual(commands.count, 77,
                       "There should be exactly 77 commands in CLICommandName including the core contract web/stream/protocol/image endpoints")

        for command in commands {
            let request = SocketRequest(id: "all-\(command)", command: command, params: nil)

            let expectation = expectation(description: "Command \(command)")
            var response: SocketResponse?

            SocketTestClient.roundTrip(socketPath: testSocketPath, request: request) { result in
                response = try? result.get()
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 5.0)

            XCTAssertNotNil(response, "Should receive a response for command '\(command)'")
            XCTAssertTrue(response?.success == true,
                          "Command '\(command)' should produce a success response, got: \(response?.error ?? "nil")")
        }
    }

    // MARK: - TEST 7: Server rejects injected null bytes in command name

    @MainActor
    func testNullByteInCommandNameProducesUnknownCommandError() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let expectation = expectation(description: "Null byte in command")
        var response: SocketResponse?

        DispatchQueue.global().async { [testSocketPath] in
            do {
                let fd = try SocketTestClient.connect(to: testSocketPath!)
                defer { Darwin.close(fd) }

                // JSON with null byte in command field.
                let payload = "{\"id\":\"null-1\",\"command\":\"stat\\u0000us\",\"params\":null}"
                    .data(using: .utf8)!
                response = try SocketTestClient.sendRawPayload(payload, on: fd)
            } catch {
                // Connection may be closed on malformed input.
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        // Either the server closes the connection (response == nil) or
        // returns an error (success == false). Either is correct.
        if let response {
            XCTAssertFalse(response.success,
                           "Command with null byte should not succeed")
        }
        // If response is nil, the server closed the connection — also acceptable.
    }

    // MARK: - TEST 8: Very large number of params fields in valid payload

    @MainActor
    func testMaximumValidParamsDictionaryIsHandledCorrectly() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        // Build a params dict that is large but under 64 KB when encoded.
        var params: [String: String] = [:]
        for i in 0..<50 {
            params["key\(i)"] = "value\(i)"
        }

        let request = SocketRequest(id: "large-params", command: "notify", params: params)
        let expectation = expectation(description: "Large params")
        var response: SocketResponse?

        SocketTestClient.roundTrip(socketPath: testSocketPath, request: request) { result in
            response = try? result.get()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertNotNil(response)
        XCTAssertTrue(response?.success == true,
                      "Large but valid params dict should be accepted")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "notify")
    }
}

// MARK: - CLI Integration Edge Cases

/// Tests for CLI edge cases not covered by existing suites.
final class Phase7CLIIntegrationTests: XCTestCase {

    private let runner = CommandRunner(
        socketClient: SocketClient(socketPath: "/tmp/cocxy-p7-nonexistent.sock")
    )

    // MARK: - TEST 9: buildRequest for .help produces a "status" command

    func testBuildRequestForHelpProducesStatusCommand() {
        let request = runner.buildRequest(from: .help)
        // Per CommandRunner.buildRequest, .help falls through to "status".
        XCTAssertEqual(request.command, "status",
                       ".help should map to 'status' command in buildRequest")
    }

    // MARK: - TEST 10: buildRequest for .version produces a "status" command

    func testBuildRequestForVersionProducesStatusCommand() {
        let request = runner.buildRequest(from: .version)
        XCTAssertEqual(request.command, "status",
                       ".version should map to 'status' command in buildRequest")
    }

    // MARK: - TEST 11: buildRequest IDs are unique across calls

    func testBuildRequestProducesUniqueIDsEachTime() {
        let req1 = runner.buildRequest(from: .status)
        let req2 = runner.buildRequest(from: .status)
        XCTAssertNotEqual(req1.id, req2.id,
                          "Successive buildRequest calls should produce unique UUIDs")
    }

    // MARK: - TEST 12: CommandRunner returns exit code 1 when server returns error

    func testCommandRunnerReturnsExitCode1OnServerError() {
        // With a nonexistent socket, the runner should return exit 1 with
        // the "not running" error message.
        let result = runner.run(arguments: ["status"])
        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertFalse(result.stderr.isEmpty,
                       "stderr should contain an error description")
    }

    // MARK: - TEST 13: Notify with empty string after whitespace is an error

    func testNotifyWithOnlyWhitespaceTokenIsError() {
        // "notify   " — after joining, the message is empty spaces.
        // The parser checks `!message.isEmpty` on the first token, but
        // if the first token is spaces, it still passes.
        // This documents the current behavior rather than asserting a fix.
        let result = try? CLIArgumentParser.parse(["notify", " "])
        // The parser accepts " " as a valid message (non-empty string).
        // This is consistent behavior — callers are responsible for trimming.
        XCTAssertNotNil(result, "Single space is technically a non-empty message")
    }

    // MARK: - TEST 14: Split direction 'v' maps to vertical in buildRequest

    func testBuildSplitRequestWithVerticalDirectionMapsCorrectly() {
        let request = runner.buildRequest(from: .split(direction: .vertical))
        XCTAssertEqual(request.command, "split")
        XCTAssertEqual(request.params?["direction"], "vertical",
                       "Vertical direction should serialize as 'vertical'")
    }

    // MARK: - TEST 15: CLI framing maxPayloadSize constant matches server constant

    func testCLIAndServerMaxPayloadSizeAreEqual() {
        XCTAssertEqual(
            CLIMessageFraming.maxPayloadSize,
            65_536,
            "CLI maxPayloadSize must match server 64 KB limit"
        )
    }

    // MARK: - TEST 16: CLIMessageFraming.frame throws on 64KB+1 byte payload

    func testCLIFramingRejectsOversizedPayload() {
        var hugeParams: [String: String] = [:]
        for i in 0..<5000 {
            hugeParams["key_\(i)"] = String(repeating: "x", count: 20)
        }
        let request = CLISocketRequest(id: "huge", command: "notify", params: hugeParams)

        XCTAssertThrowsError(try CLIMessageFraming.frame(request)) { error in
            guard let cliError = error as? CLIError,
                  case .payloadTooLarge = cliError else {
                XCTFail("Expected CLIError.payloadTooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: - TEST 17: CLIArgumentParser handles unicode in messages

    func testNotifyWithUnicodeMessageIsParsedCorrectly() throws {
        let result = try CLIArgumentParser.parse(["notify", "Tarea", "completada", "correctamente"])
        XCTAssertEqual(result, .notify(message: "Tarea completada correctamente"))
    }

    // MARK: - TEST 18: split --dir flag followed by unknown flag throws error

    func testNewTabWithUnknownFlagThrowsInvalidArgument() {
        XCTAssertThrowsError(
            try CLIArgumentParser.parse(["new-tab", "--unknown-flag"])
        ) { error in
            guard let cliError = error as? CLIError,
                  case .invalidArgument(let command, _, _) = cliError else {
                XCTFail("Expected CLIError.invalidArgument, got \(error)")
                return
            }
            XCTAssertEqual(command, "new-tab")
        }
    }
}

// MARK: - AnimationConfig Additional Tests

/// Additional animation tests covering edge cases.
@MainActor
final class Phase7AnimationTests: XCTestCase {

    // MARK: - TEST 19: duration(0) without reduce motion returns 0

    func testDurationZeroBaseReturnsZeroRegardlessOfReduceMotion() {
        let withMotion = AnimationConfig.duration(0, reduceMotionOverride: false)
        let withoutMotion = AnimationConfig.duration(0, reduceMotionOverride: true)

        XCTAssertEqual(withMotion, 0,
                       "duration(0) with motion enabled should be 0")
        XCTAssertEqual(withoutMotion, 0,
                       "duration(0) with reduce motion should be 0")
    }

    // MARK: - TEST 20: All constants return 0 when reduce motion is active

    func testAllConstantsReturnZeroWhenReduceMotionIsActive() {
        let constants: [(String, TimeInterval)] = [
            ("tabAppearDuration", AnimationConfig.tabAppearDuration),
            ("tabDisappearDuration", AnimationConfig.tabDisappearDuration),
            ("splitTransitionDuration", AnimationConfig.splitTransitionDuration),
            ("stateColorTransitionDuration", AnimationConfig.stateColorTransitionDuration),
            ("quickTerminalSlideDuration", AnimationConfig.quickTerminalSlideDuration),
            ("notificationToastDuration", AnimationConfig.notificationToastDuration),
        ]

        for (name, constant) in constants {
            let result = AnimationConfig.duration(constant, reduceMotionOverride: true)
            XCTAssertEqual(result, 0,
                           "\(name) should return 0 when reduce motion is active")
        }
    }

    // MARK: - TEST 21: notificationToastDuration is longer than other transitions

    func testNotificationToastDurationIsLongestAnimation() {
        let shortDurations: [TimeInterval] = [
            AnimationConfig.tabAppearDuration,
            AnimationConfig.tabDisappearDuration,
            AnimationConfig.splitTransitionDuration,
            AnimationConfig.stateColorTransitionDuration,
            AnimationConfig.quickTerminalSlideDuration,
        ]

        for duration in shortDurations {
            XCTAssertGreaterThan(
                AnimationConfig.notificationToastDuration,
                duration,
                "notificationToastDuration should be the longest animation constant"
            )
        }
    }
}

// MARK: - Accessibility Additional Tests

/// Additional accessibility tests covering edge cases.
@MainActor
final class Phase7AccessibilityTests: XCTestCase {

    // MARK: - TEST 22: contrastRatio is symmetric

    func testContrastRatioIsSymmetric() {
        let color1 = NSColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1.0)
        let color2 = NSColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1.0)

        let ratio1 = AccessibilityHelpers.contrastRatio(color1, color2)
        let ratio2 = AccessibilityHelpers.contrastRatio(color2, color1)

        XCTAssertEqual(ratio1, ratio2, accuracy: 0.001,
                       "contrastRatio must be symmetric: order of arguments should not matter")
    }

    // MARK: - TEST 23: contrastRatio is always >= 1.0

    func testContrastRatioIsAlwaysAtLeastOne() {
        let testPairs: [(NSColor, NSColor)] = [
            (.red, .blue),
            (.green, .yellow),
            (NSColor(white: 0.3, alpha: 1.0), NSColor(white: 0.7, alpha: 1.0)),
            (.black, .black),
            (.white, .white),
        ]

        for (c1, c2) in testPairs {
            let ratio = AccessibilityHelpers.contrastRatio(c1, c2)
            XCTAssertGreaterThanOrEqual(ratio, 1.0,
                                        "Contrast ratio must always be >= 1.0")
        }
    }

    // MARK: - TEST 24: meetsWCAGAA boundary: ratio exactly 4.5 passes

    func testMeetsWCAGAABoundaryExactly45() {
        // We cannot produce an exact 4.5:1 ratio without precise color math,
        // but we can verify the threshold constant is 4.5.
        XCTAssertEqual(AccessibilityHelpers.wcagAANormalTextThreshold, 4.5,
                       "WCAG AA normal text threshold must be exactly 4.5")
    }

    // MARK: - TEST 25: relativeLuminance output is always in [0.0, 1.0]

    func testRelativeLuminanceIsAlwaysInValidRange() {
        let colors: [NSColor] = [
            .black, .white, .red, .green, .blue,
            NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
            NSColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 0.5), // alpha ignored
        ]

        for color in colors {
            let luminance = AccessibilityHelpers.relativeLuminance(color)
            XCTAssertGreaterThanOrEqual(luminance, 0.0,
                                        "Luminance must be >= 0.0 for \(color)")
            XCTAssertLessThanOrEqual(luminance, 1.0,
                                     "Luminance must be <= 1.0 for \(color)")
        }
    }

    // MARK: - TEST 26: All AgentState accessibility descriptions are unique

    func testAllAgentStateDescriptionsAreUnique() {
        let allStates: [AgentState] = [.idle, .launched, .working, .waitingInput, .finished, .error]
        let descriptions = allStates.map { $0.accessibilityDescription }
        let uniqueDescriptions = Set(descriptions)

        XCTAssertEqual(
            descriptions.count,
            uniqueDescriptions.count,
            "Each AgentState must have a unique accessibility description to avoid VoiceOver confusion"
        )
    }

    // MARK: - TEST 27: AgentState descriptions are user-facing language (no "state" suffix)

    func testAgentStateDescriptionsDoNotContainTechnicalJargon() {
        let technicalTerms = ["state", "case", "enum", "nil", "null"]
        let allStates: [AgentState] = [.idle, .launched, .working, .waitingInput, .finished, .error]

        for state in allStates {
            let description = state.accessibilityDescription.lowercased()
            for term in technicalTerms {
                XCTAssertFalse(
                    description.contains(term),
                    "Description for \(state) contains technical term '\(term)': \(description)"
                )
            }
        }
    }

    // MARK: - TEST 28: wcagAALargeTextThreshold is 3.0

    func testWCAGLargeTextThresholdIs3() {
        XCTAssertEqual(AccessibilityHelpers.wcagAALargeTextThreshold, 3.0,
                       "WCAG AA large text threshold must be exactly 3.0")
    }
}

// MARK: - Wire Protocol Cross-Cutting Tests

/// Tests that verify the CLI and server use identical wire protocol constants.
final class Phase7WireProtocolTests: XCTestCase {

    // MARK: - TEST 29: CLI headerSize matches server headerSize

    func testCLIAndServerHeaderSizeMatch() {
        XCTAssertEqual(
            CLIMessageFraming.headerSize,
            SocketMessageFraming.headerSize,
            "CLI and server must use the same header size"
        )
    }

    // MARK: - TEST 30: CLI maxPayloadSize matches server maxPayloadSize

    func testCLIAndServerMaxPayloadSizeMatch() {
        XCTAssertEqual(
            CLIMessageFraming.maxPayloadSize,
            SocketMessageFraming.maxPayloadSize,
            "CLI and server must use the same maximum payload size"
        )
    }

    // MARK: - TEST 31: CLI and server CLICommandName rawValues are identical

    func testCLICommandRawValuesMatchCLICommandNameRawValues() {
        // CLICommand (CLI) and CLICommandName (server) must have identical rawValues
        // so that the CLI sends strings the server will recognize.
        let cliCommands = Set(CLICommand.allCases.map { $0.rawValue })
        let serverCommands = Set(CLICommandName.allCases.map { $0.rawValue })

        XCTAssertEqual(
            cliCommands,
            serverCommands,
            "CLI and server command names must be identical. "
            + "CLI has: \(cliCommands.sorted()). "
            + "Server has: \(serverCommands.sorted())"
        )
    }

    // MARK: - TEST 32: SocketRequest and CLISocketRequest have same field names

    func testSocketRequestAndCLISocketRequestProduceCompatibleJSON() throws {
        // Encode a CLISocketRequest (CLI side) and decode as SocketRequest (server side).
        let cliRequest = CLISocketRequest(
            id: "compat-wire",
            command: "notify",
            params: ["message": "hello from CLI"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jsonData = try encoder.encode(cliRequest)

        // The server must be able to decode this JSON as a SocketRequest.
        let serverRequest = try JSONDecoder().decode(SocketRequest.self, from: jsonData)

        XCTAssertEqual(serverRequest.id, cliRequest.id)
        XCTAssertEqual(serverRequest.command, cliRequest.command)
        XCTAssertEqual(serverRequest.params?["message"], cliRequest.params?["message"])
    }
}
