// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionManager+State.swift - Connection state and lifecycle limits.

import Foundation

extension RemoteConnectionManager {
    enum ConnectionState: Equatable, Sendable {
        case disconnected
        case connecting
        case connected(latencyMs: Int?)
        case reconnecting(attempt: Int)
        case failed(String)
    }

    nonisolated static var maxReconnectAttempts: Int { 5 }
    nonisolated static var maxBackoffDelay: TimeInterval { 30.0 }
    nonisolated static var terminationConfirmationAttempts: Int { 5 }
    nonisolated static var terminationConfirmationDelayNanoseconds: UInt64 { 100_000_000 }
}
