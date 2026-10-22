// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Testing

@Suite("Terminal byte write completion")
struct TerminalByteWriteCompleterSwiftTestingTests {
    @Test("partial writes continue from the exact remaining offset")
    func partialWritesCompleteExactly() {
        let plannedWrites = [3, 2, 5]
        var observedOffsets: [Int] = []
        var call = 0

        let written = TerminalByteWriteCompleter.writeAll(byteCount: 10) { offset, remaining in
            observedOffsets.append(offset)
            defer { call += 1 }
            return min(plannedWrites[call], remaining)
        }

        #expect(written == 10)
        #expect(observedOffsets == [0, 3, 5])
    }

    @Test("zero and invalid write results fail without retry loops")
    func failedWritesStopImmediately() {
        var calls = 0
        let zeroResult = TerminalByteWriteCompleter.writeAll(byteCount: 8) { _, _ in
            calls += 1
            return 0
        }
        #expect(zeroResult == 0)
        #expect(calls == 1)

        let oversizedResult = TerminalByteWriteCompleter.writeAll(byteCount: 8) { _, _ in 9 }
        #expect(oversizedResult == 0)
    }
}
