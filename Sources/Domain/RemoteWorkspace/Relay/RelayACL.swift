// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayACL.swift - Access control list for relay channels.

import Foundation

// MARK: - Relay ACL

/// Controls which processes and hosts can use a relay channel.
///
/// Evaluation requires both process name and remote host to pass.
/// An empty `allowedProcesses` list permits all processes.
/// An empty `allowedRemoteHosts` list uses the default (`["127.0.0.1"]`).
struct RelayACL: Codable, Sendable, Equatable {

    /// Process names allowed to use this channel (empty = all allowed).
    let allowedProcesses: [String]

    /// Maximum number of simultaneous connections.
    let maxConnections: Int

    /// Maximum bandwidth in bytes per second (nil = unlimited).
    let maxBandwidthBytesPerSec: Int?

    /// Remote hosts allowed to connect (empty defaults to localhost only).
    let allowedRemoteHosts: [String]

    init(
        allowedProcesses: [String] = [],
        maxConnections: Int = 10,
        maxBandwidthBytesPerSec: Int? = nil,
        allowedRemoteHosts: [String] = ["127.0.0.1"]
    ) {
        self.allowedProcesses = allowedProcesses
        self.maxConnections = maxConnections
        self.maxBandwidthBytesPerSec = maxBandwidthBytesPerSec
        self.allowedRemoteHosts = allowedRemoteHosts
    }

    // MARK: - Evaluation

    /// Evaluates whether a connection attempt should be allowed.
    ///
    /// - Parameters:
    ///   - processName: The name of the process requesting access.
    ///   - remoteHost: The remote host address of the connection.
    /// - Returns: `true` if both process and host checks pass.
    func evaluate(processName: String, remoteHost: String) -> Bool {
        let processAllowed = allowedProcesses.isEmpty || allowedProcesses.contains(processName)
        let hostAllowed = allowedRemoteHosts.contains(remoteHost)
        return processAllowed && hostAllowed
    }

    /// Checks whether the channel can accept another connection.
    ///
    /// - Parameter currentCount: The number of currently active connections.
    /// - Returns: `true` if under the max connections limit.
    func canAcceptConnection(currentCount: Int) -> Bool {
        currentCount < maxConnections
    }
}
