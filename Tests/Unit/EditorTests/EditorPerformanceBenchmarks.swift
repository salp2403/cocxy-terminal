// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorPerformanceBenchmarks.swift - Opt-in load-sensitive editor smoke gates.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

private enum EditorBenchmarkConfiguration {
    static let isEnabled =
        ProcessInfo.processInfo.environment["COCXY_RUN_EDITOR_BENCHMARKS"] == "1"
}

@Suite(
    "Editor performance benchmarks",
    .serialized,
    .enabled(
        if: EditorBenchmarkConfiguration.isEnabled,
        Comment("Set COCXY_RUN_EDITOR_BENCHMARKS=1 to run load-sensitive editor benchmarks.")
    )
)
@MainActor
struct EditorPerformanceBenchmarks {
    private static let frameTimeThreshold = 0.016

    @Test("5000-line scroll frame stays within budget")
    func fiveThousandLineScrollFrameBudget() throws {
        let text = (0..<5_000)
            .map { "let value\($0) = \($0) // editor performance smoke" }
            .joined(separator: "\n")
        let fileURL = try makeTemporaryFile(contents: text)
        let view = EditorView(fileURL: fileURL)
        view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 800)

        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        guard let textView: EditorTextView = findSubview(in: view) else {
            Issue.record("EditorTextView was not present in EditorView")
            return
        }

        let offsets = sampledOffsets(from: view.session.document.buffer.lineStartOffsets, count: 40)
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        let startedAt = DispatchTime.now().uptimeNanoseconds
        for offset in offsets {
            textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
        }
        let elapsed = secondsSince(startedAt)
        let averageFrameTime = elapsed / Double(offsets.count)
        print("Editor 5000-line average scroll frame time: \(formatMilliseconds(averageFrameTime))")

        #expect(
            averageFrameTime < Self.frameTimeThreshold,
            Comment("Measured average 5000-line editor scroll frame time: \(formatMilliseconds(averageFrameTime))")
        )
    }

    @Test("50-cursor insert and delete stay within frame budget")
    func fiftyCursorInsertAndDeleteFrameBudget() {
        let text = (0..<50)
            .map { "line-\($0)" }
            .joined(separator: "\n")
        let view = EditorView(text: text)
        view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let carets = view.session.document.buffer.lineStartOffsets.prefix(50).map {
            EditorTextRange(location: $0, length: 0)
        }

        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.setSelection(EditorSelection(ranges: Array(carets)))

        let startedAt = DispatchTime.now().uptimeNanoseconds
        view.insertTextAtSelections("> ")
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let elapsed = secondsSince(startedAt)

        print("Editor 50-cursor insertion frame time: \(formatMilliseconds(elapsed))")
        #expect(
            elapsed < Self.frameTimeThreshold,
            Comment("Measured 50-cursor insertion frame time: \(formatMilliseconds(elapsed))")
        )

        let deleteStartedAt = DispatchTime.now().uptimeNanoseconds
        view.handleDeleteBackward()
        view.handleDeleteBackward()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let deleteElapsed = secondsSince(deleteStartedAt)

        print("Editor 50-cursor delete frame time: \(formatMilliseconds(deleteElapsed))")
        #expect(
            deleteElapsed < Self.frameTimeThreshold,
            Comment("Measured 50-cursor delete frame time: \(formatMilliseconds(deleteElapsed))")
        )
        #expect(view.currentText == text)
    }

    private func makeTemporaryFile(contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-editor-benchmarks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("Large.swift")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func sampledOffsets(from offsets: [Int], count: Int) -> [Int] {
        guard offsets.count > 1, count > 1 else { return offsets }
        return (0..<count).map { index in
            let sourceIndex = Int(
                (Double(index) / Double(count - 1)) * Double(offsets.count - 1)
            )
            return offsets[sourceIndex]
        }
    }

    private func findSubview<T: NSView>(in root: NSView) -> T? {
        if let root = root as? T { return root }
        for subview in root.subviews {
            if let match: T = findSubview(in: subview) {
                return match
            }
        }
        return nil
    }

    private func secondsSince(_ startedAt: UInt64) -> Double {
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        return Double(elapsedNanoseconds) / 1_000_000_000.0
    }

    private func formatMilliseconds(_ seconds: Double) -> String {
        String(format: "%.2fms", seconds * 1_000.0)
    }
}
