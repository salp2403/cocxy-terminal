// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPRestartPolicy.swift - Bounded restart decisions for crashed servers.

import Foundation

struct LSPRestartPolicy: Equatable, Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval

    init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.5) {
        self.maxAttempts = max(0, maxAttempts)
        self.baseDelay = max(0, baseDelay)
    }
}

enum LSPRestartDecision: Equatable, Sendable {
    case restart(afterSeconds: TimeInterval)
    case stop
}

struct LSPRestartState: Equatable, Sendable {
    private var crashCount = 0

    mutating func recordCrash(policy: LSPRestartPolicy) -> LSPRestartDecision {
        guard crashCount < policy.maxAttempts else {
            return .stop
        }

        let delay = policy.baseDelay * pow(2.0, Double(crashCount))
        crashCount += 1
        return .restart(afterSeconds: delay)
    }
}
