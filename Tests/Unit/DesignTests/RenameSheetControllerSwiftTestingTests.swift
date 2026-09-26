// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("Rename sheet and Aurora host", .serialized)
@MainActor
struct RenameSheetControllerTests {

    @Test("Aurora host accepts the first click after app activation")
    func auroraHostAcceptsFirstMouse() {
        let host = AuroraHostingView(rootView: EmptyView())

        #expect(host.acceptsFirstMouse(for: nil))
    }

    @Test(
        "rename panel stays attached, focusable, and releases its coordinator on close",
        .disabled(
            if: ProcessInfo.processInfo.environment["CI"] != nil,
            "Allocates real AppKit windows; CI runners without a window server abort the suite."
        )
    )
    func renamePanelLifecycle() async {
        let parent = makeParentWindow()
        defer { parent.close() }

        var results: [RenameSheetResult] = []
        let panel = RenameSheetController.present(
            on: parent,
            currentName: "Session"
        ) { result in
            results.append(result)
        }

        #expect(panel.hidesOnDeactivate == false)
        #expect(panel.isReleasedWhenClosed == false)
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.moveToActiveSpace) == false)
        #expect(parent.childWindows?.contains { $0 === panel } == true)
        #expect(RenameSheetController.hasRetainedCoordinator(for: panel))

        panel.close()
        await Task.yield()

        #expect(parent.childWindows?.contains { $0 === panel } == false)
        #expect(RenameSheetController.hasRetainedCoordinator(for: panel) == false)
        #expect(results == [.cancelled])
    }

    @Test(
        "cancel preserves the name while Done with blank input clears it",
        .disabled(
            if: ProcessInfo.processInfo.environment["CI"] != nil,
            "Allocates real AppKit windows; CI runners without a window server abort the suite."
        )
    )
    func cancelAndBlankConfirmationAreDistinct() throws {
        let parent = makeParentWindow()
        defer { parent.close() }
        var results: [RenameSheetResult] = []

        let cancelPanel = RenameSheetController.present(
            on: parent,
            currentName: "Custom"
        ) { results.append($0) }
        let cancelButton = try #require(cancelPanel.contentView?.subviews.compactMap {
            $0 as? NSButton
        }.first { $0.keyEquivalent == "\u{1b}" })
        cancelButton.performClick(nil)

        let confirmPanel = RenameSheetController.present(
            on: parent,
            currentName: "Custom"
        ) { results.append($0) }
        let textField = try #require(confirmPanel.contentView?.subviews.compactMap {
            $0 as? NSTextField
        }.first { $0.isEditable })
        textField.stringValue = "   "
        let doneButton = try #require(confirmPanel.contentView?.subviews.compactMap {
            $0 as? NSButton
        }.first { $0.keyEquivalent == "\r" })
        doneButton.performClick(nil)

        #expect(results == [.cancelled, .confirmed(nil)])
    }

    @Test(
        "closing the parent window does not report rename cancellation",
        .disabled(
            if: ProcessInfo.processInfo.environment["CI"] != nil,
            "Allocates real AppKit windows; CI runners without a window server abort the suite."
        )
    )
    func parentWindowCloseDoesNotCompleteRename() async {
        let parent = makeParentWindow()
        var completionCount = 0
        let panel = RenameSheetController.present(
            on: parent,
            currentName: "Workspace"
        ) { _ in
            completionCount += 1
        }

        parent.close()
        if RenameSheetController.hasRetainedCoordinator(for: panel) {
            panel.close()
        }
        await Task.yield()

        #expect(RenameSheetController.hasRetainedCoordinator(for: panel) == false)
        #expect(completionCount == 0)
    }

    /// A standalone `NSWindow(contentRect:)` releases itself on `close()` by
    /// default, which under ARC over-releases it and crashes the process later.
    private func makeParentWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 900, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}
