// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorAgentTerminalOutputProvider.swift - Bridges Agent terminal context to UI state.

import Foundation

final class MainActorAgentTerminalOutputProvider: AgentTerminalOutputProviding, @unchecked Sendable {
    private let outputProvider: @MainActor @Sendable (Int) -> String

    init(outputProvider: @escaping @MainActor @Sendable (Int) -> String) {
        self.outputProvider = outputProvider
    }

    func latestCommandBlockOutputs(limit: Int) -> String {
        syncOnMainActor {
            self.outputProvider(limit)
        }
    }
}
