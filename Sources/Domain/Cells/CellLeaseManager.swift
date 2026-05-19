// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellLeaseManager.swift - Single-use HMAC leases for Cells PTY/exec access.

import CryptoKit
import Foundation

enum CellLeaseError: Error, Equatable, Sendable {
    case invalidSecretLength(Int)
}

final class CellLeaseManager: @unchecked Sendable {
    private let secret: Data
    private let ttl: TimeInterval
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var consumedLeaseIDs: Set<UUID> = []

    init(
        secret: Data = CellLeaseManager.randomSecret(),
        ttl: TimeInterval = 60,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.secret = secret
        self.ttl = ttl
        self.clock = clock
    }

    func issueLease(cellID: UUID, purpose: CellLeasePurpose) throws -> CellLease {
        try validateSecret()
        let issuedAt = clock()
        let unsigned = UnsignedCellLease(
            id: UUID(),
            cellID: cellID,
            purpose: purpose,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(ttl)
        )
        return CellLease(
            id: unsigned.id,
            cellID: unsigned.cellID,
            purpose: unsigned.purpose,
            issuedAt: unsigned.issuedAt,
            expiresAt: unsigned.expiresAt,
            signature: sign(unsigned)
        )
    }

    func consumeLease(_ lease: CellLease, cellID: UUID, purpose: CellLeasePurpose) -> Bool {
        guard lease.cellID == cellID,
              lease.purpose == purpose,
              clock() <= lease.expiresAt,
              validateSignature(lease) else {
            return false
        }

        return lock.withLock {
            guard !consumedLeaseIDs.contains(lease.id) else { return false }
            consumedLeaseIDs.insert(lease.id)
            return true
        }
    }

    private func validateSecret() throws {
        guard secret.count == 32 else {
            throw CellLeaseError.invalidSecretLength(secret.count)
        }
    }

    private func validateSignature(_ lease: CellLease) -> Bool {
        let unsigned = UnsignedCellLease(
            id: lease.id,
            cellID: lease.cellID,
            purpose: lease.purpose,
            issuedAt: lease.issuedAt,
            expiresAt: lease.expiresAt
        )
        let expected = sign(unsigned)
        guard expected.count == lease.signature.count else { return false }
        var diff: UInt8 = 0
        for (lhs, rhs) in zip(expected, lease.signature) {
            diff |= lhs ^ rhs
        }
        return diff == 0
    }

    private func sign(_ lease: UnsignedCellLease) -> Data {
        let payload = lease.signingPayload
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(mac)
    }

    private static func randomSecret() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }
}

private struct UnsignedCellLease {
    let id: UUID
    let cellID: UUID
    let purpose: CellLeasePurpose
    let issuedAt: Date
    let expiresAt: Date

    var signingPayload: Data {
        [
            id.uuidString,
            cellID.uuidString,
            purpose.rawValue,
            String(format: "%.6f", issuedAt.timeIntervalSince1970),
            String(format: "%.6f", expiresAt.timeIntervalSince1970),
        ]
        .joined(separator: "|")
        .data(using: .utf8) ?? Data()
    }
}
