// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Block OSC detector")
struct BlockOSCDetectorSwiftTestingTests {

    @Test("detects OSC 133 command block boundaries")
    func detectsOSC133CommandBlockBoundaries() {
        let detector = BlockOSCDetector()
        let data = Data(
            (
                "\u{1B}]133;A\u{7}" +
                "\u{1B}]133;B\u{7}" +
                "\u{1B}]133;C;echo hi\u{7}" +
                "\u{1B}]133;D;0\u{7}"
            ).utf8
        )

        #expect(detector.processBytes(data) == [
            .promptStarted,
            .commandStarted,
            .commandExecuted(command: "echo hi"),
            .commandFinished(exitCode: 0)
        ])
    }

    @Test("decodes percent encoded multiline command payloads")
    func decodesPercentEncodedMultilineCommandPayloads() {
        let detector = BlockOSCDetector()
        let data = oscBEL(
            code: 133,
            payload: "C;cocxy-percent-v1:for x in a b; do%0A  echo $x%0Adone"
        )

        #expect(detector.processBytes(data) == [
            .commandExecuted(command: "for x in a b; do\n  echo $x\ndone")
        ])
    }

    @Test("supports ST terminator and split chunks")
    func supportsSTTerminatorAndSplitChunks() {
        let detector = BlockOSCDetector()
        let sequence = oscST(code: 133, payload: "D;127")
        let split = sequence.count / 2

        #expect(detector.processBytes(Data(sequence.prefix(split))).isEmpty)
        #expect(detector.processBytes(Data(sequence.suffix(from: split))) == [
            .commandFinished(exitCode: 127)
        ])
    }

    @Test("ignores non block OSC and malformed command payloads safely")
    func ignoresNonBlockOSCAndMalformedCommandPayloadsSafely() {
        let detector = BlockOSCDetector()

        #expect(detector.processBytes(oscBEL(code: 9, payload: "Task completed")).isEmpty)
        #expect(detector.processBytes(oscBEL(code: 133, payload: "C;")) == [
            .commandExecuted(command: nil)
        ])
        #expect(detector.processBytes(oscBEL(code: 133, payload: "X")).isEmpty)
    }

    @Test("invokes event callback after parsing")
    func invokesEventCallbackAfterParsing() {
        let received = LockedBox<[BlockOSCEvent]>([])
        let detector = BlockOSCDetector { event in
            received.withValue { $0.append(event) }
        }

        _ = detector.processBytes(oscBEL(code: 133, payload: "B"))

        #expect(received.withValue { $0 } == [.commandStarted])
    }

    private func oscBEL(code: Int, payload: String) -> Data {
        var bytes: [UInt8] = [0x1B, 0x5D]
        bytes.append(contentsOf: "\(code)".utf8)
        bytes.append(0x3B)
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x07)
        return Data(bytes)
    }

    private func oscST(code: Int, payload: String) -> Data {
        var bytes: [UInt8] = [0x1B, 0x5D]
        bytes.append(contentsOf: "\(code)".utf8)
        bytes.append(0x3B)
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x1B)
        bytes.append(0x5C)
        return Data(bytes)
    }
}
