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
