// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+PaneCreationLimits.swift - Readability guards for split pane creation and restore.

import AppKit

extension MainWindowController {
    func canCreateAdditionalPaneForCurrentLayout() -> Bool {
        paneCreationLimitMessageForCurrentLayout(
            appendingToEnd: true,
            isVertical: true,
            using: appLocalizer()
        ) == nil
    }

    func paneCreationLimitMessageForCurrentLayout(
        leafCount: Int? = nil,
        appendingToEnd: Bool,
        isVertical: Bool,
        using localizer: AppLocalizer
    ) -> String? {
        let currentLeafCount = leafCount ?? activeSplitManager?.rootNode.leafCount ?? countSplitPanes()
        guard currentLeafCount < Self.maxPaneCount else {
            return HorizontalTabStripView.localizedAddPanelLimit(maxPaneCount: Self.maxPaneCount, using: localizer)
        }
        guard hasRoomForPaneCreation(appendingToEnd: appendingToEnd, isVertical: isVertical) else {
            return HorizontalTabStripView.localizedAddPanelSpaceLimit(using: localizer)
        }
        return nil
    }

    func hasRoomForPaneCreation(appendingToEnd: Bool, isVertical: Bool) -> Bool {
        guard countSplitPanes() < Self.maxPaneCount else { return false }
        guard let frame = paneCreationSourceFrame(appendingToEnd: appendingToEnd) else { return true }

        let available = isVertical ? frame.width : frame.height
        let minimum = isVertical
            ? Self.minimumReadableSplitPaneWidth
            : Self.minimumReadableSplitPaneHeight
        let divider = activeSplitView?.dividerThickness ?? 1

        guard available > 0 else {
            guard let fallback = terminalContainerView?.bounds, fallback.width > 0, fallback.height > 0 else {
                return true
            }
            let fallbackAvailable = isVertical ? fallback.width : fallback.height
            return fallbackAvailable >= (minimum * 2) + divider
        }

        return available >= (minimum * 2) + divider
    }

    func readableRestoredSplitNode(_ rootNode: SplitNode) -> SplitNode {
        let leaves = rootNode.allLeafIDs()
        guard leaves.count >= 3 else { return rootNode }

        let rootFrame = splitRootFrame()
        guard rootFrame.width > 0,
              minimumLeafWidth(
                in: rootNode,
                frame: rootFrame,
                dividerThickness: activeSplitView?.dividerThickness ?? 1
              ) < Self.minimumReadableSplitPaneWidth,
              let gridNode = Self.readableGridSplitNode(from: leaves)
        else {
            return rootNode
        }

        return gridNode
    }

    private static var minimumReadableSplitPaneWidth: CGFloat { 300 }
    private static var minimumReadableSplitPaneHeight: CGFloat { 180 }

    private func paneCreationSourceFrame(appendingToEnd: Bool) -> NSRect? {
        guard let splitManager = activeSplitManager else {
            return terminalContainerView?.bounds ?? terminalSurfaceView?.bounds
        }

        let leaves = splitManager.rootNode.allLeafIDs()
        let targetLeafID = appendingToEnd
            ? leaves.last?.leafID
            : splitManager.focusedLeafID
        guard let targetLeafID else { return nil }

        return frameForLeaf(
            targetLeafID,
            in: splitManager.rootNode,
            frame: splitRootFrame(),
            dividerThickness: activeSplitView?.dividerThickness ?? 1
        )
    }

    private func splitRootFrame() -> NSRect {
        if let splitBounds = activeSplitView?.bounds,
           splitBounds.width > 0,
           splitBounds.height > 0 {
            return splitBounds
        }
        if let containerBounds = terminalContainerView?.bounds,
           containerBounds.width > 0,
           containerBounds.height > 0 {
            return containerBounds
        }
        if let terminalBounds = terminalSurfaceView?.bounds,
           terminalBounds.width > 0,
           terminalBounds.height > 0 {
            return terminalBounds
        }
        return window?.contentView?.bounds ?? .zero
    }

    private func frameForLeaf(
        _ leafID: UUID,
        in node: SplitNode,
        frame: NSRect,
        dividerThickness: CGFloat
    ) -> NSRect? {
        switch node {
        case .leaf(let id, _):
            return id == leafID ? frame : nil
        case .split(_, let direction, let first, let second, let ratio):
            let childFrames = SplitLayoutGeometry.childFrames(
                in: frame,
                isVertical: direction == .horizontal,
                ratio: ratio,
                dividerThickness: dividerThickness
            )
            return frameForLeaf(
                leafID,
                in: first,
                frame: childFrames.first,
                dividerThickness: dividerThickness
            )
                ?? frameForLeaf(
                    leafID,
                    in: second,
                    frame: childFrames.second,
                    dividerThickness: dividerThickness
                )
        }
    }

    private func minimumLeafWidth(
        in node: SplitNode,
        frame: NSRect,
        dividerThickness: CGFloat
    ) -> CGFloat {
        switch node {
        case .leaf:
            return frame.width
        case .split(_, let direction, let first, let second, let ratio):
            let childFrames = SplitLayoutGeometry.childFrames(
                in: frame,
                isVertical: direction == .horizontal,
                ratio: ratio,
                dividerThickness: dividerThickness
            )
            return min(
                minimumLeafWidth(in: first, frame: childFrames.first, dividerThickness: dividerThickness),
                minimumLeafWidth(in: second, frame: childFrames.second, dividerThickness: dividerThickness)
            )
        }
    }

    private static func readableGridSplitNode(from leaves: [LeafInfo]) -> SplitNode? {
        guard leaves.count >= 3 else { return nil }
        let topCount = Int(ceil(Double(leaves.count) / 2.0))
        let topLeaves = Array(leaves.prefix(topCount))
        let bottomLeaves = Array(leaves.dropFirst(topCount))
        guard let top = readableRowSplitNode(from: topLeaves),
              let bottom = readableRowSplitNode(from: bottomLeaves) else {
            return nil
        }
        return .split(
            id: UUID(),
            direction: .vertical,
            first: top,
            second: bottom,
            ratio: 0.5
        )
    }

    private static func readableRowSplitNode(from leaves: [LeafInfo]) -> SplitNode? {
        guard let firstLeaf = leaves.first else { return nil }
        if leaves.count == 1 {
            return .leaf(id: firstLeaf.leafID, terminalID: firstLeaf.terminalID)
        }

        let first = SplitNode.leaf(id: firstLeaf.leafID, terminalID: firstLeaf.terminalID)
        guard let second = readableRowSplitNode(from: Array(leaves.dropFirst())) else { return first }
        return .split(
            id: UUID(),
            direction: .horizontal,
            first: first,
            second: second,
            ratio: 1.0 / CGFloat(leaves.count)
        )
    }
}
