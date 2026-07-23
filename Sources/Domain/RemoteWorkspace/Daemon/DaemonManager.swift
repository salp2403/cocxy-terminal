// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonManager.swift - Profile- and lease-bound remote daemon orchestration.

import Combine
import Foundation

struct DaemonTransportBinding {
    let profileID: UUID
    let connectionLeaseID: UUID
    let transport: any ProxyUpstreamTransport
}

@MainActor
protocol DaemonTransportProviding: AnyObject {
    func connectionLeaseID(for profileID: UUID) -> UUID?
    func openDaemonTransport(
        remotePort: Int,
        profileID: UUID,
        expectedConnectionLeaseID: UUID
    ) throws -> DaemonTransportBinding
}

@MainActor
protocol DaemonManaging: AnyObject {
    func state(for profileID: UUID) -> DaemonState
    func deploy(profileID: UUID) async throws
    func isRunning(profileID: UUID) async -> Bool
    func connect(profileID: UUID) async throws
    func stop(profileID: UUID) async throws
    func upgrade(profileID: UUID) async throws
    func status(profileID: UUID) async throws -> DaemonResponse
}

/// Coordinates remote installation with one authenticated direct-tcpip channel
/// per active SSH connection lease. No state or connection is shared between
/// profiles, even when the UI changes selection while work is in flight.
@MainActor
final class DaemonManagerImpl: DaemonManaging, ObservableObject {
    private struct BoundSession {
        let connectionLeaseID: UUID
        let connection: DaemonConnection
    }

    @Published private(set) var states: [UUID: DaemonState] = [:]

    private let deployer: DaemonDeployer
    private weak var transportProvider: (any DaemonTransportProviding)?
    private var sessions: [UUID: BoundSession] = [:]
    private var pendingConnections: [UUID: DaemonConnection] = [:]
    private var generations: [UUID: UInt64] = [:]

    init(
        deployer: DaemonDeployer,
        transportProvider: any DaemonTransportProviding
    ) {
        self.deployer = deployer
        self.transportProvider = transportProvider
    }

    func state(for profileID: UUID) -> DaemonState {
        states[profileID] ?? .notDeployed
    }

    func deploy(profileID: UUID) async throws {
        let operationGeneration = beginOperation(profileID: profileID, state: .deploying)
        do {
            try await deployer.deploy(profileID: profileID)
            try requireCurrent(operationGeneration, profileID: profileID)
            let port = try await deployer.start(profileID: profileID)
            try requireCurrent(operationGeneration, profileID: profileID)
            let capability = try await deployer.readRemoteCapability(profileID: profileID)
            try await establishConnection(
                profileID: profileID,
                remotePort: port,
                capability: capability,
                version: DaemonDeployer.bundledVersion,
                operationGeneration: operationGeneration
            )
        } catch {
            markUnreachableIfCurrent(operationGeneration, profileID: profileID)
            throw error
        }
    }

    func isRunning(profileID: UUID) async -> Bool {
        (try? await deployer.isRunning(profileID: profileID)) ?? false
    }

    func connect(profileID: UUID) async throws {
        let operationGeneration = beginOperation(profileID: profileID, state: .deploying)
        do {
            guard try await deployer.isRunning(profileID: profileID) else {
                throw DaemonProtocolError.daemonNotRunning
            }
            try requireCurrent(operationGeneration, profileID: profileID)
            let port = try await deployer.readRemotePort(profileID: profileID)
            let capability = try await deployer.readRemoteCapability(profileID: profileID)
            let version = try await deployer.remoteVersion(profileID: profileID)
                ?? DaemonDeployer.bundledVersion
            try await establishConnection(
                profileID: profileID,
                remotePort: port,
                capability: capability,
                version: version,
                operationGeneration: operationGeneration
            )
        } catch {
            markUnreachableIfCurrent(operationGeneration, profileID: profileID)
            throw error
        }
    }

    func stop(profileID: UUID) async throws {
        let operationGeneration = beginOperation(profileID: profileID, state: .stopped)
        do {
            try await deployer.stop(profileID: profileID)
            try requireCurrent(operationGeneration, profileID: profileID)
            states[profileID] = .stopped
        } catch {
            markUnreachableIfCurrent(operationGeneration, profileID: profileID)
            throw error
        }
    }

    func upgrade(profileID: UUID) async throws {
        let operationGeneration = beginOperation(profileID: profileID, state: .upgrading)
        do {
            try await deployer.stop(profileID: profileID)
            try requireCurrent(operationGeneration, profileID: profileID)
            try await deployer.deploy(profileID: profileID)
            try requireCurrent(operationGeneration, profileID: profileID)
            let port = try await deployer.start(profileID: profileID)
            let capability = try await deployer.readRemoteCapability(profileID: profileID)
            try await establishConnection(
                profileID: profileID,
                remotePort: port,
                capability: capability,
                version: DaemonDeployer.bundledVersion,
                operationGeneration: operationGeneration
            )
        } catch {
            markUnreachableIfCurrent(operationGeneration, profileID: profileID)
            throw error
        }
    }

    func connection(for profileID: UUID) throws -> DaemonConnection {
        guard let session = sessions[profileID],
              transportProvider?.connectionLeaseID(for: profileID)
                == session.connectionLeaseID,
              session.connection.profileID == profileID,
              session.connection.connectionLeaseID == session.connectionLeaseID,
              session.connection.isConnected else {
            invalidate(profileID: profileID, expectedConnectionLeaseID: nil)
            throw DaemonProtocolError.connectionLost
        }
        return session.connection
    }

    func send(
        profileID: UUID,
        cmd: String,
        args: [String: String]? = nil
    ) async throws -> DaemonResponse {
        try await connection(for: profileID).send(cmd: cmd, args: args)
    }

    func status(profileID: UUID) async throws -> DaemonResponse {
        try await send(profileID: profileID, cmd: DaemonCommand.status.rawValue)
    }

    /// Revokes only the daemon channel belonging to the retiring SSH lease.
    func invalidate(
        profileID: UUID,
        expectedConnectionLeaseID: UUID?
    ) {
        let activeLease = sessions[profileID]?.connectionLeaseID
            ?? pendingConnections[profileID]?.connectionLeaseID
            ?? transportProvider?.connectionLeaseID(for: profileID)
        if let expectedConnectionLeaseID,
           activeLease != expectedConnectionLeaseID {
            return
        }

        generations[profileID, default: 0] &+= 1
        sessions.removeValue(forKey: profileID)?.connection.disconnect()
        pendingConnections.removeValue(forKey: profileID)?.disconnect()
        switch states[profileID] {
        case .running, .deploying, .upgrading:
            states[profileID] = .unreachable
        default:
            break
        }
    }

    func shutdown() {
        let profileIDs = Set(sessions.keys).union(pendingConnections.keys)
        for profileID in profileIDs {
            invalidate(profileID: profileID, expectedConnectionLeaseID: nil)
        }
    }

    private func beginOperation(profileID: UUID, state: DaemonState) -> UInt64 {
        generations[profileID, default: 0] &+= 1
        sessions.removeValue(forKey: profileID)?.connection.disconnect()
        pendingConnections.removeValue(forKey: profileID)?.disconnect()
        states[profileID] = state
        return generations[profileID, default: 0]
    }

    private func establishConnection(
        profileID: UUID,
        remotePort: Int,
        capability: String,
        version: String,
        operationGeneration: UInt64
    ) async throws {
        try requireCurrent(operationGeneration, profileID: profileID)
        guard let transportProvider,
              let connectionLeaseID = transportProvider.connectionLeaseID(for: profileID) else {
            throw DaemonProtocolError.connectionLost
        }
        let binding = try transportProvider.openDaemonTransport(
            remotePort: remotePort,
            profileID: profileID,
            expectedConnectionLeaseID: connectionLeaseID
        )
        guard binding.profileID == profileID,
              binding.connectionLeaseID == connectionLeaseID else {
            binding.transport.cancel()
            throw DaemonProtocolError.connectionLost
        }

        let connection = DaemonConnection(
            profileID: profileID,
            connectionLeaseID: connectionLeaseID,
            authorizationIsCurrent: { [weak transportProvider] in
                transportProvider?.connectionLeaseID(for: profileID) == connectionLeaseID
            }
        )
        connection.onUnexpectedDisconnect = { [weak self, weak connection] in
            guard let self, let connection,
                  self.sessions[profileID]?.connection === connection else { return }
            self.sessions.removeValue(forKey: profileID)
            self.states[profileID] = .unreachable
        }
        pendingConnections[profileID] = connection

        do {
            try await connection.connect(
                transport: binding.transport,
                capability: capability
            )
            try requireCurrent(operationGeneration, profileID: profileID)
            guard transportProvider.connectionLeaseID(for: profileID) == connectionLeaseID,
                  pendingConnections[profileID] === connection,
                  connection.isConnected else {
                throw DaemonProtocolError.connectionLost
            }
            pendingConnections.removeValue(forKey: profileID)
            sessions[profileID] = BoundSession(
                connectionLeaseID: connectionLeaseID,
                connection: connection
            )
            states[profileID] = .running(version: version, uptime: 0)
        } catch {
            if pendingConnections[profileID] === connection {
                pendingConnections.removeValue(forKey: profileID)
            }
            connection.disconnect()
            throw error
        }
    }

    private func requireCurrent(_ generation: UInt64, profileID: UUID) throws {
        guard generations[profileID] == generation else {
            throw DaemonProtocolError.connectionLost
        }
    }

    private func markUnreachableIfCurrent(_ generation: UInt64, profileID: UUID) {
        guard generations[profileID] == generation else { return }
        sessions.removeValue(forKey: profileID)?.connection.disconnect()
        pendingConnections.removeValue(forKey: profileID)?.disconnect()
        states[profileID] = .unreachable
    }
}
