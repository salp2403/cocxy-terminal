// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitManager.swift - State management for split panes within a tab.

import Foundation
import Combine

// MARK: - Split Manager

/// Manages the state of split panes for a single tab.
///
/// Each tab has its own `SplitManager` instance that tracks:
/// - The root `SplitNode` tree (the layout of all panes).
/// - Which leaf currently has keyboard focus.
///
/// The manager exposes `@Published` properties so the UI layer can
/// observe changes reactively via Combine.
///
/// ## Operations
///
/// - `splitFocused(direction:)` — Divide the focused pane into two.
/// - `closeFocused()` — Close the focused pane and promote its sibling.
/// - `navigateToNextLeaf()` / `navigateToPreviousLeaf()` — Cycle focus.
/// - `focusLeaf(id:)` — Set focus to a specific leaf.
/// - `setRatio(splitID:ratio:)` — Adjust the split ratio of a divider.
///
/// - SeeAlso: `SplitNode` for the tree data structure.
/// - SeeAlso: `SplitContainer` for the NSView hierarchy.
@MainActor
final class SplitManager: ObservableObject {

    struct ResizeTarget: Equatable {
        let splitID: UUID
        let ratioDeltaSign: CGFloat
    }

    private enum PathChildSide {
        case first
        case second
    }

    private struct PathEntry {
        let splitID: UUID
        let direction: SplitDirection
        let childSide: PathChildSide
    }

    // MARK: - Published State

    /// The root of the split tree. A single leaf when no splits are active.
    @Published var rootNode: SplitNode

    /// The ID of the leaf that currently has keyboard focus.
    @Published var focusedLeafID: UUID?

    // MARK: - Panel Type Tracking

    /// Maps each leaf's content UUID to its panel type.
    /// Leaves not present in this map default to `.terminal`.
    private(set) var panelTypes: [UUID: PanelInfo] = [:]

    /// Returns the panel info for a given content ID.
    /// Defaults to `.terminal` if not explicitly registered.
    func panelInfo(for contentID: UUID) -> PanelInfo {
        panelTypes[contentID] ?? .terminal
    }

    /// Returns the panel type for a given content ID.
    func panelType(for contentID: UUID) -> PanelType {
        panelInfo(for: contentID).type
    }

    // MARK: - Panel Titles

    /// Custom user-defined titles for individual panels, keyed by content UUID.
    /// Panels not present in this map use auto-generated names.
    private(set) var panelTitles: [UUID: String] = [:]

    /// Returns the custom title for a panel, or nil if none has been set.
    func panelTitle(for contentID: UUID) -> String? {
        panelTitles[contentID]
    }

    /// Sets or clears a custom title for a panel.
    ///
    /// - Parameters:
    ///   - contentID: The content UUID of the panel.
    ///   - title: The custom title, or nil/empty to clear.
    func setPanelTitle(for contentID: UUID, title: String?) {
        if let title, !title.isEmpty {
            panelTitles[contentID] = title
        } else {
            panelTitles.removeValue(forKey: contentID)
        }
    }

    // MARK: - Initialization

    /// Creates a SplitManager with an initial single-leaf tree.
    ///
    /// - Parameter initialTerminalID: The terminal ID for the first leaf.
    ///   Defaults to a new UUID.
    init(initialTerminalID: UUID = UUID()) {
        let leafID = UUID()
        self.rootNode = .leaf(id: leafID, terminalID: initialTerminalID)
        self.focusedLeafID = leafID
    }

    /// Restores the manager from a pre-built split tree.
    ///
    /// Used during session restore and cross-window state handoff so the
    /// logical split model matches the reconstructed view hierarchy.
    func restoreLayout(
        rootNode: SplitNode,
        focusedLeafID: UUID? = nil,
        panelTypes: [UUID: PanelInfo] = [:],
        panelTitles: [UUID: String] = [:]
    ) {
        self.rootNode = rootNode
        self.focusedLeafID = focusedLeafID ?? rootNode.allLeafIDs().first?.leafID
        self.panelTypes = panelTypes
        self.panelTitles = panelTitles
        self.savedZoomRatios.removeAll()
        self.isZoomed = false
    }

    // MARK: - Split Operations

    /// Splits the currently focused leaf in the given direction.
    ///
    /// The focused leaf becomes the first child of a new split, and a
    /// new leaf (with a fresh terminal ID) becomes the second child.
    /// Focus moves to the new leaf.
    ///
    /// - Parameter direction: Whether to split horizontally or vertically.
    /// Maximum number of panes allowed per tab.
    ///
    /// Set to 4 by default (2 levels of split). This prevents the UI
    /// from becoming unusably small. Override in tests if needed.
    static let maxPaneCount = 4

    /// - Returns: The terminal ID of the newly created pane, or `nil` if
    ///   the split could not be performed.
    @discardableResult
    func splitFocused(direction: SplitDirection) -> UUID? {
        return splitFocusedWithPanel(direction: direction, panel: .terminal)
    }

    /// Splits the focused leaf and assigns a panel type to the new pane.
    ///
    /// - Parameters:
    ///   - direction: Whether to split horizontally or vertically.
    ///   - panel: The panel info for the new pane (terminal, browser, markdown).
    /// - Returns: The content ID of the newly created pane, or `nil` if the
    ///   split could not be performed (max pane count reached, no focus, etc.).
    @discardableResult
    func splitFocusedWithPanel(direction: SplitDirection, panel: PanelInfo) -> UUID? {
        // Enforce maximum pane count.
        guard rootNode.leafCount < Self.maxPaneCount else {
            return nil
        }

        guard let currentFocusedID = focusedLeafID else {
            return nil
        }

        let newContentID = UUID()

        guard let updatedTree = rootNode.splitLeaf(
            leafID: currentFocusedID,
            direction: direction,
            newTerminalID: newContentID
        ) else {
            return nil
        }

        rootNode = updatedTree

        // Register the panel type for the new pane.
        if panel.type != .terminal {
            panelTypes[newContentID] = panel
        }

        // Find the new leaf and focus it.
        let allLeaves = rootNode.allLeafIDs()
        if let newLeaf = allLeaves.first(where: { $0.terminalID == newContentID }) {
            focusedLeafID = newLeaf.leafID
        }

        return newContentID
    }

    /// Appends a panel at the rightmost position of the split tree.
    ///
    /// Unlike `splitFocusedWithPanel`, this method always places the new panel
    /// at the END of the tree, regardless of which leaf currently has focus.
    /// By default the original focus is restored so the user's workflow is not
    /// disrupted. When `focusNewPanel` is true, focus moves to the newly
    /// created panel instead (useful for browser/markdown panels that the user
    /// wants to interact with immediately).
    ///
    /// - Parameters:
    ///   - panel: The panel info for the new pane.
    ///   - focusNewPanel: When true, the new panel receives focus instead of
    ///     restoring the previous focus. Defaults to false.
    /// - Returns: The content ID of the newly created pane, or `nil` if the
    ///   tree is at max pane count or empty.
    @discardableResult
    func appendPanel(panel: PanelInfo, focusNewPanel: Bool = false) -> UUID? {
        guard rootNode.leafCount < Self.maxPaneCount else { return nil }

        let leaves = rootNode.allLeafIDs()
        guard let lastLeaf = leaves.last else { return nil }

        // Save focus so it can be restored when focusNewPanel is false.
        let savedFocus = focusedLeafID
        focusedLeafID = lastLeaf.leafID

        let result = splitFocusedWithPanel(direction: .horizontal, panel: panel)

        if !focusNewPanel {
            focusedLeafID = savedFocus
        }
        // When focusNewPanel is true, splitFocusedWithPanel already set
        // focusedLeafID to the new leaf — no restoration needed.
        return result
    }

    /// Closes the currently focused leaf.
    ///
    /// If only one leaf remains, this is a no-op. Otherwise, the focused
    /// leaf is removed and its sibling is promoted. Focus moves to the
    /// first remaining leaf.
    func closeFocused() {
        guard let currentFocusedID = focusedLeafID else { return }

        // Cannot close the last leaf.
        guard rootNode.leafCount > 1 else { return }

        let leafOrderBeforeClose = rootNode.allLeafIDs()
        let closingIndex = leafOrderBeforeClose.firstIndex(where: { $0.leafID == currentFocusedID })

        // Find the content ID of the leaf being closed for cleanup.
        let closingLeaf = rootNode.findLeaf(id: currentFocusedID)
        let closingContentID: UUID?
        if case .leaf(_, let contentID) = closingLeaf {
            closingContentID = contentID
        } else {
            closingContentID = nil
        }

        guard let updatedTree = rootNode.removeLeaf(leafID: currentFocusedID) else {
            return
        }

        rootNode = updatedTree

        // Clean up panel type and title tracking for the closed pane.
        if let contentID = closingContentID {
            panelTypes.removeValue(forKey: contentID)
            panelTitles.removeValue(forKey: contentID)
        }

        // Keep focus near the pane that was closed so navigation feels local.
        let remainingLeaves = rootNode.allLeafIDs()
        guard !remainingLeaves.isEmpty else {
            focusedLeafID = nil
            return
        }

        if let closingIndex {
            let targetIndex = min(closingIndex, remainingLeaves.count - 1)
            focusedLeafID = remainingLeaves[targetIndex].leafID
        } else {
            focusedLeafID = remainingLeaves.first?.leafID
        }
    }

    // MARK: - Navigation

    /// Moves focus to the next leaf in DFS order (wraps around).
    func navigateToNextLeaf() {
        navigate(offset: 1)
    }

    /// Moves focus to the previous leaf in DFS order (wraps around).
    func navigateToPreviousLeaf() {
        navigate(offset: -1)
    }

    /// Navigates focus to the neighbor leaf in the given direction.
    ///
    /// Uses `SplitNavigator` to find the neighbor leaf in the direction
    /// relative to the currently focused leaf. If no neighbor exists in
    /// that direction (e.g., at the edge of the layout), this is a no-op.
    ///
    /// - Parameter direction: The direction to navigate (left, right, up, down).
    /// - SeeAlso: `SplitNavigator.findNeighbor(of:direction:in:)`
    func navigateInDirection(_ direction: NavigationDirection) {
        guard let currentFocusedID = focusedLeafID else { return }

        guard let neighborID = SplitNavigator.findNeighbor(
            of: currentFocusedID,
            direction: direction,
            in: rootNode
        ) else {
            return
        }

        focusedLeafID = neighborID
    }

    /// Focuses the neighboring pane in the requested direction.
    ///
    /// - Returns: `true` when a neighboring pane exists and becomes focused.
    func focusInDirection(_ direction: NavigationDirection) -> Bool {
        guard let currentFocusedID = focusedLeafID,
              let neighborID = SplitNavigator.findNeighbor(
                  of: currentFocusedID,
                  direction: direction,
                  in: rootNode
              ) else {
            return false
        }

        focusedLeafID = neighborID
        return true
    }

    /// Moves focus by the given offset in the leaf list (wraps around).
    private func navigate(offset: Int) {
        guard let currentFocusedID = focusedLeafID else { return }

        let allLeaves = rootNode.allLeafIDs()
        guard allLeaves.count > 1 else { return }

        guard let currentIndex = allLeaves.firstIndex(where: { $0.leafID == currentFocusedID }) else {
            return
        }

        let nextIndex = (currentIndex + offset + allLeaves.count) % allLeaves.count
        focusedLeafID = allLeaves[nextIndex].leafID
    }

    // MARK: - Reorder

    /// Swaps two leaves by their DFS indices.
    ///
    /// Exchanges the `terminalID` values of the leaves at the given indices
    /// in the root tree. The leaf node identifiers remain unchanged; only the
    /// content they reference is exchanged.
    ///
    /// - Parameters:
    ///   - indexA: Index of the first leaf in DFS order.
    ///   - indexB: Index of the second leaf in DFS order.
    func swapLeaves(at indexA: Int, with indexB: Int) {
        rootNode = rootNode.swappingLeaves(at: indexA, with: indexB)
    }

    /// Swaps the focused pane with its adjacent pane in the given direction.
    ///
    /// - Returns: `true` when a neighboring pane exists and the swap succeeds.
    func swapFocused(with direction: NavigationDirection) -> Bool {
        guard let currentFocusedID = focusedLeafID,
              let neighborID = SplitNavigator.findNeighbor(
                  of: currentFocusedID,
                  direction: direction,
                  in: rootNode
              ) else {
            return false
        }

        let leaves = rootNode.allLeafIDs()
        guard let indexA = leaves.firstIndex(where: { $0.leafID == currentFocusedID }),
              let indexB = leaves.firstIndex(where: { $0.leafID == neighborID }) else {
            return false
        }

        swapLeaves(at: indexA, with: indexB)
        return true
    }

    // MARK: - Focus

    /// Sets focus to the leaf with the given ID.
    ///
    /// If the ID does not correspond to a leaf in the tree, this is a no-op.
    ///
    /// - Parameter id: The leaf ID to focus.
    func focusLeaf(id: UUID) {
        guard rootNode.findLeaf(id: id) != nil else { return }
        focusedLeafID = id
    }

    /// Returns the direct parent split ID for the given leaf.
    func parentSplitID(of leafID: UUID) -> UUID? {
        buildPath(to: leafID, in: rootNode)?.last?.splitID
    }

    // MARK: - Ratio

    /// Updates the split ratio for a specific split node.
    ///
    /// The ratio is clamped to 0.1...0.9.
    ///
    /// - Parameters:
    ///   - splitID: The ID of the split node to update.
    ///   - ratio: The new ratio value.
    func setRatio(splitID: UUID, ratio: CGFloat) {
        rootNode = rootNode.updateRatio(splitID: splitID, ratio: ratio)
    }

    /// Resolves which logical divider should move when resizing the focused pane.
    ///
    /// - Returns: The split ID and delta sign, or `nil` when there is no
    ///   adjacent pane in the requested direction.
    func resizeTarget(for direction: NavigationDirection) -> ResizeTarget? {
        guard let currentFocusedID = focusedLeafID,
              let path = buildPath(to: currentFocusedID, in: rootNode) else {
            return nil
        }

        for entry in path.reversed() {
            guard splitMatches(entry.direction, navigationDirection: direction),
                  supportsMovement(direction, childSide: entry.childSide) else {
                continue
            }

            return ResizeTarget(
                splitID: entry.splitID,
                ratioDeltaSign: ratioDeltaSign(for: direction)
            )
        }

        return nil
    }

    // MARK: - Equalize & Zoom

    /// Sets all split ratios to 0.5, equalizing space between panes.
    func equalizeSplits() {
        rootNode = equalizeNode(rootNode)
    }

    private func equalizeNode(_ node: SplitNode) -> SplitNode {
        switch node {
        case .leaf:
            return node
        case .split(let id, let direction, let first, let second, _):
            return .split(
                id: id, direction: direction,
                first: equalizeNode(first),
                second: equalizeNode(second),
                ratio: 0.5
            )
        }
    }

    /// The saved ratio before zoom, keyed by the parent split ID.
    private var savedZoomRatios: [UUID: CGFloat] = [:]

    /// Whether the focused pane is currently zoomed.
    private(set) var isZoomed: Bool = false

    /// Toggles zoom on the focused pane.
    /// When zoomed, the pane takes 95% of its parent split.
    /// When unzoomed, restores the original ratio.
    func toggleZoom() {
        guard let focusedID = focusedLeafID else { return }
        guard rootNode.leafCount > 1 else { return }

        if isZoomed {
            // Restore saved ratios.
            for (splitID, ratio) in savedZoomRatios {
                rootNode = rootNode.updateRatio(splitID: splitID, ratio: ratio)
            }
            savedZoomRatios.removeAll()
            isZoomed = false
        } else {
            // Save current ratios and maximize the focused pane.
            savedZoomRatios = collectRatios(rootNode)
            rootNode = zoomLeaf(focusedID, in: rootNode)
            isZoomed = true
        }
    }

    private func collectRatios(_ node: SplitNode) -> [UUID: CGFloat] {
        switch node {
        case .leaf:
            return [:]
        case .split(let id, _, let first, let second, let ratio):
            var result: [UUID: CGFloat] = [id: ratio]
            result.merge(collectRatios(first)) { _, new in new }
            result.merge(collectRatios(second)) { _, new in new }
            return result
        }
    }

    private func zoomLeaf(_ leafID: UUID, in node: SplitNode) -> SplitNode {
        switch node {
        case .leaf:
            return node
        case .split(let id, let direction, let first, let second, _):
            let inFirst = containsLeaf(leafID, in: first)
            let ratio: CGFloat = inFirst ? 0.95 : 0.05
            return .split(
                id: id, direction: direction,
                first: zoomLeaf(leafID, in: first),
                second: zoomLeaf(leafID, in: second),
                ratio: ratio
            )
        }
    }

    private func containsLeaf(_ leafID: UUID, in node: SplitNode) -> Bool {
        switch node {
        case .leaf(let id, _):
            return id == leafID
        case .split(_, _, let first, let second, _):
            return containsLeaf(leafID, in: first) || containsLeaf(leafID, in: second)
        }
    }

    // MARK: - Keyboard Action Dispatch

    /// Handles a keyboard shortcut action related to splits.
    ///
    /// This is the single entry point for all split-related keyboard shortcuts.
    /// The `MainWindowController` translates key events into `SplitKeyboardAction`
    /// values and dispatches them here.
    ///
    /// - Parameter action: The action to perform.
    /// - SeeAlso: `SplitKeyboardAction`
    func handleSplitAction(_ action: SplitKeyboardAction) {
        switch action {
        case .splitHorizontal:
            splitFocused(direction: .horizontal)
        case .splitVertical:
            splitFocused(direction: .vertical)
        case .splitWithBrowser:
            splitFocusedWithPanel(direction: .horizontal, panel: .browser())
        case .splitWithMarkdown:
            splitFocusedWithPanel(direction: .horizontal, panel: PanelInfo(type: .markdown))
        case .navigateLeft:
            navigateInDirection(.left)
        case .navigateRight:
            navigateInDirection(.right)
        case .navigateUp:
            navigateInDirection(.up)
        case .navigateDown:
            navigateInDirection(.down)
        case .closeActiveSplit:
            closeFocused()
        case .equalizeSplits:
            equalizeSplits()
        case .toggleZoom:
            toggleZoom()
        }
    }

    private func buildPath(to leafID: UUID, in node: SplitNode) -> [PathEntry]? {
        var path: [PathEntry] = []
        guard buildPath(to: leafID, in: node, path: &path) else {
            return nil
        }
        return path
    }

    private func buildPath(
        to leafID: UUID,
        in node: SplitNode,
        path: inout [PathEntry]
    ) -> Bool {
        switch node {
        case .leaf(let id, _):
            return id == leafID

        case .split(let splitID, let direction, let first, let second, _):
            path.append(PathEntry(splitID: splitID, direction: direction, childSide: .first))
            if buildPath(to: leafID, in: first, path: &path) {
                return true
            }
            path.removeLast()

            path.append(PathEntry(splitID: splitID, direction: direction, childSide: .second))
            if buildPath(to: leafID, in: second, path: &path) {
                return true
            }
            path.removeLast()

            return false
        }
    }

    private func splitMatches(
        _ splitDirection: SplitDirection,
        navigationDirection: NavigationDirection
    ) -> Bool {
        switch (splitDirection, navigationDirection) {
        case (.horizontal, .left), (.horizontal, .right):
            return true
        case (.vertical, .up), (.vertical, .down):
            return true
        default:
            return false
        }
    }

    private func supportsMovement(
        _ direction: NavigationDirection,
        childSide: PathChildSide
    ) -> Bool {
        switch (direction, childSide) {
        case (.right, .first), (.down, .first), (.left, .second), (.up, .second):
            return true
        default:
            return false
        }
    }

    private func ratioDeltaSign(for direction: NavigationDirection) -> CGFloat {
        switch direction {
        case .right, .down:
            return 1.0
        case .left, .up:
            return -1.0
        }
    }
}
