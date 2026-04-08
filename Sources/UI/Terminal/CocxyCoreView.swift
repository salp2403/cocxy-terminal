// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyCoreView.swift - NSView that hosts a CocxyCore terminal surface with Metal rendering.

import AppKit
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

    /// Closure called when the user submits input (Enter key).
    var onUserInputSubmitted: (() -> Void)?

    /// Closure called when files are dropped onto the terminal.
    var onFileDrop: (([URL]) -> Bool)?

    /// Optional output buffer provider retained for controller integrations
    /// such as Smart Copy. Selection content still has priority, but this
    /// hook preserves feature wiring for host-driven actions.
    var outputBufferProvider: (() -> [String])?

    /// IDE-like cursor positioning support for shell prompts.
    private(set) lazy var ideCursorController = IDECursorController(
        hostView: self,
        fontSizeProvider: { [weak self] in
            self?.viewModel?.currentFontSize ?? 14.0
        },
        arrowKeySender: { [weak self] arrows in
            self?.sendArrowKeys(arrows)
        }
    )

    // MARK: - Notification Ring

    private var notificationRingLayer: CAShapeLayer?
    private(set) var isNotificationRingActive: Bool = false

    // MARK: - Display Link

    private var displayLink: CVDisplayLink?
    private var needsRender: Bool = false

    // MARK: - Input State

    /// IME composition state.
    private var compositionState = TextCompositionState()

    /// Whether the view currently has keyboard focus.
    private(set) var isFocused: Bool = false

    // MARK: - Selection State

    /// Anchor point for mouse-drag text selection (absolute history row, col).
    private var selectionAnchor: (row: UInt32, col: UInt16)?

    /// Whether a drag selection is in progress.
    private var isDragging: Bool = false

    // MARK: - Layout Tracking

    /// Last backing-pixel size sent to the bridge, prevents redundant resize calls.
    private var lastNotifiedBackingSize: NSSize = .zero

    // MARK: - Constants

    private static let scrollSpeedFactor: CGFloat = 0.15

    private var contentPadding: (x: CGFloat, y: CGFloat) {
        guard let bridge else { return (8, 4) }
        return (bridge.configuredPaddingX, bridge.configuredPaddingY)
    }

    // MARK: - Initialization

    init(viewModel: TerminalViewModel? = nil) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CocxyCoreView does not support NSCoding")
    }

    deinit {
        MainActor.assumeIsolated {
            stopDisplayLink()
        }
    }

    // MARK: - Layer Configuration

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override var acceptsFirstResponder: Bool { true }

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
        return metalLayer
    }

    // MARK: - Setup

    /// Configures the view with a bridge and surface. Call after createSurface.
    func configure(bridge: CocxyCoreBridge, surfaceID: SurfaceID, viewModel: TerminalViewModel) {
        self.bridge = bridge
        self.surfaceID = surfaceID
        self.viewModel = viewModel
        refreshIDECursorMetrics()

        do {
            renderer = try MetalTerminalRenderer(
                device: (layer as? CAMetalLayer)?.device
            )
        } catch {
            assertionFailure("MetalTerminalRenderer init failed: \(error)")
        }

        startDisplayLink()
    }

    // MARK: - Render Loop

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let link = displayLink else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { (_, _, _, _, _, userInfo) -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnError }
            let view = Unmanaged<CocxyCoreView>.fromOpaque(userInfo).takeUnretainedValue()
            if view.needsRender {
                DispatchQueue.main.async {
                    view.renderFrame()
                }
            }
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        guard let link = displayLink else { return }
        CVDisplayLinkStop(link)
        displayLink = nil
    }

    /// Mark that a new frame is available for rendering.
    /// Called from CocxyCoreBridge after PTY data is processed.
    func setNeedsTerminalDisplay() {
        needsRender = true
    }

    private func renderFrame() {
        needsRender = false

        guard let bridge = bridge,
              let sid = surfaceID,
              let state = bridge.surfaceState(for: sid),
              let renderer = renderer,
              let metalLayer = layer as? CAMetalLayer
        else { return }

        renderer.draw(terminal: state.terminal, layer: metalLayer)
    }

    // MARK: - Layout & Resize

    override func layout() {
        super.layout()
        guard surfaceID != nil else { return }

        if let metalLayer = layer as? CAMetalLayer {
            let scale = window?.backingScaleFactor ?? 2.0
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(
                width: bounds.width * scale,
                height: bounds.height * scale
            )

            renderer?.updateViewportSize(
                bounds.size,
                scale: scale,
                paddingX: Float(contentPadding.x),
                paddingY: Float(contentPadding.y)
            )
        }

        let currentBacking = convertToBacking(bounds).size
        if currentBacking != lastNotifiedBackingSize {
            syncSizeWithTerminal()
        }

        refreshIDECursorMetrics()
        updateNotificationRingFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifySizeChanged(newSize)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor,
           let metalLayer = layer as? CAMetalLayer {
            metalLayer.contentsScale = scale
        }
        if let bridge, let sid = surfaceID {
            bridge.reapplyConfiguredFont(to: sid)
        }
        refreshIDECursorMetrics()
        requestImmediateRedraw()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let bridge, let sid = surfaceID {
            bridge.reapplyConfiguredFont(to: sid)
        }
        updateInteractionMetrics()
        requestImmediateRedraw()
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

        let scale = Float(window?.backingScaleFactor ?? 2.0)
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

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        isFocused = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
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
        guard let state = bridge.surfaceState(for: sid) else { return }

        // Ctrl+letter → compute ASCII control character directly.
        if modifiers.contains(.control),
           !modifiers.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 0x61, scalar.value <= 0x7A {
            let controlCode = UInt8(scalar.value - 0x60)
            cocxycore_pty_write(state.pty, [controlCode], 1)
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
        bridge.sendText(seq, to: sid)
    }

    private func sendArrowKeys(_ arrows: [ArrowDirection]) {
        guard !arrows.isEmpty else { return }
        let seq = arrows[0] == .left ? "\u{1B}[D" : "\u{1B}[C"
        for _ in arrows {
            sendControlSequence(seq)
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
        guard let bridge = bridge, let sid = surfaceID,
              let text = clipboardService.read(), !text.isEmpty else { return }

        // Bracketed paste if terminal supports it
        guard let state = bridge.surfaceState(for: sid) else { return }
        if cocxycore_terminal_mode_bracketed_paste(state.terminal) {
            bridge.sendText("\u{1B}[200~\(text)\u{1B}[201~", to: sid)
        } else {
            bridge.sendText(text, to: sid)
        }
    }

    // MARK: - Mouse Input + Selection

    override func mouseDown(with event: NSEvent) {
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

        cocxycore_terminal_selection_clear(state.terminal)
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

        cocxycore_terminal_selection_set(
            state.terminal,
            anchor.row, anchor.col,
            absoluteRow, pos.col
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
                if let text = self.clipboardService.read(), !text.isEmpty {
                    bridge.sendText(text, to: sid)
                }
            }
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
        if mouseMode > 0 {
            // Terminal app is tracking mouse — forward scroll as mouse events
            let delta = event.scrollingDeltaY * Self.scrollSpeedFactor
            let button: UInt8 = delta > 0 ? 64 : 65 // scroll up / down
            let count = max(1, Int(abs(delta)))
            for _ in 0..<count {
                var buf = [UInt8](repeating: 0, count: 16)
                let n = encodeMouseButton(button, terminal: state.terminal, event: event, buf: &buf)
                if n > 0 {
                    cocxycore_pty_write(state.pty, buf, n)
                }
            }
            return
        }

        let scaledDelta = event.scrollingDeltaY * Self.scrollSpeedFactor
        guard scaledDelta != 0 else { return }

        let steps = max(1, Int(abs(scaledDelta.rounded(.towardZero))))
        let signedSteps = scaledDelta > 0 ? steps : -steps
        bridge.scrollViewport(surfaceID: sid, deltaRows: signedSteps)
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

        // Default: paste file paths as text
        let paths = urls.map { $0.path }.joined(separator: " ")
        guard let bridge = bridge, let sid = surfaceID else { return false }
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

        let scale = Float(window?.backingScaleFactor ?? 2.0)
        let paddingX: Float = 8
        let paddingY: Float = 4

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

        let scale = CGFloat(window?.backingScaleFactor ?? 2.0)
        ideCursorController.setCellDimensions(
            width: CGFloat(metrics.cell_width) / scale,
            height: CGFloat(metrics.cell_height) / scale
        )
        ideCursorController.leftPadding = 8
        ideCursorController.topPadding = 4
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
}

// MARK: - Terminal Hosting View

extension CocxyCoreView: TerminalHostingView {
    var terminalViewModel: TerminalViewModel? { viewModel }

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

    func updateInteractionMetrics() {
        lastNotifiedBackingSize = .zero
        syncSizeWithTerminal()
        refreshIDECursorMetrics()
    }

    func configureSurfaceIfNeeded(
        bridge: any TerminalEngine,
        surfaceID: SurfaceID
    ) {
        guard let bridge = bridge as? CocxyCoreBridge,
              let viewModel else { return }
        configure(bridge: bridge, surfaceID: surfaceID, viewModel: viewModel)
        syncSizeWithTerminal()
        requestImmediateRedraw()
    }

    func requestImmediateRedraw() {
        setNeedsTerminalDisplay()
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
        compositionState.commit()

        let text: String
        if let attr = string as? NSAttributedString { text = attr.string }
        else if let plain = string as? String { text = plain }
        else { return }

        guard !text.isEmpty, let bridge = bridge, let sid = surfaceID else { return }
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

        let scale = Float(window?.backingScaleFactor ?? 2.0)
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
