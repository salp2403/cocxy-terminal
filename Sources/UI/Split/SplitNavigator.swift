// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitNavigator.swift - Directional navigation algorithm for split trees.

import Foundation

// MARK: - Split Navigator

/// Provides directional navigation between leaf panes in a `SplitNode` tree.
///
/// ## Algorithm
///
/// Given a leaf ID and a direction, the algorithm:
/// 1. Finds the path from the root to the target leaf.
/// 2. Walks up the path looking for a split whose orientation matches
///    the navigation direction and where the leaf is on the correct
///    side (e.g., navigating right from a leaf in the `first` child
///    of a horizontal split).
/// 3. Descends into the opposite subtree to find the nearest leaf
///    on the edge closest to the origin (e.g., the leftmost leaf
///    when navigating right).
///
/// ## Complexity
///
/// O(d) where d is the depth of the tree (max 4 by default),
/// so effectively O(1) for all practical trees.
///
/// - SeeAlso: `NavigationDirection`
/// - SeeAlso: `SplitNode`
enum SplitNavigator {

    // MARK: - Find Neighbor

    /// Finds the leaf ID of the neighbor in the given direction.
    ///
    /// - Parameters:
    ///   - leafID: The leaf to navigate from.
    ///   - direction: The direction to navigate.
    ///   - root: The root of the split tree.
    /// - Returns: The leaf ID of the neighbor, or `nil` if there is no
    ///   neighbor in that direction (e.g., at the edge of the layout).
    static func findNeighbor(
        of leafID: UUID,
        direction: NavigationDirection,
        in root: SplitNode
    ) -> UUID? {
        // Build the path from root to the target leaf.
        var path: [PathEntry] = []
        guard buildPath(to: leafID, in: root, path: &path) else {
            // Leaf not found in tree.
            return nil
        }

        // Walk up the path looking for a split that allows navigation
        // in the requested direction.
        for i in stride(from: path.count - 1, through: 0, by: -1) {
            let entry = path[i]
            guard case .split(_, let splitDirection, let first, let second, _) = entry.node else {
                continue
            }

            // Check if this split's orientation matches the navigation direction.
            guard doesSplitMatchDirection(splitDirection, direction) else {
                continue
            }

            // Check if the leaf is on the correct side to navigate.
            let childSide = entry.childSide
            guard let targetSubtree = neighborSubtree(
                direction: direction,
                childSide: childSide,
                first: first,
                second: second
            ) else {
                continue
            }

            // Found a matching split. Descend into the target subtree
            // to find the nearest leaf on the correct edge.
            return edgeLeaf(in: targetSubtree, direction: direction)
        }

        // No neighbor found in the requested direction.
        return nil
    }

    // MARK: - Edge Leaf Finders

    /// Returns the leftmost leaf ID in the subtree.
    ///
    /// Always follows the `first` child at horizontal splits and
    /// the `first` child at vertical splits (top-left corner).
    static func leftmostLeaf(in node: SplitNode) -> UUID {
        switch node {
        case .leaf(let id, _):
            return id
        case .split(_, _, let first, _, _):
            // Both horizontal and vertical: leftmost is always in the first child.
            return leftmostLeaf(in: first)
        }
    }

    /// Returns the rightmost leaf ID in the subtree.
    ///
    /// Follows `second` at horizontal splits (right side) and
    /// `first` at vertical splits (same column, top row).
    static func rightmostLeaf(in node: SplitNode) -> UUID {
        switch node {
        case .leaf(let id, _):
            return id
        case .split(_, let direction, let first, let second, _):
            if direction == .horizontal {
                return rightmostLeaf(in: second)
            }
            return rightmostLeaf(in: first)
        }
    }

    /// Returns the topmost leaf ID in the subtree.
    ///
    /// Always follows the `first` child (top at vertical splits,
    /// same row at horizontal splits).
    static func topmostLeaf(in node: SplitNode) -> UUID {
        switch node {
        case .leaf(let id, _):
            return id
        case .split(_, _, let first, _, _):
            // Both vertical and horizontal: topmost is always in the first child.
            return topmostLeaf(in: first)
        }
    }

    /// Returns the bottommost leaf ID in the subtree.
    ///
    /// Follows `second` at vertical splits (bottom) and
    /// `first` at horizontal splits (same row, left column).
    static func bottommostLeaf(in node: SplitNode) -> UUID {
        switch node {
        case .leaf(let id, _):
            return id
        case .split(_, let direction, let first, let second, _):
            if direction == .vertical {
                return bottommostLeaf(in: second)
            }
            return bottommostLeaf(in: first)
        }
    }

    // MARK: - Private Helpers

    /// Represents an entry in the path from root to a leaf.
    private struct PathEntry {
        /// The split node at this level.
        let node: SplitNode
        /// Which child of this split the path continues through.
        let childSide: ChildSide
    }

    /// Which child of a split a path passes through.
    private enum ChildSide {
        case first
        case second
        case root // The leaf itself
    }

    /// Builds the path from the root to the target leaf, recording
    /// each split along the way and which child was followed.
    ///
    /// - Returns: `true` if the leaf was found.
    private static func buildPath(
        to leafID: UUID,
        in node: SplitNode,
        path: inout [PathEntry]
    ) -> Bool {
        switch node {
        case .leaf(let id, _):
            return id == leafID

        case .split(_, _, let first, let second, _):
            // Try first child.
            path.append(PathEntry(node: node, childSide: .first))
            if buildPath(to: leafID, in: first, path: &path) {
                return true
            }
            path.removeLast()

            // Try second child.
            path.append(PathEntry(node: node, childSide: .second))
            if buildPath(to: leafID, in: second, path: &path) {
                return true
            }
            path.removeLast()

            return false
        }
    }

    /// Checks whether a split's orientation matches the navigation direction.
    ///
    /// - Horizontal splits handle left/right navigation.
    /// - Vertical splits handle up/down navigation.
    private static func doesSplitMatchDirection(
        _ splitDirection: SplitDirection,
        _ navDirection: NavigationDirection
    ) -> Bool {
        switch (splitDirection, navDirection) {
        case (.horizontal, .left), (.horizontal, .right):
            return true
        case (.vertical, .up), (.vertical, .down):
            return true
        default:
            return false
        }
    }

    /// Determines the target subtree for navigation, or nil if the
    /// current child side doesn't allow navigation in this direction.
    ///
    /// For example, navigating right from a leaf in `first` returns `second`.
    /// Navigating right from a leaf in `second` returns `nil` (we need
    /// to go further up the tree).
    private static func neighborSubtree(
        direction: NavigationDirection,
        childSide: ChildSide,
        first: SplitNode,
        second: SplitNode
    ) -> SplitNode? {
        switch (direction, childSide) {
        case (.right, .first), (.down, .first):
            return second
        case (.left, .second), (.up, .second):
            return first
        default:
            return nil
        }
    }

    /// Finds the leaf at the edge of a subtree closest to the navigation origin.
    ///
    /// When navigating right, we want the leftmost leaf of the target subtree.
    /// When navigating left, we want the rightmost leaf.
    /// When navigating down, we want the topmost leaf.
    /// When navigating up, we want the bottommost leaf.
    private static func edgeLeaf(
        in node: SplitNode,
        direction: NavigationDirection
    ) -> UUID {
        switch direction {
        case .right:
            return leftmostLeaf(in: node)
        case .left:
            return rightmostLeaf(in: node)
        case .down:
            return topmostLeaf(in: node)
        case .up:
            return bottommostLeaf(in: node)
        }
    }
}
