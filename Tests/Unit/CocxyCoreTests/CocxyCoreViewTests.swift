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

    @Test("configureSurfaceIfNeeded installs the command block overlay above the terminal")
    func configureSurfaceIfNeededInstallsCommandBlockOverlay() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let overlay = try #require(harness.view.commandBlockOverlayView)
        #expect(overlay.superview === harness.view)
        #expect(overlay.frame == harness.view.bounds)
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

    @Test("configureSurfaceIfNeeded ignores CocxyCore bridges without a view model")
    func configureSurfaceIfNeededIgnoresMissingViewModel() throws {
        let bridge = try makeBridge()
        let view = CocxyCoreView()
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 400)

        view.configureSurfaceIfNeeded(
            bridge: bridge,
            surfaceID: SurfaceID()
        )

        #expect(view.bridge == nil)
        #expect(view.surfaceID == nil)
    }

    @Test("focus lifecycle updates bridge focus state")
    func focusLifecycleUpdatesBridgeFocusState() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        #expect(harness.view.becomeFirstResponder() == true)
        #expect(harness.view.isFocused == true)

        #expect(harness.view.resignFirstResponder() == true)
        #expect(harness.view.isFocused == false)
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
        var submitCount = 0
        harness.view.onUserInputSubmitted = {
            submitCount += 1
        }

        harness.view.insertNewline(nil)

        #expect(harness.view.ideCursorController.isOnPromptLine == false)
        #expect(submitCount == 1)
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

    @Test("text input accessors expose marked text state and accepted attributes")
    func textInputAccessorsExposeCompositionState() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let marked = NSAttributedString(string: "composed")

        harness.view.setMarkedText(
            marked,
            selectedRange: NSRange(location: 2, length: 3),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        #expect(harness.view.hasMarkedText() == true)
        #expect(harness.view.markedRange().location == 0)
        #expect(harness.view.markedRange().length == "composed".count)
        #expect(harness.view.selectedRange().location == NSNotFound)
        #expect(harness.view.characterIndex(for: .zero) == 0)
        #expect(harness.view.attributedSubstring(forProposedRange: NSRange(location: 0, length: 1), actualRange: nil) == nil)
        #expect(harness.view.validAttributesForMarkedText().contains(.underlineStyle))
        #expect(harness.view.validAttributesForMarkedText().contains(.foregroundColor))
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

    @Test("insertText accepts attributed strings")
    func insertTextAcceptsAttributedStrings() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.insertText(
            NSAttributedString(string: "attributed\n"),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("attributed") == true
        }

        #expect(String(data: output.data, encoding: .utf8)?.contains("attributed") == true)
    }

    @Test("firstRect returns a usable rectangle for IME placement")
    func firstRectReturnsUsableRect() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let rect = harness.view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)

        #expect(rect.width > 0)
        #expect(rect.height > 0)
    }

    @Test("firstRect falls back when no terminal surface is attached")
    func firstRectFallsBackWhenNoSurfaceIsAttached() {
        let view = CocxyCoreView(viewModel: TerminalViewModel())

        let rect = view.firstRect(forCharacterRange: NSRange(location: 0, length: 0), actualRange: nil)

        #expect(rect == .zero)
    }

    @Test("text input ignores unsupported and empty payloads")
    func textInputIgnoresUnsupportedAndEmptyPayloads() {
        let view = CocxyCoreView(viewModel: TerminalViewModel())

        view.insertText(42, replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText(42, selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()

        #expect(view.hasMarkedText() == false)
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

    @Test("display link coalesces render requests while a frame is scheduled")
    func displayLinkCoalescesScheduledRenderRequests() {
        let view = CocxyCoreView(viewModel: TerminalViewModel())

        #expect(view.claimRenderSlotForDisplayLink() == false)

        view.needsRender = true
        #expect(view.claimRenderSlotForDisplayLink() == true)
        #expect(view.renderScheduled == true)
        #expect(view.claimRenderSlotForDisplayLink() == false)

        view.finishRenderSlotForDisplayLink()

        #expect(view.renderScheduled == false)
        #expect(view.claimRenderSlotForDisplayLink() == true)
    }

    @Test("layout and backing refresh paths keep redraw armed while detached")
    func layoutAndBackingRefreshKeepDetachedViewRenderable() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        harness.view.setFrameSize(NSSize(width: 640, height: 320))
        harness.view.layout()
        harness.view.viewDidChangeBackingProperties()
        harness.view.syncSizeWithTerminal()
        harness.view.updateInteractionMetrics()
        harness.view.refreshDisplayLinkAnchor()
        harness.view.requestImmediateRedraw()

        #expect(harness.view.needsRender == true)
        #expect(harness.view.commandBlockOverlayView?.frame == harness.view.bounds)
    }

    @Test("display link stays stopped while the terminal view is detached")
    func displayLinkStaysStoppedWhileViewIsDetached() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        #expect(harness.view.isDisplayLinkRunningForTests == false)
        harness.view.requestImmediateRedraw()
        #expect(harness.view.isDisplayLinkRunningForTests == false)
    }

    @Test("backing CAMetalLayer is opaque so translucent windows do not bleed through the terminal")
    func backingMetalLayerIsOpaque() {
        // Regression for the "transparent shell on agent launch" bug: when
        // background-opacity < 1.0 the hosting NSWindow is non-opaque, and
        // AppKit propagates that flag to backing layers unless the view
        // anchors it explicitly. Without anchoring, any transient render
        // failure during a heavy burst of agent output or a full repaint
        // composed the layer against the desktop
        // and the user saw straight through the terminal.
        //
        // The clear color used by MetalTerminalRenderer always carries
        // alpha 1.0, so locking the layer to opaque keeps the chrome
        // transparency feature intact while preventing the terminal area
        // itself from ever going see-through.
        let view = CocxyCoreView(viewModel: TerminalViewModel())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        let metalLayer = view.layer as? CAMetalLayer

        #expect(metalLayer != nil)
        #expect(metalLayer?.isOpaque == true)
        #expect(metalLayer?.backgroundColor != nil)
        #expect(metalLayer?.backgroundColor?.alpha == 1.0)
    }

    @Test("notification ring show and hide update view state")
    func notificationRingShowAndHideUpdateState() {
        let view = CocxyCoreView(viewModel: TerminalViewModel())
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        _ = view.layer

        view.showNotificationRing(color: .systemRed)
        view.showNotificationRing(color: .systemBlue)

        #expect(view.isNotificationRingActive == true)
        #expect(view.layer?.sublayers?.isEmpty == false)

        view.hideNotificationRing()
        view.hideNotificationRing()

        #expect(view.isNotificationRingActive == false)
    }

    @Test("configure applies the terminal theme background before the first Metal frame")
    func configureAppliesTerminalThemeBackgroundFallback() throws {
        let palette = makeTerminalPalette(background: "#112233")
        let bridge = CocxyCoreBridge()
        try bridge.initialize(config: makeTerminalConfig(themePalette: palette))
        let viewModel = TerminalViewModel(engine: bridge)
        let view = CocxyCoreView(viewModel: viewModel)
        view.frame = NSRect(x: 0, y: 0, width: 200, height: 120)
        _ = view.layer

        let surfaceID = try bridge.createSurface(
            in: view,
            workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
            command: "/bin/cat"
        )
        defer { bridge.destroySurface(surfaceID) }

        viewModel.markRunning(surfaceID: surfaceID)
        view.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)

        let color = try #require(view.layer?.backgroundColor)
        let nsColor = try #require(NSColor(cgColor: color)?.usingColorSpace(.sRGB))
        #expect(abs(nsColor.redComponent - (0x11 / 255.0)) < 0.001)
        #expect(abs(nsColor.greenComponent - (0x22 / 255.0)) < 0.001)
        #expect(abs(nsColor.blueComponent - (0x33 / 255.0)) < 0.001)
        #expect(nsColor.alphaComponent == 1.0)
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

    @Test("keyDown routes menu shortcuts before terminal input")
    func keyDownRoutesMenuShortcutsBeforeTerminalInput() throws {
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

        harness.view.keyDown(with: makeKeyEvent(characters: "r", modifiers: [.command, .option], keyCode: 15))

        #expect(target.didInvoke == true)
    }

    @Test("paste reads clipboard text and routes it through the terminal")
    func pasteReadsClipboardAndRoutesText() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let clipboard = RecordingClipboardService(readText: "from paste\n")
        harness.view.clipboardService = clipboard

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.paste(nil)

        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("from paste") == true
        }
        #expect(clipboard.readCallCount == 1)
        #expect(String(data: output.data, encoding: .utf8)?.contains("from paste") == true)
    }

    @Test("bracketed paste wraps clipboard payload when the terminal enables it")
    func bracketedPasteWrapsClipboardPayload() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        feed("\u{001B}[?2004h", into: state.terminal)
        let clipboard = RecordingClipboardService(readText: "bracketed payload\n")
        harness.view.clipboardService = clipboard

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.paste(nil)

        try await waitUntil {
            let text = String(data: output.data, encoding: .utf8) ?? ""
            return text.contains("\u{001B}[200~") && text.contains("bracketed payload")
        }
        let text = String(data: output.data, encoding: .utf8) ?? ""
        #expect(text.contains("\u{001B}[200~"))
        #expect(clipboard.readCallCount == 1)
    }

    @Test("keyDown application shortcuts route copy paste select all and clear screen")
    func keyDownApplicationShortcutsRouteAppCommands() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        feed("alpha beta\r\n", into: state.terminal)
        harness.bridge.setSelection(
            for: harness.surfaceID,
            startRow: 0,
            startCol: 0,
            endRow: 0,
            endCol: 4
        )
        let clipboard = RecordingClipboardService(readText: "shortcut paste\n")
        harness.view.clipboardService = clipboard

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.keyDown(with: makeKeyEvent(characters: "c", modifiers: [.command], keyCode: 0x08))
        #expect(clipboard.writtenText == "alpha")

        harness.view.keyDown(with: makeKeyEvent(characters: "v", modifiers: [.command], keyCode: 0x09))
        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("shortcut paste") == true
        }

        harness.view.keyDown(with: makeKeyEvent(characters: "a", modifiers: [.command], keyCode: 0x00))
        harness.view.keyDown(with: makeKeyEvent(characters: "k", modifiers: [.command], keyCode: 0x28))

        #expect(clipboard.readCallCount == 1)
        #expect(String(data: output.data, encoding: .utf8)?.contains("shortcut paste") == true)
    }

    @Test("responder commands route control sequences without losing prompt callbacks")
    func responderCommandsRouteControlSequences() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        var submitCount = 0
        harness.view.onUserInputSubmitted = {
            submitCount += 1
        }

        harness.view.deleteBackward(nil)
        harness.view.deleteForward(nil)
        harness.view.moveUp(nil)
        harness.view.moveDown(nil)
        harness.view.moveToBeginningOfLine(nil)
        harness.view.moveToEndOfLine(nil)
        harness.view.insertTab(nil)
        harness.view.noResponder(for: #selector(NSResponder.insertTab(_:)))
        harness.view.keyUp(with: makeKeyEvent(characters: "x"))
        harness.view.flagsChanged(with: makeKeyEvent(characters: "", modifiers: [.command]))
        harness.view.flagsChanged(with: makeKeyEvent(characters: "", modifiers: []))
        harness.view.insertNewline(nil)

        #expect(submitCount == 1)
    }

    @Test("keyDown routes printable, control, option and shift-return input")
    func keyDownRoutesTerminalInputVariants() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        harness.view.keyDown(with: makeKeyEvent(characters: "@", charactersIgnoringModifiers: "2", modifiers: [.option], keyCode: 19))

        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("@") == true
        }

        harness.view.keyDown(with: makeKeyEvent(characters: "x", keyCode: 7))
        harness.view.keyDown(with: makeKeyEvent(characters: "c", modifiers: [.control], keyCode: 8))
        harness.view.keyDown(with: makeKeyEvent(characters: "\r", modifiers: [.shift], keyCode: 0x24))

        let text = String(data: output.data, encoding: .utf8) ?? ""
        #expect(text.contains("@"))
    }

    @Test("keyDown arrow and return keys update IDE prompt tracking")
    func keyDownArrowAndReturnKeysUpdateIDEPromptTracking() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        var submitCount = 0
        harness.view.onUserInputSubmitted = {
            submitCount += 1
        }
        harness.view.handleShellPrompt(row: 0, column: 2)

        harness.view.keyDown(with: makeKeyEvent(characters: "", keyCode: 0x7C))
        #expect(harness.view.ideCursorController.cursorColumn == 3)

        harness.view.keyDown(with: makeKeyEvent(characters: "", keyCode: 0x7B))
        #expect(harness.view.ideCursorController.cursorColumn == 2)

        harness.view.keyDown(with: makeKeyEvent(characters: "\r", keyCode: 0x24))

        #expect(harness.view.ideCursorController.isOnPromptLine == false)
        #expect(submitCount == 1)
    }

    @Test("shell prompt at current cursor enables click-to-position arrow synthesis")
    func shellPromptAtCurrentCursorEnablesClickToPositionArrowSynthesis() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }

        harness.view.handleShellPromptAtCurrentCursor()
        let controller = harness.view.ideCursorController
        let target = CGPoint(
            x: controller.leftPadding + controller.cellWidth * 3,
            y: controller.topPadding + CGFloat(controller.promptRow) * controller.cellHeight + 1
        )

        #expect(controller.handleClickToPosition(at: target) == true)
        #expect(controller.cursorColumn == 3)
    }

    @Test("shell prompt at current cursor ignores missing surfaces")
    func shellPromptAtCurrentCursorIgnoresMissingSurfaces() {
        let view = CocxyCoreView(viewModel: TerminalViewModel())

        view.handleShellPromptAtCurrentCursor()

        #expect(view.ideCursorController.isOnPromptLine == false)
    }

    @Test("mouse and scroll events update selection state and request redraw")
    func mouseAndScrollEventsUpdateSelectionState() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        var focusRequests = 0
        harness.view.onFocusRequested = {
            focusRequests += 1
        }

        harness.view.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12), clickCount: 1))
        #expect(focusRequests == 1)
        #expect(harness.viewModel.lastClickCount == 1)
        #expect(harness.viewModel.isDragging == true)

        harness.view.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 80, y: 34)))
        #expect(harness.view.needsRender == true)

        harness.view.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 80, y: 34)))
        #expect(harness.viewModel.isDragging == false)

        harness.view.scrollWheel(with: makeScrollEvent(deltaY: 12))
        harness.view.scrollWheel(with: makeScrollEvent(deltaY: -12))
        #expect(harness.view.commandBlockOverlayView != nil)
    }

    @Test("scroll wheel forwards events when terminal mouse mode is enabled")
    func scrollWheelForwardsEventsWhenMouseModeIsEnabled() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        feed("\u{001B}[?1000h", into: state.terminal)

        let diagnostics = try #require(harness.bridge.modeDiagnostics(for: harness.surfaceID))
        #expect(diagnostics.mouseTrackingMode > 0)

        harness.view.scrollWheel(with: makeScrollEvent(deltaY: 24))

        #expect(harness.view.commandBlockOverlayView != nil)
    }

    @Test("active agent scroll uses local viewport when terminal mouse mode is enabled")
    func activeAgentScrollUsesLocalViewportInMouseMode() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        feed(numberedTerminalLines(100), into: state.terminal)
        let before = try #require(harness.bridge.historyVisibleStart(for: harness.surfaceID))
        let maxVisibleStart = cocxycore_terminal_history_max_visible_start(state.terminal)
        #expect(maxVisibleStart > 0)
        #expect(before == maxVisibleStart)

        feed("\u{001B}[?1000h", into: state.terminal)
        harness.view.prefersLocalScrollInMouseTrackingMode = { true }

        harness.view.scrollWheel(with: makeScrollEvent(deltaY: 120))

        let after = try #require(harness.bridge.historyVisibleStart(for: harness.surfaceID))
        #expect(after < before)
    }

    @Test("active agent scroll uses local viewport in alt screen mouse mode")
    func activeAgentScrollUsesLocalViewportInAltScreenMouseMode() throws {
        let harness = try makeViewHarness()
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let state = try #require(harness.bridge.surfaceState(for: harness.surfaceID))
        feed("\u{001B}[?1049h", into: state.terminal)
        feed(numberedTerminalLines(100), into: state.terminal)
        let before = try #require(harness.bridge.historyVisibleStart(for: harness.surfaceID))
        let maxVisibleStart = cocxycore_terminal_history_max_visible_start(state.terminal)
        #expect(maxVisibleStart > 0)
        #expect(before == maxVisibleStart)

        feed("\u{001B}[?1000h", into: state.terminal)
        harness.view.prefersLocalScrollInMouseTrackingMode = { true }

        harness.view.scrollWheel(with: makeScrollEvent(deltaY: 120))

        let after = try #require(harness.bridge.historyVisibleStart(for: harness.surfaceID))
        #expect(after < before)
    }

    @Test("file drop routes host handler and terminal paste fallback")
    func fileDropRoutesHostHandlerAndTerminalPasteFallback() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let droppedURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cocxy dropped.txt")
        let draggingInfo = MockDraggingInfo(fileURLs: [droppedURL])
        var handledURLs: [URL] = []
        harness.view.onFileDrop = { urls in
            handledURLs = urls
            return true
        }

        #expect(harness.view.draggingEntered(draggingInfo) == .copy)
        #expect(harness.view.performDragOperation(draggingInfo) == true)
        #expect(handledURLs == [droppedURL])

        harness.view.onFileDrop = nil
        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }

        #expect(harness.view.performDragOperation(draggingInfo) == true)
        try await waitUntil {
            String(data: output.data, encoding: .utf8)?
                .contains(FileDropPathFormatter.format([droppedURL]).trimmingCharacters(in: .whitespacesAndNewlines)) == true
        }
    }

    @Test("command block overlay restores rows and routes actions")
    func commandBlockOverlayRestoresRowsAndRoutesActions() async throws {
        let harness = try makeViewHarness(command: "/bin/cat")
        defer { harness.bridge.destroySurface(harness.surfaceID) }
        let clipboard = RecordingClipboardService(readText: nil)
        harness.view.clipboardService = clipboard
        let block = makeCommandBlock(
            id: 41,
            command: "overlay-rerun",
            output: "overlay output",
            startRow: 0,
            endRow: 1
        )
        let commandOnlyBlock = makeCommandBlock(
            id: 42,
            command: "copy fallback",
            output: "",
            startRow: 2,
            endRow: 2
        )
        var toggledIDs: [UInt64] = []
        harness.view.onToggleCommandBlockBookmark = { block in
            toggledIDs.append(block.id)
        }
        harness.view.restoredCommandBlocksProvider = {
            [block, commandOnlyBlock]
        }
        harness.view.updateLocalizer(AppLocalizer(languagePreference: .spanish))

        harness.view.refreshCommandBlockOverlay()

        let overlay = try #require(harness.view.commandBlockOverlayView)
        #expect(overlay.isHidden == false)
        #expect(overlay.subviews.isEmpty == false)

        overlay.onCopyBlockOutput?(block)
        #expect(clipboard.writtenText == "overlay output")

        overlay.onCopyBlockOutput?(commandOnlyBlock)
        #expect(clipboard.writtenText == "copy fallback")

        overlay.onCopySelectedBlockOutputs?([block, commandOnlyBlock])
        #expect(clipboard.writtenText?.contains("overlay output") == true)

        let output = TestDataSink()
        harness.bridge.setOutputHandler(for: harness.surfaceID) { data in
            output.data.append(data)
        }
        overlay.onRerunBlock?(block)
        try await waitUntil {
            String(data: output.data, encoding: .utf8)?.contains("overlay-rerun") == true
        }

        overlay.onToggleBookmark?(block)
        #expect(toggledIDs == [41])
    }

    @Test("Option-generated printable characters are sent as literal text")
    func optionGeneratedPrintableCharactersAreLiteralText() {
        #expect(
            CocxyCoreView.literalTextForOptionGeneratedCharacter(
                characters: "@",
                charactersIgnoringModifiers: "2",
                modifiers: .option
            ) == "@"
        )
        #expect(
            CocxyCoreView.literalTextForOptionGeneratedCharacter(
                characters: "€",
                charactersIgnoringModifiers: "e",
                modifiers: .option
            ) == "€"
        )
        #expect(
            CocxyCoreView.literalTextForOptionGeneratedCharacter(
                characters: "|",
                charactersIgnoringModifiers: "1",
                modifiers: .option
            ) == "|"
        )
        #expect(
            CocxyCoreView.literalTextForOptionGeneratedCharacter(
                characters: "\\",
                charactersIgnoringModifiers: "ç",
                modifiers: .option
            ) == "\\"
        )
        #expect(
            CocxyCoreView.literalTextForOptionGeneratedCharacter(
                characters: "b",
                charactersIgnoringModifiers: "b",
                modifiers: .option
            ) == nil
        )
        #expect(
            CocxyCoreView.literalTextForOptionGeneratedCharacter(
                characters: "@",
                charactersIgnoringModifiers: "2",
                modifiers: [.option, .command]
            ) == nil
        )
    }
}

@MainActor
private final class RecordingClipboardService: ClipboardServiceProtocol {
    private let readText: String?
    private(set) var readCallCount = 0
    private(set) var writtenText: String?

    init(readText: String?) {
        self.readText = readText
    }

    func read() -> String? {
        readCallCount += 1
        return readText
    }

    func write(_ text: String) {
        writtenText = text
    }

    func clear() {
        writtenText = nil
    }
}

@MainActor
private final class MenuActionTarget: NSObject {
    private(set) var didInvoke = false

    @objc func toggleCodeReview(_ sender: Any?) {
        didInvoke = true
    }
}

private final class MockDraggingInfo: NSObject, NSDraggingInfo {
    private let pasteboard: NSPasteboard

    init(fileURLs: [URL]) {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("cocxy-file-drop-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { NSImage(size: NSSize(width: 1, height: 1)) }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}

    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? {
        nil
    }

    func resetSpringLoading() {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
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
    charactersIgnoringModifiers: String? = nil,
    modifiers: NSEvent.ModifierFlags = [],
    keyCode: UInt16 = 15
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        characters: characters,
        charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters.lowercased(),
        isARepeat: false,
        keyCode: keyCode
    )!
}

private func makeMouseEvent(
    type: NSEvent.EventType,
    location: NSPoint,
    clickCount: Int = 1
) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: clickCount,
        pressure: 1
    )!
}

private func makeScrollEvent(deltaY: CGFloat) -> NSEvent {
    let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 1,
        wheel1: Int32(deltaY),
        wheel2: 0,
        wheel3: 0
    )!
    event.location = NSPoint(x: 10, y: 10)
    return NSEvent(cgEvent: event)!
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private func numberedTerminalLines(_ count: Int) -> String {
    (0..<count)
        .map { "line-\($0)" }
        .joined(separator: "\r\n") + "\r\n"
}

private func makeCommandBlock(
    id: UInt64,
    command: String,
    output: String,
    startRow: UInt32,
    endRow: UInt32
) -> TerminalCommandBlock {
    TerminalCommandBlock(
        id: id,
        command: command,
        output: output,
        exitCode: 0,
        pwd: "/tmp/project",
        startTimeNs: 100,
        endTimeNs: 200,
        durationNs: 100,
        startRow: startRow,
        endRow: endRow,
        streamID: 1,
        blockType: 3
    )
}

private func makeTerminalConfig(themePalette: ThemePalette? = nil) -> TerminalEngineConfig {
    TerminalEngineConfig(
        fontFamily: "Menlo",
        fontSize: 14,
        themeName: "Test",
        shell: "/bin/zsh",
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        themePalette: themePalette,
        windowPaddingX: 8,
        windowPaddingY: 4
    )
}

private func makeTerminalPalette(background: String) -> ThemePalette {
    ThemePalette(
        background: background,
        foreground: "#cdd6f4",
        cursor: "#f5e0dc",
        selectionBackground: "#585b70",
        selectionForeground: "#cdd6f4",
        tabActiveBackground: background,
        tabActiveForeground: "#cdd6f4",
        tabInactiveBackground: "#181825",
        tabInactiveForeground: "#6c7086",
        badgeAttention: "#f9e2af",
        badgeCompleted: "#a6e3a1",
        badgeError: "#f38ba8",
        badgeWorking: "#89b4fa",
        ansiColors: [
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
            "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"
        ]
    )
}
