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

    private weak var bridge: (any TerminalEngine)?
    private var surfaceID: SurfaceID?
    private var latestFrame: PTYDaemonSurfaceFrame?
    private var font: NSFont
    private var cellSize: CGSize
    private var notificationRingLayer: CAShapeLayer?
    private var eventDrainTimer: Timer?

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
        if let surfaceID {
            bridge?.notifyFocus(false, for: surfaceID)
        }
        return true
    }

    func configureSurfaceIfNeeded(bridge: any TerminalEngine, surfaceID: SurfaceID) {
        guard self.surfaceID != surfaceID else { return }
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
        let keyEvent = KeyEvent(
            characters: event.characters,
            keyCode: UInt16(event.keyCode),
            modifiers: Self.keyModifiers(from: event.modifierFlags),
            isKeyDown: true,
            isRepeat: event.isARepeat,
            unshiftedCodepoint: event.charactersIgnoringModifiers?.unicodeScalars.first?.value ?? 0
        )
        if bridge.sendKeyEvent(keyEvent, to: surfaceID) {
            if event.keyCode == 36 {
                onUserInputSubmitted?()
            }
        } else {
            super.keyDown(with: event)
        }
    }

    override func insertText(_ insertString: Any) {
        let text: String
        if let attributed = insertString as? NSAttributedString {
            text = attributed.string
        } else if let string = insertString as? String {
            text = string
        } else {
            return
        }
        guard let bridge, let surfaceID else { return }
        bridge.sendText(text, to: surfaceID)
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
    }

    private func apply(_ frame: PTYDaemonSurfaceFrame) {
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
