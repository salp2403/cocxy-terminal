// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorAgentLSPDiagnosticsProvider.swift - Bridges Agent LSP context to UI state.

import Foundation

final class MainActorAgentLSPDiagnosticsProvider: AgentLSPDiagnosticsProviding, @unchecked Sendable {
    private let diagnosticsProvider: @MainActor @Sendable (Int) -> [AgentLSPDiagnostic]

    init(diagnosticsProvider: @escaping @MainActor @Sendable (Int) -> [AgentLSPDiagnostic]) {
        self.diagnosticsProvider = diagnosticsProvider
    }

    func currentDiagnostics(limit: Int) -> [AgentLSPDiagnostic] {
        syncOnMainActor {
            self.diagnosticsProvider(limit)
        }
    }
}
