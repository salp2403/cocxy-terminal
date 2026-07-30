// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalScrollRouting.swift - Shared terminal wheel routing and mouse encoding.

import AppKit
import Foundation

enum TerminalScrollDestination: Equatable, Sendable {
    case localViewport
    case terminalApplication
    case alternateScreenApplication
    case none
}

enum TerminalMouseEncoding: UInt8, Sendable {
    case x10 = 0
    case utf8 = 1
    case urxvt = 2
    case sgr = 3
    case sgrPixels = 4

    var usesSGRWireFormat: Bool {
        self == .sgr || self == .sgrPixels
    }
}

enum TerminalMouseTracking: UInt8, Sendable {
    case none = 0
    case x10 = 1
    case normal = 2
    case highlight = 3
    case buttonEvent = 4
    case anyEvent = 5

    static func normalized(rawValue: UInt8) -> TerminalMouseTracking {
        TerminalMouseTracking(rawValue: rawValue) ?? (rawValue == 0 ? .none : .normal)
    }

    func reports(_ action: TerminalMouseAction, hasButton: Bool) -> Bool {
        switch self {
        case .none:
            return false
        case .x10, .highlight:
            return action == .press
        case .normal:
            return action == .press || action == .release
        case .buttonEvent:
            return action != .motion || hasButton
        case .anyEvent:
            return true
        }
    }
}

enum TerminalMouseButton: UInt8, Sendable {
    case left = 0
    case middle = 1
    case right = 2

    init?(appKitButtonNumber: Int) {
        switch appKitButtonNumber {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .middle
        default: return nil
        }
    }
}

enum TerminalMouseAction: Equatable, Sendable {
    case press
    case release
    case motion
}

enum TerminalMouseCapturePolicy {
    static func terminalCaptures(
        trackingRawValue: UInt8,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        return trackingRawValue > 0
            && !flags.contains(.shift)
            && !flags.contains(.command)
    }
}

enum TerminalScrollRouter {
    static func destination(
        localRange: UInt32,
        prefersLocal: Bool,
        mouseTrackingMode: UInt8,
        isAltScreen: Bool,
        alternateScrollMode: Bool,
        modifiers: NSEvent.ModifierFlags
    ) -> TerminalScrollDestination {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.option) {
            return localRange > 0 ? .localViewport : .none
        }
        if flags.contains(.shift), localRange > 0 {
            return .localViewport
        }
        if isAltScreen, alternateScrollMode, mouseTrackingMode == 0 {
            return .alternateScreenApplication
        }
        if localRange > 0, prefersLocal {
            return .localViewport
        }
        if mouseTrackingMode > 0 {
            return .terminalApplication
        }
        if localRange > 0 {
            return .localViewport
        }
        return .none
    }
}

enum TerminalAlternateScrollKey {
    static func keyCode(forScrollingDeltaY deltaY: CGFloat) -> UInt16 {
        deltaY > 0 ? 126 : 125
    }
}

enum TerminalScrollWheelMetrics {
    private static let preciseScrollSpeedFactor: CGFloat = 0.15
    private static let rowsPerWheelNotch = 3

    static func forwardedEventCount(for event: NSEvent) -> Int {
        let scaledDelta = event.scrollingDeltaY * preciseScrollSpeedFactor
        return max(1, Int(abs(scaledDelta)))
    }

    static func localDeltaRows(for event: NSEvent) -> Int {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return 0 }

        let magnitude: Int
        if event.hasPreciseScrollingDeltas {
            let scaledDelta = delta * preciseScrollSpeedFactor
            magnitude = max(1, Int(abs(scaledDelta.rounded(.towardZero))))
        } else {
            let notches = max(1, Int(abs(delta).rounded(.awayFromZero)))
            magnitude = notches * rowsPerWheelNotch
        }
        return delta > 0 ? magnitude : -magnitude
    }
}

enum TerminalMouseWireEncoder {
    static func buttonPayload(
        action: TerminalMouseAction,
        button: TerminalMouseButton?,
        trackingRawValue: UInt8,
        encodingRawValue: UInt8,
        row: UInt16,
        column: UInt16,
        pixelX: Int,
        pixelY: Int,
        modifiers: NSEvent.ModifierFlags
    ) -> Data? {
        guard action == .motion || button != nil else { return nil }

        let tracking = TerminalMouseTracking.normalized(rawValue: trackingRawValue)
        guard tracking.reports(action, hasButton: button != nil) else { return nil }

        let encoding = TerminalMouseEncoding(rawValue: encodingRawValue) ?? .x10
        var buttonCode: Int
        if action == .release, !encoding.usesSGRWireFormat {
            buttonCode = 3
        } else {
            buttonCode = Int(button?.rawValue ?? 3)
        }
        if action == .motion {
            buttonCode += 32
        }
        buttonCode += modifierCode(from: modifiers)

        return encodeEvent(
            buttonCode: buttonCode,
            encoding: encoding,
            row: row,
            column: column,
            pixelX: pixelX,
            pixelY: pixelY,
            isRelease: action == .release
        )
    }

    static func wheelPayload(
        button: UInt8,
        encodingRawValue: UInt8,
        row: UInt16,
        column: UInt16,
        pixelX: Int,
        pixelY: Int,
        count: Int
    ) -> Data {
        let encoding = TerminalMouseEncoding(rawValue: encodingRawValue) ?? .x10
        let event = encodeEvent(
            buttonCode: Int(button),
            encoding: encoding,
            row: row,
            column: column,
            pixelX: pixelX,
            pixelY: pixelY,
            isRelease: false
        )

        let repetitions = max(1, count)
        var payload = Data()
        payload.reserveCapacity(event.count * repetitions)
        for _ in 0..<repetitions {
            payload.append(event)
        }
        return payload
    }

    private static func encodeEvent(
        buttonCode: Int,
        encoding: TerminalMouseEncoding,
        row: UInt16,
        column: UInt16,
        pixelX: Int,
        pixelY: Int,
        isRelease: Bool
    ) -> Data {
        switch encoding {
        case .x10:
            return Data([
                0x1B,
                0x5B,
                0x4D,
                UInt8(clamping: buttonCode + 32),
                UInt8(clamping: Int(column) + 33),
                UInt8(clamping: Int(row) + 33),
            ])
        case .utf8:
            var payload = Data([0x1B, 0x5B, 0x4D])
            payload.append(utf8Codepoint(buttonCode + 32))
            payload.append(utf8Codepoint(Int(column) + 33))
            payload.append(utf8Codepoint(Int(row) + 33))
            return payload
        case .urxvt:
            return Data("\u{1B}[\(buttonCode + 32);\(Int(column) + 1);\(Int(row) + 1)M".utf8)
        case .sgr:
            let suffix = isRelease ? "m" : "M"
            return Data("\u{1B}[<\(buttonCode);\(Int(column) + 1);\(Int(row) + 1)\(suffix)".utf8)
        case .sgrPixels:
            let suffix = isRelease ? "m" : "M"
            return Data("\u{1B}[<\(buttonCode);\(max(0, pixelX) + 1);\(max(0, pixelY) + 1)\(suffix)".utf8)
        }
    }

    private static func modifierCode(from modifiers: NSEvent.ModifierFlags) -> Int {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        var code = 0
        if flags.contains(.shift) { code += 4 }
        if flags.contains(.option) { code += 8 }
        if flags.contains(.control) { code += 16 }
        return code
    }

    private static func utf8Codepoint(_ value: Int) -> Data {
        guard let scalar = UnicodeScalar(value) else { return Data() }
        return Data(String(scalar).utf8)
    }
}
