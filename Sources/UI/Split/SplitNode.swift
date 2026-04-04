// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitNode.swift - Binary tree data structure for split pane layouts.

import Foundation

// MARK: - Split Node

/// Recursive binary tree representing the layout of split panes within a tab.
///
/// Each node is either a **leaf** (a single terminal pane identified by its
/// `terminalID`) or a **split** (two children separated by a divider).
///
/// ```
/// SplitNode
///   |-- .leaf(id, terminalID)
///   `-- .split(id, direction, first, second, ratio)
/// ```
///
/// The `ratio` (clamped to 0.1...0.9) determines how space is divided between
/// the two children. A ratio of 0.5 means equal split.
///
/// ## Depth limit
///
/// To prevent an unusably small grid, the tree enforces a maximum depth of 4
/// (which allows up to 16 leaves, though 8 is the practical maximum for
/// usability). The `splitLeaf` method refuses to split beyond this limit.
///
/// ## Identity
///
/// Both leaves and splits carry a `UUID` for identity. Leaves also carry a
/// `terminalID` which maps to the `SurfaceID` of the terminal they host.
///
/// - SeeAlso: `SplitContainer` for the NSView hierarchy.
/// - SeeAlso: `SplitNodeState` in SessionManaging for the serializable version.
/// - SeeAlso: `SplitManager` for the state management service.
indirect enum SplitNode: Identifiable, Equatable, Sendable {

    /// The default maximum depth allowed for the split tree.
    static let defaultMaxDepth = 4

    /// Minimum allowed ratio for a split.
    static let minimumRatio: CGFloat = 0.1

    /// Maximum allowed ratio for a split.
    static let maximumRatio: CGFloat = 0.9

    /// A single terminal pane.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this leaf node.
    ///   - terminalID: Identifier of the terminal surface hosted by this leaf.
    case leaf(id: UUID, terminalID: UUID)

    /// A split containing two child nodes separated by a divider.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for this split node.
    ///   - direction: Whether the split is horizontal (side by side) or vertical (stacked).
    ///   - first: The first child (left or top).
    ///   - second: The second child (right or bottom).
    ///   - ratio: How space is divided (0.1...0.9). Applied to the first child.
    case split(id: UUID, direction: SplitDirection, first: SplitNode, second: SplitNode, ratio: CGFloat)

    // MARK: - Identifiable

    /// The unique identifier for this node.
    var id: UUID {
        switch self {
        case .leaf(let id, _):
            return id
        case .split(let id, _, _, _, _):
            return id
        }
    }

    // MARK: - Computed Properties

    /// The number of terminal leaves in this subtree.
    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(_, _, let first, let second, _):
            return first.leafCount + second.leafCount
        }
    }

    /// The depth of this subtree.
    ///
    /// A leaf has depth 0. A split has depth 1 + max(first.depth, second.depth).
    var depth: Int {
        switch self {
        case .leaf:
            return 0
        case .split(_, _, let first, let second, _):
            return 1 + max(first.depth, second.depth)
        }
    }

    // MARK: - Tree Operations

    /// Splits a leaf node into a split with two children.
    ///
    /// The original leaf becomes the first child, and a new leaf with
    /// `newTerminalID` becomes the second child. The split ratio is 0.5.
    ///
    /// - Parameters:
    ///   - leafID: The ID of the leaf to split.
    ///   - direction: The direction of the new split.
    ///   - newTerminalID: The terminal ID for the new leaf.
    ///   - maxDepth: Maximum allowed depth for the tree. Defaults to `defaultMaxDepth`.
    /// - Returns: The updated tree, or `nil` if the leaf was not found or the
    ///   depth limit would be exceeded.
    func splitLeaf(
        leafID: UUID,
        direction: SplitDirection,
        newTerminalID: UUID,
        maxDepth: Int = SplitNode.defaultMaxDepth
    ) -> SplitNode? {
        return splitLeafInternal(
            leafID: leafID,
            direction: direction,
            newTerminalID: newTerminalID,
            maxDepth: maxDepth,
            currentDepth: 0
        )
    }

    /// Internal recursive implementation of `splitLeaf`.
    private func splitLeafInternal(
        leafID: UUID,
        direction: SplitDirection,
        newTerminalID: UUID,
        maxDepth: Int,
        currentDepth: Int
    ) -> SplitNode? {
        switch self {
        case .leaf(let id, let terminalID):
            guard id == leafID else { return nil }

            // Check depth limit: the new split would add one level.
            guard currentDepth < maxDepth else { return nil }

            let newLeaf = SplitNode.leaf(id: UUID(), terminalID: newTerminalID)
            return .split(
                id: UUID(),
                direction: direction,
                first: .leaf(id: id, terminalID: terminalID),
                second: newLeaf,
                ratio: 0.5
            )

        case .split(let id, let dir, let first, let second, let ratio):
            // Try to split in the first subtree.
            if let updatedFirst = first.splitLeafInternal(
                leafID: leafID,
                direction: direction,
                newTerminalID: newTerminalID,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1
            ) {
                return .split(id: id, direction: dir, first: updatedFirst, second: second, ratio: ratio)
            }

            // Try to split in the second subtree.
            if let updatedSecond = second.splitLeafInternal(
                leafID: leafID,
                direction: direction,
                newTerminalID: newTerminalID,
                maxDepth: maxDepth,
                currentDepth: currentDepth + 1
            ) {
                return .split(id: id, direction: dir, first: first, second: updatedSecond, ratio: ratio)
            }

            return nil
        }
    }

    /// Removes a leaf from the tree and promotes its sibling.
    ///
    /// When a leaf is removed from a split, its sibling replaces the split node
    /// (it "moves up" one level). If the leaf is the only node in the tree,
    /// returns `nil`.
    ///
    /// - Parameter leafID: The ID of the leaf to remove.
    /// - Returns: The updated tree, `nil` if this is the last leaf, or
    ///   the tree unchanged if the leaf was not found.
    func removeLeaf(leafID: UUID) -> SplitNode? {
        switch self {
        case .leaf(let id, _):
            return id == leafID ? nil : self

        case .split(let id, let direction, let first, let second, let ratio):
            // If a direct child is the target leaf, promote its sibling.
            if let promoted = promoteSiblingIfChildMatches(
                first: first, second: second, targetLeafID: leafID
            ) {
                return promoted
            }

            // Recurse into subtrees.
            if let updatedFirst = first.removeLeafFromSubtree(leafID: leafID) {
                return .split(id: id, direction: direction, first: updatedFirst, second: second, ratio: ratio)
            }
            if let updatedSecond = second.removeLeafFromSubtree(leafID: leafID) {
                return .split(id: id, direction: direction, first: first, second: updatedSecond, ratio: ratio)
            }

            // Leaf not found in either subtree: return self unchanged.
            return self
        }
    }

    /// If one of the two children is a leaf matching `targetLeafID`,
    /// returns the other child (promoted). Otherwise returns `nil`.
    private func promoteSiblingIfChildMatches(
        first: SplitNode,
        second: SplitNode,
        targetLeafID: UUID
    ) -> SplitNode? {
        if case .leaf(let firstID, _) = first, firstID == targetLeafID {
            return second
        }
        if case .leaf(let secondID, _) = second, secondID == targetLeafID {
            return first
        }
        return nil
    }

    /// Recursively removes a leaf from a subtree.
    ///
    /// Returns `nil` when the leaf is NOT found in this subtree (signaling
    /// the caller to try the other subtree). When found and removed, returns
    /// the updated subtree.
    private func removeLeafFromSubtree(leafID: UUID) -> SplitNode? {
        switch self {
        case .leaf:
            return nil

        case .split(let id, let direction, let first, let second, let ratio):
            if let promoted = promoteSiblingIfChildMatches(
                first: first, second: second, targetLeafID: leafID
            ) {
                return promoted
            }

            if let updatedFirst = first.removeLeafFromSubtree(leafID: leafID) {
                return .split(id: id, direction: direction, first: updatedFirst, second: second, ratio: ratio)
            }
            if let updatedSecond = second.removeLeafFromSubtree(leafID: leafID) {
                return .split(id: id, direction: direction, first: first, second: updatedSecond, ratio: ratio)
            }

            return nil
        }
    }

    /// Finds a leaf node by its ID.
    ///
    /// - Parameter id: The ID of the leaf to find.
    /// - Returns: The leaf node, or `nil` if not found.
    func findLeaf(id: UUID) -> SplitNode? {
        switch self {
        case .leaf(let leafID, _):
            return leafID == id ? self : nil
        case .split(_, _, let first, let second, _):
            return first.findLeaf(id: id) ?? second.findLeaf(id: id)
        }
    }

    /// Returns all leaf identifiers in depth-first (left-to-right) order.
    ///
    /// Each entry contains both the leaf's node ID and its terminal ID.
    ///
    /// - Returns: An array of `(leafID, terminalID)` tuples in DFS order.
    func allLeafIDs() -> [LeafInfo] {
        var result: [LeafInfo] = []
        collectLeafIDs(into: &result)
        return result
    }

    /// Internal recursive helper for `allLeafIDs`.
    private func collectLeafIDs(into result: inout [LeafInfo]) {
        switch self {
        case .leaf(let id, let terminalID):
            result.append(LeafInfo(leafID: id, terminalID: terminalID))
        case .split(_, _, let first, let second, _):
            first.collectLeafIDs(into: &result)
            second.collectLeafIDs(into: &result)
        }
    }

    /// Updates the ratio of a specific split node.
    ///
    /// The new ratio is clamped to `minimumRatio...maximumRatio`.
    ///
    /// - Parameters:
    ///   - splitID: The ID of the split node to update.
    ///   - ratio: The new ratio value.
    /// - Returns: The updated tree (unchanged if the split was not found).
    func updateRatio(splitID: UUID, ratio: CGFloat) -> SplitNode {
        switch self {
        case .leaf:
            return self

        case .split(let id, let direction, let first, let second, let currentRatio):
            if id == splitID {
                let clampedRatio = Self.clampRatio(ratio)
                return .split(id: id, direction: direction, first: first, second: second, ratio: clampedRatio)
            }

            let updatedFirst = first.updateRatio(splitID: splitID, ratio: ratio)
            let updatedSecond = second.updateRatio(splitID: splitID, ratio: ratio)
            return .split(id: id, direction: direction, first: updatedFirst, second: updatedSecond, ratio: currentRatio)
        }
    }

    // MARK: - Leaf Swapping

    /// Returns a new tree with two leaves' terminal IDs swapped.
    ///
    /// Finds the leaves at the given DFS indices and exchanges their
    /// `terminalID` values. The leaf node IDs remain the same.
    ///
    /// - Parameters:
    ///   - indexA: DFS index of the first leaf.
    ///   - indexB: DFS index of the second leaf.
    /// - Returns: The updated tree, or `self` unchanged if indices are invalid.
    func swappingLeaves(at indexA: Int, with indexB: Int) -> SplitNode {
        let leaves = allLeafIDs()
        guard indexA >= 0, indexA < leaves.count,
              indexB >= 0, indexB < leaves.count,
              indexA != indexB else {
            return self
        }

        let leafA = leaves[indexA]
        let leafB = leaves[indexB]

        // Replace leafA's terminalID with leafB's, and vice versa.
        let step1 = replaceTerminalID(leafID: leafA.leafID, newTerminalID: leafB.terminalID)
        let step2 = step1.replaceTerminalID(leafID: leafB.leafID, newTerminalID: leafA.terminalID)
        return step2
    }

    /// Returns a new tree with a specific leaf's terminal ID replaced.
    private func replaceTerminalID(leafID: UUID, newTerminalID: UUID) -> SplitNode {
        switch self {
        case .leaf(let id, _) where id == leafID:
            return .leaf(id: id, terminalID: newTerminalID)
        case .leaf:
            return self
        case .split(let id, let direction, let first, let second, let ratio):
            return .split(
                id: id,
                direction: direction,
                first: first.replaceTerminalID(leafID: leafID, newTerminalID: newTerminalID),
                second: second.replaceTerminalID(leafID: leafID, newTerminalID: newTerminalID),
                ratio: ratio
            )
        }
    }

    // MARK: - Ratio Clamping

    /// Clamps a ratio to the valid range.
    static func clampRatio(_ ratio: CGFloat) -> CGFloat {
        return min(maximumRatio, max(minimumRatio, ratio))
    }
}

// MARK: - Leaf Info

/// Information about a leaf in the split tree, used by `allLeafIDs()`.
struct LeafInfo: Equatable {
    /// The leaf node's own identifier.
    let leafID: UUID
    /// The terminal surface identifier hosted by this leaf.
    let terminalID: UUID
}

// MARK: - SplitNode Initializer with Ratio Clamping

extension SplitNode {
    /// Creates a split node with automatic ratio clamping.
    ///
    /// This is the preferred way to create split nodes, as it ensures
    /// the ratio is always within the valid range (0.1...0.9).
    static func clampedSplit(
        id: UUID,
        direction: SplitDirection,
        first: SplitNode,
        second: SplitNode,
        ratio: CGFloat
    ) -> SplitNode {
        return .split(
            id: id,
            direction: direction,
            first: first,
            second: second,
            ratio: clampRatio(ratio)
        )
    }
}
