// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayManager+MobileMirror.swift - Local mobile relay lifecycle.

import Foundation

@MainActor
final class MobileMirrorLocalRelayPool {
    private var relays: [UUID: MobileMirrorLocalRelay] = [:]

    func open(
        gatewayPort: UInt16,
        preambleSecret: String,
        bindAddress: String
    ) async throws -> MobileMirrorLocalRelayLease {
        let relay = MobileMirrorLocalRelay(
            gatewayPort: gatewayPort,
            preambleSecret: preambleSecret,
            addressProvider: { bindAddress }
        )
        let lease = try await relay.start()
        relays[lease.id] = relay
        return lease
    }

    func close(leaseID: UUID) {
        relays.removeValue(forKey: leaseID)?.stop()
    }

    func stopAll() {
        let activeRelays = Array(relays.values)
        relays.removeAll()
        activeRelays.forEach { $0.stop() }
    }
}

extension RelayManagerImpl {
    func openMobileMirrorRelay(
        gatewayPort: UInt16,
        preambleSecret: String,
        bindAddress: String
    ) async throws -> MobileMirrorLocalRelayLease {
        try await mobileMirrorRelayPool.open(
            gatewayPort: gatewayPort,
            preambleSecret: preambleSecret,
            bindAddress: bindAddress
        )
    }

    func privateMobileMirrorAddress() -> String? {
        MobileMirrorPrivateNetworkAddress.current()
    }

    func closeMobileMirrorRelay(leaseID: UUID) {
        mobileMirrorRelayPool.close(leaseID: leaseID)
    }
}
