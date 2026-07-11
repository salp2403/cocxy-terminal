// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainActorAgentTerminalOutputProvider.swift - Bridges Agent terminal context to UI state.

import Foundation

final class MainActorAgentTerminalOutputProvider: AgentTerminalOutputProviding, @unchecked Sendable {
    private let selectionProvider: @MainActor @Sendable (Int) -> AgentTerminalOutputSelection
    private let snapshotProvider: @MainActor @Sendable (
        AgentTerminalOutputSelection
    ) -> AgentTerminalOutputSnapshot

    init(
        selectionProvider: @escaping @MainActor @Sendable (Int) -> AgentTerminalOutputSelection,
        snapshotProvider: @escaping @MainActor @Sendable (
            AgentTerminalOutputSelection
        ) -> AgentTerminalOutputSnapshot
    ) {
        self.selectionProvider = selectionProvider
        self.snapshotProvider = snapshotProvider
    }

    func latestCommandBlockSelection(limit: Int) -> AgentTerminalOutputSelection {
        syncOnMainActor {
            self.selectionProvider(limit)
        }
    }

    func captureCommandBlockOutputs(
        selection: AgentTerminalOutputSelection
    ) -> AgentTerminalOutputSnapshot {
        syncOnMainActor {
            self.snapshotProvider(selection)
        }
    }
}
