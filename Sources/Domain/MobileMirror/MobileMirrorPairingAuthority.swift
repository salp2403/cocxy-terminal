// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorPairingAuthority.swift - One-use local pairing and signed actions.

import CryptoKit
import Foundation

struct MobileMirrorClientIdentity: Equatable, Sendable {
    let remoteAddress: String
    let userAgent: String

    var fingerprint: String {
        MobileMirrorPairingAuthority.digest(Data("\(remoteAddress)\n\(userAgent)".utf8))
    }
}

struct MobileMirrorPairingOffer: Equatable, Sendable, Identifiable {
    let id: UUID
    let token: String
    let pairingSecret: String
    let expiresAt: Date
}

struct MobileMirrorPendingPairing: Equatable, Sendable, Identifiable {
    let id: UUID
    let channelID: UUID
    let identity: MobileMirrorClientIdentity
    let expiresAt: Date
}

struct MobileMirrorActivePairing: Equatable, Sendable {
    let channelID: UUID
    let identity: MobileMirrorClientIdentity
    let pairedAt: Date
    let expiresAt: Date
}

struct MobileMirrorSessionCredentials: Equatable, Sendable {
    let channelID: UUID
    let terminalEncryptionKey: Data
    let selectedSessionID: String?
    let selectedSurfaceID: String?
}

struct MobileMirrorOpenedAction: Equatable, Sendable {
    let channelID: UUID
    let body: Data
}

struct MobileMirrorTerminalSelection: Equatable, Sendable {
    let sessionID: String
    let surfaceID: String
}

private struct MobileMirrorInputSequenceWindow: Sendable {
    private static let width: UInt64 = 64

    private var highest: UInt64?
    private var seen: UInt64 = 0

    mutating func accept(_ sequence: UInt64) -> Bool {
        guard let highest else {
            self.highest = sequence
            seen = 1
            return true
        }
        if sequence > highest {
            let distance = sequence - highest
            seen = distance >= Self.width
                ? 1
                : (seen << Int(distance)) | 1
            self.highest = sequence
            return true
        }
        let distance = highest - sequence
        guard distance < Self.width else { return false }
        let bit = UInt64(1) << Int(distance)
        guard seen & bit == 0 else { return false }
        seen |= bit
        return true
    }
}

enum MobileMirrorPairingPollResult: Equatable, Sendable {
    case pending
    case denied
    case confirmed(cookie: String)
}

final class MobileMirrorPairingAuthority: @unchecked Sendable {
    static let pairingTTL: TimeInterval = 90
    static let sessionTTL: TimeInterval = 8 * 60 * 60
    static let actionFreshnessSeconds = 60

    private struct Offer {
        let id: UUID
        let channelID: UUID
        let tokenDigest: String
        let pairingSecret: Data
        let expiresAt: Date
    }

    private struct Pending {
        let value: MobileMirrorPendingPairing
        let pairingSecret: Data
        var decision: Bool?
        var cookieDeliveryToken: String?
    }

    private struct Session {
        let channelID: UUID
        let identity: MobileMirrorClientIdentity
        let cookieDigest: String
        let actionToken: RelayToken
        let terminalEncryptionKey: Data
        let terminalInputEncryptionKey: Data
        let pairedAt: Date
        let expiresAt: Date
        var selectedSessionID: String?
        var selectedSurfaceID: String?
        var inputSequenceWindow: MobileMirrorInputSequenceWindow
        var replayTracker: ReplayTracker
    }

    private let lock = NSLock()
    private let clock: @Sendable () -> Date
    private var offer: Offer?
    private var pending: Pending?
    private var session: Session?

    init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    func makeOffer(ttl: TimeInterval = pairingTTL) -> MobileMirrorPairingOffer {
        let now = clock()
        let token = Self.randomToken()
        let pairingSecret = RelayToken.generate().secret
        let id = UUID()
        let value = Offer(
            id: id,
            channelID: id,
            tokenDigest: Self.digest(Data(token.utf8)),
            pairingSecret: pairingSecret,
            expiresAt: now.addingTimeInterval(max(1, ttl))
        )
        lock.withLock {
            offer = value
            pending = nil
        }
        return MobileMirrorPairingOffer(
            id: id,
            token: token,
            pairingSecret: Self.base64URL(pairingSecret),
            expiresAt: value.expiresAt
        )
    }

    func remainingLifetime(until deadline: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(clock()))
    }

    func consumeOffer(
        token: String,
        identity: MobileMirrorClientIdentity
    ) throws -> MobileMirrorPendingPairing {
        let now = clock()
        return try lock.withLock {
            guard let current = offer else { throw MobileMirrorError.invalidPairingToken }
            guard current.expiresAt > now else {
                offer = nil
                throw MobileMirrorError.pairingExpired
            }
            guard Self.constantTimeEqual(
                current.tokenDigest,
                Self.digest(Data(token.utf8))
            ) else {
                throw MobileMirrorError.invalidPairingToken
            }

            offer = nil
            let value = MobileMirrorPendingPairing(
                id: UUID(),
                channelID: current.channelID,
                identity: identity,
                expiresAt: current.expiresAt
            )
            pending = Pending(
                value: value,
                pairingSecret: current.pairingSecret,
                decision: nil,
                cookieDeliveryToken: nil
            )
            return value
        }
    }

    func decide(pendingID: UUID, approve: Bool) throws -> MobileMirrorActivePairing? {
        let now = clock()
        return try lock.withLock {
            guard var current = pending, current.value.id == pendingID else {
                throw MobileMirrorError.invalidPairingToken
            }
            guard current.value.expiresAt > now else {
                pending = nil
                throw MobileMirrorError.pairingExpired
            }
            current.decision = approve
            guard approve else {
                current.cookieDeliveryToken = nil
                pending = current
                return nil
            }

            let cookie = Self.randomToken()
            let pairedAt = now
            let expiresAt = now.addingTimeInterval(Self.sessionTTL)
            let keys = MobileMirrorSessionKeys.derive(
                pairingSecret: current.pairingSecret,
                channelID: current.value.channelID
            )
            session = Session(
                channelID: current.value.channelID,
                identity: current.value.identity,
                cookieDigest: Self.digest(Data(cookie.utf8)),
                actionToken: keys.actionToken,
                terminalEncryptionKey: keys.terminalEncryptionKey,
                terminalInputEncryptionKey: keys.terminalInputEncryptionKey,
                pairedAt: pairedAt,
                expiresAt: expiresAt,
                selectedSessionID: nil,
                selectedSurfaceID: nil,
                inputSequenceWindow: MobileMirrorInputSequenceWindow(),
                replayTracker: ReplayTracker(windowSeconds: Self.actionFreshnessSeconds)
            )
            current.cookieDeliveryToken = cookie
            pending = current
            return MobileMirrorActivePairing(
                channelID: current.value.channelID,
                identity: current.value.identity,
                pairedAt: pairedAt,
                expiresAt: expiresAt
            )
        }
    }

    func poll(
        pendingID: UUID,
        identity: MobileMirrorClientIdentity
    ) throws -> MobileMirrorPairingPollResult {
        let now = clock()
        return try lock.withLock {
            guard var current = pending,
                  current.value.id == pendingID,
                  current.value.identity.fingerprint == identity.fingerprint else {
                throw MobileMirrorError.invalidPairingToken
            }
            guard current.value.expiresAt > now else {
                pending = nil
                throw MobileMirrorError.pairingExpired
            }
            switch current.decision {
            case nil:
                return .pending
            case false:
                return .denied
            case true:
                guard let cookie = current.cookieDeliveryToken else {
                    throw MobileMirrorError.sessionExpired
                }
                current.cookieDeliveryToken = nil
                pending = current
                return .confirmed(cookie: cookie)
            }
        }
    }

    func credentials(cookie: String) throws -> MobileMirrorSessionCredentials {
        let now = clock()
        return try lock.withLock {
            guard let current = validSession(cookie: cookie, now: now) else {
                throw MobileMirrorError.sessionExpired
            }
            return MobileMirrorSessionCredentials(
                channelID: current.channelID,
                terminalEncryptionKey: current.terminalEncryptionKey,
                selectedSessionID: current.selectedSessionID,
                selectedSurfaceID: current.selectedSurfaceID
            )
        }
    }

    func activePairing(cookie: String? = nil) -> MobileMirrorActivePairing? {
        let now = clock()
        return lock.withLock {
            guard let current = session, current.expiresAt > now else {
                session = nil
                return nil
            }
            if let cookie,
               !Self.constantTimeEqual(
                    current.cookieDigest,
                    Self.digest(Data(cookie.utf8))
               ) {
                return nil
            }
            return MobileMirrorActivePairing(
                channelID: current.channelID,
                identity: current.identity,
                pairedAt: current.pairedAt,
                expiresAt: current.expiresAt
            )
        }
    }

    func selectedTerminal(cookie: String) -> MobileMirrorTerminalSelection? {
        let now = clock()
        return lock.withLock {
            guard let current = validSession(cookie: cookie, now: now),
                  let sessionID = current.selectedSessionID,
                  let surfaceID = current.selectedSurfaceID else {
                return nil
            }
            return MobileMirrorTerminalSelection(sessionID: sessionID, surfaceID: surfaceID)
        }
    }

    func selectedTerminal() -> MobileMirrorTerminalSelection? {
        let now = clock()
        return lock.withLock {
            guard let current = session, current.expiresAt > now else {
                session = nil
                return nil
            }
            guard let sessionID = current.selectedSessionID,
                  let surfaceID = current.selectedSurfaceID else {
                return nil
            }
            return MobileMirrorTerminalSelection(sessionID: sessionID, surfaceID: surfaceID)
        }
    }

    @discardableResult
    func selectTerminal(
        sessionID: String?,
        surfaceID: String?,
        cookie: String
    ) -> Bool {
        let now = clock()
        return lock.withLock {
            guard var current = validSession(cookie: cookie, now: now) else { return false }
            current.selectedSessionID = sessionID
            current.selectedSurfaceID = surfaceID
            session = current
            return true
        }
    }

    func openAction(
        cookie: String,
        method: String,
        path: String,
        timestamp: String,
        nonce: String,
        signature: String,
        body: Data
    ) throws -> MobileMirrorOpenedAction {
        guard let timestampValue = UInt64(timestamp),
              let nonceUUID = UUID(uuidString: nonce),
              let receivedSignature = Self.decodeBase64URL(signature) else {
            throw MobileMirrorError.invalidSignature
        }
        let now = clock()
        return try lock.withLock {
            guard var current = validSession(cookie: cookie, now: now) else {
                throw MobileMirrorError.sessionExpired
            }
            let canonical = MobileMirrorSessionKeys.canonicalActionPayload(
                method: method,
                path: path,
                body: body,
                timestamp: timestamp,
                nonce: nonce
            )
            guard current.actionToken.validate(
                payload: canonical,
                signature: receivedSignature
            ) else {
                throw MobileMirrorError.invalidSignature
            }
            let opened = try MobileMirrorEncryptedActionEnvelope.open(
                requestBody: body,
                encryptionKey: current.terminalInputEncryptionKey
            )
            var sequenceWindow = current.inputSequenceWindow
            guard sequenceWindow.accept(opened.sequence) else {
                throw MobileMirrorError.replayDetected
            }
            let nonceData = withUnsafeBytes(of: nonceUUID.uuid) { Data($0) }
            switch current.replayTracker.admit(
                timestamp: timestampValue,
                nonce: nonceData,
                now: UInt64(max(0, now.timeIntervalSince1970))
            ) {
            case .allowed:
                break
            case .stale:
                throw MobileMirrorError.clockSkew
            case .rejected:
                throw MobileMirrorError.replayDetected
            }
            current.inputSequenceWindow = sequenceWindow
            session = current
            return MobileMirrorOpenedAction(
                channelID: current.channelID,
                body: opened.plaintext
            )
        }
    }

    @discardableResult
    func revoke() -> MobileMirrorActivePairing? {
        lock.withLock {
            guard let current = session else {
                offer = nil
                pending = nil
                return nil
            }
            let value = MobileMirrorActivePairing(
                channelID: current.channelID,
                identity: current.identity,
                pairedAt: current.pairedAt,
                expiresAt: current.expiresAt
            )
            offer = nil
            pending = nil
            session = nil
            return value
        }
    }

    private func validSession(cookie: String, now: Date) -> Session? {
        guard let current = session, current.expiresAt > now else {
            session = nil
            return nil
        }
        guard Self.constantTimeEqual(
            current.cookieDigest,
            Self.digest(Data(cookie.utf8))
        ) else {
            return nil
        }
        return current
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeBase64URL(_ value: String) -> Data? {
        guard value.utf8.count <= 512 else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static func randomToken() -> String {
        base64URL(RelayToken.generate().secret)
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhsBytes, rhsBytes) {
            difference |= left ^ right
        }
        return difference == 0
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
