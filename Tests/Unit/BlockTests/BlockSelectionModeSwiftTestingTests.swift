// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Block selection mode")
struct BlockSelectionModeSwiftTestingTests {

    @Test("toggle and prune maintain selected block ids")
    func toggleAndPruneMaintainSelectedBlockIDs() {
        var selection = BlockSelectionMode()

        selection.toggle(1)
        selection.toggle(2)
        #expect(selection.selectedCount == 2)
        #expect(selection.contains(1))
        #expect(selection.contains(2))

        selection.toggle(1)
        #expect(selection.selectedCount == 1)
        #expect(selection.contains(1) == false)

        selection.prune(validIDs: [1, 3])
        #expect(selection.isActive == false)
    }

    @Test("selectedBlocks preserves display order")
    func selectedBlocksPreservesDisplayOrder() {
        var selection = BlockSelectionMode()
        selection.toggle(3)
        selection.toggle(1)

        let blocks = [
            sampleBlock(id: 1, output: "one"),
            sampleBlock(id: 2, output: "two"),
            sampleBlock(id: 3, output: "three")
        ]

        #expect(selection.selectedBlocks(in: blocks).map(\.id) == [1, 3])
    }

    @Test("copy formatter joins selected outputs and falls back to commands")
    func copyFormatterJoinsSelectedOutputsAndFallsBackToCommands() {
        let text = BlockSelectionCopyFormatter.outputText(for: [
            sampleBlock(id: 1, command: "pwd", output: "/tmp\n"),
            sampleBlock(id: 2, command: "whoami", output: "")
        ])

        #expect(text == "/tmp\n\nwhoami")
    }

    private func sampleBlock(
        id: UInt64,
        command: String = "echo hi",
        output: String
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            command: command,
            output: output,
            exitCode: 0,
            pwd: nil,
            startTimeNs: 1,
            endTimeNs: 2,
            durationNs: 1,
            startRow: 1,
            endRow: 2,
            streamID: 0,
            blockType: 2
        )
    }
}
