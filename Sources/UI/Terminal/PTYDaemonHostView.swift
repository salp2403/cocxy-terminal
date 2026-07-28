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

    private weak var bridge: (any TerminalEngine)?
    private var surfaceID: SurfaceID?
    private var latestFrame: PTYDaemonSurfaceFrame?
    private var font: NSFont
    private var cellSize: CGSize
    private var notificationRingLayer: CAShapeLayer?
    private var eventDrainTimer: Timer?
    private var compositionState = TextCompositionState()

    private struct KeyTextInterpretation {
        var text = ""
        var didMutateComposition = false
    }

    private var activeKeyTextInterpretation: KeyTextInterpretation?
    private var isDiscardingInputMethodComposition = false
    var keyEventInterpreterOverride: ((NSEvent) -> Void)?

    private static let scrollSpeedFactor: CGFloat = 0.15

    init(viewModel: TerminalViewModel?) {
        self.viewModel = viewModel
        self.font = NSFont.monospacedSystemFont(
            ofSize: viewModel?.currentFontSize ?? 14,
            weight: .regular
        )
        self.cellSize = Self.measureCellSize(font: font)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL])
    }

    deinit {
        MainActor.assumeIsolated {
            clearComposition(forceEngineClear: true)
            eventDrainTimer?.invalidate()
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
        latestFrame = nil
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
        font = NSFont.monospacedSystemFont(
            ofSize: viewModel?.currentFontSize ?? 14,
            weight: .regular
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

    func requestImmediateRedraw() {
        needsDisplay = true
    }

    func refreshDisplayLinkAnchor() {}

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncSizeWithTerminal()
        notificationRingLayer?.frame = bounds
        notificationRingLayer?.path = CGPath(rect: bounds.insetBy(dx: 1, dy: 1), transform: nil)
    }

    override func keyDown(with event: NSEvent) {
        guard let bridge, let surfaceID else {
            super.keyDown(with: event)
            return
        }
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
            }
            bridge.sendText(controlText, to: surfaceID)
            return
        }

        let interpretation = interpretTerminalKeyEvent(event)
        if interpretation.text.isEmpty == false {
            bridge.sendText(interpretation.text, to: surfaceID)
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

        let keyEvent = KeyEvent(
            characters: event.characters,
            keyCode: UInt16(event.keyCode),
            modifiers: modifiers,
            isKeyDown: true,
            isRepeat: event.isARepeat,
            isComposing: hasMarkedText(),
            unshiftedCodepoint: event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        )
        if bridge.sendKeyEvent(keyEvent, to: surfaceID) {
            if event.keyCode == 36 {
                onUserInputSubmitted?()
            }
        }
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

    override func scrollWheel(with event: NSEvent) {
        guard let bridge, let surfaceID else {
            super.scrollWheel(with: event)
            return
        }
        let scaledDelta = event.scrollingDeltaY * Self.scrollSpeedFactor
        guard scaledDelta != 0 else { return }

        let mouseMode = latestFrame?.mouseTrackingMode ?? 0
        if mouseMode > 0,
           shouldScrollLocallyWhileMouseTracking(event) == false,
           let daemon = bridge as? PTYDaemonClient,
           let frame = latestFrame {
            let position = cellPosition(for: event, frame: frame)
            let button: UInt8 = scaledDelta > 0 ? 64 : 65
            let count = max(1, Int(abs(scaledDelta)))
            daemon.sendRawBytes(
                Self.mouseWheelPayload(
                    button: button,
                    mouseMode: mouseMode,
                    row: position.row,
                    column: position.column,
                    count: count
                ),
                to: surfaceID
            )
            return
        }

        let steps = max(1, Int(abs(scaledDelta.rounded(.towardZero))))
        bridge.scrollViewport(
            surfaceID: surfaceID,
            deltaRows: scaledDelta > 0 ? steps : -steps
        )
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
            guard cell.glyph != 0, cell.glyph != 32,
                  let scalar = UnicodeScalar(cell.glyph) else { continue }
            let rect = CGRect(
                x: CGFloat(cell.column) * cellSize.width,
                y: CGFloat(cell.row) * cellSize.height,
                width: cellSize.width,
                height: cellSize.height
            )
            NSColor(rgba: cell.backgroundRGBA).setFill()
            rect.fill()
            var cellAttributes = attributes
            cellAttributes[.foregroundColor] = NSColor(rgba: cell.foregroundRGBA)
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

    private func apply(_ frame: PTYDaemonSurfaceFrame) {
        guard let surfaceID,
              UUID(uuidString: frame.surfaceID) == surfaceID.rawValue else { return }
        if let latestFrame, frame.revision <= latestFrame.revision {
            return
        }
        self.latestFrame = frame
        needsDisplay = true
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

    private static func keyModifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
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

    private func shouldScrollLocallyWhileMouseTracking(_ event: NSEvent) -> Bool {
        if prefersLocalScrollInMouseTrackingMode?() == true {
            return true
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.contains(.option) || modifiers.contains(.shift)
    }

    private func cellPosition(
        for event: NSEvent,
        frame: PTYDaemonSurfaceFrame
    ) -> (row: UInt16, column: UInt16) {
        let location = convert(event.locationInWindow, from: nil)
        let rawColumn = max(0, Int(location.x / max(1, cellSize.width)))
        let rawRow = max(0, Int(location.y / max(1, cellSize.height)))
        return (
            row: UInt16(min(rawRow, max(0, Int(frame.rows) - 1))),
            column: UInt16(min(rawColumn, max(0, Int(frame.columns) - 1)))
        )
    }

    static func mouseWheelPayload(
        button: UInt8,
        mouseMode: UInt8,
        row: UInt16,
        column: UInt16,
        count: Int
    ) -> Data {
        let repetitions = max(1, count)
        let event: Data
        if mouseMode == 6 {
            event = Data("\u{1B}[<\(button);\(column + 1);\(row + 1)M".utf8)
        } else {
            event = Data([
                0x1B,
                0x5B,
                0x4D,
                UInt8(clamping: Int(button) + 32),
                UInt8(clamping: Int(column) + 33),
                UInt8(clamping: Int(row) + 33),
            ])
        }

        var payload = Data()
        payload.reserveCapacity(event.count * repetitions)
        for _ in 0..<repetitions {
            payload.append(event)
        }
        return payload
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
