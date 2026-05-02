// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorAgentTerminalOutputProviderSwiftTestingTests.swift - UI terminal output bridge.

import Testing
@testable import CocxyTerminal

@Suite("MainActorAgentTerminalOutputProvider")
@MainActor
struct MainActorAgentTerminalOutputProviderSwiftTestingTests {

    @Test("provider synchronously hops to main actor and returns clean output")
    func providerReturnsMainActorOutput() async throws {
        let provider = MainActorAgentTerminalOutputProvider { limit in
            "limit=\(limit)\nrecent output"
        }

        let output = await Task.detached {
            provider.latestCommandBlockOutputs(limit: 7)
        }.value

        #expect(output == "limit=7\nrecent output")
    }
}
