// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonHostView.swift - Host renderer for daemon-backed terminal frames.

import AppKit
import CocxyShared

@MainActor
final class PTYDaemonHostView: NSView, TerminalHostingView {
    private(set) weak var viewModel: TerminalViewModel?
    var terminalViewModel: TerminalViewModel? { viewModel }
    var onFileDrop: (([URL]) -> Bool)?
    var onUserInputSubmitted: (() -> Void)?
    var onFramePresented: (() -> Void)?
    var prefersLocalScrollInMouseTrackingMode: (() -> Bool)?
    var onTerminalInteractionStateChanged: (() -> Void)?
    var onFocusRequested: (() -> Void)?
    var clipboardService: ClipboardServiceProtocol = SystemClipboardService()

    private weak var bridge: (any TerminalEngine)?
    private var surfaceID: SurfaceID?
    private var latestFrame: PTYDaemonSurfaceFrame?
    private var latestReceivedFrameRevision: UInt64?
    private var pendingSynchronizedFrame: PTYDaemonSurfaceFrame?
    private var synchronizedOutputGate = SynchronizedOutputPresentationGate()
    private var synchronizedOutputFlushWorkItem: DispatchWorkItem?
    var synchronizedOutputClock: () -> TimeInterval = {
        ProcessInfo.processInfo.systemUptime
    }
    private var fontFamily: String
    private var font: NSFont
    private var cellSize: CGSize
    private var notificationRingLayer: CAShapeLayer?
    private var eventDrainTimer: Timer?
    private(set) var historyPillView: TerminalHistoryPillView?
    private var lastNotifiedMouseTrackingActive: Bool?
    private var mouseMotionTrackingArea: NSTrackingArea?
    private var terminalMouseCaptureByButton: [TerminalMouseButton: Bool] = [:]
    private var localSelectionAnchor: PTYDaemonGridPosition?
    private var localSelection: PTYDaemonGridSelection?
    private var isDraggingLocalSelection = false
    private var compositionState = TextCompositionState()

    private struct KeyTextInterpretation {
        var text = ""
        var didMutateComposition = false
    }

    private var activeKeyTextInterpretation: KeyTextInterpretation?
    private var isDiscardingInputMethodComposition = false
    private var forwardedKeyCodes = Set<UInt16>()
    var keyEventInterpreterOverride: ((NSEvent) -> Void)?

    init(
        viewModel: TerminalViewModel?,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.viewModel = viewModel
        let initialFamily = AppearanceConfig.defaults.fontFamily
        let initialFont = Self.resolveFont(
            family: initialFamily,
            size: viewModel?.currentFontSize ?? 14
        )
        self.fontFamily = initialFamily
        self.font = initialFont
        self.cellSize = Self.measureCellSize(font: initialFont)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
        installHistoryPill(localizer: localizer)
    }

    deinit {
        MainActor.assumeIsolated {
            clearComposition(forceEngineClear: true)
            eventDrainTimer?.invalidate()
            synchronizedOutputFlushWorkItem?.cancel()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let surfaceID {
            bridge?.notifyFocus(true, for: surfaceID)
        }
        return true
    }

    override func resignFirstResponder() -> Bool {
        clearComposition(forceEngineClear: true, discardInputContext: true)
        if let surfaceID {
            bridge?.notifyFocus(false, for: surfaceID)
        }
        return true
    }

    func configureSurfaceIfNeeded(bridge: any TerminalEngine, surfaceID: SurfaceID) {
        guard self.surfaceID != surfaceID else { return }
        clearComposition(forceEngineClear: true, discardInputContext: true)
        synchronizedOutputFlushWorkItem?.cancel()
        synchronizedOutputFlushWorkItem = nil
        synchronizedOutputGate.reset()
        pendingSynchronizedFrame = nil
        latestReceivedFrameRevision = nil
        latestFrame = nil
        forwardedKeyCodes.removeAll()
        terminalMouseCaptureByButton.removeAll()
        clearLocalSelection()
        self.bridge = bridge
        self.surfaceID = surfaceID
        if let daemon = bridge as? PTYDaemonClient {
            daemon.setFrameHandler(for: surfaceID) { [weak self] frame in
                Task { @MainActor in
                    self?.apply(frame)
                }
            }
            if let initialFrame = daemon.subscribeFrames(for: surfaceID) {
                apply(initialFrame)
            }
            startEventDrainTimerIfNeeded()
        }
        syncSizeWithTerminal()
        requestImmediateRedraw()
    }

    func syncSizeWithTerminal() {
        font = Self.resolveFont(
            family: fontFamily,
            size: viewModel?.currentFontSize ?? 14
        )
        cellSize = Self.measureCellSize(font: font)
        guard let bridge, let surfaceID else { return }
        let columns = UInt16(max(1, Int(bounds.width / max(1, cellSize.width))))
        let rows = UInt16(max(1, Int(bounds.height / max(1, cellSize.height))))
        bridge.resize(
            surfaceID,
            to: TerminalSize(
                columns: columns,
                rows: rows,
                pixelWidth: UInt16(clamping: Int(bounds.width)),
                pixelHeight: UInt16(clamping: Int(bounds.height))
            )
        )
    }

    func showNotificationRing(color: NSColor) {
        wantsLayer = true
        let ring = notificationRingLayer ?? CAShapeLayer()
        ring.strokeColor = color.cgColor
        ring.fillColor = NSColor.clear.cgColor
        ring.lineWidth = 2
        ring.frame = bounds
        ring.path = CGPath(rect: bounds.insetBy(dx: 1, dy: 1), transform: nil)
        if notificationRingLayer == nil {
            layer?.addSublayer(ring)
            notificationRingLayer = ring
        }
    }

    func hideNotificationRing() {
        notificationRingLayer?.removeFromSuperlayer()
        notificationRingLayer = nil
    }

    func handleShellPrompt(row: Int, column: Int) {}

    func updateInteractionMetrics() {
        syncSizeWithTerminal()
    }

    func applyFont(family: String, size: Double) {
        fontFamily = family
        viewModel?.setCurrentFontSize(CGFloat(size))
        syncSizeWithTerminal()
        requestImmediateRedraw()
    }

    func requestImmediateRedraw() {
        needsDisplay = true
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        historyPillView?.updateLocalizer(localizer)
    }

    func refreshDisplayLinkAnchor() {}

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSizeWithTerminal()
        notificationRingLayer?.frame = bounds
        notificationRingLayer?.path = CGPath(rect: bounds.insetBy(dx: 1, dy: 1), transform: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let mouseMotionTrackingArea {
            removeTrackingArea(mouseMotionTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        mouseMotionTrackingArea = trackingArea
    }

    override func keyDown(with event: NSEvent) {
        if performTerminalViewportKeyEquivalent(with: event) {
            return
        }
        guard let bridge, let surfaceID else {
            super.keyDown(with: event)
            return
        }
        followLiveViewportBeforeUserInput()
        let modifiers = Self.keyModifiers(from: event.modifierFlags)
        let wasComposing = hasMarkedText()

        if wasComposing, event.keyCode == 53 {
            clearComposition(forceEngineClear: true, discardInputContext: true)
            return
        }

        if let controlText = Self.controlCharacterText(
            for: event,
            modifiers: modifiers
        ) {
            if wasComposing {
                commitComposition(bridge: bridge, surfaceID: surfaceID)
                bridge.sendText(controlText, to: surfaceID)
                return
            }
            let keyEvent = MacTerminalKeyEventTranslator.event(
                from: event,
                characters: event.charactersIgnoringModifiers,
                isKeyDown: true,
                isComposing: false
            )
            if bridge.sendKeyEvent(keyEvent, to: surfaceID) {
                forwardedKeyCodes.insert(event.keyCode)
            } else {
                bridge.sendText(controlText, to: surfaceID)
            }
            return
        }

        let interpretation = interpretTerminalKeyEvent(event)
        if interpretation.text.isEmpty == false {
            let mustPreserveCommittedText = interpretation.didMutateComposition
                || (event.keyCode == 36 && modifiers.contains(.shift))
                || CocxyCoreView.literalTextForOptionGeneratedCharacter(
                    characters: interpretation.text,
                    charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                    modifiers: modifiers
                ) != nil
            if mustPreserveCommittedText {
                bridge.sendText(interpretation.text, to: surfaceID)
            } else {
                let keyEvent = MacTerminalKeyEventTranslator.event(
                    from: event,
                    characters: interpretation.text,
                    isKeyDown: true,
                    isComposing: false
                )
                if bridge.sendKeyEvent(keyEvent, to: surfaceID) {
                    forwardedKeyCodes.insert(event.keyCode)
                } else {
                    bridge.sendText(interpretation.text, to: surfaceID)
                }
            }
            if Self.containsInputSubmission(interpretation.text),
               modifiers.contains(.shift) == false {
                onUserInputSubmitted?()
            }
            return
        }
        if hasMarkedText() {
            return
        }
        if interpretation.didMutateComposition {
            return
        }
        let keyEvent = MacTerminalKeyEventTranslator.event(
            from: event,
            isKeyDown: true,
            isComposing: hasMarkedText()
        )
        if bridge.sendKeyEvent(keyEvent, to: surfaceID) {
            forwardedKeyCodes.insert(event.keyCode)
            if event.keyCode == 36 {
                onUserInputSubmitted?()
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let bridge,
              let surfaceID,
              forwardedKeyCodes.remove(event.keyCode) != nil else { return }
        _ = bridge.sendKeyEvent(
            MacTerminalKeyEventTranslator.event(
                from: event,
                isKeyDown: false,
                isComposing: hasMarkedText()
            ),
            to: surfaceID
        )
    }

    override func flagsChanged(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
        guard let bridge,
              let surfaceID,
              let isKeyDown = MacTerminalKeyEventTranslator.modifierIsActive(
                  keyCode: event.keyCode,
                  flags: event.modifierFlags
              ) else { return }
        _ = bridge.sendKeyEvent(
            MacTerminalKeyEventTranslator.event(
                from: event,
                isKeyDown: isKeyDown,
                isComposing: hasMarkedText()
            ),
            to: surfaceID
        )
    }

    private func interpretTerminalKeyEvent(_ event: NSEvent) -> KeyTextInterpretation {
        activeKeyTextInterpretation = KeyTextInterpretation()
        defer { activeKeyTextInterpretation = nil }

        if let keyEventInterpreterOverride {
            keyEventInterpreterOverride(event)
        } else {
            interpretKeyEvents([event])
        }

        return activeKeyTextInterpretation ?? KeyTextInterpretation()
    }

    private func commitComposition(
        bridge: any TerminalEngine,
        surfaceID: SurfaceID
    ) {
        guard compositionState.hasMarkedText else { return }
        let markedText = compositionState.markedText
        compositionState.commit()
        discardInputMethodComposition()
        bridge.sendPreeditText("", cursorByteOffset: 0, to: surfaceID)
        if markedText.isEmpty == false {
            bridge.sendText(markedText, to: surfaceID)
        }
    }

    private func clearComposition(
        forceEngineClear: Bool = false,
        discardInputContext: Bool = false
    ) {
        let hadMarkedText = compositionState.hasMarkedText
        compositionState.unmarkText()
        if discardInputContext, hadMarkedText {
            discardInputMethodComposition()
        }
        guard hadMarkedText || forceEngineClear,
              let bridge,
              let surfaceID else { return }
        bridge.sendPreeditText("", cursorByteOffset: 0, to: surfaceID)
    }

    private func discardInputMethodComposition() {
        guard isDiscardingInputMethodComposition == false else { return }
        isDiscardingInputMethodComposition = true
        defer { isDiscardingInputMethodComposition = false }
        inputContext?.discardMarkedText()
        // The context can synchronously re-enter this client while discarding.
        compositionState.unmarkText()
    }

    override func doCommand(by selector: Selector) {
        guard activeKeyTextInterpretation == nil else { return }
        super.doCommand(by: selector)
    }

    @discardableResult
    private func sendResponderKey(keyCode: UInt16) -> Bool {
        guard activeKeyTextInterpretation == nil,
              let bridge,
              let surfaceID else { return false }
        followLiveViewportBeforeUserInput()
        return bridge.sendKeyEvent(
            KeyEvent(
                characters: nil,
                keyCode: keyCode,
                modifiers: [],
                isKeyDown: true,
                isComposing: hasMarkedText()
            ),
            to: surfaceID
        )
    }

    override func moveUp(_ sender: Any?) { _ = sendResponderKey(keyCode: 126) }
    override func moveDown(_ sender: Any?) { _ = sendResponderKey(keyCode: 125) }
    override func moveRight(_ sender: Any?) { _ = sendResponderKey(keyCode: 124) }
    override func moveLeft(_ sender: Any?) { _ = sendResponderKey(keyCode: 123) }
    override func moveToBeginningOfLine(_ sender: Any?) { _ = sendResponderKey(keyCode: 115) }
    override func moveToEndOfLine(_ sender: Any?) { _ = sendResponderKey(keyCode: 119) }

    override func mouseDown(with event: NSEvent) {
        onFocusRequested?()
        viewModel?.recordMouseDown(clickCount: event.clickCount)
        if beginTerminalMouseGesture(button: .left, event: event) {
            localSelectionAnchor = nil
            isDraggingLocalSelection = false
            return
        }
        guard beginLocalSelection(with: event) else {
            super.mouseDown(with: event)
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if continueTerminalMouseGesture(button: .left, event: event) {
            return
        }
        guard updateLocalSelection(with: event) else {
            super.mouseDragged(with: event)
            return
        }
    }

    override func mouseUp(with event: NSEvent) {
        viewModel?.recordMouseUp()
        if endTerminalMouseGesture(button: .left, event: event) {
            localSelectionAnchor = nil
            isDraggingLocalSelection = false
            return
        }
        guard localSelectionAnchor != nil else {
            super.mouseUp(with: event)
            return
        }
        finishLocalSelection()
    }

    override func rightMouseDown(with event: NSEvent) {
        onFocusRequested?()
        if beginTerminalMouseGesture(button: .right, event: event) {
            return
        }
        super.rightMouseDown(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if continueTerminalMouseGesture(button: .right, event: event) {
            return
        }
        super.rightMouseDragged(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        if endTerminalMouseGesture(button: .right, event: event) {
            return
        }
        super.rightMouseUp(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onFocusRequested?()
        guard let button = TerminalMouseButton(appKitButtonNumber: event.buttonNumber) else {
            super.otherMouseDown(with: event)
            return
        }
        if beginTerminalMouseGesture(button: button, event: event) {
            return
        }
        super.otherMouseDown(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard let button = TerminalMouseButton(appKitButtonNumber: event.buttonNumber) else {
            super.otherMouseDragged(with: event)
            return
        }
        if continueTerminalMouseGesture(button: button, event: event) {
            return
        }
        super.otherMouseDragged(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let button = TerminalMouseButton(appKitButtonNumber: event.buttonNumber) else {
            super.otherMouseUp(with: event)
            return
        }
        if endTerminalMouseGesture(button: button, event: event) {
            return
        }
        super.otherMouseUp(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard terminalReportsCurrentUnbuttonedMotion(event) else {
            super.mouseMoved(with: event)
            return
        }
        reportTerminalMouse(action: .motion, button: nil, event: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let bridge,
              let surfaceID,
              let frame = latestFrame else {
            super.scrollWheel(with: event)
            return
        }
        guard event.scrollingDeltaY != 0 else { return }

        let mouseModes = Self.mouseModes(for: frame)
        let destination = TerminalScrollRouter.destination(
            localRange: UInt32(clamping: frame.historyMaxVisibleStart),
            prefersLocal: prefersLocalScrollInMouseTrackingMode?() == true,
            mouseTrackingMode: mouseModes.tracking,
            modifiers: event.modifierFlags
        )

        switch destination {
        case .terminalApplication:
            guard let daemon = bridge as? PTYDaemonClient else { return }
            let position = mousePosition(for: event, frame: frame)
            daemon.sendRawBytes(
                TerminalMouseWireEncoder.wheelPayload(
                    button: event.scrollingDeltaY > 0 ? 64 : 65,
                    encodingRawValue: mouseModes.encoding,
                    row: position.row,
                    column: position.column,
                    pixelX: position.pixelX,
                    pixelY: position.pixelY,
                    count: TerminalScrollWheelMetrics.forwardedEventCount(for: event)
                ),
                to: surfaceID
            )
            return
        case .localViewport:
            let deltaRows = TerminalScrollWheelMetrics.localDeltaRows(for: event)
            guard deltaRows != 0 else { return }
            bridge.scrollViewport(surfaceID: surfaceID, deltaRows: deltaRows)
        case .none:
            return
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)

        guard let frame = latestFrame else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.86, alpha: 1),
        ]

        for cell in frame.cells {
            let rect = CGRect(
                x: CGFloat(cell.column) * cellSize.width,
                y: CGFloat(cell.row) * cellSize.height,
                width: cellSize.width,
                height: cellSize.height
            )
            let isSelected = localSelection?.contains(
                row: cell.row,
                column: cell.column,
                columnCount: frame.columns
            ) == true
            if isSelected {
                NSColor.selectedTextBackgroundColor.setFill()
                rect.fill()
            }

            guard cell.glyph != 0, cell.glyph != 32,
                  let scalar = UnicodeScalar(cell.glyph) else { continue }
            if !isSelected {
                NSColor(rgba: cell.backgroundRGBA).setFill()
                rect.fill()
            }
            var cellAttributes = attributes
            cellAttributes[.foregroundColor] = isSelected
                ? NSColor.selectedTextColor
                : NSColor(rgba: cell.foregroundRGBA)
            String(scalar).draw(
                at: CGPoint(x: rect.minX, y: rect.minY),
                withAttributes: cellAttributes
            )
        }

        if frame.cursor.visible {
            let cursorRect = CGRect(
                x: CGFloat(frame.cursor.column) * cellSize.width,
                y: CGFloat(frame.cursor.row) * cellSize.height,
                width: max(2, cellSize.width),
                height: cellSize.height
            )
            context.setFillColor(NSColor(calibratedWhite: 0.9, alpha: 0.35).cgColor)
            switch frame.cursor.style {
            case "bar":
                context.fill(cursorRect.insetBy(dx: max(1, cellSize.width - 2), dy: 1))
            case "underline":
                context.fill(CGRect(x: cursorRect.minX, y: cursorRect.maxY - 2, width: cursorRect.width, height: 2))
            default:
                context.fill(cursorRect)
            }
        }

        if let onFramePresented {
            self.onFramePresented = nil
            onFramePresented()
        }
    }

    func apply(_ frame: PTYDaemonSurfaceFrame) {
        guard let surfaceID,
              UUID(uuidString: frame.surfaceID) == surfaceID.rawValue else { return }
        if let latestReceivedFrameRevision,
           frame.revision <= latestReceivedFrameRevision {
            return
        }
        latestReceivedFrameRevision = frame.revision

        if let delay = synchronizedOutputGate.presentationDelay(
            isActive: frame.synchronizedOutput,
            now: synchronizedOutputClock()
        ) {
            pendingSynchronizedFrame = frame
            scheduleSynchronizedOutputFlush(after: delay)
            return
        }

        synchronizedOutputFlushWorkItem?.cancel()
        synchronizedOutputFlushWorkItem = nil
        pendingSynchronizedFrame = nil
        present(frame)
    }

    private func present(_ frame: PTYDaemonSurfaceFrame) {
        if let latestFrame,
           latestFrame.surfaceID != frame.surfaceID ||
            latestFrame.columns != frame.columns ||
            latestFrame.rows != frame.rows {
            clearLocalSelection()
        }
        self.latestFrame = frame
        refreshHistoryPill(using: frame)
        needsDisplay = true
    }

    private func scheduleSynchronizedOutputFlush(after delay: TimeInterval) {
        synchronizedOutputFlushWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushPendingSynchronizedFrame()
            }
        }
        synchronizedOutputFlushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: workItem)
    }

    private func flushPendingSynchronizedFrame() {
        guard let frame = pendingSynchronizedFrame else {
            synchronizedOutputFlushWorkItem = nil
            return
        }
        if let delay = synchronizedOutputGate.presentationDelay(
            isActive: true,
            now: synchronizedOutputClock()
        ) {
            scheduleSynchronizedOutputFlush(after: delay)
            return
        }

        pendingSynchronizedFrame = nil
        synchronizedOutputFlushWorkItem = nil
        present(frame)
    }

    var latestFrameRevisionForTesting: UInt64? { latestFrame?.revision }
    var hasPendingSynchronizedFrameForTesting: Bool { pendingSynchronizedFrame != nil }
    var renderedFontFamilyForTesting: String? { font.familyName }
    var renderedFontPointSizeForTesting: CGFloat { font.pointSize }

    func flushPendingSynchronizedFrameForTesting() {
        synchronizedOutputFlushWorkItem?.cancel()
        synchronizedOutputFlushWorkItem = nil
        flushPendingSynchronizedFrame()
    }

    var isTerminalMouseTrackingActive: Bool {
        guard let latestFrame else { return false }
        return Self.mouseModes(for: latestFrame).tracking > 0
    }

    func performLocalViewportScroll(_ command: TerminalViewportScrollCommand) {
        guard let bridge, let surfaceID, let latestFrame else { return }
        let pageRows = max(1, Int(latestFrame.rows))
        let deltaRows: Int
        switch command {
        case .pageUp:
            deltaRows = pageRows
        case .pageDown:
            deltaRows = -pageRows
        case .top:
            deltaRows = Int(Int32.max)
        case .bottom:
            deltaRows = Int(Int32.min)
        }
        bridge.scrollViewport(surfaceID: surfaceID, deltaRows: deltaRows)
        if command == .bottom {
            historyPillView?.update(linesAbove: 0)
        }
    }

    private func installHistoryPill(localizer: AppLocalizer) {
        let pill = TerminalHistoryPillView(localizer: localizer)
        pill.onJumpToBottom = { [weak self] in
            self?.performLocalViewportScroll(.bottom)
        }
        addSubview(pill)
        NSLayoutConstraint.activate([
            pill.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            pill.centerXAnchor.constraint(equalTo: centerXAnchor),
            pill.heightAnchor.constraint(equalToConstant: 28),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            pill.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
        ])
        historyPillView = pill
    }

    private func refreshHistoryPill(using frame: PTYDaemonSurfaceFrame) {
        let offset = max(0, frame.historyMaxVisibleStart - frame.scrollbackTop)
        historyPillView?.update(linesAbove: UInt32(clamping: offset))
        let isMouseTrackingActive = Self.mouseModes(for: frame).tracking > 0
        if lastNotifiedMouseTrackingActive != isMouseTrackingActive {
            lastNotifiedMouseTrackingActive = isMouseTrackingActive
            onTerminalInteractionStateChanged?()
        }
    }

    private func followLiveViewportBeforeUserInput() {
        guard let latestFrame,
              latestFrame.historyMaxVisibleStart > latestFrame.scrollbackTop else { return }
        performLocalViewportScroll(.bottom)
    }

    private func startEventDrainTimerIfNeeded() {
        guard eventDrainTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.bridge?.tick()
            }
        }
        eventDrainTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func measureCellSize(font: NSFont) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = ("M" as NSString).size(withAttributes: attributes)
        return CGSize(width: max(1, ceil(size.width)), height: max(1, ceil(font.ascender - font.descender + font.leading)))
    }

    private static func resolveFont(family: String, size: CGFloat) -> NSFont {
        NSFont(name: family, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    private func performTerminalViewportKeyEquivalent(with event: NSEvent) -> Bool {
        guard let menu = NSApp.mainMenu,
              MenuKeybindingsBinder.matches(
                event,
                actionIds: TerminalViewportScrollCommand.keybindingActionIDs,
                in: menu
              ) else { return false }
        return menu.performKeyEquivalent(with: event)
    }

    private static func keyModifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        MacTerminalKeyEventTranslator.modifiers(from: flags)
    }

    private func beginTerminalMouseGesture(
        button: TerminalMouseButton,
        event: NSEvent
    ) -> Bool {
        let captures = terminalCapturesCurrentMouseEvent(event)
        terminalMouseCaptureByButton[button] = captures
        guard captures else { return false }
        reportTerminalMouse(action: .press, button: button, event: event)
        return true
    }

    private func continueTerminalMouseGesture(
        button: TerminalMouseButton,
        event: NSEvent
    ) -> Bool {
        let captures = terminalMouseCaptureByButton[button]
            ?? terminalCapturesCurrentMouseEvent(event)
        guard captures else { return false }
        reportTerminalMouse(action: .motion, button: button, event: event)
        return true
    }

    private func endTerminalMouseGesture(
        button: TerminalMouseButton,
        event: NSEvent
    ) -> Bool {
        let captures = terminalMouseCaptureByButton.removeValue(forKey: button)
            ?? terminalCapturesCurrentMouseEvent(event)
        guard captures else { return false }
        reportTerminalMouse(action: .release, button: button, event: event)
        return true
    }

    private func terminalCapturesCurrentMouseEvent(_ event: NSEvent) -> Bool {
        guard let latestFrame else { return false }
        return TerminalMouseCapturePolicy.terminalCaptures(
            trackingRawValue: Self.mouseModes(for: latestFrame).tracking,
            modifiers: event.modifierFlags
        )
    }

    private func terminalReportsCurrentUnbuttonedMotion(_ event: NSEvent) -> Bool {
        guard let latestFrame else { return false }
        let tracking = Self.mouseModes(for: latestFrame).tracking
        return TerminalMouseCapturePolicy.terminalCaptures(
            trackingRawValue: tracking,
            modifiers: event.modifierFlags
        ) && TerminalMouseTracking
            .normalized(rawValue: tracking)
            .reports(.motion, hasButton: false)
    }

    private func reportTerminalMouse(
        action: TerminalMouseAction,
        button: TerminalMouseButton?,
        event: NSEvent
    ) {
        guard let daemon = bridge as? PTYDaemonClient,
              let surfaceID,
              let frame = latestFrame else {
            return
        }
        let modes = Self.mouseModes(for: frame)
        let position = mousePosition(for: event, frame: frame)
        guard let payload = TerminalMouseWireEncoder.buttonPayload(
            action: action,
            button: button,
            trackingRawValue: modes.tracking,
            encodingRawValue: modes.encoding,
            row: position.row,
            column: position.column,
            pixelX: position.pixelX,
            pixelY: position.pixelY,
            modifiers: event.modifierFlags
        ) else { return }
        daemon.sendRawBytes(payload, to: surfaceID)
    }

    private static func controlCharacterText(
        for event: NSEvent,
        modifiers: KeyModifiers
    ) -> String? {
        guard modifiers.contains(.control),
              modifiers.contains(.command) == false,
              let scalar = event.charactersIgnoringModifiers?
                .lowercased()
                .unicodeScalars
                .first else { return nil }
        return ControlCharacterMapper.controlCharacterText(forLetter: String(scalar))
    }

    private static func containsInputSubmission(_ text: String) -> Bool {
        text.contains("\r") || text.contains("\n")
    }

    private func beginLocalSelection(with event: NSEvent) -> Bool {
        guard let frame = latestFrame else { return false }
        let position = mousePosition(for: event, frame: frame)
        localSelectionAnchor = PTYDaemonGridPosition(
            row: position.row,
            column: position.column
        )
        localSelection = nil
        isDraggingLocalSelection = false
        needsDisplay = true
        return true
    }

    private func updateLocalSelection(with event: NSEvent) -> Bool {
        guard let frame = latestFrame,
              let anchor = localSelectionAnchor else {
            return false
        }
        let position = mousePosition(for: event, frame: frame)
        localSelection = PTYDaemonGridSelection(
            anchor: anchor,
            head: PTYDaemonGridPosition(row: position.row, column: position.column)
        )
        isDraggingLocalSelection = true
        needsDisplay = true
        return true
    }

    private func finishLocalSelection() {
        if isDraggingLocalSelection,
           viewModel?.autoCopyOnSelect == true,
           let frame = latestFrame,
           let text = localSelection?.text(in: frame),
           !text.isEmpty {
            clipboardService.write(text)
        }
        localSelectionAnchor = nil
        isDraggingLocalSelection = false
        needsDisplay = true
    }

    private func clearLocalSelection() {
        localSelectionAnchor = nil
        localSelection = nil
        isDraggingLocalSelection = false
        needsDisplay = true
    }

    private func mousePosition(
        for event: NSEvent,
        frame: PTYDaemonSurfaceFrame
    ) -> (row: UInt16, column: UInt16, pixelX: Int, pixelY: Int) {
        let location = convert(event.locationInWindow, from: nil)
        let rawColumn = max(0, Int(location.x / max(1, cellSize.width)))
        let rawRow = max(0, Int(location.y / max(1, cellSize.height)))
        let scale = window?.backingScaleFactor ?? 1
        return (
            row: UInt16(min(rawRow, max(0, Int(frame.rows) - 1))),
            column: UInt16(min(rawColumn, max(0, Int(frame.columns) - 1))),
            pixelX: max(0, Int(location.x * scale)),
            pixelY: max(0, Int(location.y * scale))
        )
    }

    private static func mouseModes(for frame: PTYDaemonSurfaceFrame) -> (tracking: UInt8, encoding: UInt8) {
        if let encoding = frame.mouseEncodingMode {
            return (frame.mouseTrackingMode ?? 0, encoding)
        }

        let legacyMode = frame.mouseTrackingMode ?? 0
        if legacyMode == 6 {
            return (2, TerminalMouseEncoding.sgr.rawValue)
        }
        return (legacyMode, TerminalMouseEncoding.x10.rawValue)
    }

    static func mouseWheelPayload(
        button: UInt8,
        mouseMode: UInt8,
        row: UInt16,
        column: UInt16,
        count: Int
    ) -> Data {
        TerminalMouseWireEncoder.wheelPayload(
            button: button,
            encodingRawValue: mouseMode == 6
                ? TerminalMouseEncoding.sgr.rawValue
                : TerminalMouseEncoding.x10.rawValue,
            row: row,
            column: column,
            pixelX: Int(column),
            pixelY: Int(row),
            count: count
        )
    }
}

private struct PTYDaemonGridPosition: Equatable {
    let row: UInt16
    let column: UInt16

    func linearIndex(columnCount: UInt16) -> Int {
        Int(row) * max(1, Int(columnCount)) + Int(column)
    }
}

private struct PTYDaemonGridSelection: Equatable {
    let anchor: PTYDaemonGridPosition
    let head: PTYDaemonGridPosition

    func contains(row: UInt16, column: UInt16, columnCount: UInt16) -> Bool {
        let candidate = PTYDaemonGridPosition(row: row, column: column)
            .linearIndex(columnCount: columnCount)
        let anchorIndex = anchor.linearIndex(columnCount: columnCount)
        let headIndex = head.linearIndex(columnCount: columnCount)
        return (min(anchorIndex, headIndex)...max(anchorIndex, headIndex)).contains(candidate)
    }

    func text(in frame: PTYDaemonSurfaceFrame) -> String? {
        guard frame.columns > 0, frame.rows > 0 else { return nil }
        let columnCount = Int(frame.columns)
        let maximumIndex = Int(frame.rows) * columnCount - 1
        let anchorIndex = min(anchor.linearIndex(columnCount: frame.columns), maximumIndex)
        let headIndex = min(head.linearIndex(columnCount: frame.columns), maximumIndex)
        let lowerBound = min(anchorIndex, headIndex)
        let upperBound = max(anchorIndex, headIndex)
        var glyphByIndex: [Int: UInt32] = [:]
        for cell in frame.cells {
            glyphByIndex[Int(cell.row) * columnCount + Int(cell.column)] = cell.glyph
        }

        var lines: [String] = []
        for row in (lowerBound / columnCount)...(upperBound / columnCount) {
            let rowStart = row * columnCount
            let start = max(lowerBound, rowStart)
            let end = min(upperBound, rowStart + columnCount - 1)
            var line = ""
            for index in start...end {
                if let glyph = glyphByIndex[index],
                   glyph != 0,
                   let scalar = UnicodeScalar(glyph) {
                    line.append(Character(scalar))
                } else {
                    line.append(" ")
                }
            }
            while line.last == " " {
                line.removeLast()
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - NSTextInputClient Conformance

extension PTYDaemonHostView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else if let plain = string as? String {
            text = plain
        } else {
            return
        }
        guard text.isEmpty == false else { return }

        let wasComposing = compositionState.hasMarkedText
        compositionState.commit()
        if wasComposing, let bridge, let surfaceID {
            bridge.sendPreeditText("", cursorByteOffset: 0, to: surfaceID)
        }
        if activeKeyTextInterpretation != nil {
            activeKeyTextInterpretation?.text.append(contentsOf: text)
            if wasComposing {
                activeKeyTextInterpretation?.didMutateComposition = true
            }
            return
        }

        guard let bridge, let surfaceID else { return }
        bridge.sendText(text, to: surfaceID)
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        let text: String
        if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else if let plain = string as? String {
            text = plain
        } else {
            return
        }

        compositionState.setMarkedText(text, selectedRange: selectedRange)
        if activeKeyTextInterpretation != nil {
            activeKeyTextInterpretation?.didMutateComposition = true
        }
        guard let bridge, let surfaceID else { return }
        bridge.sendPreeditText(
            text,
            cursorByteOffset: compositionState.cursorUTF8ByteOffset,
            to: surfaceID
        )
    }

    func unmarkText() {
        compositionState.unmarkText()
        if activeKeyTextInterpretation != nil {
            activeKeyTextInterpretation?.didMutateComposition = true
        }
        guard isDiscardingInputMethodComposition == false else { return }
        guard let bridge, let surfaceID else { return }
        bridge.sendPreeditText("", cursorByteOffset: 0, to: surfaceID)
    }

    func hasMarkedText() -> Bool {
        compositionState.hasMarkedText
    }

    func markedRange() -> NSRange {
        compositionState.markedRange
    }

    func selectedRange() -> NSRange {
        compositionState.hasMarkedText
            ? compositionState.selectedRange
            : NSRange(location: NSNotFound, length: 0)
    }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: UnsafeMutablePointer<NSRange>?
    ) -> NSRect {
        guard let frame = latestFrame else {
            return window?.convertToScreen(
                NSRect(origin: .zero, size: CGSize(width: 1, height: cellSize.height))
            ) ?? .zero
        }
        let viewRect = NSRect(
            x: CGFloat(frame.cursor.column) * cellSize.width,
            y: CGFloat(frame.cursor.row) * cellSize.height,
            width: cellSize.width,
            height: cellSize.height
        )
        let windowRect = convert(viewRect, to: nil)
        return window?.convertToScreen(windowRect) ?? viewRect
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: UnsafeMutablePointer<NSRange>?
    ) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .foregroundColor]
    }
}

private extension NSColor {
    convenience init(rgba: UInt32) {
        self.init(
            srgbRed: CGFloat((rgba >> 24) & 0xff) / 255,
            green: CGFloat((rgba >> 16) & 0xff) / 255,
            blue: CGFloat((rgba >> 8) & 0xff) / 255,
            alpha: CGFloat(rgba & 0xff) / 255
        )
    }
}
