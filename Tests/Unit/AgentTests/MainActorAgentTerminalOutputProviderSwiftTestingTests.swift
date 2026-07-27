// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorAgentTerminalOutputProviderSwiftTestingTests.swift - UI terminal output bridge.

import Testing
@testable import CocxyTerminal

@Suite("MainActorAgentTerminalOutputProvider")
@MainActor
struct MainActorAgentTerminalOutputProviderSwiftTestingTests {

    @Test("provider synchronously hops to main actor and returns clean output")
    func providerReturnsMainActorOutput() async throws {
        var capturedSelections: [AgentTerminalOutputSelection] = []
        let provider = MainActorAgentTerminalOutputProvider(
            selectionProvider: { limit in
                AgentTerminalOutputSelection(
                    source: .focusedSplit,
                    surfaceID: "surface-1",
                    blockLimit: limit,
                    blockReferences: [
                        TerminalCommandBlockReference(id: 41, endTimeNs: 410),
                    ]
                )
            },
            snapshotProvider: { selection in
                capturedSelections.append(selection)
                return AgentTerminalOutputSnapshot(
                    source: selection.source,
                    surfaceID: selection.surfaceID,
                    blockLimit: selection.blockLimit,
                    blockCount: selection.blockCount,
                    blockReferences: selection.blockReferences,
                    output: "limit=\(selection.blockLimit)\nrecent output"
                )
            }
        )

        let selection = await Task.detached {
            provider.latestCommandBlockSelection(limit: 100)
        }.value

        #expect(selection.blockLimit == AgentTerminalOutputSnapshot.maximumBlockLimit)
        #expect(selection.blockIDs == [41])
        #expect(capturedSelections.isEmpty)

        let snapshot = await Task.detached {
            provider.captureCommandBlockOutputs(selection: selection)
        }.value

        #expect(snapshot.output == "limit=64\nrecent output")
        #expect(snapshot.source == .focusedSplit)
        #expect(snapshot.surfaceID == "surface-1")
        #expect(snapshot.blockLimit == AgentTerminalOutputSnapshot.maximumBlockLimit)
        #expect(snapshot.blockCount == 1)
        #expect(snapshot.blockIDs == [41])
        #expect(capturedSelections == [selection])
    }
}
