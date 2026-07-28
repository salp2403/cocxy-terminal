// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalScrollRouting.swift - Shared terminal wheel routing and encoding.

import AppKit
import Foundation

enum TerminalScrollDestination: Equatable, Sendable {
    case localViewport
    case terminalApplication
    case none
}

enum TerminalMouseEncoding: UInt8, Sendable {
    case x10 = 0
    case utf8 = 1
    case urxvt = 2
    case sgr = 3
    case sgrPixels = 4
}

enum TerminalScrollRouter {
    static func destination(
        localRange: UInt32,
        prefersLocal: Bool,
        mouseTrackingMode: UInt8,
        modifiers: NSEvent.ModifierFlags
    ) -> TerminalScrollDestination {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.option) {
            return localRange > 0 ? .localViewport : .none
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
        let event = encodeWheelEvent(
            button: button,
            encoding: encoding,
            row: row,
            column: column,
            pixelX: pixelX,
            pixelY: pixelY
        )

        let repetitions = max(1, count)
        var payload = Data()
        payload.reserveCapacity(event.count * repetitions)
        for _ in 0..<repetitions {
            payload.append(event)
        }
        return payload
    }

    private static func encodeWheelEvent(
        button: UInt8,
        encoding: TerminalMouseEncoding,
        row: UInt16,
        column: UInt16,
        pixelX: Int,
        pixelY: Int
    ) -> Data {
        switch encoding {
        case .x10:
            return Data([
                0x1B,
                0x5B,
                0x4D,
                UInt8(clamping: Int(button) + 32),
                UInt8(clamping: Int(column) + 33),
                UInt8(clamping: Int(row) + 33),
            ])
        case .utf8:
            var payload = Data([0x1B, 0x5B, 0x4D])
            payload.append(utf8Codepoint(Int(button) + 32))
            payload.append(utf8Codepoint(Int(column) + 33))
            payload.append(utf8Codepoint(Int(row) + 33))
            return payload
        case .urxvt:
            return Data("\u{1B}[\(Int(button) + 32);\(column + 1);\(row + 1)M".utf8)
        case .sgr:
            return Data("\u{1B}[<\(button);\(column + 1);\(row + 1)M".utf8)
        case .sgrPixels:
            return Data("\u{1B}[<\(button);\(max(0, pixelX) + 1);\(max(0, pixelY) + 1)M".utf8)
        }
    }

    private static func utf8Codepoint(_ value: Int) -> Data {
        guard let scalar = UnicodeScalar(value) else { return Data() }
        return Data(String(scalar).utf8)
    }
}
