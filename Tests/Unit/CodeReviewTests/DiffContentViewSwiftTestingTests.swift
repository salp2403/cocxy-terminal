// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("DiffContentView")
struct DiffContentViewSwiftTestingTests {
    @Test("selection changes do not rebuild the rendered diff hierarchy")
    func selectionUpdatesReuseRenderedRows() throws {
        let view = DiffContentView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let fileDiff = FileDiff(
            filePath: "foo.swift",
            status: .modified,
            hunks: [sampleHunk(lineCount: 3)]
        )

        view.fileDiff = fileDiff
        let stackView = try #require(findStackView(in: view))
        let before = stackView.arrangedSubviews.map(ObjectIdentifier.init)

        view.selectedLineNumber = 2
        view.selectedHunkID = fileDiff.hunks.first?.id

        let after = stackView.arrangedSubviews.map(ObjectIdentifier.init)
        #expect(before == after)
    }

    @Test("large diffs are truncated to keep the panel responsive")
    func largeDiffsAreTruncated() throws {
        let view = DiffContentView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let fileDiff = FileDiff(
            filePath: "big.swift",
            status: .modified,
            hunks: [sampleHunk(lineCount: 5_000)]
        )

        view.fileDiff = fileDiff
        let stackView = try #require(findStackView(in: view))

        #expect(stackView.arrangedSubviews.count == 4_002)
    }
}

@MainActor
private func sampleHunk(lineCount: Int) -> DiffHunk {
    let lines = (1...lineCount).map { index in
        DiffLine(kind: .addition, content: "line \(index)", oldLineNumber: nil, newLineNumber: index)
    }
    return DiffHunk(
        header: "@@ -0,0 +1,\(lineCount) @@",
        oldStart: 0,
        oldCount: 0,
        newStart: 1,
        newCount: lineCount,
        lines: lines
    )
}

@MainActor
private func findStackView(in root: NSView) -> NSStackView? {
    if let stack = root as? NSStackView {
        return stack
    }
    for subview in root.subviews {
        if let stack = findStackView(in: subview) {
            return stack
        }
    }
    return nil
}
