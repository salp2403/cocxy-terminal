// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import CocxyCoreKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Surface agent semantic verdict cache", .serialized)
@MainActor
struct SurfaceAgentSemanticVerdictCacheSwiftTestingTests {
    @Test("semantic bridge reads are reused until the short TTL expires")
    func semanticVerdictExpiresDeterministically() throws {
        let bridge = try makeBridge()
        let controller = MainWindowController(bridge: bridge)
        let view = CocxyCoreView(viewModel: TerminalViewModel(engine: bridge))
        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: "/bin/cat"
        )
        defer { bridge.destroySurface(surfaceID) }

        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        controller.surfaceAgentSemanticVerdictNow = { now }

        #expect(controller.surfaceLooksLikeActiveAgent(surfaceID) == false)
        #expect(controller.surfaceAgentSemanticVerdictCache[surfaceID]?.verdict == false)

        let state = try #require(bridge.surfaceState(for: surfaceID))
        feedSemanticSequence("\u{1B}]133;A\u{07}", into: state.terminal)
        feedSemanticSequence("\u{1B}]133;B\u{07}", into: state.terminal)
        feedSemanticSequence("\u{1B}]133;C;claude\u{07}", into: state.terminal)

        #expect(controller.surfaceLooksLikeActiveAgent(surfaceID) == false)

        now.addTimeInterval(SurfaceAgentSemanticVerdictCacheEntry.lifetime + 0.001)

        #expect(controller.surfaceLooksLikeActiveAgent(surfaceID) == true)
        #expect(controller.surfaceAgentSemanticVerdictCache[surfaceID]?.verdict == true)

        controller.clearSurfaceTracking(for: surfaceID)
        #expect(controller.surfaceAgentSemanticVerdictCache[surfaceID] == nil)
    }

    @Test("authoritative per-surface state bypasses a cached negative verdict")
    func perSurfaceStateBypassesCachedNegative() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let store = AgentStatePerSurfaceStore()
        let surfaceID = SurfaceID()
        controller.injectedPerSurfaceStore = store

        #expect(controller.surfaceLooksLikeActiveAgent(surfaceID) == false)
        #expect(controller.surfaceAgentSemanticVerdictCache[surfaceID]?.verdict == false)

        store.update(surfaceID: surfaceID) { state in
            state.agentState = .working
        }

        #expect(controller.surfaceLooksLikeActiveAgent(surfaceID) == true)
    }
}

private func feedSemanticSequence(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}
