// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SynchronizedOutputPresentationGate.swift - Bounded presentation hold for DEC mode 2026.

import Foundation

struct SynchronizedOutputPresentationGate {
    static let defaultMaximumHoldDuration: TimeInterval = 0.150

    let maximumHoldDuration: TimeInterval
    private(set) var activationTime: TimeInterval?

    init(maximumHoldDuration: TimeInterval = defaultMaximumHoldDuration) {
        self.maximumHoldDuration = max(0, maximumHoldDuration)
    }

    /// Returns the remaining presentation delay, or `nil` when a frame may be shown.
    mutating func presentationDelay(isActive: Bool, now: TimeInterval) -> TimeInterval? {
        guard isActive else {
            reset()
            return nil
        }

        if activationTime == nil {
            activationTime = now
        }
        guard let activationTime else { return nil }
        let remaining = maximumHoldDuration - max(0, now - activationTime)
        return remaining > 0 ? remaining : nil
    }

    mutating func reset() {
        activationTime = nil
    }
}
