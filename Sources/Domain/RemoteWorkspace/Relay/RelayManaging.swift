// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManaging.swift - Relay management contracts.

import Foundation

@MainActor
protocol RelayManaging: AnyObject {
    func openChannel(config: RelayChannelConfig, profileID: UUID) async throws -> RelayChannel
    func closeChannel(channelID: UUID) async
    func closeAllChannels(profileID: UUID) async
    func listChannels(profileID: UUID) -> [RelayChannel]
    func rotateToken(channelID: UUID) throws
    func updateACL(channelID: UUID, acl: RelayACL)
}

enum RelayManagerError: Error, LocalizedError, Equatable {
    case invalidName
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Relay channel name is required"
        case .invalidPort:
            return "Relay ports must be between 1 and 65535"
        }
    }
}

typealias RelayAuthBrokerFactory = @MainActor (
    _ channelID: UUID,
    _ token: RelayToken,
    _ acl: RelayACL,
    _ targetHost: String,
    _ targetPort: UInt16,
    _ auditLog: RelayAuditLog?
) -> any RelayAuthBrokering

typealias RelayProfileSessionRevoker = @MainActor (
    _ profileID: UUID,
    _ connectionLeaseID: UUID
) async -> Bool
