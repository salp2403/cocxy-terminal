// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ColdStartBudget.swift - Deterministic cold-start budget evaluation.

import Foundation

public struct ColdStartSample: Codable, Sendable, Equatable {
    public let milliseconds: Double

    public init(milliseconds: Double) {
        self.milliseconds = milliseconds
    }
}

public struct ColdStartBudgetEvaluation: Codable, Sendable, Equatable {
    public let budgetMilliseconds: Double
    public let toleranceRatio: Double
    public let medianMilliseconds: Double?
    public let consecutiveFailures: Int
    public let requiredConsecutiveFailures: Int

    public var toleratedBudgetMilliseconds: Double {
        budgetMilliseconds * (1 + toleranceRatio)
    }

    public var isWithinBudget: Bool {
        guard let medianMilliseconds else { return false }
        return medianMilliseconds <= toleratedBudgetMilliseconds
    }

    public var shouldFailGate: Bool {
        !isWithinBudget && consecutiveFailures >= requiredConsecutiveFailures
    }

    public init(
        budgetMilliseconds: Double,
        toleranceRatio: Double,
        medianMilliseconds: Double?,
        consecutiveFailures: Int,
        requiredConsecutiveFailures: Int
    ) {
        self.budgetMilliseconds = budgetMilliseconds
        self.toleranceRatio = toleranceRatio
        self.medianMilliseconds = medianMilliseconds
        self.consecutiveFailures = consecutiveFailures
        self.requiredConsecutiveFailures = requiredConsecutiveFailures
    }
}

public enum ColdStartBudget {
    /// Budget for the current benchmark harness: launch the macOS app bundle
    /// with `/usr/bin/open` and wait until the bundled `cocxy status` command
    /// can reach the app socket.
    ///
    /// This is intentionally different from a future in-process signpost budget
    /// for synchronous work inside `applicationDidFinishLaunching`. That inner
    /// budget can target tens of milliseconds once it is instrumented. The
    /// bundle-readiness path crosses LaunchServices, app startup, socket
    /// binding, and CLI round-trip overhead, so a 50 ms gate would fail even for
    /// healthy local builds and would not protect users from real regressions.
    public static let defaultBudgetMilliseconds: Double = 500

    /// Target kept for the future signpost-level benchmark that measures only
    /// Cocxy-owned synchronous launch work, not LaunchServices or socket
    /// round-trips.
    public static let internalCriticalPathBudgetMilliseconds: Double = 50

    public static let defaultToleranceRatio: Double = 0.10
    public static let defaultRequiredConsecutiveFailures = 3

    public static func evaluate(
        samples: [ColdStartSample],
        budgetMilliseconds: Double = defaultBudgetMilliseconds,
        toleranceRatio: Double = defaultToleranceRatio,
        requiredConsecutiveFailures: Int = defaultRequiredConsecutiveFailures
    ) -> ColdStartBudgetEvaluation {
        let rawValues = samples
            .map(\.milliseconds)
            .filter { $0.isFinite && $0 >= 0 }
        let values = rawValues
            .sorted()
        let median = median(of: values)
        let tolerated = budgetMilliseconds * (1 + toleranceRatio)
        let failures = rawValues.reversed().prefix { $0 > tolerated }.count
        return ColdStartBudgetEvaluation(
            budgetMilliseconds: budgetMilliseconds,
            toleranceRatio: toleranceRatio,
            medianMilliseconds: median,
            consecutiveFailures: failures,
            requiredConsecutiveFailures: requiredConsecutiveFailures
        )
    }

    public static func median(of sortedValues: [Double]) -> Double? {
        guard sortedValues.isEmpty == false else { return nil }
        let midpoint = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[midpoint - 1] + sortedValues[midpoint]) / 2
        }
        return sortedValues[midpoint]
    }
}
