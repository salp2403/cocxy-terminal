// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonManager.swift - Remote daemon lifecycle orchestrator.

import Foundation
import Combine

// MARK: - Daemon Managing Protocol

@MainActor
protocol DaemonManaging: AnyObject {
    var state: DaemonState { get }
    func deploy(profileID: UUID) async throws
    func isRunning(profileID: UUID) async -> Bool
    func connect(profileID: UUID) async throws
    func stop(profileID: UUID) async throws
    func upgrade(profileID: UUID) async throws
    func status(profileID: UUID) async throws -> DaemonResponse
}

// MARK: - Daemon Manager Implementation

/// Orchestrates the full lifecycle of the remote cocxyd daemon.
///
/// Coordinates `DaemonDeployer` for upload/start/stop and
/// `DaemonConnection` for JSON-RPC communication.
///
/// ## State Machine
///
/// `.notDeployed` → `.deploying` → `.running` → `.stopped`
///                                              → `.upgrading` → `.running`
///                                              → `.unreachable`
@MainActor
final class DaemonManagerImpl: DaemonManaging, ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: DaemonState = .notDeployed

    // MARK: - Dependencies

    private let deployer: DaemonDeployer
    let connection: DaemonConnection

    // MARK: - Initialization

    init(deployer: DaemonDeployer, connection: DaemonConnection = DaemonConnection()) {
        self.deployer = deployer
        self.connection = connection
    }

    // MARK: - Deploy

    /// Deploys cocxyd.sh to the remote server.
    ///
    /// Uploads the script, makes it executable, and starts the daemon.
    func deploy(profileID: UUID) async throws {
        state = .deploying

        do {
            try await deployer.deploy(profileID: profileID)
            let port = try await deployer.start(profileID: profileID)
            connection.connect(port: UInt16(port))
            state = .running(version: DaemonDeployer.bundledVersion, uptime: 0)
        } catch {
            state = .unreachable
            throw error
        }
    }

    // MARK: - Is Running

    /// Checks if the daemon is currently running.
    func isRunning(profileID: UUID) async -> Bool {
        (try? await deployer.isRunning(profileID: profileID)) ?? false
    }

    // MARK: - Connect

    /// Connects to an already-running daemon.
    ///
    /// Reads the daemon's TCP port from its port file on the remote server
    /// without starting a new instance.
    func connect(profileID: UUID) async throws {
        guard try await deployer.isRunning(profileID: profileID) else {
            throw DaemonProtocolError.daemonNotRunning
        }

        // Read the daemon's TCP port from its port file — NOT start a new daemon.
        guard let executor = deployer as? DaemonDeployer else {
            throw DaemonProtocolError.connectionLost
        }
        let portStr = try await executor.readRemotePort(profileID: profileID)
        guard let port = Int(portStr.trimmingCharacters(in: .whitespacesAndNewlines)),
              port > 0, port <= 65535 else {
            throw DaemonProtocolError.invalidResponse
        }

        let version = try await deployer.remoteVersion(profileID: profileID)
        connection.connect(port: UInt16(port))
        state = .running(version: version ?? DaemonDeployer.bundledVersion, uptime: 0)
    }

    // MARK: - Stop

    /// Stops the remote daemon.
    func stop(profileID: UUID) async throws {
        connection.disconnect()
        try await deployer.stop(profileID: profileID)
        state = .stopped
    }

    // MARK: - Upgrade

    /// Upgrades the daemon to the bundled version.
    func upgrade(profileID: UUID) async throws {
        state = .upgrading

        do {
            connection.disconnect()
            try await deployer.stop(profileID: profileID)
            try await deployer.deploy(profileID: profileID)
            let port = try await deployer.start(profileID: profileID)
            connection.connect(port: UInt16(port))
            state = .running(version: DaemonDeployer.bundledVersion, uptime: 0)
        } catch {
            state = .unreachable
            throw error
        }
    }

    // MARK: - Status

    /// Queries the daemon for its current status.
    func status(profileID: UUID) async throws -> DaemonResponse {
        try await connection.send(cmd: DaemonCommand.status.rawValue)
    }
}
