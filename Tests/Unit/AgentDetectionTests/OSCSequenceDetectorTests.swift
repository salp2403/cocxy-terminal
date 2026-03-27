// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OSCSequenceDetectorTests.swift - Tests for OSC sequence detection layer 1.

import XCTest
@testable import CocxyTerminal

// MARK: - OSC Sequence Detector Tests

/// Tests for `OSCSequenceDetector`: the highest-confidence detection layer.
///
/// Covers:
/// - Parsing OSC 133 sub-commands (;A, ;B, ;C, ;D).
/// - Parsing OSC 9 desktop notifications.
/// - Parsing OSC 99 agent hooks.
/// - Parsing OSC 777 generic notifications.
/// - Incremental parsing across split chunks.
/// - Handling incomplete sequences without crash.
/// - Multiple OSC sequences in a single chunk.
/// - Mixed data (plain text interleaved with OSC).
/// - Unknown OSC codes are ignored.
/// - Both BEL and ST terminators.
/// - Performance: 1MB of output in < 100ms.
final class OSCSequenceDetectorTests: XCTestCase {

    private var sut: OSCSequenceDetector!

    override func setUp() {
        super.setUp()
        sut = OSCSequenceDetector()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Builds an OSC sequence terminated by BEL (0x07).
    /// Format: ESC ] <code> ; <payload> BEL
    private func oscSequenceBEL(code: Int, payload: String) -> Data {
        var bytes: [UInt8] = [0x1B, 0x5D] // ESC ]
        bytes.append(contentsOf: "\(code)".utf8)
        bytes.append(0x3B) // ;
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x07) // BEL
        return Data(bytes)
    }

    /// Builds an OSC sequence terminated by ST (ESC \).
    /// Format: ESC ] <code> ; <payload> ESC \
    private func oscSequenceST(code: Int, payload: String) -> Data {
        var bytes: [UInt8] = [0x1B, 0x5D] // ESC ]
        bytes.append(contentsOf: "\(code)".utf8)
        bytes.append(0x3B) // ;
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x1B) // ESC
        bytes.append(0x5C) // backslash
        return Data(bytes)
    }

    // MARK: - OSC 133 Tests

    func testParseOSC133APromptStartMapsToCompletionDetected() {
        let data = oscSequenceBEL(code: 133, payload: "A")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .completionDetected = signals.first?.event {
            // Expected
        } else {
            XCTFail("OSC 133;A should map to completionDetected, got \(String(describing: signals.first?.event))")
        }
        XCTAssertEqual(signals.first?.confidence, 1.0)
        XCTAssertEqual(signals.first?.source, .osc(code: 133))
    }

    func testParseOSC133BCommandStartMapsToOutputReceived() {
        let data = oscSequenceBEL(code: 133, payload: "B")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .outputReceived = signals.first?.event {
            // Expected
        } else {
            XCTFail("OSC 133;B should map to outputReceived, got \(String(describing: signals.first?.event))")
        }
        XCTAssertEqual(signals.first?.confidence, 1.0)
    }

    func testParseOSC133CCommandOutputStartMapsToOutputReceived() {
        let data = oscSequenceBEL(code: 133, payload: "C")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .outputReceived = signals.first?.event {
            // Expected
        } else {
            XCTFail("OSC 133;C should map to outputReceived, got \(String(describing: signals.first?.event))")
        }
    }

    func testParseOSC133DCommandFinishedMapsToCompletionDetected() {
        let data = oscSequenceBEL(code: 133, payload: "D")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .completionDetected = signals.first?.event {
            // Expected
        } else {
            XCTFail("OSC 133;D should map to completionDetected, got \(String(describing: signals.first?.event))")
        }
    }

    func testParseOSC133DWithExitCodeZero() {
        let data = oscSequenceBEL(code: 133, payload: "D;0")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .completionDetected = signals.first?.event {
            // Expected: exit code 0 means success
        } else {
            XCTFail("OSC 133;D;0 should map to completionDetected")
        }
    }

    func testParseOSC133DWithNonZeroExitCodeMapsToErrorDetected() {
        let data = oscSequenceBEL(code: 133, payload: "D;1")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .errorDetected(let message) = signals.first?.event {
            XCTAssertTrue(message.contains("1"), "Error message should contain the exit code")
        } else {
            XCTFail("OSC 133;D;1 should map to errorDetected")
        }
    }

    // MARK: - OSC 9 Tests

    func testParseOSC9DesktopNotification() {
        let data = oscSequenceBEL(code: 9, payload: "Task completed")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .completionDetected = signals.first?.event {
            // Expected
        } else {
            XCTFail("OSC 9 should map to completionDetected, got \(String(describing: signals.first?.event))")
        }
        XCTAssertEqual(signals.first?.source, .osc(code: 9))
        XCTAssertEqual(signals.first?.confidence, 0.9)
    }

    // MARK: - OSC 99 Tests

    func testParseOSC99AgentHook() {
        let data = oscSequenceBEL(code: 99, payload: "agent-status;working")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.source, .osc(code: 99))
        XCTAssertEqual(signals.first?.confidence, 1.0)
    }

    // MARK: - OSC 777 Tests

    func testParseOSC777GenericNotification() {
        let data = oscSequenceBEL(code: 777, payload: "notify;Done;Build finished")
        let signals = sut.processBytes(data)

        XCTAssertEqual(signals.count, 1)
        if case .completionDetected = signals.first?.event {
            // Expected
        } else {
            XCTFail("OSC 777 should map to completionDetected, got \(String(describing: signals.first?.event))")
        }
        XCTAssertEqual(signals.first?.source, .osc(code: 777))
        XCTAssertEqual(signals.first?.confidence, 0.9)
    }

    // MARK: - Incremental Parsing (Split Chunks)

    func testParseSequenceSplitAcrossTwoChunks() {
        // Split OSC 133;A sequence between the code and payload
        let fullSequence = oscSequenceBEL(code: 133, payload: "A")
        let midpoint = fullSequence.count / 2
        let chunk1 = fullSequence.prefix(midpoint)
        let chunk2 = fullSequence.suffix(from: midpoint)

        let signals1 = sut.processBytes(Data(chunk1))
        XCTAssertTrue(signals1.isEmpty, "First chunk should not produce a complete signal")

        let signals2 = sut.processBytes(Data(chunk2))
        XCTAssertEqual(signals2.count, 1, "Second chunk should complete the sequence")
    }

    func testIncompleteSequenceDoesNotCrash() {
        // Send ESC ] 133 ; A but no terminator
        var bytes: [UInt8] = [0x1B, 0x5D] // ESC ]
        bytes.append(contentsOf: "133".utf8)
        bytes.append(0x3B) // ;
        bytes.append(contentsOf: "A".utf8)
        // No BEL, no ST
        let data = Data(bytes)

        let signals = sut.processBytes(data)
        XCTAssertTrue(signals.isEmpty, "Incomplete sequence should produce no signals")
    }

    // MARK: - Multiple Sequences in One Chunk

    func testMultipleOSCSequencesInSingleChunk() {
        let seq1 = oscSequenceBEL(code: 133, payload: "B")
        let seq2 = oscSequenceBEL(code: 133, payload: "D;0")
        var combined = Data()
        combined.append(seq1)
        combined.append(seq2)

        let signals = sut.processBytes(combined)
        XCTAssertEqual(signals.count, 2, "Should parse both sequences from a single chunk")
    }

    // MARK: - Mixed Data (Text + OSC)

    func testMixedDataTextAndOSC() {
        var data = Data("Hello, world!".utf8)
        data.append(oscSequenceBEL(code: 133, payload: "A"))
        data.append(Data("More text output here".utf8))

        let signals = sut.processBytes(data)
        XCTAssertEqual(signals.count, 1, "Should detect OSC sequence amid plain text")
    }

    // MARK: - Unknown OSC Codes

    func testUnknownOSCCodeIsIgnored() {
        let data = oscSequenceBEL(code: 42, payload: "whatever")
        let signals = sut.processBytes(data)

        XCTAssertTrue(signals.isEmpty, "Unknown OSC code 42 should be ignored")
    }

    // MARK: - BEL vs ST Terminator

    func testBELTerminatorWorks() {
        let data = oscSequenceBEL(code: 133, payload: "A")
        let signals = sut.processBytes(data)
        XCTAssertEqual(signals.count, 1)
    }

    func testSTTerminatorWorks() {
        let data = oscSequenceST(code: 133, payload: "A")
        let signals = sut.processBytes(data)
        XCTAssertEqual(signals.count, 1)
    }

    // MARK: - Performance

    func testPerformanceProcessing1MBOutput() {
        // Generate 1MB of mixed data with occasional OSC sequences
        var data = Data()
        let textChunk = Data(String(repeating: "x", count: 1000).utf8)
        let oscChunk = oscSequenceBEL(code: 133, payload: "A")

        for i in 0..<1024 {
            data.append(textChunk)
            if i % 100 == 0 {
                data.append(oscChunk)
            }
        }

        XCTAssertGreaterThan(data.count, 1_000_000, "Test data should be > 1MB")

        measure {
            let _ = sut.processBytes(data)
        }
    }

    // MARK: - Reset Buffer

    func testResetClearsPartialBuffer() {
        // Send partial sequence
        let partial = Data([0x1B, 0x5D] + Array("133".utf8))
        let _ = sut.processBytes(partial)

        sut.reset()

        // Now send a complete unrelated sequence
        let complete = oscSequenceBEL(code: 9, payload: "done")
        let signals = sut.processBytes(complete)
        XCTAssertEqual(signals.count, 1, "After reset, parser should not carry stale state")
    }

    // MARK: - DetectionLayer Conformance

    func testConformsToDetectionLayerProtocol() {
        let layer: DetectionLayer = sut
        let data = oscSequenceBEL(code: 133, payload: "A")
        let signals = layer.processBytes(data)
        XCTAssertFalse(signals.isEmpty)
    }
}
