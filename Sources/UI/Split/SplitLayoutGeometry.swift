// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitLayoutGeometry.swift - Shared split view sizing helpers.

import AppKit

final class SplitPaneHostView: NSView {
    let contentView: NSView

    init(contentView: NSView) {
        self.contentView = contentView
        super.init(frame: contentView.frame)

        wantsLayer = true
        layer?.masksToBounds = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        contentView.removeFromSuperview()
        contentView.translatesAutoresizingMaskIntoConstraints = true
        contentView.autoresizingMask = [.width, .height]
        contentView.frame = bounds
        contentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentView.setContentHuggingPriority(.defaultLow, for: .vertical)
        contentView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        contentView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SplitPaneHostView does not support NSCoding")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        contentView.frame = bounds
    }
}

private final class SplitLayoutDelegate: NSObject, NSSplitViewDelegate {
    nonisolated(unsafe) static var associatedKey: UInt8 = 0

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let totalSize = splitView.isVertical
            ? splitView.bounds.width
            : splitView.bounds.height
        return totalSize * SplitNode.minimumRatio
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let totalSize = splitView.isVertical
            ? splitView.bounds.width
            : splitView.bounds.height
        return totalSize * SplitNode.maximumRatio
    }
}

enum SplitLayoutGeometry {
    @MainActor
    static func installFlexibleDelegate(on splitView: NSSplitView) {
        let delegate = SplitLayoutDelegate()
        splitView.delegate = delegate
        objc_setAssociatedObject(
            splitView,
            &SplitLayoutDelegate.associatedKey,
            delegate,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func childFrames(
        in frame: NSRect,
        isVertical: Bool,
        ratio: CGFloat,
        dividerThickness: CGFloat
    ) -> (first: NSRect, second: NSRect) {
        let width = max(0, frame.width)
        let height = max(0, frame.height)
        let ratio = SplitNode.clampRatio(ratio)

        if isVertical {
            let divider = clampedDividerThickness(dividerThickness, totalSize: width)
            let availableWidth = max(0, width - divider)
            let firstWidth = availableWidth * ratio
            let secondWidth = max(0, availableWidth - firstWidth)
            return (
                NSRect(x: 0, y: 0, width: firstWidth, height: height),
                NSRect(x: firstWidth + divider, y: 0, width: secondWidth, height: height)
            )
        }

        let divider = clampedDividerThickness(dividerThickness, totalSize: height)
        let availableHeight = max(0, height - divider)
        let firstHeight = availableHeight * ratio
        let secondHeight = max(0, availableHeight - firstHeight)
        return (
            NSRect(x: 0, y: 0, width: width, height: firstHeight),
            NSRect(x: 0, y: firstHeight + divider, width: width, height: secondHeight)
        )
    }

    static func dividerPosition(
        totalSize: CGFloat,
        dividerThickness: CGFloat,
        ratio: CGFloat
    ) -> CGFloat {
        let totalSize = max(0, totalSize)
        let divider = clampedDividerThickness(dividerThickness, totalSize: totalSize)
        return max(0, totalSize - divider) * SplitNode.clampRatio(ratio)
    }

    @MainActor
    static func applyRatios(from node: SplitNode, to view: NSView) {
        guard case .split(_, _, let first, let second, let ratio) = node,
              let splitView = view as? NSSplitView else {
            return
        }

        splitView.bounds = NSRect(origin: .zero, size: splitView.frame.size)
        splitView.layoutSubtreeIfNeeded()
        let totalSize = splitView.isVertical
            ? splitView.frame.width
            : splitView.frame.height
        guard splitView.subviews.count >= 2 else { return }
        splitView.subviews[0].autoresizingMask = []
        splitView.subviews[1].autoresizingMask = []

        if totalSize > 0 {
            let position = dividerPosition(
                totalSize: totalSize,
                dividerThickness: splitView.dividerThickness,
                ratio: ratio
            )
            splitView.setPosition(position, ofDividerAt: 0)
            splitView.adjustSubviews()
            let childFrames = childFrames(
                in: NSRect(origin: .zero, size: splitView.frame.size),
                isVertical: splitView.isVertical,
                ratio: ratio,
                dividerThickness: splitView.dividerThickness
            )
            splitView.subviews[0].frame = childFrames.first
            splitView.subviews[1].frame = childFrames.second
        }

        applyRatios(from: first, to: splitView.subviews[0])
        applyRatios(from: second, to: splitView.subviews[1])
    }

    private static func clampedDividerThickness(_ dividerThickness: CGFloat, totalSize: CGFloat) -> CGFloat {
        min(max(0, dividerThickness), max(0, totalSize))
    }
}
