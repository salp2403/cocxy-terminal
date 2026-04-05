// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineImageOSCDetectorTests.swift - Tests for dedicated OSC 1337 parser.

import XCTest
@testable import CocxyTerminal

// MARK: - Inline Image OSC Detector Tests

/// Tests for `InlineImageOSCDetector`: a dedicated OSC 1337 parser
/// that handles large image payloads independently of the general
/// `OSCSequenceDetector` (which has a 4KB buffer limit).
///
/// Covers:
/// - BEL and ST terminator detection.
/// - Non-1337 OSC sequences are ignored.
/// - Large payloads (above the 4KB limit of the general detector).
/// - Incremental byte processing across chunked input.
/// - Reset clears partial state.
/// - Empty payloads are not emitted.
/// - Oversized payloads (above 16MB) are discarded.
final class InlineImageOSCDetectorTests: XCTestCase {

    private func makePayloadBox() -> LockedBox<String?> {
        LockedBox(nil)
    }

    private func makeDetector(received: LockedBox<String?>) -> InlineImageOSCDetector {
        InlineImageOSCDetector { payload in
            received.withValue { $0 = payload }
        }
    }

    // MARK: - BEL Terminator

    func testDetectsOSC1337WithBELTerminator() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:AAAA".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertEqual(received.withValue { $0 }, "File=inline=1:AAAA")
    }

    // MARK: - ST Terminator

    func testDetectsOSC1337WithSTTerminator() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:BBBB".utf8)
            + [0x1B, 0x5C]
        detector.processBytes(Data(bytes))

        XCTAssertEqual(received.withValue { $0 }, "File=inline=1:BBBB")
    }

    // MARK: - Non-1337 Filtering

    func testIgnoresNon1337OSC() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("133;A".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received.withValue { $0 }, "OSC 133 should be ignored by the image detector")
    }

    func testIgnoresOSC9() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("9;notification".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received.withValue { $0 }, "OSC 9 should be ignored by the image detector")
    }

    // MARK: - Large Payloads

    func testHandlesPayloadAbove4KBLimit() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let largeData = String(repeating: "A", count: 100_000)
        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:\(largeData)".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        let payload = received.withValue { $0 }
        XCTAssertNotNil(payload, "100KB payload should be handled")
        XCTAssertTrue(payload?.contains(largeData) == true)
    }

    // MARK: - Incremental Processing

    func testIncrementalProcessingAcrossChunks() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        detector.processBytes(Data([0x1B, 0x5D]))
        detector.processBytes(Data(Array("1337;".utf8)))
        detector.processBytes(Data(Array("File=inline=1:DATA".utf8)))
        XCTAssertNil(received.withValue { $0 }, "Should not emit before terminator")

        detector.processBytes(Data([0x07]))
        XCTAssertEqual(received.withValue { $0 }, "File=inline=1:DATA")
    }

    // MARK: - Reset

    func testResetClearsPartialState() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        detector.processBytes(Data([0x1B, 0x5D] + Array("1337;partial".utf8)))
        detector.reset()
        detector.processBytes(Data([0x07]))

        XCTAssertNil(received.withValue { $0 }, "Reset should discard partial payload")
    }

    // MARK: - Empty Payload

    func testEmptyPayloadIsNotEmitted() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received.withValue { $0 }, "Empty payload should not trigger handler")
    }

    // MARK: - Multiple Sequences

    func testMultipleSequencesInSingleChunk() {
        let received = LockedBox<[String]>([])
        let detector = InlineImageOSCDetector { payload in
            received.withValue { $0.append(payload) }
        }

        let first: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=1:AAA".utf8)
            + [0x07]
        let second: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=2:BBB".utf8)
            + [0x1B, 0x5C]
        detector.processBytes(Data(first + second))

        let payloads = received.withValue { $0 }
        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads[0], "File=1:AAA")
        XCTAssertEqual(payloads[1], "File=2:BBB")
    }

    // MARK: - Interleaved Non-OSC Data

    func testIgnoresPlainTextBetweenSequences() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let plainText = Array("Hello, world! Some terminal output.\r\n".utf8)
        let oscSequence: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:IMG".utf8)
            + [0x07]
        detector.processBytes(Data(plainText + oscSequence))

        XCTAssertEqual(received.withValue { $0 }, "File=inline=1:IMG")
    }

    // MARK: - Oversized Payload

    func testDiscardsPayloadExceeding16MB() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        // 16MB + 1 byte exceeds the limit.
        let oversizedData = String(repeating: "X", count: 16 * 1024 * 1024 + 1)
        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;".utf8)
            + Array(oversizedData.utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received.withValue { $0 }, "Payload exceeding 16MB should be discarded")
    }

    // MARK: - Non-Digit Code

    func testRejectsNonDigitOSCCode() {
        let received = makePayloadBox()
        let detector = makeDetector(received: received)

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("abc;payload".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received.withValue { $0 }, "Non-digit OSC code should be rejected")
    }
}
