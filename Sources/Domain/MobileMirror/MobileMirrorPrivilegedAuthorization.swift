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
            let keys = Set(request.params.keys)
            if keys == ["surfaceId", "tabId", "text"] {
                return request.params["text"]?.isEmpty == false
                    && (request.params["text"]?.utf8.count ?? 0) <= 8_192
            }
            guard keys == ["pasteByteCount", "pasteDigest", "surfaceId", "tabId"],
                  let rawByteCount = request.params["pasteByteCount"],
                  let byteCount = Int(rawByteCount),
                  (1...MobileMirrorTerminalControl.maximumPasteUTF8Bytes).contains(byteCount),
                  let digest = request.params["pasteDigest"], digest.utf8.count == 64,
                  digest.unicodeScalars.allSatisfy({
                      (48...57).contains($0.value) || (97...102).contains($0.value)
                  }) else {
                return false
            }
            return true
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
