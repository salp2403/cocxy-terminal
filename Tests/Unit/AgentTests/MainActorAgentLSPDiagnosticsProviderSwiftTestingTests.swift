// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorAgentLSPDiagnosticsProviderSwiftTestingTests.swift - UI LSP diagnostics bridge.

import Testing
@testable import CocxyTerminal

@Suite("MainActorAgentLSPDiagnosticsProvider")
@MainActor
struct MainActorAgentLSPDiagnosticsProviderSwiftTestingTests {

    @Test("provider synchronously hops to main actor and returns diagnostics")
    func providerReturnsMainActorDiagnostics() async throws {
        let provider = MainActorAgentLSPDiagnosticsProvider { limit in
            [
                AgentLSPDiagnostic(
                    path: "Sources/App.swift",
                    line: limit,
                    column: 5,
                    severity: "warning",
                    message: "Unused value",
                    source: "sourcekit"
                ),
            ]
        }

        let diagnostics = await Task.detached {
            provider.currentDiagnostics(limit: 9)
        }.value

        #expect(diagnostics == [
            AgentLSPDiagnostic(
                path: "Sources/App.swift",
                line: 9,
                column: 5,
                severity: "warning",
                message: "Unused value",
                source: "sourcekit"
            ),
        ])
    }
}
