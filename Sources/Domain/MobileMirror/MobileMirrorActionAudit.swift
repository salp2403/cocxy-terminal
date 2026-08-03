// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorActionAudit.swift - Content-free mobile action audit projection.

import Foundation

enum MobileMirrorActionAudit {
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
}
