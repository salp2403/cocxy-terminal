// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitNodeStateConversion.swift - Conversions between SplitNode (runtime) and SplitNodeState (serializable).

import Foundation

// MARK: - SplitNode -> SplitNodeState

extension SplitNode {

    /// Converts the runtime split tree to a serializable `SplitNodeState`.
    ///
    /// Terminal IDs are resolved to working directories using the provided
    /// closure. If a terminal ID cannot be resolved, the home directory is
    /// used as a fallback.
    ///
    /// - Parameter workingDirectoryResolver: Closure that maps a terminal ID
    ///   to its current working directory. Called for each leaf node.
    /// - Returns: A `SplitNodeState` mirroring this tree's structure.
    func toSessionState(
        workingDirectoryResolver: (UUID) -> URL
    ) -> SplitNodeState {
        switch self {
        case .leaf(_, let terminalID):
            let workingDirectory = workingDirectoryResolver(terminalID)
            return .leaf(workingDirectory: workingDirectory, command: nil)

        case .split(_, let direction, let first, let second, let ratio):
            return .split(
                direction: direction,
                first: first.toSessionState(workingDirectoryResolver: workingDirectoryResolver),
                second: second.toSessionState(workingDirectoryResolver: workingDirectoryResolver),
                ratio: Double(ratio)
            )
        }
    }
}

// MARK: - SplitNodeState -> SplitNode

extension SplitNodeState {

    /// Converts a serializable `SplitNodeState` back to a runtime `SplitNode`.
    ///
    /// New UUIDs are generated for both leaf IDs and terminal IDs, since
    /// the original identifiers are not persisted in the session state.
    /// The structure (directions, ratios, tree shape) is preserved exactly.
    ///
    /// - Returns: A `SplitNode` with fresh identifiers but identical structure.
    func toSplitNode() -> SplitNode {
        switch self {
        case .leaf:
            return .leaf(id: UUID(), terminalID: UUID())

        case .split(let direction, let first, let second, let ratio):
            return .split(
                id: UUID(),
                direction: direction,
                first: first.toSplitNode(),
                second: second.toSplitNode(),
                ratio: CGFloat(ratio)
            )
        }
    }
}
