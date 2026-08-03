// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorSSHTunnelController.swift - Loopback-only phone transport over SSH.

import Combine
import Foundation

struct MobileMirrorTunnelTarget: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let destination: String
}

struct MobileMirrorTunnelLease: Equatable, Sendable {
    let profileID: UUID
    let connectionLeaseID: UUID
    let forward: RemoteConnectionProfile.PortForward
    let tunnelID: UUID
    let remotePort: UInt16
}

enum MobileMirrorTunnelError: Error, Equatable, LocalizedError {
    case noConnectedTarget
    case invalidLocalPort
    case remotePortUnavailable
    case closureUnconfirmed

    var errorDescription: String? {
        switch self {
        case .noConnectedTarget:
            return "Connect an SSH profile for this phone before pairing."
        case .invalidLocalPort:
            return "The loopback mobile service did not receive a valid port."
        case .remotePortUnavailable:
            return "The phone could not reserve a loopback port for pairing."
        case .closureUnconfirmed:
            return "The SSH phone tunnel could not be closed safely."
        }
    }
}

@MainActor
final class MobileMirrorSSHTunnelController: ObservableObject {
    typealias PortProvider = @Sendable () -> UInt16

    @Published private(set) var targets: [MobileMirrorTunnelTarget] = []

    private let connectionManager: RemoteConnectionManager
    private let profileStore: any RemoteProfileStoring
    private let tunnelManager: SSHTunnelManager
    private let portProvider: PortProvider
    private var cancellables = Set<AnyCancellable>()

    init(
        connectionManager: RemoteConnectionManager,
        profileStore: any RemoteProfileStoring,
        tunnelManager: SSHTunnelManager,
        portProvider: @escaping PortProvider = {
            UInt16.random(in: 49_152...65_535)
        }
    ) {
        self.connectionManager = connectionManager
        self.profileStore = profileStore
        self.tunnelManager = tunnelManager
        self.portProvider = portProvider
        connectionManager.$connections
            .sink { [weak self] connections in
                self?.refreshTargets(connections: connections)
            }
            .store(in: &cancellables)
    }

    func open(profileID: UUID, localPort: UInt16) async throws -> MobileMirrorTunnelLease {
        guard localPort > 0,
              targets.contains(where: { $0.id == profileID }),
              let connectionLeaseID = connectionManager.connectionLeaseID(for: profileID) else {
            throw localPort == 0
                ? MobileMirrorTunnelError.invalidLocalPort
                : MobileMirrorTunnelError.noConnectedTarget
        }

        var lastForwardError: Error?
        for _ in 0..<3 {
            let remotePort = portProvider()
            guard remotePort > 0 else { continue }
            let forward = RemoteConnectionProfile.PortForward.remote(
                remotePort: Int(remotePort),
                localPort: Int(localPort),
                localHost: "127.0.0.1",
                remoteBindHost: RemoteConnectionProfile.PortForward.remoteLoopbackBindHost
            )
            do {
                try await connectionManager.forwardPort(
                    forward,
                    for: profileID,
                    expectedConnectionLeaseID: connectionLeaseID
                )
                guard connectionManager.connectionLeaseID(for: profileID) == connectionLeaseID else {
                    throw SSHMultiplexerError.notConnected
                }
                let tunnel = tunnelManager.addTunnel(forward: forward, for: profileID)
                return MobileMirrorTunnelLease(
                    profileID: profileID,
                    connectionLeaseID: connectionLeaseID,
                    forward: forward,
                    tunnelID: tunnel.id,
                    remotePort: remotePort
                )
            } catch let error as SSHMultiplexerError {
                lastForwardError = error
                guard case .forwardFailed = error else { throw error }
            }
        }
        if let lastForwardError { throw lastForwardError }
        throw MobileMirrorTunnelError.remotePortUnavailable
    }

    func close(_ lease: MobileMirrorTunnelLease) async throws {
        guard connectionManager.connectionLeaseID(for: lease.profileID)
                == lease.connectionLeaseID else {
            _ = tunnelManager.removeTunnel(id: lease.tunnelID)
            return
        }
        do {
            try await connectionManager.cancelForward(
                lease.forward,
                for: lease.profileID,
                expectedConnectionLeaseID: lease.connectionLeaseID
            )
            _ = tunnelManager.removeTunnel(id: lease.tunnelID)
        } catch {
            let revoked = await connectionManager.revokeForwardingSession(
                profileID: lease.profileID,
                expectedLeaseID: lease.connectionLeaseID
            )
            guard revoked
                    || connectionManager.connectionLeaseID(for: lease.profileID)
                        != lease.connectionLeaseID else {
                tunnelManager.updateTunnelStatus(
                    id: lease.tunnelID,
                    status: .failed(MobileMirrorTunnelError.closureUnconfirmed.localizedDescription)
                )
                throw MobileMirrorTunnelError.closureUnconfirmed
            }
            _ = tunnelManager.removeTunnel(id: lease.tunnelID)
        }
    }

    private func refreshTargets(
        connections: [UUID: RemoteConnectionManager.ConnectionState]
    ) {
        let connectedIDs = Set(connections.compactMap { profileID, state in
            if case .connected = state { return profileID }
            return nil
        })
        let profiles = (try? profileStore.loadAll()) ?? []
        targets = profiles
            .filter { connectedIDs.contains($0.id) }
            .map {
                MobileMirrorTunnelTarget(
                    id: $0.id,
                    name: $0.name,
                    destination: $0.displayTitle
                )
            }
            .sorted {
                let comparison = $0.name.localizedStandardCompare($1.name)
                return comparison == .orderedSame
                    ? $0.id.uuidString < $1.id.uuidString
                    : comparison == .orderedAscending
            }
    }
}
