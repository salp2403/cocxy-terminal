// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorErrorContract.swift - Phone-facing error codes and limiter policy.

import Foundation

/// Codes the phone client branches on. The client discards its pairing keys
/// only for `credentialInvalid` and `sessionExpired`.
enum MobileMirrorResponseCode: String, CaseIterable, Sendable {
    case credentialInvalid = "credential-invalid"
    case sessionExpired = "session-expired"
    case replayDetected = "replay-detected"
    case authorizationDenied = "authorization-denied"
    case invalidRequest = "invalid-request"
    case projectExists = "project-exists"
    case targetUnavailable = "target-unavailable"
    case rateLimited = "rate-limited"
    case unavailable = "unavailable"
}

struct MobileMirrorFailure: Equatable, Sendable {
    let status: Int
    let code: MobileMirrorResponseCode
    let messageKey: String
    /// Whether the failure spends the per-address authentication budget. Only
    /// failures that a peer without the session keys can provoke do: anything
    /// raised after the signature and the encrypted envelope verified cannot
    /// be part of a credential search.
    let countsAsAuthenticationFailure: Bool

    func response(using localization: MobileMirrorWebLocalization) -> MobileMirrorHTTPResponse {
        .error(localization.text(messageKey), status: status, code: code)
    }
}

extension MobileMirrorFailure {
    init(_ error: any Error) {
        guard let mirrorError = error as? MobileMirrorError else {
            switch error {
            case is CancellationError: self = .timedOut
            case is RelayAuditLogError: self = .auditUnavailable
            default: self = .unexpected
            }
            return
        }
        self.init(mirrorError)
    }

    init(_ error: MobileMirrorError) {
        let key = error.localizationEntry.key
        switch error {
        case .invalidPairingToken, .invalidSignature:
            self.init(status: 403, code: .credentialInvalid, messageKey: key, countsAsAuthenticationFailure: true)
        case .pairingExpired, .sessionExpired:
            self.init(status: 401, code: .sessionExpired, messageKey: key, countsAsAuthenticationFailure: true)
        case .replayDetected:
            self.init(status: 409, code: .replayDetected, messageKey: key, countsAsAuthenticationFailure: true)
        case .clockSkew:
            // A rescan cannot repair a skewed phone clock, so this never
            // invalidates; scoring it would replace the clock guidance with a
            // generic rate-limit message after a few keystrokes.
            self.init(status: 400, code: .invalidRequest, messageKey: key, countsAsAuthenticationFailure: false)
        case .invalidAction, .invalidProjectName:
            self.init(status: 400, code: .invalidRequest, messageKey: key, countsAsAuthenticationFailure: false)
        case .projectAlreadyExists:
            self.init(status: 409, code: .projectExists, messageKey: key, countsAsAuthenticationFailure: false)
        case .authorizationDenied, .pairingDenied:
            self.init(status: 403, code: .authorizationDenied, messageKey: key, countsAsAuthenticationFailure: false)
        case .targetUnavailable:
            self.init(status: 503, code: .targetUnavailable, messageKey: key, countsAsAuthenticationFailure: false)
        case .unavailable, .noPrivateNetwork, .pairingPending, .projectCreationUnavailable,
             .projectCreationFailed:
            self.init(status: 503, code: .unavailable, messageKey: key, countsAsAuthenticationFailure: false)
        }
    }

    private static let invalidRequestKey = "mobile.web.error.invalidRequest"
    private static let terminalUnavailableKey = "mobile.web.status.unavailable"

    static let rateLimited = Self(
        status: 429, code: .rateLimited,
        messageKey: "mobile.web.error.rateLimited", countsAsAuthenticationFailure: false
    )
    static let timedOut = Self(
        status: 504, code: .unavailable,
        messageKey: "mobile.web.error.timedOut", countsAsAuthenticationFailure: false
    )
    static let unexpected = Self(
        status: 503, code: .unavailable,
        messageKey: "mobile.mirror.error.unavailable", countsAsAuthenticationFailure: false
    )
    static let auditUnavailable = Self(
        status: 503, code: .unavailable,
        messageKey: "mobile.mirror.audit.unavailable", countsAsAuthenticationFailure: false
    )
    static let missingSession = Self(
        status: 401, code: .sessionExpired,
        messageKey: "mobile.web.status.rescanRequired", countsAsAuthenticationFailure: true
    )
    static let invalidHost = Self(
        status: 403, code: .invalidRequest,
        messageKey: invalidRequestKey, countsAsAuthenticationFailure: true
    )
    static let unsignedAction = Self(
        status: 403, code: .invalidRequest,
        messageKey: invalidRequestKey, countsAsAuthenticationFailure: true
    )
    static let invalidTerminalOrigin = Self(
        status: 403, code: .invalidRequest,
        messageKey: invalidRequestKey, countsAsAuthenticationFailure: true
    )
    static let malformedRequest = Self(
        status: 400, code: .invalidRequest,
        messageKey: invalidRequestKey, countsAsAuthenticationFailure: false
    )
    static let notFound = Self(
        status: 404, code: .invalidRequest,
        messageKey: invalidRequestKey, countsAsAuthenticationFailure: false
    )
    static let missingTerminalStream = Self(
        status: 404, code: .targetUnavailable,
        messageKey: terminalUnavailableKey, countsAsAuthenticationFailure: false
    )
    static let noTerminalStream = Self(
        status: 503, code: .targetUnavailable,
        messageKey: terminalUnavailableKey, countsAsAuthenticationFailure: false
    )
    static let terminalProxyUnavailable = Self(
        status: 503, code: .targetUnavailable,
        messageKey: terminalUnavailableKey, countsAsAuthenticationFailure: false
    )
}

/// Final pairing-page poll answer. The page script stops on `status`
/// (`denied` or `expired`); the remaining fields keep the phone error contract.
struct MobileMirrorPairingOutcome: Encodable, Sendable {
    let ok = false
    let status: String
    let error: String
    let code: String
}
