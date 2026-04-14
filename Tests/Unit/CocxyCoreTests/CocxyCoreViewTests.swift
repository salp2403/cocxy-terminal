// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CocxyCoreView", .serialized)
@MainActor
struct CocxyCoreViewTests {

    @Test("configureSurfaceIfNeeded wires bridge, surfaceID, and view model")
    func configureSurfaceIfNeededWiresState() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        #expect(harness.view.bridge === harness.bridge)
        #expect(harness.view.surfaceID == harness.surfaceID)
        #expect(harness.view.terminalViewModel === harness.viewModel)
    }

    @Test("configureSurfaceIfNeeded ignores non-CocxyCore bridges")
    func configureSurfaceIfNeededIgnoresOtherBridges() {
        let viewModel = TerminalViewModel()
        let view = CocxyCoreView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)

        view.configureSurfaceIfNeeded(
            bridge: MockTerminalEngine(),
            surfaceID: SurfaceID()
        )

        #expect(view.bridge == nil)
        #expect(view.surfaceID == nil)
    }

    @Test("handleShellPrompt updates IDE cursor state")
    func handleShellPromptUpdatesIDECursorState() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        harness.view.handleShellPrompt(row: 3, column: 5)

        #expect(harness.view.ideCursorController.promptRow == 3)
        #expect(harness.view.ideCursorController.promptColumn == 5)
        #expect(harness.view.ideCursorController.cursorColumn == 5)
        #expect(harness.view.ideCursorController.isOnPromptLine == true)
    }

    @Test("moveRight advances the IDE cursor when on the prompt line")
    func moveRightAdvancesIDECursor() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        harness.view.handleShellPrompt(row: 0, column: 2)

        harness.view.moveRight(nil)

        #expect(harness.view.ideCursorController.cursorColumn == 3)
    }

    @Test("moveLeft never moves before the prompt column")
    func moveLeftClampsAtPromptColumn() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        harness.view.handleShellPrompt(row: 0, column: 2)

        harness.view.moveLeft(nil)

        #expect(harness.view.ideCursorController.cursorColumn == 2)
    }

    @Test("insertNewline clears prompt tracking")
    func insertNewlineClearsPromptTracking() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        harness.view.handleShellPrompt(row: 0, column: 2)

        harness.view.insertNewline(nil)

        #expect(harness.view.ideCursorController.isOnPromptLine == false)
    }

    @Test("setMarkedText activates preedit state in the terminal")
    func setMarkedTextActivatesPreedit() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText("hola", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(harness.view.hasMarkedText() == true)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == true)
        #expect(readPreedit(from: state.terminal) == "hola")
    }

    @Test("unmarkText clears terminal preedit state")
    func unmarkTextClearsPreedit() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        harness.view.setMarkedText("hola", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        harness.view.unmarkText()

        #expect(harness.view.hasMarkedText() == false)
        #expect(cocxycore_terminal_preedit_active(state.terminal) == false)
    }

    @Test("insertText sends text through the PTY-backed bridge")
    func insertTextSendsTextThroughBridge() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.insertText("typed\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("typed") == true
        }

        #expect(String(data: output.data, encoding: .utf8)?.contains("typed") == true)
    }

    @Test("firstRect returns a usable rectangle for IME placement")
    func firstRectReturnsUsableRect() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let rect = harness.view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)

        #expect(rect.width > 0)
        #expect(rect.height > 0)
    }

    // MARK: - Display Fix Regression Coverage

    @Test("renderFrame clears needsRender when prerequisites are missing")
    func renderFrameClearsFlagWhenNotConfigured() {
        let view = CocxyCoreView(viewModel: TerminalViewModel())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        _ = view.layer

        view.needsRender = true
        view.renderFrame()

        #expect(view.needsRender == false)
    }

    @Test("renderFrame clears needsRender when the surface was destroyed")
    func renderFrameClearsFlagAfterDestroy() throws {
        let harness = try makeViewHarness()
        harness.bridge.destroySurface(harness.surfaceID)

        // After destroy the bridge no longer has a SurfaceState for this id,
        // so renderFrame hits the prerequisites-missing branch and must
        // clear the flag. Anything reviving the view (new surface, new
        // configure call) will re-arm needsRender deliberately.
        harness.view.needsRender = true
        harness.view.renderFrame()

        #expect(harness.view.needsRender == false)
    }

    @Test("surface state carries a usable terminal lock for render serialization")
    func surfaceStateExposesTerminalLock() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))

        // Lock must be acquirable (not held by any other path at rest) and
        // must release cleanly, so the render path can safely take/drop it
        // every frame without deadlocking against the PTY feed loop.
        #expect(state.terminalLock.try() == true)
        state.terminalLock.unlock()
    }

    @Test("Cmd+Option+R is routed to the main menu before terminal input")
    func commandOptionRRoutesThroughMenu() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let application = NSApplication.shared
        let oldMenu = application.mainMenu
        let target = MenuActionTarget()
        let mainMenu = NSMenu(title: "Main")
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "App")
        let reviewItem = NSMenuItem(
            title: "Toggle Code Review",
            action: #selector(MenuActionTarget.toggleCodeReview(_:)),
            keyEquivalent: "r"
        )
        reviewItem.keyEquivalentModifierMask = [.command, .option]
        reviewItem.target = target
        appMenu.addItem(reviewItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        application.mainMenu = mainMenu
        defer { application.mainMenu = oldMenu }

        let event = makeKeyEvent(characters: "r", modifiers: [.command, .option])

        #expect(harness.view.performKeyEquivalent(with: event) == true)
        #expect(target.didInvoke == true)
    }
}

@MainActor
private final class MenuActionTarget: NSObject {
    private(set) var didInvoke = false

    @objc func toggleCodeReview(_ sender: Any?) {
        didInvoke = true
    }
}

@MainActor
private struct ViewHarness {
    let bridge: CocxyCoreBridge
    let viewModel: TerminalViewModel
    let view: CocxyCoreView
    let surfaceID: SurfaceID
}

@MainActor
private func makeViewHarness(command: String = "/bin/cat") throws -> ViewHarness {
    let bridge = try makeBridge()
    let viewModel = TerminalViewModel(engine: bridge)
    let view = CocxyCoreView(viewModel: viewModel)
    view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
    _ = view.layer

    let surfaceID = try bridge.createSurface(
        in: view,
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        command: command
    )
    viewModel.markRunning(surfaceID: surfaceID)
    view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)

    return ViewHarness(
        bridge: bridge,
        viewModel: viewModel,
        view: view,
        surfaceID: surfaceID
    )
}

private func makeKeyEvent(
    characters: String,
    modifiers: NSEvent.ModifierFlags
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: characters.lowercased(),
        isARepeat: false,
        keyCode: 15
    )!
}
