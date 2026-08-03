// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorPrivilegedAuthorization.swift - Exact grants for an approved paired session.

import CocxyShared
import Foundation

enum MobileMirrorPrivilegedAuthorization {
    static func grant(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        channelID: UUID,
        activePairing: MobileMirrorActivePairing?,
        tabID: TabID,
        context: SocketPrivilegedCommandContext,
        at date: Date = Date()
    ) -> SocketPrivilegedCommandAuthorizationGrant? {
        guard let activePairing,
              activePairing.channelID == channelID,
              activePairing.expiresAt > date,
              request.isValid(at: date),
              request.params["tabId"] == tabID.rawValue.uuidString,
              context.scope == .terminalSurface,
              context.windowControllerIdentifier != nil,
              context.tabID == tabID.rawValue,
              let surfaceID = context.surfaceID,
              request.params["surfaceId"] == surfaceID.uuidString,
              hasExactParameters(request) else {
            return nil
        }
        return SocketPrivilegedCommandAuthorizationGrant(
            request: request,
            context: context,
            issuedAt: date
        )
    }

    private static func hasExactParameters(
        _ request: SocketPrivilegedCommandAuthorizationRequest
    ) -> Bool {
        switch request.command {
        case .send:
            return Set(request.params.keys) == ["surfaceId", "tabId", "text"]
                && request.params["text"]?.isEmpty == false
                && (request.params["text"]?.utf8.count ?? 0) <= 8_192
        case .sendKey:
            return Set(request.params.keys) == ["key", "surfaceId", "tabId"]
                && MobileMirrorTerminalControl.supportedKeys.contains(
                    request.params["key"]?.lowercased() ?? ""
                )
        default:
            return false
        }
    }
}
