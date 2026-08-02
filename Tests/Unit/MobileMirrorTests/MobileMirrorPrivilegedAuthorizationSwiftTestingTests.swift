// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror paired-session authorization")
struct MobileMirrorPrivilegedAuthorizationSwiftTestingTests {
    @Test("approved pairing issues one exact terminal grant")
    func approvedPairingIssuesExactGrant() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let channelID = UUID()
        let tabID = TabID()
        let request = try #require(Self.request(tabID: tabID, createdAt: now))
        let active = MobileMirrorActivePairing(
            channelID: channelID,
            identity: MobileMirrorClientIdentity(remoteAddress: "192.168.1.20", userAgent: "Phone"),
            pairedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )
        let context = Self.context(tabID: tabID)

        let grant = try #require(MobileMirrorPrivilegedAuthorization.grant(
            for: request,
            channelID: channelID,
            activePairing: active,
            tabID: tabID,
            context: context,
            at: now
        ))

        #expect(grant.context == context)
        #expect(grant.consume(for: request, at: now))
        #expect(!grant.consume(for: request, at: now))
    }

    @Test("wrong channel and non-terminal context cannot authorize input")
    func mismatchedScopeIsDenied() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let tabID = TabID()
        let request = try #require(Self.request(tabID: tabID, createdAt: now))
        let active = MobileMirrorActivePairing(
            channelID: UUID(),
            identity: MobileMirrorClientIdentity(remoteAddress: "10.0.0.2", userAgent: "Phone"),
            pairedAt: now,
            expiresAt: now.addingTimeInterval(60)
        )

        #expect(MobileMirrorPrivilegedAuthorization.grant(
            for: request,
            channelID: UUID(),
            activePairing: active,
            tabID: tabID,
            context: Self.context(tabID: tabID),
            at: now
        ) == nil)
        #expect(MobileMirrorPrivilegedAuthorization.grant(
            for: request,
            channelID: active.channelID,
            activePairing: active,
            tabID: tabID,
            context: Self.context(tabID: tabID, scope: .terminalTab),
            at: now
        ) == nil)
    }

    private static func request(
        tabID: TabID,
        createdAt: Date
    ) -> SocketPrivilegedCommandAuthorizationRequest? {
        SocketPrivilegedCommandAuthorizationRequest(
            socketRequest: SocketRequest(
                id: UUID().uuidString,
                command: CLICommandName.send.rawValue,
                params: ["tabId": tabID.rawValue.uuidString, "text": "pwd"]
            ),
            createdAt: createdAt
        )
    }

    private static func context(
        tabID: TabID,
        scope: SocketPrivilegedCommandContext.Scope = .terminalSurface
    ) -> SocketPrivilegedCommandContext {
        SocketPrivilegedCommandContext(
            scope: scope,
            windowControllerIdentifier: ObjectIdentifier(AuthorizationIdentity()),
            tabID: tabID.rawValue,
            workingDirectory: "/tmp",
            surfaceID: UUID(),
            browserViewModelIdentifier: nil,
            browserTabID: nil,
            browserURL: nil,
            targetDisplayName: "Paired terminal"
        )
    }
}

private final class AuthorizationIdentity {}
