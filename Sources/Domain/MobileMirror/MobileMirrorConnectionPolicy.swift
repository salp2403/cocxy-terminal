// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorConnectionPolicy.swift - Bounded listener admission and deadlines.

import Foundation

struct MobileMirrorConnectionLimits: Equatable, Sendable {
    var maximumTotal = 16
    var maximumPerAddress = 4
    var maximumStartsPerWindow = 12
    var rateWindow: TimeInterval = 10

    static let `default` = MobileMirrorConnectionLimits()
}

struct MobileMirrorConnectionPolicy: Sendable {
    enum Decision: Equatable, Sendable {
        case accepted
        case tooManyConnections
        case rateLimited
    }

    private let limits: MobileMirrorConnectionLimits
    private var activeByAddress: [String: Int] = [:]
    private var startsByAddress: [String: [TimeInterval]] = [:]

    init(limits: MobileMirrorConnectionLimits = .default) {
        self.limits = limits
    }

    mutating func admit(address: String, now: TimeInterval) -> Decision {
        let total = activeByAddress.values.reduce(0, +)
        guard total < limits.maximumTotal,
              activeByAddress[address, default: 0] < limits.maximumPerAddress else {
            return .tooManyConnections
        }

        let threshold = now - limits.rateWindow
        let recentStarts = startsByAddress[address, default: []].filter { $0 > threshold }
        guard recentStarts.count < limits.maximumStartsPerWindow else {
            startsByAddress[address] = recentStarts
            return .rateLimited
        }
        startsByAddress[address] = recentStarts + [now]
        activeByAddress[address, default: 0] += 1
        return .accepted
    }

    mutating func release(address: String) {
        guard let count = activeByAddress[address] else { return }
        if count <= 1 {
            activeByAddress.removeValue(forKey: address)
        } else {
            activeByAddress[address] = count - 1
        }
    }

    mutating func reset() {
        activeByAddress.removeAll()
        startsByAddress.removeAll()
    }
}

struct MobileMirrorRequestDeadline: Equatable, Sendable {
    let expiresAt: TimeInterval

    init(startedAt: TimeInterval, timeout: TimeInterval) {
        expiresAt = startedAt + max(0, timeout)
    }

    func remainingPollMilliseconds(at now: TimeInterval) -> Int32? {
        let remaining = expiresAt - now
        guard remaining > 0 else { return nil }
        return Int32(min(Double(Int32.max), max(1, ceil(remaining * 1_000))))
    }
}
