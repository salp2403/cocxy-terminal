// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyCoreView.swift - NSView that hosts a CocxyCore terminal surface with Metal rendering.

import AppKit
import CocxyCommandCorrections
import CocxyCoreKit

// MARK: - CocxyCore View

/// NSView subclass that hosts a CocxyCore terminal with Metal-accelerated rendering.
///
/// It owns:
/// - A `CAMetalLayer` for GPU rendering.
/// - A `MetalTerminalRenderer` that draws CocxyCore's frame data.
/// - Keyboard, mouse, and scroll event forwarding to `CocxyCoreBridge`.
/// - NSTextInputClient conformance for IME composition.
/// - A CVDisplayLink-based render loop.
///
/// ## Coordinate system
///
/// The view is flipped (`isFlipped = true`) to match CocxyCore's top-left
/// origin coordinate system and Metal's clip-space convention.
///
/// ## Event routing
///
/// Keyboard events follow the terminal host-view classification pipeline:
/// 1. `KeyInputAction.classify()` → .copy, .paste, .selectAll, .clearScreen, .sendToTerminal
/// 2. Special keys (arrows, backspace, enter, etc.) → `cocxycore_terminal_encode_key()`
/// 3. Regular characters → `cocxycore_terminal_encode_char()`
/// 4. Ctrl+letter → compute control character directly
/// 5. Unhandled → fall through to `interpretKeyEvents()` (NSTextInputClient)
///
/// Mouse events drive CocxyCore's selection model:
/// - mouseDown sets the selection anchor
/// - mouseDragged extends the selection
/// - mouseUp copies to clipboard (if auto-copy enabled)
@MainActor
final class CocxyCoreView: NSView {

    // MARK: - Properties

    /// Bridge reference for terminal I/O.
    weak var bridge: CocxyCoreBridge?

    /// Surface ID for this view's terminal session.
    var surfaceID: SurfaceID?

    /// ViewModel for state tracking (title, font size, running state).
    private(set) weak var viewModel: TerminalViewModel?

    /// Metal renderer consuming CocxyCore frame data.
    private var renderer: MetalTerminalRenderer?

    /// Clipboard service for Cmd+C/V operations.
    var clipboardService: ClipboardServiceProtocol = SystemClipboardService()

    /// Localized copy for native context menus owned by this view.
    private var localizer: AppLocalizer

    /// Closure called when the user submits input (Enter key).
    var onUserInputSubmitted: (() -> Void)?

    /// Closure fired once after the next successful Metal frame commit.
    var onFramePresented: (() -> Void)?

    /// Closure called when the user directly interacts with this
    /// surface and expects it to become the focused split. The window
    /// controller uses this to keep split-manager focus, the top tab
    /// strip, Aurora sidebar/status and agent overlays in sync with
    /// AppKit first-responder changes.
    var onFocusRequested: (() -> Void)?

    /// Returns whether scroll gestures should move Cocxy's viewport even
    /// while the foreground process has enabled terminal mouse tracking.
    var prefersLocalScrollInMouseTrackingMode: (() -> Bool)?

    /// Returns whether delete-key autorepeat should be paced because the
    /// foreground prompt is an agent UI. This keeps agent prompt editing
    /// controllable even when the TUI has not enabled alt-screen or mouse
    /// tracking flags.
    var prefersPacedDeleteRepeat: (() -> Bool)?

    /// Returns whether large paste delivery should use conservative chunks
    /// for agent prompts. Agent TUIs often parse paste incrementally while
    /// updating their own prompt UI, so they need more breathing room than
    /// a shell reading from the PTY.
    var prefersPacedPasteDelivery: (() -> Bool)?

    /// Gives the host a chance to present a rich composer for complex
    /// agent input instead of writing a large or image-backed paste directly
    /// into the PTY.
    var onRichInputRequested: ((TerminalRichInputRequest) -> Bool)?

    /// Closure called when files are dropped onto the terminal.
    var onFileDrop: (([URL]) -> Bool)?

    /// Optional output buffer provider retained for controller integrations
    /// such as Smart Copy. Selection content still has priority, but this
    /// hook preserves feature wiring for host-driven actions.
    var outputBufferProvider: (() -> [String])?

    /// Persisted command blocks for a restored tab before CocxyCore has
    /// produced new live block metadata in the current process.
    var restoredCommandBlocksProvider: (() -> [TerminalCommandBlock])?

    /// Host callback used to persist bookmark toggles for command blocks.
    var onToggleCommandBlockBookmark: ((TerminalCommandBlock) -> Void)?

    /// IDE-like cursor positioning support for shell prompts.
    private(set) lazy var ideCursorController = IDECursorController(
        hostView: self,
        fontSizeProvider: { [weak self] in
            self?.viewModel?.currentFontSize ?? 14.0
        },
        cursorPositionProvider: { [weak self] in
            guard let self = self,
                  let bridge = self.bridge,
                  let sid = self.surfaceID else { return nil }
            return bridge.cursorPosition(for: sid)
        },
        arrowKeySender: { [weak self] arrows in
            self?.sendArrowKeys(arrows)
        }
    )

    // MARK: - Notification Ring

    private var notificationRingLayer: CAShapeLayer?
    private(set) var isNotificationRingActive: Bool = false

    // MARK: - Command Block Overlay

    private(set) var commandBlockOverlayView: TerminalBlockOverlayView?

    // MARK: - Command Corrections

    private(set) var pendingCommandCorrection: CommandCorrection?
    private var commandCorrectionSuggestionView: CommandCorrectionSuggestionView?
    private var commandCorrectionShowsConfidenceBadge = true

    // MARK: - Display Link

    private var displayLink: CVDisplayLink?
    internal var isDisplayLinkRunningForTests: Bool { displayLink != nil }

    /// Whether the render loop must produce a new frame on the next tick.
    ///
    /// Set to `true` by `setNeedsTerminalDisplay()` (invoked from the bridge
    /// after PTY output or from resize paths) and cleared inside
    /// `renderFrame()`. `renderFrame()` re-arms it automatically whenever
    /// `MetalTerminalRenderer.draw(...)` bails early, so a transient
    /// failure (no drawable, lost race with PTY feed) cannot freeze the
    /// view indefinitely.
    ///
    /// Exposed as `internal` for `@testable import` so the re-arm contract
    /// can be verified without going through the display link.
    internal var needsRender: Bool = false
    private let renderScheduleLock = NSLock()
    internal private(set) var renderScheduled: Bool = false

    // MARK: - Input State

    /// IME composition state.
    private var compositionState = TextCompositionState()

    /// Whether the view currently has keyboard focus.
    private(set) var isFocused: Bool = false

    /// Active async paste delivery, used to keep large clipboard writes from
    /// monopolizing the main thread while an agent TUI is reading from the PTY.
    private var pasteDeliveryTask: Task<Void, Never>?
    private var activeBracketedPasteSurfaceID: SurfaceID?
    private var activeBracketedPasteSessionID: UUID?

    /// Last dispatched repeated delete key event by hardware key code.
    private var repeatedDeleteDispatchTimestamps: [UInt16: TimeInterval] = [:]

    // MARK: - Selection State

    /// Anchor point for mouse-drag text selection (absolute history row, col).
    private var selectionAnchor: (row: UInt32, col: UInt16)?

    /// Whether a drag selection is in progress.
    private var isDragging: Bool = false

    // MARK: - Layout Tracking

    /// Last backing-pixel size sent to the bridge, prevents redundant resize calls.
    private var lastNotifiedBackingSize: NSSize = .zero

    /// Observes screen changes on the hosting window so terminal metrics can be
    /// recalculated immediately when the view moves between displays.
    private var windowScreenObserver: NSObjectProtocol?

    // MARK: - Constants

    private static let scrollSpeedFactor: CGFloat = 0.15
    static let defaultPasteChunkMaxUTF8Bytes = 512
    static let agentPasteChunkMaxUTF8Bytes = 128
    private static let pasteChunkMaxUTF8Bytes = defaultPasteChunkMaxUTF8Bytes
    private static let pasteChunkDelayNanoseconds: UInt64 = 6_000_000
    private static let agentPasteChunkDelayNanoseconds: UInt64 = 18_000_000
    private static let repeatedDeleteMinimumInterval: TimeInterval = 0.095
    private static let agentRepeatedDeleteMinimumInterval: TimeInterval = 0.145
    private static let throttledDeleteKeyCodes: Set<UInt16> = [51, 117]

    private var contentPadding: (x: CGFloat, y: CGFloat) {
        guard let bridge else { return (8, 4) }
        return (bridge.configuredPaddingX, bridge.configuredPaddingY)
    }

    // MARK: - Initialization

    init(
        viewModel: TerminalViewModel? = nil,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.viewModel = viewModel
        self.localizer = localizer
        super.init(frame: .zero)
        wantsLayer = true
        applyTerminalBackingBackground()
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CocxyCoreView does not support NSCoding")
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        commandBlockOverlayView?.updateLocalizer(localizer)
        if let pendingCommandCorrection {
            commandCorrectionSuggestionView?.update(
                correction: pendingCommandCorrection,
                showConfidenceBadge: commandCorrectionShowsConfidenceBadge,
                localizer: localizer
            )
        }
    }

    deinit {
        MainActor.assumeIsolated {
            pasteDeliveryTask?.cancel()
            removeWindowObservers()
            stopDisplayLink()
        }
    }

    // MARK: - Layer Configuration

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isHidden: Bool {
        didSet {
            updateDisplayLinkRunningState()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let commandFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if commandFlags.contains(.command),
           let menu = NSApp.mainMenu,
           menu.performKeyEquivalent(with: event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func makeBackingLayer() -> CALayer {
        let metalLayer = CAMetalLayer()
        metalLayer.device = MTLCreateSystemDefaultDevice()
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.displaySyncEnabled = true
        // The terminal surface always paints an opaque background colour
        // (clearColor.alpha == 1.0 in MetalTerminalRenderer). Anchor the
        // layer's opacity here so AppKit cannot flip it to non-opaque
        // when the hosting window is translucent (background-opacity < 1).
        // Without this anchor, any transient frame failure during a heavy
        // burst of agent output or a full repaint composes the layer
        // against whatever sits behind the window —
        // showing the desktop straight through the terminal — instead of
        // keeping the previous valid frame visible.
        metalLayer.isOpaque = true
        metalLayer.backgroundColor = CocxyColors.base.cgColor
        return metalLayer
    }

    // MARK: - Setup

    /// Configures the view with a bridge and surface. Call after createSurface.
    func configure(bridge: CocxyCoreBridge, surfaceID: SurfaceID, viewModel: TerminalViewModel) {
        self.bridge = bridge
        self.surfaceID = surfaceID
        self.viewModel = viewModel
        applyTerminalBackingBackground()
        refreshIDECursorMetrics()

        do {
            renderer = try MetalTerminalRenderer(
                device: (layer as? CAMetalLayer)?.device
            )
        } catch {
            assertionFailure("MetalTerminalRenderer init failed: \(error)")
        }

        installCommandBlockOverlayIfNeeded()
        refreshBackingConfiguration(forceGridSync: true)
        updateDisplayLinkRunningState()
    }

    // MARK: - Render Loop

    /// Retained self pointer for the CVDisplayLink callback. Released in stopDisplayLink.
    private var displayLinkSelfPtr: UnsafeMutableRawPointer?

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        // passRetained prevents use-after-free if the display link callback
        // fires between deinit starting and stopDisplayLink completing.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        displayLinkSelfPtr = selfPtr
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnError }
            let view = Unmanaged<CocxyCoreView>.fromOpaque(userInfo).takeUnretainedValue()
            if view.claimRenderSlotForDisplayLink() {
                DispatchQueue.main.async {
                    view.renderFrame()
                    view.finishRenderSlotForDisplayLink()
                }
            }
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        if let ptr = displayLinkSelfPtr {
            Unmanaged<CocxyCoreView>.fromOpaque(ptr).release()
            displayLinkSelfPtr = nil
        }
        displayLink = nil
    }

    /// Mark that a new frame is available for rendering.
    /// Called from CocxyCoreBridge after PTY data is processed.
    func setNeedsTerminalDisplay() {
        needsRender = true
        updateDisplayLinkRunningState()
    }

    internal func claimRenderSlotForDisplayLink() -> Bool {
        renderScheduleLock.lock()
        defer { renderScheduleLock.unlock() }
        guard needsRender, !renderScheduled else { return false }
        renderScheduled = true
        return true
    }

    internal func finishRenderSlotForDisplayLink() {
        renderScheduleLock.lock()
        renderScheduled = false
        renderScheduleLock.unlock()
    }

    /// Runs one render cycle. Called from the CVDisplayLink callback (see
    /// `startDisplayLink()`) and also from tests via `@testable import` to
    /// verify the `needsRender` re-arm contract directly without having to
    /// wait on the display link.
    internal func renderFrame() {
        guard let bridge = bridge,
              let sid = surfaceID,
              let state = bridge.surfaceState(for: sid),
              let renderer = renderer,
              let metalLayer = layer as? CAMetalLayer
        else {
            // Prerequisites missing. Clearing the flag here is safe because
            // whatever creates these prerequisites will re-arm it.
            needsRender = false
            return
        }

        // Optimistically clear the flag, then re-arm if the renderer bailed.
        // `draw()` returns `false` when any stage failed silently: resources
        // unavailable, `nextDrawable()` returned `nil`, encoder creation
        // failed, or `prepareFrameResources` returned `false` due to a race
        // with the PTY feed loop. Without this re-arm, the display link sees
        // `needsRender == false` forever and the surface freezes until
        // something external (tab switch, resize, new PTY output) re-sets
        // the flag. That was the root cause of the transparent-on-display-
        // change and transparent-on-agent-launch bugs.
        needsRender = false
        let drawn = renderer.draw(
            terminal: state.terminal,
            layer: metalLayer,
            terminalLock: state.terminalLock
        )
        if !drawn {
            needsRender = true
        } else if let onFramePresented {
            self.onFramePresented = nil
            onFramePresented()
        }
    }

    // MARK: - Layout & Resize

    override func layout() {
        super.layout()
        guard surfaceID != nil else { return }

        updateMetalViewportForCurrentScale()

        let currentBacking = convertToBacking(bounds).size
        if currentBacking != lastNotifiedBackingSize {
            syncSizeWithTerminal()
        }

        refreshIDECursorMetrics()
        updateNotificationRingFrame()
        commandBlockOverlayView?.frame = bounds
        layoutCommandCorrectionSuggestion()
        refreshCommandBlockOverlay()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifySizeChanged(newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshBackingConfiguration(forceGridSync: true)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow !== window {
            removeWindowObservers()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installWindowObserversIfNeeded()
        refreshBackingConfiguration(forceGridSync: true)
        updateDisplayLinkRunningState()
    }

    /// Forces a size sync after surface creation.
    func syncSizeWithTerminal() {
        notifySizeChanged(bounds.size)
    }

    private func notifySizeChanged(_ newSize: NSSize) {
        guard let bridge = bridge, let sid = surfaceID else { return }

        let backingSize = convertToBacking(NSRect(origin: .zero, size: newSize)).size
        guard backingSize != lastNotifiedBackingSize,
              backingSize.width > 0, backingSize.height > 0 else { return }
        lastNotifiedBackingSize = backingSize

        // CocxyCore needs rows/cols, not just pixels. Calculate from font metrics.
        guard let state = bridge.surfaceState(for: sid) else { return }
        var metrics = cocxycore_font_metrics()
        guard cocxycore_terminal_get_font_metrics(state.terminal, &metrics),
              metrics.cell_width > 0, metrics.cell_height > 0 else { return }

        let scale = Float(currentBackingScale())
        let padding = contentPadding
        let paddingX = Float(padding.x) * scale
        let paddingY = Float(padding.y) * scale
        let availableWidth = Float(backingSize.width) - paddingX * 2
        let availableHeight = Float(backingSize.height) - paddingY * 2

        let cols = UInt16(max(1, availableWidth / metrics.cell_width))
        let rows = UInt16(max(1, availableHeight / metrics.cell_height))

        let terminalSize = TerminalSize(
            columns: cols,
            rows: rows,
            pixelWidth: UInt16(backingSize.width),
            pixelHeight: UInt16(backingSize.height)
        )
        bridge.resize(sid, to: terminalSize)
        renderer?.updateGridSize(rows: rows, cols: cols)
        requestImmediateRedraw()
    }

    private func currentBackingScale() -> CGFloat {
        window?.backingScaleFactor
            ?? window?.screen?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
    }

    private func updateMetalViewportForCurrentScale() {
        guard let metalLayer = layer as? CAMetalLayer else { return }
        let scale = currentBackingScale()

        // Apply both layer mutations inside a single CATransaction with
        // implicit animations disabled. Without this, Core Animation can
        // interpolate `contentsScale` / `drawableSize` across a frame,
        // leaving the drawable temporarily inconsistent with the layer's
        // advertised size. That inconsistency is one of the reasons
        // `nextDrawable()` returns nil mid-display-transition.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        CATransaction.commit()

        renderer?.updateViewportSize(
            bounds.size,
            scale: scale,
            paddingX: Float(contentPadding.x),
            paddingY: Float(contentPadding.y)
        )
    }

    /// Re-anchors the CVDisplayLink to the display currently hosting the
    /// window. The display link is created with the active display set at
    /// construction time and does not follow the window when it moves to a
    /// different screen. Without re-anchoring, it keeps ticking at the old
    /// display's refresh rate (and can skip ticks entirely if the old
    /// display is asleep), contributing to the "transparent on display
    /// change" symptom. Silent no-op if the current display can't be
    /// resolved — the MainWindowController delegate path is the backup.
    private func anchorDisplayLinkToCurrentScreen() {
        guard let link = displayLink,
              let screen = window?.screen,
              let screenNumber = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
              ] as? NSNumber
        else { return }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        CVDisplayLinkSetCurrentCGDisplay(link, displayID)
    }

    private func updateDisplayLinkRunningState() {
        guard surfaceID != nil else {
            stopDisplayLink()
            return
        }

        if window != nil, !isHiddenOrHasHiddenAncestor {
            startDisplayLink()
            anchorDisplayLinkToCurrentScreen()
        } else {
            stopDisplayLink()
        }
    }

    private func refreshBackingConfiguration(forceGridSync: Bool) {
        updateMetalViewportForCurrentScale()
        anchorDisplayLinkToCurrentScreen()
        if let bridge, let sid = surfaceID {
            bridge.reapplyConfiguredFont(to: sid)
        }
        if forceGridSync {
            updateInteractionMetrics()
        } else {
            refreshIDECursorMetrics()
        }
        updateNotificationRingFrame()
        requestImmediateRedraw()
    }

    private func installWindowObserversIfNeeded() {
        guard windowScreenObserver == nil, let window else { return }
        windowScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // The observer block already runs on the main queue. Posting
            // through `Task { @MainActor }` added an unnecessary run-loop
            // hop that could land after the display link had already dropped
            // a tick, so we refresh synchronously and schedule a second
            // pass on the next tick as a safety net for cases where the
            // backing scale is still being committed when the notification
            // fires.
            MainActor.assumeIsolated {
                self?.refreshBackingConfiguration(forceGridSync: true)
            }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.refreshBackingConfiguration(forceGridSync: true)
                }
            }
        }
    }

    private func removeWindowObservers() {
        if let windowScreenObserver {
            NotificationCenter.default.removeObserver(windowScreenObserver)
            self.windowScreenObserver = nil
        }
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        isFocused = true
        if let bridge, let sid = surfaceID {
            bridge.notifyFocus(true, for: sid)
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        if let bridge, let sid = surfaceID {
            bridge.notifyFocus(false, for: sid)
        }
        return true
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard let bridge = bridge, let sid = surfaceID else {
            super.keyDown(with: event)
            return
        }

        let modifiers = Self.translateModifierFlags(event.modifierFlags)
        let action = KeyInputAction.classify(
            keyCode: event.keyCode,
            modifiers: modifiers,
            characters: event.characters
        )

        if action == .sendToTerminal,
           modifiers.contains(.command),
           performKeyEquivalent(with: event) {
            return
        }

        NSCursor.setHiddenUntilMouseMoves(true)

        switch action {
        case .copy:
            handleCopy()
            return
        case .paste:
            handlePaste()
            return
        case .selectAll, .clearScreen:
            let keyEvent = Self.translateKeyEvent(event, isKeyDown: true)
            bridge.sendKeyEvent(keyEvent, to: sid)
            return
        case .sendToTerminal:
            if handlePendingCommandCorrectionShortcut(
                event,
                bridge: bridge,
                surfaceID: sid,
                modifiers: modifiers
            ) {
                return
            }
            if shouldThrottleTerminalDeleteRepeat(event, bridge: bridge, surfaceID: sid) {
                return
            }
            handleTerminalInput(event, bridge: bridge, surfaceID: sid, modifiers: modifiers)
        }
    }

    override func keyUp(with event: NSEvent) {
        // CocxyCore's encode_key only handles key-down. Key-up is a no-op.
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func handleTerminalInput(
        _ event: NSEvent,
        bridge: CocxyCoreBridge,
        surfaceID sid: SurfaceID,
        modifiers: KeyModifiers
    ) {
        followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)

        if let literalText = Self.literalTextForOptionGeneratedCharacter(
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: modifiers
        ) {
            bridge.sendText(literalText, to: sid)
            return
        }

        // Shift+Return: multiline prompt UIs expect a newline that does
        // NOT submit the prompt. Encode it explicitly so the chord is
        // reported as the kitty keyboard CSI 13;2u when the protocol is
        // active, or as a single LF when it is not. Plain Return arrives
        // unchanged as CR via the regular dispatch below, preserving the
        // "submit" semantics every shell and TUI already relies on.
        if let state = bridge.surfaceState(for: sid),
           let bytes = MultilineEnterEncoder.bytes(
               keyCode: event.keyCode,
               modifiers: modifiers,
               kittyKeyboardActive: cocxycore_terminal_mode_kitty_keyboard(state.terminal) > 0
           ) {
            _ = bridge.writeBytes(bytes, to: sid)
            return
        }

        // Ctrl+letter → compute ASCII control character directly.
        if modifiers.contains(.control),
           !modifiers.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 0x61, scalar.value <= 0x7A {
            let controlCode = UInt8(scalar.value - 0x60)
            _ = bridge.writeBytes([controlCode], to: sid)
            return
        }

        // Use CocxyCore's mode-aware encoder for all other keys.
        let keyEvent = KeyEvent(
            characters: event.characters,
            keyCode: event.keyCode,
            modifiers: modifiers,
            isKeyDown: true,
            isRepeat: event.isARepeat
        )

        let handled = bridge.sendKeyEvent(keyEvent, to: sid)
        if !handled {
            interpretKeyEvents([event])
        } else {
            updateIDECursorState(afterHandling: event)
        }
    }

    // MARK: - Text Command Handlers (NSResponder)

    private func sendControlSequence(_ seq: String) {
        guard let bridge = bridge, let sid = surfaceID else { return }
        followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
        bridge.sendText(seq, to: sid)
    }

    private func sendArrowKeys(_ arrows: [ArrowDirection]) {
        guard !arrows.isEmpty, let bridge, let sid = surfaceID else { return }
        followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
        // Route arrow key synthesis through the bridge's key event path
        // so the terminal emits the correct CSI/SS3 escape sequence for
        // its current keypad / cursor mode.
        //
        // Sending raw `\e[D` / `\e[C` here would bypass the terminal's
        // mode flags and cause shells in application keypad mode — which
        // every popular zsh framework (Prezto, Powerlevel10k, oh-my-zsh,
        // YADR, Spaceship, Starship) enables by default — to ignore the
        // synthesized arrows. That was the root cause of the v0.1.52
        // click-to-position bug where the IDE blink moved to the click
        // position but the real shell cursor stayed at the end of the
        // line.
        for arrow in arrows {
            // macOS hardware key codes for the arrow keys:
            // 123 → NSLeftArrowFunctionKey, 124 → NSRightArrowFunctionKey.
            let keyCode: UInt16 = arrow == .left ? 123 : 124
            let keyEvent = KeyEvent(
                characters: nil,
                keyCode: keyCode,
                modifiers: [],
                isKeyDown: true
            )
            _ = bridge.sendKeyEvent(keyEvent, to: sid)
        }
    }

    private func updateIDECursorState(afterHandling event: NSEvent) {
        switch event.keyCode {
        case 0x7C: // Right arrow
            if ideCursorController.isOnPromptLine {
                ideCursorController.cursorMoved(toColumn: ideCursorController.cursorColumn + 1)
            }
        case 0x7B: // Left arrow
            if ideCursorController.isOnPromptLine {
                let newColumn = max(
                    ideCursorController.promptColumn,
                    ideCursorController.cursorColumn - 1
                )
                ideCursorController.cursorMoved(toColumn: newColumn)
            }
        case 0x24: // Return / Enter
            if !event.modifierFlags.contains(.shift) {
                ideCursorController.commandExecuted()
            }
            onUserInputSubmitted?()
        default:
            break
        }
    }

    override func deleteBackward(_ sender: Any?) { sendControlSequence("\u{7F}") }
    override func deleteForward(_ sender: Any?) { sendControlSequence("\u{1B}[3~") }
    override func moveUp(_ sender: Any?) { sendControlSequence("\u{1B}[A") }
    override func moveDown(_ sender: Any?) { sendControlSequence("\u{1B}[B") }
    override func moveRight(_ sender: Any?) {
        if ideCursorController.isOnPromptLine {
            ideCursorController.cursorMoved(toColumn: ideCursorController.cursorColumn + 1)
        }
        sendControlSequence("\u{1B}[C")
    }
    override func moveLeft(_ sender: Any?) {
        if ideCursorController.isOnPromptLine {
            let newColumn = max(
                ideCursorController.promptColumn,
                ideCursorController.cursorColumn - 1
            )
            ideCursorController.cursorMoved(toColumn: newColumn)
        }
        sendControlSequence("\u{1B}[D")
    }
    override func moveToBeginningOfLine(_ sender: Any?) { sendControlSequence("\u{1B}[H") }
    override func moveToEndOfLine(_ sender: Any?) { sendControlSequence("\u{1B}[F") }
    override func insertTab(_ sender: Any?) { sendControlSequence("\t") }
    override func insertNewline(_ sender: Any?) {
        ideCursorController.commandExecuted()
        onUserInputSubmitted?()
        sendControlSequence("\r")
    }
    override func noResponder(for eventSelector: Selector) {}

    // MARK: - Command Corrections

    func presentCommandCorrection(
        _ correction: CommandCorrection,
        showConfidenceBadge: Bool = true
    ) {
        pendingCommandCorrection = correction
        commandCorrectionShowsConfidenceBadge = showConfidenceBadge

        let suggestionView: CommandCorrectionSuggestionView
        if let existing = commandCorrectionSuggestionView {
            suggestionView = existing
        } else {
            let view = CommandCorrectionSuggestionView(localizer: localizer)
            view.autoresizingMask = [.width, .minYMargin]
            addSubview(view)
            commandCorrectionSuggestionView = view
            suggestionView = view
        }

        suggestionView.update(
            correction: correction,
            showConfidenceBadge: showConfidenceBadge,
            localizer: localizer
        )
        layoutCommandCorrectionSuggestion()
    }

    func dismissCommandCorrection() {
        pendingCommandCorrection = nil
        commandCorrectionSuggestionView?.removeFromSuperview()
        commandCorrectionSuggestionView = nil
    }

    private func handlePendingCommandCorrectionShortcut(
        _ event: NSEvent,
        bridge: CocxyCoreBridge,
        surfaceID sid: SurfaceID,
        modifiers: KeyModifiers
    ) -> Bool {
        guard let correction = pendingCommandCorrection,
              modifiers.isEmpty else {
            return false
        }

        switch event.keyCode {
        case 48: // Tab
            followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
            bridge.sendText(correction.suggestion, to: sid)
            dismissCommandCorrection()
            return true
        case 53: // Escape
            dismissCommandCorrection()
            return true
        default:
            dismissCommandCorrection()
            return false
        }
    }

    private func layoutCommandCorrectionSuggestion() {
        guard let suggestionView = commandCorrectionSuggestionView else { return }
        let horizontalInset = max(12, contentPadding.x)
        let width = max(0, bounds.width - horizontalInset * 2)
        let height: CGFloat = 34
        let y = max(8, bounds.height - height - 12)
        suggestionView.frame = NSRect(
            x: horizontalInset,
            y: y,
            width: width,
            height: height
        )
    }

    // MARK: - Copy / Paste

    @objc func copy(_ sender: Any?) {
        handleCopy()
    }

    @objc func paste(_ sender: Any?) {
        handlePaste()
    }

    override func selectAll(_ sender: Any?) {
        guard let bridge = bridge, let sid = surfaceID else { return }
        let keyEvent = KeyEvent(
            characters: "a",
            keyCode: 0x00,
            modifiers: [.command],
            isKeyDown: true
        )
        bridge.sendKeyEvent(keyEvent, to: sid)
    }

    private func handleCopy() {
        guard let bridge = bridge, let sid = surfaceID else { return }
        if let text = bridge.readSelection(for: sid), !text.isEmpty {
            clipboardService.write(text)
        }
    }

    private func handlePaste() {
        guard let bridge = bridge, let sid = surfaceID else { return }

        switch clipboardService.readTerminalPastePayload() {
        case .text(let text):
            let normalizedText = Self.normalizedTerminalPasteText(text)
            if requestRichInputIfNeeded(text: normalizedText, fileURLs: []) {
                return
            }
            sendClipboardText(text, bridge: bridge, surfaceID: sid)
        case .fileURLs(let urls):
            if requestRichInputIfNeeded(text: "", fileURLs: urls) {
                return
            }
            sendClipboardText(
                FileDropPathFormatter.format(urls),
                bridge: bridge,
                surfaceID: sid
            )
        case nil:
            break
        }
    }

    private func requestRichInputIfNeeded(text: String, fileURLs: [URL]) -> Bool {
        guard prefersPacedPasteDelivery?() == true,
              let onRichInputRequested else {
            return false
        }

        let hasMultilineText = text.contains("\n")
        let hasAttachments = fileURLs.contains(where: Self.isLikelyRichInputImageURL(_:))
        guard hasMultilineText || hasAttachments else { return false }

        return onRichInputRequested(TerminalRichInputRequest(text: text, fileURLs: fileURLs))
    }

    func submitRichInputPayload(_ text: String) {
        guard let bridge = bridge, let sid = surfaceID else { return }
        sendClipboardText(text, bridge: bridge, surfaceID: sid)
    }

    private static func isLikelyRichInputImageURL(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "tif", "tiff", "gif", "heic", "heif", "webp":
            return true
        default:
            return false
        }
    }

    private func sendClipboardText(
        _ text: String,
        bridge: CocxyCoreBridge,
        surfaceID sid: SurfaceID
    ) {
        guard let state = bridge.surfaceState(for: sid) else { return }

        let usesBracketedPaste = cocxycore_terminal_mode_bracketed_paste(state.terminal)
        let normalizedText = Self.normalizedTerminalPasteText(text)
        let agentPacedPaste = prefersPacedPasteDelivery?() == true
        let chunks = Self.terminalPasteChunks(
            for: normalizedText,
            agentPaced: agentPacedPaste
        )
        guard !chunks.isEmpty else { return }

        closeActiveBracketedPasteIfNeeded(bridge: bridge)
        pasteDeliveryTask?.cancel()
        let pasteSessionID = UUID()
        pasteDeliveryTask = Task { @MainActor [weak self, weak bridge] in
            guard let self, let bridge else { return }
            self.followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
            defer {
                if self.activeBracketedPasteSessionID == pasteSessionID {
                    self.closeActiveBracketedPasteIfNeeded(bridge: bridge)
                }
            }
            guard !Task.isCancelled else { return }

            if usesBracketedPaste {
                bridge.sendText("\u{1B}[200~", to: sid)
                self.activeBracketedPasteSurfaceID = sid
                self.activeBracketedPasteSessionID = pasteSessionID
                await Self.sleepBetweenPasteChunksIfNeeded(
                    chunks.count,
                    agentPaced: agentPacedPaste
                )
            }

            for chunk in chunks {
                guard !Task.isCancelled,
                      bridge.surfaceState(for: sid) != nil else { return }
                bridge.sendText(chunk, to: sid)
                await Self.sleepBetweenPasteChunksIfNeeded(
                    chunks.count,
                    agentPaced: agentPacedPaste
                )
            }

            guard !Task.isCancelled,
                  bridge.surfaceState(for: sid) != nil else { return }
            if usesBracketedPaste {
                self.closeActiveBracketedPasteIfNeeded(bridge: bridge)
            }
        }
    }

    private func closeActiveBracketedPasteIfNeeded(bridge: CocxyCoreBridge) {
        guard let activeSurfaceID = activeBracketedPasteSurfaceID else { return }
        if bridge.surfaceState(for: activeSurfaceID) != nil {
            bridge.sendText("\u{1B}[201~", to: activeSurfaceID)
        }
        activeBracketedPasteSurfaceID = nil
        activeBracketedPasteSessionID = nil
    }

    nonisolated static func normalizedTerminalPasteText(_ text: String) -> String {
        let lineNormalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(lineNormalized.unicodeScalars.count)
        for scalar in lineNormalized.unicodeScalars {
            switch scalar.value {
            case 0x09, 0x0A:
                scalars.append(scalar)
            case 0x00...0x1F, 0x7F:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func terminalPasteChunks(for text: String) -> [String] {
        terminalPasteChunks(for: text, agentPaced: false)
    }

    static func terminalPasteChunks(for text: String, agentPaced: Bool) -> [String] {
        terminalPasteChunks(
            for: text,
            maxUTF8Bytes: agentPaced ? agentPasteChunkMaxUTF8Bytes : pasteChunkMaxUTF8Bytes
        )
    }

    static func terminalPasteChunks(
        for text: String,
        maxUTF8Bytes: Int
    ) -> [String] {
        guard maxUTF8Bytes > 0 else { return [text] }

        var chunks: [String] = []
        var current = ""
        var currentBytes = 0

        for character in text {
            let characterText = String(character)
            let byteCount = characterText.utf8.count
            if currentBytes > 0, currentBytes + byteCount > maxUTF8Bytes {
                chunks.append(current)
                current = ""
                currentBytes = 0
            }
            current.append(character)
            currentBytes += byteCount
        }

        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    private static func sleepBetweenPasteChunksIfNeeded(
        _ chunkCount: Int,
        agentPaced: Bool
    ) async {
        guard chunkCount > 1 else { return }
        let delay = agentPaced ? agentPasteChunkDelayNanoseconds : pasteChunkDelayNanoseconds
        try? await Task.sleep(nanoseconds: delay)
    }

    internal func shouldThrottleTerminalDeleteRepeat(
        _ event: NSEvent,
        bridge: CocxyCoreBridge,
        surfaceID sid: SurfaceID
    ) -> Bool {
        guard Self.throttledDeleteKeyCodes.contains(event.keyCode),
              let state = bridge.surfaceState(for: sid) else {
            return false
        }
        let shouldPaceRepeat = prefersPacedDeleteRepeat?() == true
            || cocxycore_terminal_is_alt_screen(state.terminal)
            || cocxycore_terminal_mode_mouse(state.terminal) > 0
        guard shouldPaceRepeat else { return false }
        let minimumInterval = prefersPacedDeleteRepeat?() == true
            ? Self.agentRepeatedDeleteMinimumInterval
            : Self.repeatedDeleteMinimumInterval

        let timestamp = event.timestamp > 0
            ? event.timestamp
            : ProcessInfo.processInfo.systemUptime
        guard event.isARepeat else {
            repeatedDeleteDispatchTimestamps[event.keyCode] = timestamp
            return false
        }

        guard let lastTimestamp = repeatedDeleteDispatchTimestamps[event.keyCode],
              timestamp >= lastTimestamp,
              timestamp - lastTimestamp < minimumInterval else {
            repeatedDeleteDispatchTimestamps[event.keyCode] = timestamp
            return false
        }
        return true
    }

    // MARK: - Mouse Input + Selection

    override func mouseDown(with event: NSEvent) {
        onFocusRequested?()

        guard let bridge = bridge, let sid = surfaceID,
              let state = bridge.surfaceState(for: sid) else {
            super.mouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        viewModel?.recordMouseDown(clickCount: event.clickCount)

        if event.clickCount == 1, ideCursorController.handleClickToPosition(at: location) {
            return
        }

        let pos = cellPosition(for: event, terminal: state.terminal)
        let historyStart = cocxycore_terminal_history_visible_start(state.terminal)
        let absoluteRow = historyStart + UInt32(pos.row)

        // Route the selection mutation through the bridge so it acquires
        // the per-surface terminal lock and cannot race with the background
        // PTY feed loop.
        bridge.clearSelection(for: sid)
        selectionAnchor = (row: absoluteRow, col: pos.col)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let bridge = bridge, let sid = surfaceID,
              let state = bridge.surfaceState(for: sid),
              let anchor = selectionAnchor else { return }

        isDragging = true
        let pos = cellPosition(for: event, terminal: state.terminal)
        let historyStart = cocxycore_terminal_history_visible_start(state.terminal)
        let absoluteRow = historyStart + UInt32(pos.row)

        // Route the selection mutation through the bridge so it acquires
        // the per-surface terminal lock and cannot race with the background
        // PTY feed loop.
        bridge.setSelection(
            for: sid,
            startRow: anchor.row,
            startCol: anchor.col,
            endRow: absoluteRow,
            endCol: pos.col
        )

        setNeedsTerminalDisplay()
    }

    override func mouseUp(with event: NSEvent) {
        viewModel?.recordMouseUp()

        guard let bridge = bridge, let sid = surfaceID,
              let state = bridge.surfaceState(for: sid) else { return }

        if isDragging && cocxycore_terminal_selection_active(state.terminal) {
            if viewModel?.autoCopyOnSelect == true {
                if let text = bridge.readSelection(for: sid), !text.isEmpty {
                    clipboardService.write(text)
                }
            }
        }

        isDragging = false
        selectionAnchor = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let bridge = bridge,
              let sid = surfaceID,
              let state = bridge.surfaceState(for: sid) else { return }

        let nearText = smartCopyContextText(
            for: event,
            bridge: bridge,
            surfaceID: sid,
            terminal: state.terminal
        )

        let menu = SmartCopyMenuBuilder.buildMenu(
            nearText: nearText,
            clipboardService: clipboardService,
            paste: { [weak bridge] in
                guard let bridge else { return }
                switch self.clipboardService.readTerminalPastePayload() {
                case .text(let text):
                    self.sendClipboardText(text, bridge: bridge, surfaceID: sid)
                case .fileURLs(let urls):
                    self.sendClipboardText(
                        FileDropPathFormatter.format(urls),
                        bridge: bridge,
                        surfaceID: sid
                    )
                case nil:
                    break
                }
            },
            localizer: localizer
        )
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Scroll

    override func scrollWheel(with event: NSEvent) {
        guard let bridge = bridge, let sid = surfaceID,
              let state = bridge.surfaceState(for: sid) else {
            super.scrollWheel(with: event)
            return
        }

        let mouseMode = cocxycore_terminal_mode_mouse(state.terminal)
        if mouseMode > 0 && !shouldScrollLocallyWhileMouseTracking(event) {
            // Terminal app is tracking mouse — forward scroll as mouse events
            let delta = event.scrollingDeltaY * Self.scrollSpeedFactor
            let button: UInt8 = delta > 0 ? 64 : 65 // scroll up / down
            let count = max(1, Int(abs(delta)))
            for _ in 0..<count {
                var buf = [UInt8](repeating: 0, count: 16)
                let n = encodeMouseButton(button, terminal: state.terminal, event: event, buf: &buf)
                if n > 0 {
                    _ = bridge.writeBytes(Array(buf.prefix(n)), to: sid)
                }
            }
            return
        }

        let scaledDelta = event.scrollingDeltaY * Self.scrollSpeedFactor
        guard scaledDelta != 0 else { return }

        let steps = max(1, Int(abs(scaledDelta.rounded(.towardZero))))
        let signedSteps = scaledDelta > 0 ? steps : -steps
        bridge.scrollViewport(surfaceID: sid, deltaRows: signedSteps)
        refreshCommandBlockOverlay()
    }

    private func shouldScrollLocallyWhileMouseTracking(_ event: NSEvent) -> Bool {
        if prefersLocalScrollInMouseTrackingMode?() == true {
            return true
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.contains(.option) || modifiers.contains(.shift)
    }

    private func followLiveViewportBeforeUserInput(
        bridge: CocxyCoreBridge,
        surfaceID: SurfaceID
    ) {
        bridge.scrollToLiveBottom(surfaceID: surfaceID)
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else { return [] }
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }

        if let handler = onFileDrop, handler(urls) { return true }

        if requestRichInputIfNeeded(text: "", fileURLs: urls) { return true }

        // Default: paste each file path as shell-escaped text so
        // terminal-aware CLIs treat the drop as a single argument and
        // trigger their image / file detection. The payload follows the
        // canonical macOS shell-escape convention so the receiving
        // process sees the same bytes it receives from any other native
        // terminal on the platform.
        let paths = FileDropPathFormatter.format(urls)
        guard let bridge = bridge, let sid = surfaceID else { return false }
        followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
        bridge.sendText(paths, to: sid)
        return true
    }

    // MARK: - Coordinate Conversion

    /// Converts a mouse event location to terminal cell coordinates.
    private func cellPosition(
        for event: NSEvent,
        terminal: OpaquePointer
    ) -> (row: UInt16, col: UInt16) {
        let location = convert(event.locationInWindow, from: nil)
        var metrics = cocxycore_font_metrics()
        guard cocxycore_terminal_get_font_metrics(terminal, &metrics),
              metrics.cell_width > 0, metrics.cell_height > 0 else {
            return (0, 0)
        }

        let scale = Float(currentBackingScale())
        let padding = contentPadding
        let paddingX = Float(padding.x)
        let paddingY = Float(padding.y)

        let col = UInt16(max(0, (Float(location.x) - paddingX) / (metrics.cell_width / scale)))
        let row = UInt16(max(0, (Float(location.y) - paddingY) / (metrics.cell_height / scale)))

        let maxCol = cocxycore_terminal_cols(terminal)
        let maxRow = cocxycore_terminal_rows(terminal)

        return (
            row: min(row, maxRow > 0 ? maxRow - 1 : 0),
            col: min(col, maxCol > 0 ? maxCol - 1 : 0)
        )
    }

    /// Encode a mouse button event for SGR mouse mode.
    private func encodeMouseButton(
        _ button: UInt8,
        terminal: OpaquePointer,
        event: NSEvent,
        buf: inout [UInt8]
    ) -> Int {
        let pos = cellPosition(for: event, terminal: terminal)
        let seq = "\u{1B}[<\(button);\(pos.col + 1);\(pos.row + 1)M"
        let bytes = Array(seq.utf8)
        let count = min(bytes.count, buf.count)
        buf.replaceSubrange(0..<count, with: bytes[0..<count])
        return count
    }

    private func smartCopyContextText(
        for event: NSEvent,
        bridge: CocxyCoreBridge,
        surfaceID: SurfaceID,
        terminal: OpaquePointer
    ) -> String {
        if let selectedText = bridge.readSelection(for: surfaceID),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selectedText
        }

        let pos = cellPosition(for: event, terminal: terminal)
        if let visibleLine = bridge.visibleLineText(for: surfaceID, visibleRow: pos.row),
           !visibleLine.isEmpty {
            return visibleLine
        }

        if let fallbackLine = outputBufferProvider?().last, !fallbackLine.isEmpty {
            return fallbackLine
        }

        return clipboardService.read() ?? ""
    }

    private func refreshIDECursorMetrics() {
        guard let bridge = bridge,
              let sid = surfaceID,
              let state = bridge.surfaceState(for: sid) else {
            ideCursorController.updateCellDimensions()
            return
        }

        var metrics = cocxycore_font_metrics()
        guard cocxycore_terminal_get_font_metrics(state.terminal, &metrics),
              metrics.cell_width > 0,
              metrics.cell_height > 0 else {
            ideCursorController.updateCellDimensions()
            return
        }

        let scale = currentBackingScale()
        ideCursorController.setCellDimensions(
            width: CGFloat(metrics.cell_width) / scale,
            height: CGFloat(metrics.cell_height) / scale
        )
        let padding = contentPadding
        ideCursorController.leftPadding = padding.x
        ideCursorController.topPadding = padding.y
    }

    // MARK: - Static Helpers

    static func translateModifierFlags(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers = KeyModifiers()
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option)  { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    static func translateKeyEvent(_ event: NSEvent, isKeyDown: Bool) -> KeyEvent {
        KeyEvent(
            characters: event.characters,
            keyCode: event.keyCode,
            modifiers: translateModifierFlags(event.modifierFlags),
            isKeyDown: isKeyDown,
            isRepeat: event.isARepeat
        )
    }

    static func literalTextForOptionGeneratedCharacter(
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: KeyModifiers
    ) -> String? {
        guard modifiers.contains(.option),
              !modifiers.contains(.command),
              !modifiers.contains(.control),
              let characters,
              !characters.isEmpty,
              characters != charactersIgnoringModifiers,
              characters.rangeOfCharacter(from: .controlCharacters) == nil else {
            return nil
        }
        return characters
    }

    // MARK: - Command Block Overlay

    private func installCommandBlockOverlayIfNeeded() {
        guard commandBlockOverlayView == nil else { return }

        let overlay = TerminalBlockOverlayView(frame: bounds, localizer: localizer)
        overlay.autoresizingMask = [.width, .height]
        overlay.onCopyBlockOutput = { [weak self] block in
            self?.copyBlockOutputFromOverlay(block)
        }
        overlay.onCopySelectedBlockOutputs = { [weak self] blocks in
            self?.copySelectedBlockOutputsFromOverlay(blocks)
        }
        overlay.onRerunBlock = { [weak self] block in
            self?.rerunBlockFromOverlay(block)
        }
        overlay.onShareBlock = { [weak self] block, sourceView in
            self?.shareBlockFromOverlay(block, sourceView: sourceView)
        }
        overlay.onToggleBookmark = { [weak self] block in
            self?.toggleBlockBookmarkFromOverlay(block)
        }
        addSubview(overlay)
        commandBlockOverlayView = overlay
    }

    func refreshCommandBlockOverlay() {
        guard let overlay = commandBlockOverlayView else { return }
        overlay.frame = bounds

        guard let bridge, let sid = surfaceID,
              let snapshot = bridge.terminalViewportSnapshot(for: sid),
              !snapshot.isAltScreen else {
            overlay.clear()
            return
        }

        let scale = currentBackingScale()
        let cellHeight = CGFloat(snapshot.cellHeight) / scale
        let blocks = TerminalBlockRestoration.blocksForDisplay(
            live: bridge.commandBlocks(for: sid, limit: 32),
            restored: restoredCommandBlocksProvider?() ?? [],
            limit: 32
        )
        overlay.update(
            blocks: blocks,
            visibleStartRow: snapshot.visibleStartRow,
            visibleRowCount: snapshot.visibleRowCount,
            cellHeight: cellHeight,
            padding: CGPoint(x: contentPadding.x, y: contentPadding.y)
        )
    }

    private func copyBlockOutputFromOverlay(_ block: TerminalCommandBlock) {
        let text = block.output.isEmpty ? block.command : block.output
        guard !text.isEmpty else { return }
        clipboardService.write(text)
    }

    private func copySelectedBlockOutputsFromOverlay(_ blocks: [TerminalCommandBlock]) {
        let text = BlockSelectionCopyFormatter.outputText(for: blocks)
        guard !text.isEmpty else { return }
        clipboardService.write(text)
    }

    private func rerunBlockFromOverlay(_ block: TerminalCommandBlock) {
        guard !block.command.isEmpty,
              let bridge,
              let sid = surfaceID else {
            return
        }
        followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
        bridge.sendText(block.command + "\r", to: sid)
    }

    private func shareBlockFromOverlay(_ block: TerminalCommandBlock, sourceView: NSView) {
        let text = TerminalBlockShareFormatter.text(for: block)
        guard !text.isEmpty else { return }
        NSSharingServicePicker(items: [text]).show(
            relativeTo: sourceView.bounds,
            of: sourceView,
            preferredEdge: .minY
        )
    }

    private func toggleBlockBookmarkFromOverlay(_ block: TerminalCommandBlock) {
        onToggleCommandBlockBookmark?(block)
    }
}

// MARK: - Terminal Hosting View

extension CocxyCoreView: TerminalHostingView {
    var terminalViewModel: TerminalViewModel? { viewModel }

    /// Re-anchors the CVDisplayLink to the display currently hosting
    /// the window. Called from `MainWindowController.windowDidChangeScreen`
    /// as a safety net for detached/hidden surface views whose own
    /// `NSWindow.didChangeScreenNotification` observer does not fire
    /// (because they have no window reference). The view-local observer
    /// also calls `anchorDisplayLinkToCurrentScreen` directly when the
    /// view is attached, so this entry point is idempotent.
    func refreshDisplayLinkAnchor() {
        anchorDisplayLinkToCurrentScreen()
    }

    func showNotificationRing(color: NSColor = CocxyColors.blue) {
        guard !isNotificationRingActive else { return }
        isNotificationRingActive = true

        guard let layer = self.layer else { return }

        let ringLayer = CAShapeLayer()
        ringLayer.frame = layer.bounds
        let inset: CGFloat = 1.0
        ringLayer.path = CGPath(
            roundedRect: layer.bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
        ringLayer.fillColor = nil
        ringLayer.strokeColor = color.cgColor
        ringLayer.lineWidth = 2.0
        ringLayer.opacity = 0
        ringLayer.shadowColor = color.cgColor
        ringLayer.shadowOffset = .zero
        ringLayer.shadowRadius = 6
        ringLayer.shadowOpacity = 0.8

        layer.addSublayer(ringLayer)
        notificationRingLayer = ringLayer

        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.4
        pulse.duration = AnimationConfig.duration(AnimationConfig.notificationRingPulseDuration)
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ringLayer.add(pulse, forKey: "notificationPulse")
        ringLayer.opacity = 1.0
    }

    func hideNotificationRing() {
        guard isNotificationRingActive, let ringLayer = notificationRingLayer else { return }
        isNotificationRingActive = false

        ringLayer.removeAllAnimations()

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = ringLayer.presentation()?.opacity ?? ringLayer.opacity
        fadeOut.toValue = 0
        fadeOut.duration = AnimationConfig.duration(0.3)
        fadeOut.isRemovedOnCompletion = false
        fadeOut.fillMode = .forwards

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak ringLayer] in
            ringLayer?.removeFromSuperlayer()
        }
        ringLayer.add(fadeOut, forKey: "fadeOut")
        CATransaction.commit()

        notificationRingLayer = nil
    }

    func handleShellPrompt(row: Int, column: Int) {
        refreshIDECursorMetrics()
        ideCursorController.shellPromptDetected(row: row, column: column)
    }

    /// Reads the real cursor row/col from the backing CocxyCore terminal
    /// and notifies the IDE cursor controller that a shell prompt has
    /// been detected at that position.
    ///
    /// Preferred over `handleShellPrompt(row:column:)` for OSC 133 `A`
    /// routing, because the real cursor position is the only reliable
    /// source for the prompt row — the view-geometry heuristic
    /// (`viewHeight / cellHeight - 1`) always yields the last visible
    /// row and is never the right answer, which is the root cause of
    /// the v0.1.52 "blinking line near the status bar" bug.
    func handleShellPromptAtCurrentCursor() {
        guard let bridge, let sid = surfaceID,
              let position = bridge.cursorPosition(for: sid) else {
            return
        }
        handleShellPrompt(row: position.row, column: position.col)
    }

    func updateInteractionMetrics() {
        lastNotifiedBackingSize = .zero
        syncSizeWithTerminal()
        refreshIDECursorMetrics()
    }

    func configureSurfaceIfNeeded(
        bridge: any TerminalEngine,
        surfaceID: SurfaceID
    ) {
        guard let bridge = bridge.cocxyCoreBridge,
              let viewModel else { return }
        configure(bridge: bridge, surfaceID: surfaceID, viewModel: viewModel)
        syncSizeWithTerminal()
        requestImmediateRedraw()
    }

    func requestImmediateRedraw() {
        applyTerminalBackingBackground()
        setNeedsTerminalDisplay()
    }

    private func applyTerminalBackingBackground() {
        guard let layer else { return }
        let color = bridge?.configuredTerminalBackgroundColor ?? CocxyColors.base
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color.cgColor
        layer.isOpaque = true
        if let metalLayer = layer as? CAMetalLayer {
            metalLayer.isOpaque = true
        }
        CATransaction.commit()
    }

    private func updateNotificationRingFrame() {
        guard let ringLayer = notificationRingLayer, let layer = self.layer else { return }
        ringLayer.frame = layer.bounds
        let inset: CGFloat = 1.0
        ringLayer.path = CGPath(
            roundedRect: layer.bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: 4,
            cornerHeight: 4,
            transform: nil
        )
    }
}

// MARK: - NSTextInputClient Conformance

extension CocxyCoreView: @preconcurrency NSTextInputClient {

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attr = string as? NSAttributedString { text = attr.string }
        else if let plain = string as? String { text = plain }
        else { return }

        guard !text.isEmpty else { return }

        let wasComposing = compositionState.hasMarkedText
        compositionState.commit()

        guard let bridge = bridge, let sid = surfaceID else { return }
        followLiveViewportBeforeUserInput(bridge: bridge, surfaceID: sid)
        if wasComposing {
            bridge.sendPreeditText("", to: sid)
        }
        bridge.sendText(text, to: sid)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let attr = string as? NSAttributedString { text = attr.string }
        else if let plain = string as? String { text = plain }
        else { return }

        compositionState.setMarkedText(text, selectedRange: selectedRange)

        guard let bridge = bridge, let sid = surfaceID else { return }
        bridge.sendPreeditText(text, to: sid)
    }

    func unmarkText() {
        compositionState.unmarkText()
        guard let bridge = bridge, let sid = surfaceID else { return }
        bridge.sendPreeditText("", to: sid)
    }

    func hasMarkedText() -> Bool {
        compositionState.hasMarkedText
    }

    func markedRange() -> NSRange {
        compositionState.markedRange
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: UnsafeMutablePointer<NSRange>?) -> NSRect {
        // Return cursor position in screen coordinates for IME popup placement.
        guard let bridge = bridge, let sid = surfaceID,
              let state = bridge.surfaceState(for: sid) else {
            return window?.convertToScreen(NSRect(origin: .zero, size: CGSize(width: 1, height: 20))) ?? .zero
        }

        var metrics = cocxycore_font_metrics()
        guard cocxycore_terminal_get_font_metrics(state.terminal, &metrics),
              metrics.cell_width > 0 else {
            return .zero
        }

        let scale = Float(currentBackingScale())
        let cursorRow = cocxycore_terminal_cursor_row(state.terminal)
        let cursorCol = cocxycore_terminal_cursor_col(state.terminal)

        let x = CGFloat(Float(cursorCol) * metrics.cell_width / scale + 8)
        let y = CGFloat(Float(cursorRow) * metrics.cell_height / scale + 4)
        let cellW = CGFloat(metrics.cell_width / scale)
        let cellH = CGFloat(metrics.cell_height / scale)

        let viewRect = NSRect(x: x, y: y, width: cellW, height: cellH)
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? viewRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: UnsafeMutablePointer<NSRange>?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .foregroundColor]
    }
}
