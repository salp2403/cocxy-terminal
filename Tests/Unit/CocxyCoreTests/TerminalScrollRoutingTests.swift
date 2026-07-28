// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Terminal scroll routing")
@MainActor
struct TerminalScrollRoutingTests {
    @Test("routing cascade never leaves an available destination orphaned")
    func routingCascade() {
        expectDestination(.localViewport, localRange: 12, prefersLocal: true, tracking: 2)
        expectDestination(.terminalApplication, localRange: 0, prefersLocal: true, tracking: 2, modifiers: [.shift])
        expectDestination(.terminalApplication, localRange: 12, prefersLocal: false, tracking: 2)
        expectDestination(.localViewport, localRange: 12, prefersLocal: false, tracking: 0)
        expectDestination(.none, localRange: 0, prefersLocal: false, tracking: 0)
        expectDestination(.none, localRange: 0, prefersLocal: false, tracking: 2, modifiers: [.option])
        expectDestination(.localViewport, localRange: 12, prefersLocal: false, tracking: 2, modifiers: [.option])
    }

    @Test("non-precise wheel uses three local rows without multiplying forwarded events")
    func wheelGranularitySeparatesLocalAndForwardedCounts() throws {
        let event = try #require(makeScrollEvent(deltaY: 1, units: .line))

        #expect(event.hasPreciseScrollingDeltas == false)
        #expect(TerminalScrollWheelMetrics.localDeltaRows(for: event) == 3)
        #expect(TerminalScrollWheelMetrics.forwardedEventCount(for: event) == 1)
    }

    @Test("mouse encoder supports every negotiated coordinate format")
    func mouseEncoderSupportsAllFormats() {
        let x10 = encode(.x10)
        let utf8 = encode(.utf8, row: 230, column: 230)
        let urxvt = encode(.urxvt)
        let sgr = encode(.sgr)
        let pixels = encode(.sgrPixels)

        #expect(x10 == Data([0x1B, 0x5B, 0x4D, 0x60, 0x25, 0x23]))
        #expect(utf8 == Data([0x1B, 0x5B, 0x4D, 0x60, 0xC4, 0x87, 0xC4, 0x87]))
        #expect(urxvt == Data("\u{1B}[96;5;3M".utf8))
        #expect(sgr == Data("\u{1B}[<64;5;3M".utf8))
        #expect(pixels == Data("\u{1B}[<64;121;81M".utf8))
    }

    private func encode(
        _ encoding: TerminalMouseEncoding,
        row: UInt16 = 2,
        column: UInt16 = 4
    ) -> Data {
        TerminalMouseWireEncoder.wheelPayload(
            button: 64,
            encodingRawValue: encoding.rawValue,
            row: row,
            column: column,
            pixelX: 120,
            pixelY: 80,
            count: 1
        )
    }

    private func expectDestination(
        _ expected: TerminalScrollDestination,
        localRange: UInt32,
        prefersLocal: Bool,
        tracking: UInt8,
        modifiers: NSEvent.ModifierFlags = []
    ) {
        #expect(TerminalScrollRouter.destination(
            localRange: localRange,
            prefersLocal: prefersLocal,
            mouseTrackingMode: tracking,
            modifiers: modifiers
        ) == expected)
    }

    private func makeScrollEvent(
        deltaY: Int32,
        units: CGScrollEventUnit
    ) -> NSEvent? {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 1,
            wheel1: deltaY,
            wheel2: 0,
            wheel3: 0
        ) else { return nil }
        return NSEvent(cgEvent: event)
    }
}
