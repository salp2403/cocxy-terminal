// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ColdStartBudgetSwiftTestingTests.swift - Cold-start gate model coverage.

import Testing
import CocxyShared

@Suite("Cold start budget evaluation")
struct ColdStartBudgetSwiftTestingTests {

    @Test("median ignores invalid samples and keeps stable ordering")
    func medianIgnoresInvalidSamples() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: .nan),
            ColdStartSample(milliseconds: 330),
            ColdStartSample(milliseconds: -1),
            ColdStartSample(milliseconds: 380),
            ColdStartSample(milliseconds: 360),
        ])
        #expect(evaluation.medianMilliseconds == 360)
        #expect(evaluation.isWithinBudget)
    }

    @Test("gate allows values inside the tolerance band")
    func toleranceBandIsAccepted() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: 440),
            ColdStartSample(milliseconds: 435),
            ColdStartSample(milliseconds: 430),
        ])
        #expect(abs(evaluation.toleratedBudgetMilliseconds - 440) < 0.001)
        #expect(evaluation.isWithinBudget)
        #expect(evaluation.shouldFailGate == false)
    }

    @Test("gate fails only after required consecutive over-budget samples")
    func consecutiveFailuresAreRequired() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: 441),
            ColdStartSample(milliseconds: 475),
            ColdStartSample(milliseconds: 500),
        ])
        #expect(evaluation.isWithinBudget == false)
        #expect(evaluation.consecutiveFailures == 3)
        #expect(evaluation.shouldFailGate)
    }

    @Test("documented budgets separate app readiness from local internal launch timing")
    func budgetConstantsDocumentMeasurementScope() {
        #expect(ColdStartBudget.defaultBudgetMilliseconds == 400)
        #expect(ColdStartBudget.internalCriticalPathBudgetMilliseconds == 50)
    }

    @Test("empty samples are a failed evaluation")
    func emptySamplesFail() {
        let evaluation = ColdStartBudget.evaluate(samples: [])
        #expect(evaluation.medianMilliseconds == nil)
        #expect(evaluation.isWithinBudget == false)
        #expect(evaluation.shouldFailGate == false)
    }
}
