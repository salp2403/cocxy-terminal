// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalSemanticNavigationSwiftTestingTests.swift - Deterministic semantic navigation tests.

import Foundation
import Testing
import CocxyShared

@Suite("Terminal semantic navigation resolver")
struct TerminalSemanticNavigationSwiftTestingTests {
    private let prompts = [
        TerminalSemanticRegion(offset: 0, kind: .prompt, startRow: 30, endRow: 30),
        TerminalSemanticRegion(offset: 2, kind: .prompt, startRow: 20, endRow: 20),
        TerminalSemanticRegion(offset: 4, kind: .prompt, startRow: 10, endRow: 10),
    ]

    @Test("previous and next prompt preserve CocxyCore offset direction")
    func promptDirectionsUseOlderAndNewerOffsets() {
        let older: [UInt32: Int32] = [0: 2, 2: 4]
        let newer: [UInt32: Int32] = [4: 2, 2: 0]

        let previousFromBottom = resolvePrompt(
            .previousPrompt,
            visibleStartRow: 35,
            older: older,
            newer: newer
        )
        let previousAgain = resolvePrompt(
            .previousPrompt,
            visibleStartRow: 30,
            older: older,
            newer: newer
        )
        let nextAgain = resolvePrompt(
            .nextPrompt,
            visibleStartRow: 20,
            older: older,
            newer: newer
        )
        let nextFromTop = resolvePrompt(
            .nextPrompt,
            visibleStartRow: 5,
            older: older,
            newer: newer
        )

        #expect(previousFromBottom?.startRow == 30)
        #expect(previousAgain?.startRow == 20)
        #expect(nextAgain?.startRow == 30)
        #expect(nextFromTop?.startRow == 10)
    }

    @Test("prompt search skips offsets whose rows were evicted")
    func promptSearchSkipsUnmappedOffsets() {
        let target = TerminalSemanticNavigationResolver.promptRegion(
            for: .previousPrompt,
            visibleStartRow: 30,
            regions: prompts,
            maximumSearchSteps: 5,
            findOlder: { [0: 1, 1: 2][$0] ?? -1 },
            findNewer: { _ in -1 }
        )

        #expect(target?.offset == 2)
        #expect(target?.startRow == 20)
    }

    @Test("output selection follows the command associated with the current prompt")
    func outputSelectionUsesCurrentPromptBlock() {
        let regions = prompts + [
            TerminalSemanticRegion(
                blockID: 101,
                kind: .commandOutput,
                startRow: 12,
                endRow: 18
            ),
            TerminalSemanticRegion(
                blockID: 102,
                kind: .errorOutput,
                startRow: 22,
                endRow: 27
            ),
        ]

        #expect(output(at: 10, regions: regions)?.blockID == 101)
        #expect(output(at: 15, regions: regions)?.blockID == 101)
        #expect(output(at: 20, regions: regions)?.blockID == 102)
        #expect(output(at: 30, regions: regions)?.blockID == 102)
    }

    @Test("semantic result round-trips and selection uses absolute coordinates")
    func semanticResultRoundTrips() throws {
        let selection = TerminalSemanticSelection(
            blockID: 42,
            startRow: 8,
            startColumn: 2,
            endRow: 10,
            endColumn: 7,
            text: "complete output"
        )
        let result = TerminalSemanticNavigationResult(
            action: .selectCommandOutput,
            viewportStartRow: 8,
            selection: selection
        )

        let encoded = try JSONEncoder().encode(result)
        #expect(try JSONDecoder().decode(TerminalSemanticNavigationResult.self, from: encoded) == result)
        #expect(selection.contains(absoluteRow: 8, column: 2))
        #expect(selection.contains(absoluteRow: 9, column: 0))
        #expect(selection.contains(absoluteRow: 10, column: 7))
        #expect(selection.contains(absoluteRow: 10, column: 8) == false)
    }

    private func resolvePrompt(
        _ action: TerminalSemanticNavigationAction,
        visibleStartRow: UInt32,
        older: [UInt32: Int32],
        newer: [UInt32: Int32]
    ) -> TerminalSemanticRegion? {
        TerminalSemanticNavigationResolver.promptRegion(
            for: action,
            visibleStartRow: visibleStartRow,
            regions: prompts,
            maximumSearchSteps: 5,
            findOlder: { older[$0] ?? -1 },
            findNewer: { newer[$0] ?? -1 }
        )
    }

    private func output(
        at row: UInt32,
        regions: [TerminalSemanticRegion]
    ) -> TerminalSemanticRegion? {
        TerminalSemanticNavigationResolver.commandOutputRegion(
            visibleStartRow: row,
            regions: regions
        )
    }
}
