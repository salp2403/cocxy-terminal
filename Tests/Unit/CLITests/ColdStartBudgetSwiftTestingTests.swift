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
            ColdStartSample(milliseconds: 430),
            ColdStartSample(milliseconds: -1),
            ColdStartSample(milliseconds: 480),
            ColdStartSample(milliseconds: 460),
        ])
        #expect(evaluation.medianMilliseconds == 460)
        #expect(evaluation.isWithinBudget)
    }

    @Test("gate allows values inside the tolerance band")
    func toleranceBandIsAccepted() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: 550),
            ColdStartSample(milliseconds: 545),
            ColdStartSample(milliseconds: 540),
        ])
        #expect(abs(evaluation.toleratedBudgetMilliseconds - 550) < 0.001)
        #expect(evaluation.isWithinBudget)
        #expect(evaluation.shouldFailGate == false)
    }

    @Test("gate fails only after required consecutive over-budget samples")
    func consecutiveFailuresAreRequired() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: 551),
            ColdStartSample(milliseconds: 575),
            ColdStartSample(milliseconds: 600),
        ])
        #expect(evaluation.isWithinBudget == false)
        #expect(evaluation.consecutiveFailures == 3)
        #expect(evaluation.shouldFailGate)
    }

    @Test("documented budgets separate app readiness from future internal signpost work")
    func budgetConstantsDocumentMeasurementScope() {
        #expect(ColdStartBudget.defaultBudgetMilliseconds == 500)
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
