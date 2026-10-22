// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Synchronized output presentation gate")
struct SynchronizedOutputPresentationGateSwiftTestingTests {
    @Test("active synchronized output is held for at most 150 milliseconds")
    func activeOutputUsesBoundedHold() throws {
        var gate = SynchronizedOutputPresentationGate()

        let initialDelay = gate.presentationDelay(isActive: true, now: 10.000)
        let finalDelay = gate.presentationDelay(isActive: true, now: 10.149)
        #expect(try #require(initialDelay) == 0.150)
        #expect(try #require(finalDelay) < 0.002)
        #expect(gate.presentationDelay(isActive: true, now: 10.150) == nil)
        #expect(gate.presentationDelay(isActive: true, now: 11.000) == nil)
    }

    @Test("ending synchronized output resets the next hold window")
    func inactiveOutputResetsGate() throws {
        var gate = SynchronizedOutputPresentationGate()

        _ = gate.presentationDelay(isActive: true, now: 1.0)
        #expect(gate.presentationDelay(isActive: false, now: 1.02) == nil)
        #expect(gate.activationTime == nil)
        let nextDelay = gate.presentationDelay(isActive: true, now: 2.0)
        #expect(try #require(nextDelay) == 0.150)
    }

    @Test("zero hold duration fails open immediately")
    func zeroDurationFailsOpen() {
        var gate = SynchronizedOutputPresentationGate(maximumHoldDuration: 0)

        #expect(gate.presentationDelay(isActive: true, now: 1.0) == nil)
    }
}
