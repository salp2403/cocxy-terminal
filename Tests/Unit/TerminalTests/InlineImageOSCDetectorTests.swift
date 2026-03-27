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

    // MARK: - BEL Terminator

    func testDetectsOSC1337WithBELTerminator() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:AAAA".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertEqual(received, "File=inline=1:AAAA")
    }

    // MARK: - ST Terminator

    func testDetectsOSC1337WithSTTerminator() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:BBBB".utf8)
            + [0x1B, 0x5C]
        detector.processBytes(Data(bytes))

        XCTAssertEqual(received, "File=inline=1:BBBB")
    }

    // MARK: - Non-1337 Filtering

    func testIgnoresNon1337OSC() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("133;A".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received, "OSC 133 should be ignored by the image detector")
    }

    func testIgnoresOSC9() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("9;notification".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received, "OSC 9 should be ignored by the image detector")
    }

    // MARK: - Large Payloads

    func testHandlesPayloadAbove4KBLimit() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let largeData = String(repeating: "A", count: 100_000)
        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:\(largeData)".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNotNil(received, "100KB payload should be handled")
        XCTAssertTrue(received!.contains(largeData))
    }

    // MARK: - Incremental Processing

    func testIncrementalProcessingAcrossChunks() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        detector.processBytes(Data([0x1B, 0x5D]))
        detector.processBytes(Data(Array("1337;".utf8)))
        detector.processBytes(Data(Array("File=inline=1:DATA".utf8)))
        XCTAssertNil(received, "Should not emit before terminator")

        detector.processBytes(Data([0x07]))
        XCTAssertEqual(received, "File=inline=1:DATA")
    }

    // MARK: - Reset

    func testResetClearsPartialState() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        detector.processBytes(Data([0x1B, 0x5D] + Array("1337;partial".utf8)))
        detector.reset()
        detector.processBytes(Data([0x07]))

        XCTAssertNil(received, "Reset should discard partial payload")
    }

    // MARK: - Empty Payload

    func testEmptyPayloadIsNotEmitted() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received, "Empty payload should not trigger handler")
    }

    // MARK: - Multiple Sequences

    func testMultipleSequencesInSingleChunk() {
        var received: [String] = []
        let detector = InlineImageOSCDetector { payload in
            received.append(payload)
        }

        let first: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=1:AAA".utf8)
            + [0x07]
        let second: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=2:BBB".utf8)
            + [0x1B, 0x5C]
        detector.processBytes(Data(first + second))

        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0], "File=1:AAA")
        XCTAssertEqual(received[1], "File=2:BBB")
    }

    // MARK: - Interleaved Non-OSC Data

    func testIgnoresPlainTextBetweenSequences() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let plainText = Array("Hello, world! Some terminal output.\r\n".utf8)
        let oscSequence: [UInt8] = [0x1B, 0x5D]
            + Array("1337;File=inline=1:IMG".utf8)
            + [0x07]
        detector.processBytes(Data(plainText + oscSequence))

        XCTAssertEqual(received, "File=inline=1:IMG")
    }

    // MARK: - Oversized Payload

    func testDiscardsPayloadExceeding16MB() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        // 16MB + 1 byte exceeds the limit.
        let oversizedData = String(repeating: "X", count: 16 * 1024 * 1024 + 1)
        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("1337;".utf8)
            + Array(oversizedData.utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received, "Payload exceeding 16MB should be discarded")
    }

    // MARK: - Non-Digit Code

    func testRejectsNonDigitOSCCode() {
        var received: String?
        let detector = InlineImageOSCDetector { payload in
            received = payload
        }

        let bytes: [UInt8] = [0x1B, 0x5D]
            + Array("abc;payload".utf8)
            + [0x07]
        detector.processBytes(Data(bytes))

        XCTAssertNil(received, "Non-digit OSC code should be rejected")
    }
}
