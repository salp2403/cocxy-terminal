// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonHostPasteSwiftTestingTests.swift - Daemon host paste delivery coverage.

import CocxyShared
import Testing
@testable import CocxyTerminal

@MainActor
extension CocxyCoreHostWiringTests {
    @Test("daemon host paste preserves bracketed mode and shared normalization")
    func daemonHostPasteUsesSharedDelivery() async throws {
        let engine = MockTerminalEngine()
        let view = PTYDaemonHostView(viewModel: TerminalViewModel(engine: engine))
        let surfaceID = SurfaceID()
        view.configureSurfaceIfNeeded(bridge: engine, surfaceID: surfaceID)
        view.apply(PTYDaemonSurfaceFrame(
            surfaceID: surfaceID.rawValue.uuidString,
            revision: 1,
            timestamp: 1,
            columns: 80,
            rows: 24,
            cells: [],
            cursor: PTYDaemonCursor(row: 0, column: 0),
            bracketedPasteMode: true
        ))

        view.deliverTerminalPaste("alpha\r\nbeta\u{0000}")

        try await waitUntil { engine.sentTexts.count == 2 }
        #expect(engine.sentTexts.map(\.surface) == [surfaceID, surfaceID])
        #expect(engine.sentTexts.map(\.text) == [
            TerminalPasteDelivery.bracketedPasteStart + "alpha\nbeta",
            TerminalPasteDelivery.bracketedPasteEnd,
        ])
    }
}
