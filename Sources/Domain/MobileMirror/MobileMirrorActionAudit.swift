// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorActionAudit.swift - Content-free mobile action audit projection.

import Foundation

enum MobileMirrorActionAudit {
    enum Outcome: String, Sendable {
        case accepted
        case rejected
        case queued
        case partial
    }

    enum RejectionReason: String, Sendable {
        case invalidEnvelope = "invalid-envelope"
        case invalidSignature = "invalid-signature"
        case replayDetected = "replay-detected"
        case malformedAction = "malformed-action"
        case sessionExpired = "session-expired"
    }

    static func event(
        action: MobileMirrorAction,
        channelID: UUID,
        identity: MobileMirrorClientIdentity,
        accepted: Bool
    ) -> RelayAuditEvent {
        event(
            action: action,
            channelID: channelID,
            identity: identity,
            outcome: accepted ? .accepted : .rejected
        )
    }

    static func event(
        action: MobileMirrorAction,
        channelID: UUID,
        identity: MobileMirrorClientIdentity,
        outcome: Outcome
    ) -> RelayAuditEvent {
        let target = action.sessionID
            ?? action.approvalID
            ?? action.name
            ?? "none"
        return .mobileAction(
            channelID: channelID,
            remoteHost: identity.remoteAddress,
            action: action.kind.rawValue,
            targetDigest: MobileMirrorPairingAuthority.digest(Data(target.utf8)),
            outcome: outcome.rawValue
        )
    }

    static func rejectionEvent(
        reason: RejectionReason,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) -> RelayAuditEvent {
        .mobileRequestRejected(
            channelID: channelID,
            remoteHost: identity.remoteAddress,
            reason: reason.rawValue
        )
    }
}
