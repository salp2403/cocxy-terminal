// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Terminal paste delivery")
@MainActor
struct TerminalPasteDeliverySwiftTestingTests {
    @Test("replacement closes the active bracket before opening the next paste")
    func replacementClosesActiveBracket() async throws {
        let coordinator = TerminalPasteDeliveryCoordinator(timing: TerminalPasteDeliveryTiming(
            standardChunkMaxUTF8Bytes: 2,
            agentChunkMaxUTF8Bytes: 2,
            standardDelayNanoseconds: 500_000_000,
            agentDelayNanoseconds: 500_000_000
        ))
        let surfaceID = SurfaceID()
        var writes: [String] = []
        let configuration = TerminalPasteDeliveryConfiguration(
            usesBracketedPaste: true,
            agentPaced: false
        )
        let first = Task { @MainActor in
            await coordinator.deliver(
                "abcd",
                to: surfaceID,
                configuration: configuration,
                isAvailable: { true },
                sendText: { writes.append($0); return true }
            )
        }
        while writes.isEmpty { await Task.yield() }

        let second = await coordinator.deliver(
            "XY",
            to: surfaceID,
            configuration: configuration,
            isAvailable: { true },
            sendText: { writes.append($0); return true }
        )

        #expect(await first.value == false)
        #expect(second)
        #expect(writes == [
            TerminalPasteDelivery.bracketedPasteStart + "ab",
            TerminalPasteDelivery.bracketedPasteEnd,
            TerminalPasteDelivery.bracketedPasteStart + "XY",
            TerminalPasteDelivery.bracketedPasteEnd,
        ])
    }
}
