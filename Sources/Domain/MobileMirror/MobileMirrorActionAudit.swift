// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorActionAudit.swift - Content-free mobile action audit projection.

import Foundation

enum MobileMirrorActionAudit {
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
        let target = action.sessionID
            ?? action.approvalID
            ?? action.name
            ?? "none"
        return .mobileAction(
            channelID: channelID,
            remoteHost: identity.remoteAddress,
            action: action.kind.rawValue,
            targetDigest: MobileMirrorPairingAuthority.digest(Data(target.utf8)),
            outcome: accepted ? "accepted" : "rejected"
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
