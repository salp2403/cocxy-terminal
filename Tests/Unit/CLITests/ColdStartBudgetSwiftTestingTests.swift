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
            ColdStartSample(milliseconds: 1_940),
            ColdStartSample(milliseconds: -1),
            ColdStartSample(milliseconds: 1_980),
            ColdStartSample(milliseconds: 1_960),
        ])
        #expect(evaluation.medianMilliseconds == 1_960)
        #expect(evaluation.isWithinBudget)
    }

    @Test("gate allows values inside the tolerance band")
    func toleranceBandIsAccepted() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: 2_200),
            ColdStartSample(milliseconds: 2_190),
            ColdStartSample(milliseconds: 2_160),
        ])
        #expect(abs(evaluation.toleratedBudgetMilliseconds - 2_200) < 0.001)
        #expect(evaluation.isWithinBudget)
        #expect(evaluation.shouldFailGate == false)
    }

    @Test("gate fails only after required consecutive over-budget samples")
    func consecutiveFailuresAreRequired() {
        let evaluation = ColdStartBudget.evaluate(samples: [
            ColdStartSample(milliseconds: 2_201),
            ColdStartSample(milliseconds: 2_250),
            ColdStartSample(milliseconds: 2_300),
        ])
        #expect(evaluation.isWithinBudget == false)
        #expect(evaluation.consecutiveFailures == 3)
        #expect(evaluation.shouldFailGate)
    }

    @Test("documented budgets separate app readiness from future internal signpost work")
    func budgetConstantsDocumentMeasurementScope() {
        #expect(ColdStartBudget.defaultBudgetMilliseconds == 2_000)
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
