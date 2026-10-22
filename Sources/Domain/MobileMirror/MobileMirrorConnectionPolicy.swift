// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorConnectionPolicy.swift - Bounded listener admission and deadlines.

import Foundation

struct MobileMirrorConnectionLimits: Equatable, Sendable {
    var maximumTotal = 16
    var maximumPerAddress = 8
    var maximumStartsPerWindow = 48
    var maximumFailuresPerWindow = 12
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

    init(limits: MobileMirrorConnectionLimits = .default) {
        self.limits = limits
    }

    mutating func admit(address: String, now _: TimeInterval) -> Decision {
        let total = activeByAddress.values.reduce(0, +)
        guard total < limits.maximumTotal,
              activeByAddress[address, default: 0] < limits.maximumPerAddress else {
            return .tooManyConnections
        }

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
    }
}

struct MobileMirrorRequestRatePolicy: Sendable {
    private let limits: MobileMirrorConnectionLimits
    private var preAuthenticationStartsByAddress: [String: [TimeInterval]] = [:]
    private var failuresByAddress: [String: [TimeInterval]] = [:]

    init(limits: MobileMirrorConnectionLimits = .default) {
        self.limits = limits
    }

    mutating func admitPreAuthentication(address: String, now: TimeInterval) -> Bool {
        admit(
            address: address,
            now: now,
            maximum: limits.maximumStartsPerWindow,
            values: &preAuthenticationStartsByAddress
        )
    }

    mutating func recordAuthenticationFailure(address: String, now: TimeInterval) -> Bool {
        admit(
            address: address,
            now: now,
            maximum: limits.maximumFailuresPerWindow,
            values: &failuresByAddress
        )
    }

    private func admit(
        address: String,
        now: TimeInterval,
        maximum: Int,
        values: inout [String: [TimeInterval]]
    ) -> Bool {
        let threshold = now - limits.rateWindow
        let recent = values[address, default: []].filter { $0 > threshold }
        guard recent.count < maximum else {
            values[address] = recent
            return false
        }
        values[address] = recent + [now]
        return true
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
