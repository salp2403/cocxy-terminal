// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror security")
struct MobileMirrorSecuritySwiftTestingTests {
    @Test("pairing token is consumed once and requires desktop approval")
    func pairingTokenIsOneUse() throws {
        let clock = MobileMirrorTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let authority = MobileMirrorPairingAuthority(clock: { clock.now })
        let identity = MobileMirrorClientIdentity(
            remoteAddress: "192.168.1.23",
            userAgent: "Mobile Browser"
        )
        let offer = authority.makeOffer()
        let pending = try authority.consumeOffer(token: offer.token, identity: identity)

        #expect(pending.channelID == offer.id)
        #expect(throws: MobileMirrorError.invalidPairingToken) {
            try authority.consumeOffer(token: offer.token, identity: identity)
        }
        #expect(try authority.poll(pendingID: pending.id, identity: identity) == .pending)

        let active = try #require(try authority.decide(pendingID: pending.id, approve: true))
        guard case .confirmed(let cookie) = try authority.poll(
            pendingID: pending.id,
            identity: identity
        ) else {
            Issue.record("Expected confirmed pairing")
            return
        }
        let credentials = try authority.credentials(cookie: cookie)
        #expect(credentials.channelID == active.channelID)
        #expect(credentials.actionSecret.isEmpty == false)
        #expect(authority.activePairing(cookie: "wrong") == nil)
        #expect(authority.activePairing(cookie: cookie)?.identity == identity)
    }

    @Test("pairing token expires before it can create a pending client")
    func pairingTokenExpires() throws {
        let clock = MobileMirrorTestClock(Date(timeIntervalSince1970: 2_000_000_000))
        let authority = MobileMirrorPairingAuthority(clock: { clock.now })
        let offer = authority.makeOffer(ttl: 5)
        clock.now = clock.now.addingTimeInterval(6)

        #expect(throws: MobileMirrorError.pairingExpired) {
            try authority.consumeOffer(
                token: offer.token,
                identity: MobileMirrorClientIdentity(remoteAddress: "10.0.0.4", userAgent: "Phone")
            )
        }
    }

    @Test("signed actions bind timestamp nonce and exact body and reject replay")
    func signedActionsRejectReplay() throws {
        let authority = MobileMirrorPairingAuthority()
        let identity = MobileMirrorClientIdentity(remoteAddress: "10.0.0.8", userAgent: "Phone")
        let offer = authority.makeOffer()
        let pending = try authority.consumeOffer(token: offer.token, identity: identity)
        _ = try authority.decide(pendingID: pending.id, approve: true)
        guard case .confirmed(let cookie) = try authority.poll(
            pendingID: pending.id,
            identity: identity
        ) else {
            Issue.record("Expected confirmed pairing")
            return
        }
        let credentials = try authority.credentials(cookie: cookie)
        let body = Data("{\"kind\":\"select-session\"}".utf8)
        let timestamp = String(UInt64(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        let signature = try sign(
            timestamp: timestamp,
            nonce: nonce,
            body: body,
            secret: credentials.actionSecret
        )

        #expect(try authority.validateAction(
            cookie: cookie,
            timestamp: timestamp,
            nonce: nonce,
            signature: signature,
            body: body
        ) == credentials.channelID)
        #expect(throws: MobileMirrorError.replayDetected) {
            try authority.validateAction(
                cookie: cookie,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature,
                body: body
            )
        }

        let changedBody = Data("{\"kind\":\"project-create\"}".utf8)
        #expect(throws: MobileMirrorError.invalidSignature) {
            try authority.validateAction(
                cookie: cookie,
                timestamp: timestamp,
                nonce: UUID().uuidString,
                signature: signature,
                body: changedBody
            )
        }
    }

    @Test("HTTP parser accepts exact content length and rejects duplicate signature headers")
    func boundedHTTPParser() throws {
        let body = "{\"kind\":\"project-create\",\"name\":\"Demo\"}"
        let request = Data((
            "POST /mobile/api/action HTTP/1.1\r\n"
                + "Host: 192.168.1.2:42100\r\n"
                + "Content-Type: application/json\r\n"
                + "Content-Length: \(body.utf8.count)\r\n\r\n"
                + body
        ).utf8)
        let parsed = try #require(try MobileMirrorHTTPRequest.parseIfComplete(request))
        #expect(parsed.method == "POST")
        #expect(parsed.path == "/mobile/api/action")
        #expect(parsed.body == Data(body.utf8))

        let duplicate = Data((
            "POST /mobile/api/action HTTP/1.1\r\n"
                + "Host: local\r\n"
                + "X-Cocxy-Signature: one\r\n"
                + "X-Cocxy-Signature: two\r\n"
                + "Content-Length: 0\r\n\r\n"
        ).utf8)
        #expect(throws: MobileMirrorHTTPError.duplicateSecurityHeader) {
            try MobileMirrorHTTPRequest.parseIfComplete(duplicate)
        }
    }

    @Test("terminal action permits bounded viewport scroll but rejects browser mouse controls")
    func terminalActionValidatesViewportNavigation() throws {
        let action = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "mouse",
            mouseAction: "press",
            row: 1,
            col: 1,
            button: 1
        )
        #expect(throws: MobileMirrorError.invalidAction) {
            try action.validate()
        }

        let viewportScroll = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "viewport-scroll",
            scrollDelta: 4
        )
        try viewportScroll.validate()

        let unboundedScroll = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "viewport-scroll",
            scrollDelta: 65
        )
        #expect(throws: MobileMirrorError.invalidAction) {
            try unboundedScroll.validate()
        }

        let ambiguous = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            controlType: "key",
            key: "enter",
            text: "unexpected"
        )
        #expect(throws: MobileMirrorError.invalidAction) {
            try ambiguous.validate()
        }

        let pollutedSelection = MobileMirrorAction(
            kind: .selectSession,
            sessionID: UUID().uuidString,
            text: "unexpected"
        )
        #expect(throws: MobileMirrorError.invalidAction) {
            try pollutedSelection.validate()
        }
    }

    private func sign(
        timestamp: String,
        nonce: String,
        body: Data,
        secret: String
    ) throws -> String {
        let secretData = try #require(MobileMirrorPairingAuthority.decodeBase64URL(secret))
        let key = SymmetricKey(data: secretData)
        let payload = Data("\(timestamp)\n\(nonce)\n".utf8) + body
        let signature = Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        return MobileMirrorPairingAuthority.base64URL(signature)
    }
}

private final class MobileMirrorTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var storedNow: Date

    init(_ now: Date) {
        storedNow = now
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedNow
        }
        set {
            lock.lock()
            storedNow = newValue
            lock.unlock()
        }
    }
}
