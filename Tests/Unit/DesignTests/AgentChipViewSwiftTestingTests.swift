// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentChipViewSwiftTestingTests.swift - Pure math coverage for the
// Aurora agent chip's pulse animation.
//
// The chip itself is a SwiftUI view; the only behaviour that needs
// asserting is the pulse curve used by the halo when the agent is
// `working` or `launched`. These tests pin the shape of the curve
// against the design reference's `softPulse` keyframes so future
// refactors cannot silently flatten the visual feedback.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Aurora agent chip — pulse math")
struct AgentChipViewSwiftTestingTests {

    // MARK: - Keyframe anchors

    @Test("Pulse at t = 0 renders the minimum scale and low opacity")
    func pulseAtZeroIsMinimum() {
        let phase = Design.AgentChipView.pulsePhase(at: 0.0)
        #expect(abs(phase.scale - 1.0) < 0.0001)
        #expect(abs(phase.opacity - 0.30) < 0.0001)
    }

    @Test("Pulse at half-period hits the peak scale and full opacity")
    func pulseAtHalfPeriodIsPeak() {
        // Period = 1.6s; half = 0.8s. The sine wave shifted to stay
        // non-negative maxes at 1.0 when t = 0.5.
        let phase = Design.AgentChipView.pulsePhase(at: 0.8)
        #expect(abs(phase.scale - 1.06) < 0.0001)
        #expect(abs(phase.opacity - 1.0) < 0.0001)
    }

    @Test("Pulse at full-period returns to the minimum (loops cleanly)")
    func pulseAtFullPeriodLoops() {
        let phase = Design.AgentChipView.pulsePhase(at: 1.6)
        #expect(abs(phase.scale - 1.0) < 0.0001)
        #expect(abs(phase.opacity - 0.30) < 0.0001)
    }

    @Test("Pulse handles multi-period wall-clock values")
    func pulseHandlesMultiplePeriods() {
        // 5.3 seconds modulo the 1.6 s period is 0.5 s (three full
        // cycles fold away, leaving 0.5 s inside the current period).
        // Normalising the leftover to the period yields 0.5 / 1.6 =
        // 0.3125, and the shifted-sine 0.5 - 0.5 * cos(2π * 0.3125)
        // produces the expected wave amplitude below.
        let phase = Design.AgentChipView.pulsePhase(at: 5.3)
        let expectedWave = 0.5 - 0.5 * cos(2 * .pi * (0.5 / 1.6))
        #expect(abs(Double(phase.scale) - (1.0 + expectedWave * 0.06)) < 0.0001)
        #expect(abs(phase.opacity - (0.30 + expectedWave * 0.70)) < 0.0001)
    }

    @Test("Negative wall-clock values fold to their positive equivalent")
    func pulseAcceptsNegativeInput() {
        // A negative seed should not crash nor produce a negative
        // phase — the helper folds to the absolute value so tests can
        // seed wall-clock times from any epoch.
        let phase = Design.AgentChipView.pulsePhase(at: -0.8)
        #expect(abs(phase.scale - 1.06) < 0.0001)
        #expect(abs(phase.opacity - 1.0) < 0.0001)
    }

    // MARK: - Phase structural invariants

    @Test("Pulse phase opacity always stays inside the 0.30 / 1.00 band")
    func pulseOpacityStaysInBand() {
        for step in stride(from: 0.0, through: 1.6, by: 0.05) {
            let phase = Design.AgentChipView.pulsePhase(at: step)
            #expect(phase.opacity >= 0.30)
            #expect(phase.opacity <= 1.00 + 1e-6)
        }
    }

    @Test("Pulse phase scale always stays inside the 1.00 / 1.06 band")
    func pulseScaleStaysInBand() {
        for step in stride(from: 0.0, through: 1.6, by: 0.05) {
            let phase = Design.AgentChipView.pulsePhase(at: step)
            #expect(phase.scale >= 1.00 - 1e-6)
            #expect(phase.scale <= 1.06 + 1e-6)
        }
    }
}
