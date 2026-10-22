// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Terminal output buffer bounds")
@MainActor
struct TerminalOutputBufferBoundsSwiftTestingTests {
    @Test("ANSI controls split across chunks remain hidden")
    func splitANSIControlsRemainHidden() {
        let buffer = TerminalOutputBuffer(maxLineCount: 10)

        buffer.append(Data("\u{1B}[38;5".utf8))
        buffer.append(Data(";42mgreen\u{1B}[0m \u{1B}]0;private title".utf8))
        buffer.append(Data("\u{07}visible Û漢字\n".utf8))

        #expect(buffer.lines == ["green visible Û漢字"])
    }

    @Test("ten MiB without a newline retains a fixed tail in bounded time")
    func largeUnterminatedChunkRemainsBounded() {
        let buffer = TerminalOutputBuffer(maxLineCount: 10)
        let payload = Data(repeating: Character("x").asciiValue!, count: 10 * 1_024 * 1_024)
        let clock = ContinuousClock()
        let startedAt = clock.now

        buffer.append(payload)

        let elapsed = startedAt.duration(to: clock.now)
        #expect(elapsed < .seconds(5))
        #expect(buffer.lineCount == 0)
        #expect(
            buffer.retainedPartialLineByteCount
                == TerminalOutputBuffer.maxPartialLineByteCount
        )

        buffer.append(Data("tail\n".utf8))

        let retainedLine = buffer.lines.first
        #expect(retainedLine?.utf8.count == TerminalOutputBuffer.maxPartialLineByteCount)
        #expect(retainedLine?.hasSuffix("tail") == true)
        #expect(buffer.retainedPartialLineByteCount == 0)
    }
}
