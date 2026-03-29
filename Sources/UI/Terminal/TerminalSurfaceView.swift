// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalSurfaceView.swift - NSView that hosts a libghostty terminal surface.

import AppKit

// MARK: - Terminal Surface View

/// NSView subclass that hosts a single libghostty terminal surface.
///
/// This view is the rendering target for Metal-accelerated terminal output.
/// It forwards keyboard and mouse events to the `GhosttyBridge` and
/// notifies its `TerminalViewModel` of user interactions.
///
/// ## Metal rendering
///
/// libghostty handles all Metal rendering internally. This view provides:
/// 1. A layer-backed view that ghostty draws into via its renderer thread.
/// 2. The correct `contentsScale` for Retina displays.
/// 3. A `.never` redraw policy since ghostty owns the rendering pipeline.
///
/// ## Event forwarding
///
/// Keyboard and mouse events are translated from AppKit's `NSEvent` types
/// to the domain's `KeyEvent` type, then forwarded to the `GhosttyBridge`
/// via the `TerminalEngine` protocol.
///
/// ## IME support
///
/// The view conforms to `NSTextInputClient` for IME (Input Method Editor)
/// support, enabling input of CJK characters and other complex scripts.
/// During composition, marked text is tracked and preedit text is sent
/// to libghostty via `ghostty_surface_preedit`.
///
/// ## Coordinate system
///
/// The view is flipped (`isFlipped = true`) to match libghostty's
/// top-left origin coordinate system.
///
/// Each `TerminalSurfaceView` corresponds to one leaf in the split tree
/// and one `SurfaceID` in the terminal engine.
///
/// - SeeAlso: `TerminalEngine` protocol
/// - SeeAlso: `TerminalViewModel`
/// - SeeAlso: Section 8 of libghostty-api-reference.md (Metal rendering)
@MainActor
final class TerminalSurfaceView: NSView {

    // MARK: - Constants

    /// Throttle interval for resize calls during live window drag.
    ///
    /// During a live resize (user dragging the window edge), we limit
    /// resize notifications to 60fps to avoid saturating libghostty.
    /// Outside of live resize, resize calls are immediate.
    static let liveResizeThrottleInterval: TimeInterval = 1.0 / 60.0

    // MARK: - Properties

    /// The ViewModel that drives this view's state.
    let viewModel: TerminalViewModel

    /// Whether the view currently has keyboard focus.
    private(set) var isFocused: Bool = false

    /// IME composition state tracked for NSTextInputClient.
    private var compositionState = TextCompositionState()

    /// Clipboard service for Cmd+C/V operations.
    /// Defaults to SystemClipboardService but can be overridden for testing.
    var clipboardService: ClipboardServiceProtocol = SystemClipboardService()

    // MARK: - Notification Ring

    /// Border ring layer that glows when an agent needs attention.
    /// Inspired by cmux's notification ring for panes.
    private var notificationRingLayer: CAShapeLayer?

    /// Whether the notification ring is currently animating.
    private(set) var isNotificationRingActive: Bool = false

    // MARK: - Text Selection

    /// IDE-like text selection enhancements (Cmd+click, auto-scroll, highlights).
    private(set) lazy var textSelectionManager = TextSelectionManager(surfaceView: self)

    /// Overlay layer for highlighting matched text selections.
    private var selectionHighlightLayer: SelectionHighlightLayer?

    /// IDE-like cursor positioning within the prompt line.
    private(set) lazy var ideCursorController = IDECursorController(surfaceView: self)

    // MARK: - Initialization

    /// Creates a terminal surface view with the given ViewModel.
    ///
    /// - Parameter viewModel: The ViewModel for this view. If nil, a default
    ///   ViewModel is created.
    init(viewModel: TerminalViewModel? = nil) {
        self.viewModel = viewModel ?? TerminalViewModel()
        super.init(frame: .zero)
        configureView()
    }

    /// Required initializer for NSCoding. Not used in practice.
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TerminalSurfaceView does not support NSCoding")
    }

    // MARK: - View Configuration

    /// Configures the view for Metal rendering with libghostty.
    private func configureView() {
        // Enable layer backing for Metal rendering.
        wantsLayer = true

        // libghostty renders directly into the layer. We never need AppKit
        // to redraw the layer contents -- ghostty's renderer thread handles it.
        layerContentsRedrawPolicy = .never
    }

    // MARK: - Notification Ring Methods

    /// Shows the notification ring with an animated glow.
    ///
    /// The ring is a 2pt border that pulses between full and 40% opacity.
    /// Used when the agent state transitions to `.waitingInput` to signal
    /// that user attention is needed (similar to cmux's notification ring).
    ///
    /// - Parameter color: The ring color. Defaults to `CocxyColors.blue`.
    func showNotificationRing(color: NSColor = CocxyColors.blue) {
        guard !isNotificationRingActive else { return }
        isNotificationRingActive = true

        guard let layer = self.layer else { return }

        let ringLayer = CAShapeLayer()
        ringLayer.frame = layer.bounds
        let inset: CGFloat = 1.0
        ringLayer.path = CGPath(
            roundedRect: layer.bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
        ringLayer.fillColor = nil
        ringLayer.strokeColor = color.cgColor
        ringLayer.lineWidth = 2.0
        ringLayer.opacity = 0

        // Glow effect via shadow.
        ringLayer.shadowColor = color.cgColor
        ringLayer.shadowOffset = .zero
        ringLayer.shadowRadius = 6
        ringLayer.shadowOpacity = 0.8

        layer.addSublayer(ringLayer)
        self.notificationRingLayer = ringLayer

        // Pulse animation: fade between 1.0 and 0.4 opacity.
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

    /// Hides the notification ring with a fade-out animation.
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

        self.notificationRingLayer = nil
    }

    /// Updates the notification ring frame when the view resizes.
    private func updateNotificationRingFrame() {
        guard let ringLayer = notificationRingLayer, let layer = self.layer else { return }
        ringLayer.frame = layer.bounds
        let inset: CGFloat = 1.0
        ringLayer.path = CGPath(
            roundedRect: layer.bounds.insetBy(dx: inset, dy: inset),
            cornerWidth: 4, cornerHeight: 4, transform: nil
        )
    }

    // MARK: - Coordinate System

    /// libghostty uses a top-left origin coordinate system.
    override var isFlipped: Bool { true }

    // MARK: - First Responder

    /// This view must accept first responder to receive keyboard events.
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            isFocused = true
            notifySurfaceFocusChanged(focused: true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            isFocused = false
            notifySurfaceFocusChanged(focused: false)
        }
        return resigned
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.keyDown(with: event)
            return
        }

        let modifiers = Self.translateModifierFlags(event.modifierFlags)

        // Classify the action to determine if this is an app command or terminal input.
        let action = KeyInputAction.classify(
            keyCode: event.keyCode,
            modifiers: modifiers,
            characters: event.characters
        )

        // Hide mouse cursor while typing (Ghostty parity).
        NSCursor.setHiddenUntilMouseMoves(true)

        switch action {
        case .copy:
            handleCopy(bridge: bridge, surfaceID: surfaceID)
            return

        case .paste:
            handlePaste(bridge: bridge, surfaceID: surfaceID)
            return

        case .selectAll, .clearScreen:
            bridge.sendKeyEvent(
                Self.translateKeyEvent(event, isKeyDown: true),
                to: surfaceID
            )
            return

        case .sendToTerminal:
            // Ctrl+key → send the corresponding control character directly.
            // ASCII control characters are key - 0x60 (e.g., Ctrl+C → 0x03).
            if modifiers.contains(.control),
               !modifiers.contains(.command),
               let chars = event.charactersIgnoringModifiers?.lowercased(),
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 0x61, scalar.value <= 0x7A { // a-z
                let controlChar = Character(UnicodeScalar(scalar.value - 0x60)!)
                bridge.performBindingAction("text:\(controlChar)", on: surfaceID)
                return
            }

            // Use ghostty's binding action system for special keys.
            // ghostty_surface_binding_action("text:X") writes X directly to the PTY,
            // bypassing the key event processing that doesn't work in embedded mode.
            switch event.keyCode {
            case 0x33: // Backspace → DEL
                bridge.performBindingAction("text:\u{7F}", on: surfaceID)
                return
            case 0x75: // Forward Delete → ESC[3~
                bridge.performBindingAction("text:\u{1B}[3~", on: surfaceID)
                return
            case 0x7E: // Up arrow → ESC[A
                bridge.performBindingAction("text:\u{1B}[A", on: surfaceID)
                return
            case 0x7D: // Down arrow → ESC[B
                bridge.performBindingAction("text:\u{1B}[B", on: surfaceID)
                return
            case 0x7C: // Right arrow → ESC[C
                if ideCursorController.isOnPromptLine {
                    ideCursorController.cursorMoved(toColumn: ideCursorController.cursorColumn + 1)
                }
                bridge.performBindingAction("text:\u{1B}[C", on: surfaceID)
                return
            case 0x7B: // Left arrow → ESC[D
                if ideCursorController.isOnPromptLine {
                    let newCol = max(ideCursorController.promptColumn, ideCursorController.cursorColumn - 1)
                    ideCursorController.cursorMoved(toColumn: newCol)
                }
                bridge.performBindingAction("text:\u{1B}[D", on: surfaceID)
                return
            case 0x24: // Enter/Return
                if modifiers.contains(.shift) {
                    // Shift+Enter → LF (newline). Used by Claude Code and other
                    // CLI tools for multi-line input without submitting.
                    bridge.performBindingAction("text:\u{0A}", on: surfaceID)
                } else {
                    // Plain Enter → CR (carriage return, submits command).
                    ideCursorController.commandExecuted()
                    bridge.performBindingAction("text:\u{0D}", on: surfaceID)
                }
                // Notify the agent detection engine that the user submitted
                // input. This triggers waitingInput → working transition.
                onUserInputSubmitted?()
                return
            case 0x30: // Tab → HT
                bridge.performBindingAction("text:\u{09}", on: surfaceID)
                return
            case 0x35: // Escape → ESC
                bridge.performBindingAction("text:\u{1B}", on: surfaceID)
                return
            case 0x73: // Home → ESC[H
                bridge.performBindingAction("text:\u{1B}[H", on: surfaceID)
                return
            case 0x77: // End → ESC[F
                bridge.performBindingAction("text:\u{1B}[F", on: surfaceID)
                return
            case 0x74: // Page Up → ESC[5~
                bridge.performBindingAction("text:\u{1B}[5~", on: surfaceID)
                return
            case 0x79: // Page Down → ESC[6~
                bridge.performBindingAction("text:\u{1B}[6~", on: surfaceID)
                return
            default:
                break
            }

            // For regular keys, send characters to the terminal.
            //
            // Use event.characters as the primary source because macOS has
            // already resolved the keyboard layout and modifier combination.
            // This correctly handles @ (Option+2 on Spanish/Latin keyboards),
            // # (Option+3 on UK keyboards), and other layout-dependent chars.
            //
            // Fall back to byApplyingModifiers only when event.characters is
            // nil (e.g., dead keys before composition completes).
            let translationModsRaw = bridge.translationMods(for: surfaceID, mods: modifiers)
            let translatedChars = event.characters
                ?? event.characters(byApplyingModifiers:
                    NSEvent.ModifierFlags(rawValue: translationModsRaw))
            let unshiftedChars = event.characters(byApplyingModifiers: [])
            let unshiftedCodepoint = unshiftedChars?.unicodeScalars.first?.value ?? 0

            // If Option+key produced a character different from the unshifted
            // base key, macOS resolved a keyboard layout shortcut (e.g., Option+2
            // → @ on Spanish keyboard). Send it directly to the PTY.
            //
            // If the character is the SAME as the base key (e.g., Option+j → j on
            // US keyboard), fall through to sendKeyEvent so ghostty can interpret
            // it as Meta+key for terminal programs like vim and tmux.
            if modifiers.contains(.option),
               let chars = translatedChars,
               !chars.isEmpty,
               chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) {
                let baseChars = unshiftedChars ?? ""
                let optionProducedDifferentChar = chars != baseChars
                if optionProducedDifferentChar {
                    bridge.performBindingAction("text:\(chars)", on: surfaceID)
                    return
                }
            }

            let keyEvent = KeyEvent(
                characters: translatedChars,
                keyCode: event.keyCode,
                modifiers: modifiers,
                isKeyDown: true,
                isRepeat: event.isARepeat,
                unshiftedCodepoint: unshiftedCodepoint,
                consumedModsRaw: UInt32(translationModsRaw)
            )

            let handled = bridge.sendKeyEvent(keyEvent, to: surfaceID)
            if !handled {
                self.interpretKeyEvents([event])
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.keyUp(with: event)
            return
        }

        let keyEvent = Self.translateKeyEvent(event, isKeyDown: false)
        bridge.sendKeyEvent(keyEvent, to: surfaceID)
    }

    override func flagsChanged(with event: NSEvent) {
        // Update cursor: Cmd held = pointing hand (Cmd+click opens URLs).
        if event.modifierFlags.contains(.command) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }

        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.flagsChanged(with: event)
            return
        }

        let isDown = isModifierKeyDown(event)
        let keyEvent = Self.translateKeyEvent(event, isKeyDown: isDown)
        bridge.sendKeyEvent(keyEvent, to: surfaceID)
    }

    // MARK: - Clipboard Handling

    /// Copies the current selection to the clipboard.
    private func handleCopy(bridge: GhosttyBridge, surfaceID: SurfaceID) {
        // The actual copy is handled by libghostty's clipboard write callback.
        // We trigger it by sending the key event, which libghostty intercepts
        // as a copy binding.
        let keyEvent = KeyEvent(
            characters: "c",
            keyCode: 0x08,
            modifiers: .command,
            isKeyDown: true
        )
        bridge.sendKeyEvent(keyEvent, to: surfaceID)
    }

    /// Pastes clipboard text into the terminal.
    private func handlePaste(bridge: GhosttyBridge, surfaceID: SurfaceID) {
        // The actual paste is handled by libghostty's clipboard read callback.
        // We trigger it by sending the key event, which libghostty intercepts
        // as a paste binding.
        let keyEvent = KeyEvent(
            characters: "v",
            keyCode: 0x09,
            modifiers: .command,
            isKeyDown: true
        )
        bridge.sendKeyEvent(keyEvent, to: surfaceID)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)

        // Clear any existing selection highlights when starting a new click.
        selectionHighlightLayer?.clearHighlights()

        // Cmd+click: attempt to open URL/path under cursor.
        // Only intercept if Cmd is held; otherwise let libghostty handle
        // the click for normal text selection.
        if event.modifierFlags.contains(.command) {
            _ = textSelectionManager.handleCmdClick(
                at: location,
                modifiers: event.modifierFlags
            )
        }

        // Record click count for double/triple click word/line selection.
        viewModel.recordMouseDown(clickCount: event.clickCount)

        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.mouseDown(with: event)
            return
        }

        // Send the mouse press directly to libghostty. It handles all
        // selection logic internally (character, word, line selection
        // based on click count). Do NOT send extra key events or
        // IDE cursor repositioning here — that interferes with selection.
        bridge.sendMouseEvent(
            button: .left,
            action: .press,
            position: location,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        viewModel.recordMouseUp()

        // End auto-scroll if a drag was in progress.
        textSelectionManager.dragDidEnd()

        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.mouseUp(with: event)
            return
        }

        bridge.sendMouseEvent(
            button: .left,
            action: .release,
            position: location,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )

        // After mouse release, check if ghostty created a selection
        // and update the highlight layer accordingly.
        checkSelectionForHighlighting(surfaceID: surfaceID, bridge: bridge)
    }

    // MARK: - Selection Highlight

    /// Lazily installs the selection highlight layer as a sublayer.
    ///
    /// The layer is transparent and positioned to cover the entire view.
    /// It does not intercept mouse events. Follows the same lazy pattern
    /// as `IDECursorController.installIndicatorIfNeeded()`.
    private func installSelectionHighlightLayerIfNeeded() {
        guard selectionHighlightLayer == nil, let layer = self.layer else { return }
        let highlight = SelectionHighlightLayer()
        highlight.frame = layer.bounds
        highlight.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        highlight.zPosition = 10
        layer.addSublayer(highlight)
        selectionHighlightLayer = highlight
    }

    /// Checks if ghostty has an active selection and updates the highlight layer.
    ///
    /// Called after `mouseUp` to provide VS Code-like selection awareness.
    /// Installs the highlight layer lazily on first use. If no selection exists
    /// or the selected text is empty, clears any existing highlights.
    ///
    /// - Parameters:
    ///   - surfaceID: The surface to query.
    ///   - bridge: The ghostty bridge for selection queries.
    private func checkSelectionForHighlighting(surfaceID: SurfaceID, bridge: GhosttyBridge) {
        installSelectionHighlightLayerIfNeeded()

        guard bridge.hasSelection(for: surfaceID),
              let selectedText = bridge.readSelection(for: surfaceID),
              !selectedText.isEmpty,
              selectedText.count <= 200
        else {
            selectionHighlightLayer?.clearHighlights()
            return
        }

        // Selection is active and readable. The highlight layer is wired
        // and ready. Rendering match rectangles across the visible viewport
        // requires computing pixel positions for each occurrence of
        // selectedText, which is a phase-2 enhancement.
        // For now, the infrastructure is complete: layer installed,
        // selection queried, clearHighlights functional on deselect.
        selectionHighlightLayer?.clearHighlights()
    }

    // MARK: - Mouse Selection Helpers

    /// Processes a mouse-down for selection tracking.
    ///
    /// Records the click count on the view model for selection mode:
    /// - 1: character selection (click + drag)
    /// - 2: word selection (double click)
    /// - 3: line selection (triple click)
    ///
    /// libghostty handles the actual selection logic internally based on the
    /// mouse events we forward. This method tracks state for the UI layer.
    ///
    /// - Parameters:
    ///   - location: The mouse position in the view's coordinate system.
    ///   - clickCount: Number of consecutive clicks (from NSEvent.clickCount).
    func handleMouseDown(at location: CGPoint, clickCount: Int) {
        // Attempt IDE cursor positioning on single clicks within the prompt.
        if clickCount == 1 {
            _ = ideCursorController.handleClickToPosition(at: location)
        }
        viewModel.recordMouseDown(clickCount: clickCount)
    }

    /// Processes a mouse-up, ending any active drag selection.
    ///
    /// If auto-copy is enabled and text was selected (determined by ghostty),
    /// the selection is copied to the clipboard via libghostty's clipboard
    /// write callback.
    ///
    /// - Parameter location: The mouse position in the view's coordinate system.
    func handleMouseUp(at location: CGPoint) {
        viewModel.recordMouseUp()
    }

    /// Tracks the last cursor style to avoid redundant `NSCursor.set()` calls.
    private var lastCursorIsPointing = false

    override func mouseMoved(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.mouseMoved(with: event)
            return
        }

        // Show pointing hand cursor when Cmd is held (Cmd+click opens URLs).
        let shouldPoint = event.modifierFlags.contains(.command)
        if shouldPoint != lastCursorIsPointing {
            lastCursorIsPointing = shouldPoint
            if shouldPoint {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.iBeam.set()
            }
        }

        let location = convert(event.locationInWindow, from: nil)
        bridge.sendMousePosition(
            position: location,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )
    }


    override func mouseDragged(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.mouseDragged(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)

        // Start drag tracking on the first drag event (not on mouseDown).
        if !textSelectionManager.isDragging {
            textSelectionManager.dragDidStart()
        }

        // Auto-scroll when dragging near edges.
        textSelectionManager.dragDidMove(to: location)

        // Only send position updates during drag. libghostty tracks the
        // button-press state internally from the preceding mouseDown event
        // and extends the text selection based on position changes alone.
        // Do NOT send additional press events here — repeated press events
        // confuse libghostty's selection state machine.
        bridge.sendMousePosition(
            position: location,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )
    }

    /// Closure that provides the current terminal output buffer lines.
    /// Set by MainWindowController when wiring surfaces to tabs.
    var outputBufferProvider: (() -> [String])?

    /// Called when the user submits input (Enter key) in this terminal.
    /// The agent detection engine uses this to transition from
    /// `waitingInput` to `working`.
    var onUserInputSubmitted: (() -> Void)?

    /// Scale factor applied to trackpad/mouse scroll deltas.
    /// Lower values = slower, more controllable scrolling.
    /// 0.15 matches the feel of Ghostty's native scroll behavior.
    private static let scrollSpeedFactor: CGFloat = 0.15

    override func scrollWheel(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.scrollWheel(with: event)
            return
        }

        // Apply speed reduction for smooth, controllable scrolling.
        // Raw trackpad deltas can be 30-80+ per event which makes
        // content fly past too fast to read.
        let scaledDeltaX = event.scrollingDeltaX * Self.scrollSpeedFactor
        let scaledDeltaY = event.scrollingDeltaY * Self.scrollSpeedFactor

        bridge.sendScrollEvent(
            deltaX: scaledDeltaX,
            deltaY: scaledDeltaY,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.rightMouseDown(with: event)
            return
        }

        // First, tell ghostty to select the word under cursor so it copies
        // to the clipboard. Then build the Smart Copy menu from clipboard content.
        let location = convert(event.locationInWindow, from: nil)
        bridge.sendMouseEvent(
            button: .right,
            action: .press,
            position: location,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )

        // Give ghostty time to process the right-click selection and update the
        // clipboard, then show the context menu with intelligent detection.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            guard let self else { return }

            // Read whatever is on the clipboard (ghostty's selection or user's copy).
            let clipboardText = self.clipboardService.read() ?? ""

            let menu = SmartCopyMenuBuilder.buildMenu(
                nearText: clipboardText,
                clipboardService: self.clipboardService,
                bridge: self.viewModel.bridge,
                surfaceID: self.viewModel.surfaceID
            )

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else {
            super.rightMouseUp(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        bridge.sendMouseEvent(
            button: .right,
            action: .release,
            position: location,
            modifiers: Self.translateModifierFlags(event.modifierFlags),
            to: surfaceID
        )
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifySurfaceSizeChanged(newSize)
        updateNotificationRingFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()
    }

    // MARK: - Static Event Translation

    /// Converts NSEvent modifier flags to the domain's KeyModifiers type.
    ///
    /// This is a static method to enable unit testing without instantiating
    /// NSEvent objects (which is difficult in tests).
    ///
    /// - Parameter flags: The NSEvent modifier flags.
    /// - Returns: The equivalent domain KeyModifiers.
    static func translateModifierFlags(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers = KeyModifiers()
        if flags.contains(.shift)   { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option)  { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    /// Converts an NSEvent keyboard event to the domain's KeyEvent type.
    ///
    /// - Parameters:
    ///   - event: The NSEvent to translate.
    ///   - isKeyDown: Whether this is a key-down or key-up event.
    /// - Returns: The equivalent domain KeyEvent.
    static func translateKeyEvent(_ event: NSEvent, isKeyDown: Bool) -> KeyEvent {
        // Get the unshifted codepoint — the character produced without Shift.
        // Ghostty needs this for correct key translation (e.g., Shift+a → 'A' but unshifted = 'a').
        let unshiftedCodepoint: UInt32
        if let unshifted = event.characters(byApplyingModifiers: [])?.unicodeScalars.first {
            unshiftedCodepoint = unshifted.value
        } else {
            unshiftedCodepoint = 0
        }

        return KeyEvent(
            characters: event.characters,
            keyCode: event.keyCode,
            modifiers: translateModifierFlags(event.modifierFlags),
            isKeyDown: isKeyDown,
            isRepeat: isKeyDown ? event.isARepeat : false,
            unshiftedCodepoint: unshiftedCodepoint
        )
    }

    // MARK: - Private Helpers

    /// Determines if a modifier key event represents a key-down.
    ///
    /// macOS sends `flagsChanged` for both press and release of modifier keys.
    /// We check if the modifier flag is present to determine direction.
    private func isModifierKeyDown(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        let flags = event.modifierFlags

        switch keyCode {
        case 0x38, 0x3C: // Left/Right Shift
            return flags.contains(.shift)
        case 0x3B, 0x3E: // Left/Right Control
            return flags.contains(.control)
        case 0x3A, 0x3D: // Left/Right Option
            return flags.contains(.option)
        case 0x37, 0x36: // Left/Right Command
            return flags.contains(.command)
        case 0x39: // Caps Lock
            return flags.contains(.capsLock)
        default:
            return true
        }
    }

    /// Notifies libghostty that the surface focus changed.
    private func notifySurfaceFocusChanged(focused: Bool) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }
        bridge.notifyFocusChanged(surfaceID: surfaceID, focused: focused)
    }

    /// Notifies libghostty that the surface size changed.
    private func notifySurfaceSizeChanged(_ newSize: NSSize) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }

        let backingSize = convertToBacking(NSRect(origin: .zero, size: newSize)).size
        let terminalSize = TerminalSize(
            columns: 0, // libghostty calculates columns from pixel size
            rows: 0,    // libghostty calculates rows from pixel size
            pixelWidth: UInt16(backingSize.width),
            pixelHeight: UInt16(backingSize.height)
        )
        bridge.resize(surfaceID, to: terminalSize)
    }

    /// Updates the layer's content scale factor for Retina displays.
    private func updateContentScale() {
        guard let window = window else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window.backingScaleFactor
        CATransaction.commit()

        // Also notify libghostty of the scale change.
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }
        bridge.notifyContentScaleChanged(
            surfaceID: surfaceID,
            scaleFactor: Double(window.backingScaleFactor)
        )
    }

    // MARK: - Text Command Handlers

    // macOS routes Backspace, Delete, and arrow keys through the
    // NSResponder command system (doCommandBySelector:) instead of keyDown
    // for views conforming to NSTextInputClient. These overrides ensure
    // terminal control keys reach libghostty.

    /// Sends a control character to the active terminal surface.
    private func sendControlCharacter(_ char: String) {
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }
        bridge.sendText(char, to: surfaceID)
    }

    /// Backspace key — sends DEL (0x7F) to the terminal.
    override func deleteBackward(_ sender: Any?) {
        sendControlCharacter("\u{7F}")
    }

    /// Forward Delete key — sends ESC[3~ to the terminal.
    override func deleteForward(_ sender: Any?) {
        sendControlCharacter("\u{1B}[3~")
    }

    /// Up arrow — sends ESC[A (cursor up).
    override func moveUp(_ sender: Any?) {
        sendControlCharacter("\u{1B}[A")
    }

    /// Down arrow — sends ESC[B (cursor down).
    override func moveDown(_ sender: Any?) {
        sendControlCharacter("\u{1B}[B")
    }

    /// Right arrow — sends ESC[C (cursor right).
    override func moveRight(_ sender: Any?) {
        sendControlCharacter("\u{1B}[C")
    }

    /// Left arrow — sends ESC[D (cursor left).
    override func moveLeft(_ sender: Any?) {
        sendControlCharacter("\u{1B}[D")
    }

    /// Home — sends ESC[H.
    override func moveToBeginningOfLine(_ sender: Any?) {
        sendControlCharacter("\u{1B}[H")
    }

    /// End — sends ESC[F.
    override func moveToEndOfLine(_ sender: Any?) {
        sendControlCharacter("\u{1B}[F")
    }

    /// Tab key fallback.
    override func insertTab(_ sender: Any?) {
        sendControlCharacter("\t")
    }

    /// Enter/Return key fallback.
    override func insertNewline(_ sender: Any?) {
        sendControlCharacter("\r")
    }

    /// Prevent the system beep on unhandled keys.
    override func noResponder(for eventSelector: Selector) {
        // Silently ignore — terminals handle all input.
    }
}

// MARK: - NSTextInputClient Conformance

extension TerminalSurfaceView: @preconcurrency NSTextInputClient {

    /// Called by the input method when text should be inserted.
    ///
    /// This is the primary text entry point for both regular typing (after
    /// interpretKeyEvents) and IME composition confirmation.
    ///
    /// - Parameters:
    ///   - string: The text to insert (String or NSAttributedString).
    ///   - replacementRange: The range to replace, or NSNotFound for append.
    func insertText(_ string: Any, replacementRange: NSRange) {
        // Clear any active composition.
        compositionState.commit()

        // Extract the plain text string.
        let text: String
        if let attributedString = string as? NSAttributedString {
            text = attributedString.string
        } else if let plainString = string as? String {
            text = plainString
        } else {
            return
        }

        guard !text.isEmpty else { return }

        // Send the text to libghostty via the bridge.
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }

        bridge.sendText(text, to: surfaceID)
    }

    /// Called by the input method to update marked (composing) text.
    ///
    /// During IME composition, this shows a preview of the text being composed.
    /// The text is typically shown underlined in the terminal.
    ///
    /// - Parameters:
    ///   - string: The marked text (String or NSAttributedString).
    ///   - selectedRange: The selected range within the marked text.
    ///   - replacementRange: The range to replace, or NSNotFound.
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let attributedString = string as? NSAttributedString {
            text = attributedString.string
        } else if let plainString = string as? String {
            text = plainString
        } else {
            return
        }

        compositionState.setMarkedText(text, selectedRange: selectedRange)

        // Send preedit text to libghostty for display.
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }

        bridge.sendPreeditText(text, to: surfaceID)
    }

    /// Called by the input method to finalize (cancel) the current composition.
    func unmarkText() {
        compositionState.unmarkText()

        // Clear preedit in libghostty.
        guard let surfaceID = viewModel.surfaceID,
              let bridge = viewModel.bridge else { return }

        bridge.sendPreeditText("", to: surfaceID)
    }

    /// Returns the range of the currently selected text.
    ///
    /// For a terminal, we report an empty selection at position 0.
    func selectedRange() -> NSRange {
        compositionState.selectedRange
    }

    /// Returns the range of the currently marked (composing) text.
    func markedRange() -> NSRange {
        compositionState.markedRange
    }

    /// Whether there is currently marked text (IME composition in progress).
    func hasMarkedText() -> Bool {
        compositionState.hasMarkedText
    }

    /// Returns the attributes supported for marked text rendering.
    ///
    /// Terminal views handle their own rendering, so we return an empty array.
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// Returns an attributed substring for the proposed range.
    ///
    /// Terminal views don't provide attributed substrings of their content
    /// through this API. Returns `nil`.
    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        nil
    }

    /// Returns the character index closest to the given point.
    ///
    /// We return 0 as a reasonable default since we don't maintain a
    /// character-level mapping between screen positions and text indices.
    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    /// Returns the rectangle for the character at the given index.
    ///
    /// This is used by the IME to position its candidate window near the
    /// text being composed. We return a rectangle near the current cursor
    /// position.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Default to the view's origin in screen coordinates.
        // When a surface is available, this should use ghostty_surface_ime_point.
        guard let window = window else {
            return NSRect(x: 0, y: 0, width: 0, height: 0)
        }

        let viewRect = NSRect(x: 0, y: 0, width: 1, height: 20)
        let windowRect = convert(viewRect, to: nil)
        return window.convertToScreen(windowRect)
    }
}

// MARK: - Mouse Button Type

/// Represents a mouse button for event forwarding.
enum MouseButton: Sendable {
    case left
    case right
    case middle
}

/// Represents a mouse action for event forwarding.
enum MouseAction: Sendable {
    case press
    case release
}

// MARK: - Scroll Delta

/// Scroll event data extracted from NSEvent for trackpad-aware scrolling.
///
/// macOS distinguishes between discrete mouse wheel scrolls and continuous
/// trackpad scrolls. This type preserves that distinction so the terminal
/// engine can handle them appropriately:
/// - Discrete scrolls: integer line steps (mouse wheel)
/// - Precise scrolls: fractional pixel offsets (trackpad, with inertia)
///
/// - SeeAlso: `NSEvent.hasPreciseScrollingDeltas`
struct ScrollDelta: Sendable {
    /// Horizontal scroll distance. Positive = right, negative = left.
    let deltaX: CGFloat

    /// Vertical scroll distance. Positive = down, negative = up.
    let deltaY: CGFloat

    /// Whether the scroll deltas are precise (trackpad) or discrete (mouse wheel).
    ///
    /// When true, deltas are fractional pixel values suitable for smooth scrolling.
    /// When false, deltas are integer line-step values.
    let hasPreciseScrollingDeltas: Bool

    /// The momentum phase for inertia scrolling.
    ///
    /// Trackpad scrolling on macOS includes a momentum phase after the user
    /// lifts their fingers. This enables "flick to scroll" behavior.
    let momentumPhase: ScrollMomentumPhase
}

/// Momentum phase for trackpad inertia scrolling.
///
/// Maps to `NSEvent.Phase` values relevant for scroll momentum:
/// - `.none`: No momentum (discrete scroll or start of gesture).
/// - `.began`: Momentum phase is starting.
/// - `.changed`: Momentum is in progress (inertia).
/// - `.ended`: Momentum has stopped.
enum ScrollMomentumPhase: Sendable, Equatable {
    case none
    case began
    case changed
    case ended
}
