// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RelayToken.swift - HMAC-SHA256 token for relay channel authentication.

import Foundation
import CryptoKit

// MARK: - Relay Token

/// Authentication token for relay channels using HMAC-SHA256.
///
/// Each channel has its own token with a 32-byte random secret.
/// The token is used to sign and validate handshake payloads in
/// the `RelayAuthBroker` wire protocol.
///
/// ## Security Properties
///
/// - Secret generated via `SecRandomCopyBytes` (cryptographically secure).
/// - HMAC-SHA256 provides authentication and integrity.
/// - Rotation generates a fresh secret, invalidating all prior signatures.
/// - Tokens are stored in Keychain (via `RelayKeychainStore`), never in plain text.
struct RelayToken: Codable, Sendable {

    /// 32-byte random secret for HMAC computation.
    let secret: Data

    /// Generates a new token with a cryptographically random 32-byte secret.
    static func generate() -> RelayToken {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
        return RelayToken(secret: Data(bytes))
    }

    /// Signs a payload using HMAC-SHA256 with this token's secret.
    ///
    /// - Parameter payload: The data to authenticate.
    /// - Returns: A 32-byte HMAC signature.
    func sign(_ payload: Data) -> Data {
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return Data(mac)
    }

    /// Validates an HMAC signature against a payload.
    ///
    /// Uses constant-time comparison to prevent timing attacks.
    ///
    /// - Parameters:
    ///   - payload: The original data that was signed.
    ///   - signature: The HMAC signature to verify.
    /// - Returns: `true` if the signature is valid for the given payload.
    func validate(payload: Data, signature: Data) -> Bool {
        let key = SymmetricKey(data: secret)
        return HMAC<SHA256>.isValidAuthenticationCode(
            signature,
            authenticating: payload,
            using: key
        )
    }

    /// Creates a new token with a fresh secret, invalidating this one.
    ///
    /// The old token's signatures will no longer validate against the
    /// new token's secret.
    func rotated() -> RelayToken {
        RelayToken.generate()
    }
}

// MARK: - Replay Tracker

/// Tracks seen timestamps to prevent replay attacks.
///
/// Maintains a set of recently seen timestamps within a configurable
/// time window. Timestamps outside the window (past or future) are
/// rejected immediately. Timestamps already seen within the window
/// are also rejected.
struct ReplayTracker: Sendable {

    /// Maximum age of a valid timestamp (in seconds from now).
    let windowSeconds: Int

    /// Set of timestamps seen within the current window.
    private var seenTimestamps: Set<UInt64> = []

    init(windowSeconds: Int = 60) {
        self.windowSeconds = windowSeconds
    }

    /// Checks if a timestamp is valid and not replayed.
    ///
    /// - Parameter timestamp: Unix epoch seconds.
    /// - Returns: `true` if the timestamp is within the window and hasn't been seen.
    mutating func isAllowed(_ timestamp: UInt64) -> Bool {
        let now = UInt64(Date().timeIntervalSince1970)
        let windowU64 = UInt64(windowSeconds)

        // Reject timestamps too far in the past.
        if timestamp + windowU64 < now { return false }

        // Reject timestamps too far in the future.
        if timestamp > now + windowU64 { return false }

        // Reject replayed timestamps.
        guard !seenTimestamps.contains(timestamp) else { return false }

        seenTimestamps.insert(timestamp)
        pruneOldTimestamps(now: now)
        return true
    }

    /// Removes timestamps that have fallen outside the window.
    private mutating func pruneOldTimestamps(now: UInt64) {
        let windowU64 = UInt64(windowSeconds)
        let cutoff = now > windowU64 ? now - windowU64 : 0
        seenTimestamps = seenTimestamps.filter { $0 >= cutoff }
    }
}
