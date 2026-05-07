// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SplitLayoutGeometrySwiftTestingTests.swift - Split view geometry regression tests.

import AppKit
import Testing
@testable import CocxyTerminal

@Suite("Split layout geometry")
struct SplitLayoutGeometrySwiftTestingTests {

    @Test("nested appended panels stay inside the parent pane")
    func nestedAppendedPanelsStayInsideParentPane() {
        let rootFrame = NSRect(x: 0, y: 0, width: 1200, height: 700)

        let rootFrames = SplitLayoutGeometry.childFrames(
            in: rootFrame,
            isVertical: true,
            ratio: 0.5,
            dividerThickness: 1
        )
        let nestedFrames = SplitLayoutGeometry.childFrames(
            in: NSRect(origin: .zero, size: rootFrames.second.size),
            isVertical: true,
            ratio: 0.5,
            dividerThickness: 1
        )

        #expect(rootFrames.second.width < rootFrame.width)
        #expect(nestedFrames.first.maxX <= rootFrames.second.width + 0.001)
        #expect(nestedFrames.second.maxX <= rootFrames.second.width + 0.001)
        #expect(nestedFrames.first.width > 250)
        #expect(nestedFrames.second.width > 250)
    }

    @Test("divider positions clamp ratios to the split node range")
    func dividerPositionsClampRatiosToSplitNodeRange() {
        let totalSize: CGFloat = 1000
        let dividerThickness: CGFloat = 1

        let minimumPosition = SplitLayoutGeometry.dividerPosition(
            totalSize: totalSize,
            dividerThickness: dividerThickness,
            ratio: -1
        )
        let maximumPosition = SplitLayoutGeometry.dividerPosition(
            totalSize: totalSize,
            dividerThickness: dividerThickness,
            ratio: 2
        )

        #expect(abs(minimumPosition - 99.9) < 0.001)
        #expect(abs(maximumPosition - 899.1) < 0.001)
    }

    @Test("stacked splits divide height and preserve full width")
    func stackedSplitsDivideHeightAndPreserveFullWidth() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        let frames = SplitLayoutGeometry.childFrames(
            in: frame,
            isVertical: false,
            ratio: 0.25,
            dividerThickness: 2
        )

        #expect(abs(frames.first.height - 149.5) < 0.001)
        #expect(abs(frames.second.height - 448.5) < 0.001)
        #expect(frames.first.width == 800)
        #expect(frames.second.width == 800)
        #expect(frames.second.minY == frames.first.height + 2)
    }

    @MainActor
    @Test("recursive ratio application repairs an out of range nested divider")
    func recursiveRatioApplicationRepairsOutOfRangeNestedDivider() {
        let rootFrame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        let terminalID = UUID()
        let markdownID = UUID()
        let notebookID = UUID()
        let rootNode = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: terminalID),
            second: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: UUID(), terminalID: markdownID),
                second: .leaf(id: UUID(), terminalID: notebookID),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let rootSplit = NSSplitView(frame: rootFrame)
        rootSplit.isVertical = true
        rootSplit.dividerStyle = .thin
        let terminalView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        let nestedSplit = NSSplitView(frame: NSRect(x: 600, y: 0, width: 600, height: 700))
        nestedSplit.isVertical = true
        nestedSplit.dividerStyle = .thin
        let markdownView = NSView(frame: NSRect(x: 0, y: 0, width: 599, height: 700))
        let notebookView = NSView(frame: NSRect(x: 620, y: 0, width: 1, height: 700))

        nestedSplit.addSubview(markdownView)
        nestedSplit.addSubview(notebookView)
        rootSplit.addSubview(terminalView)
        rootSplit.addSubview(nestedSplit)

        SplitLayoutGeometry.applyRatios(from: rootNode, to: rootSplit)

        #expect(nestedSplit.subviews[0].frame.width > 250)
        #expect(nestedSplit.subviews[1].frame.width > 250)
        #expect(nestedSplit.subviews[0].frame.maxX <= nestedSplit.bounds.width + 0.001)
        #expect(nestedSplit.subviews[1].frame.maxX <= nestedSplit.bounds.width + 0.001)
    }

    @MainActor
    @Test("flexible pane hosts keep constrained content from pushing sibling panels offscreen")
    func flexiblePaneHostsKeepConstrainedContentFromPushingSiblingPanelsOffscreen() {
        let rootFrame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        let rootNode = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            first: .leaf(id: UUID(), terminalID: UUID()),
            second: .split(
                id: UUID(),
                direction: .horizontal,
                first: .leaf(id: UUID(), terminalID: UUID()),
                second: .leaf(id: UUID(), terminalID: UUID()),
                ratio: 0.5
            ),
            ratio: 0.5
        )

        let rootSplit = NSSplitView(frame: rootFrame)
        rootSplit.isVertical = true
        rootSplit.dividerStyle = .thin

        let terminalHost = SplitPaneHostView(contentView: MinimumIntrinsicWidthView(width: 500))
        let nestedSplit = NSSplitView(frame: NSRect(x: 600, y: 0, width: 600, height: 700))
        nestedSplit.isVertical = true
        nestedSplit.dividerStyle = .thin
        let markdownHost = SplitPaneHostView(contentView: MinimumIntrinsicWidthView(width: 620))
        let notebookHost = SplitPaneHostView(contentView: MinimumIntrinsicWidthView(width: 320))

        nestedSplit.addSubview(markdownHost)
        nestedSplit.addSubview(notebookHost)
        rootSplit.addSubview(terminalHost)
        rootSplit.addSubview(nestedSplit)

        SplitLayoutGeometry.applyRatios(from: rootNode, to: rootSplit)
        rootSplit.layoutSubtreeIfNeeded()
        nestedSplit.layoutSubtreeIfNeeded()

        #expect(markdownHost.intrinsicContentSize.width == NSView.noIntrinsicMetric)
        #expect(notebookHost.intrinsicContentSize.width == NSView.noIntrinsicMetric)
        #expect(markdownHost.frame.width > 250)
        #expect(notebookHost.frame.width > 250)
        #expect(notebookHost.frame.maxX <= nestedSplit.bounds.width + 0.001)
        #expect(notebookHost.contentView.frame.size == notebookHost.bounds.size)
    }
}

private final class MinimumIntrinsicWidthView: NSView {
    private let width: CGFloat

    init(width: CGFloat) {
        self.width = width
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MinimumIntrinsicWidthView does not support NSCoding")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: width, height: NSView.noIntrinsicMetric)
    }
}
