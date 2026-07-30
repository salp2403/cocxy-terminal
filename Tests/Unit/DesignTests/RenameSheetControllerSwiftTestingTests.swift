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
        let parent = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 900, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        defer { parent.close() }

        var completionCount = 0
        let panel = RenameSheetController.present(
            on: parent,
            currentName: "Session"
        ) { _ in
            completionCount += 1
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
        #expect(completionCount == 1)
    }

    @Test(
        "closing the parent window does not report rename cancellation",
        .disabled(
            if: ProcessInfo.processInfo.environment["CI"] != nil,
            "Allocates real AppKit windows; CI runners without a window server abort the suite."
        )
    )
    func parentWindowCloseDoesNotCompleteRename() async {
        let parent = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 900, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
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
}
