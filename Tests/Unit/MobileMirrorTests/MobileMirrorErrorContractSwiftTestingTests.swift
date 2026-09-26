// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror error contract", .serialized)
struct MobileMirrorErrorContractSwiftTestingTests: MobileMirrorRouterTestSupport {
    private static let invalidatingCodes: Set<String> = ["credential-invalid", "session-expired"]

    @Test("desktop denial answers authorization-denied without scoring or invalidating")
    func desktopDenialKeepsPairing() async throws {
        let paired = try PairedMirrorRouter.make(localization: webLocalization(.spanish)) { _ in
            throw MobileMirrorError.authorizationDenied
        }

        for sequence in 0..<14 {
            let reply = try await paired.post(Self.scrollAction, sequence: UInt64(sequence))
            #expect(reply.status == 403)
            #expect(reply.payload.code == "authorization-denied")
            #expect(reply.payload.error == "Se rechazó la acción móvil")
            #expect(!Self.invalidatingCodes.contains(reply.payload.code ?? ""))
        }
        #expect(paired.authority.activePairing() != nil)
    }

    @Test("a vanished mirrored target never exhausts the authentication budget")
    func vanishedTargetDoesNotScore() async throws {
        let paired = try PairedMirrorRouter.make(localization: webLocalization(.spanish)) { _ in
            throw MobileMirrorError.targetUnavailable
        }

        for sequence in 0..<14 {
            let reply = try await paired.post(Self.scrollAction, sequence: UInt64(sequence))
            #expect(reply.status == 503)
            #expect(reply.payload.code == "target-unavailable")
            #expect(reply.payload.error == "No hay ninguna sesión de terminal seleccionada")
        }
    }

    @Test("only rejected credentials and expired sessions carry invalidating codes")
    func credentialFailuresInvalidate() async throws {
        let paired = try PairedMirrorRouter.make(localization: webLocalization(.spanish)) { _ in
            .empty
        }

        let pairing = try response(from: await paired.router.route(
            request: request(path: "/pair", query: ["token": "not-the-token"]),
            identity: paired.identity
        ))
        let pairingPayload = try Self.decode(pairing)
        #expect(pairing.status == 403)
        #expect(pairingPayload.code == "credential-invalid")
        #expect(pairingPayload.error == "Falló la autenticación")

        var forged = try paired.signedRequest(Self.scrollAction, sequence: 0)
        forged = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: forged.headers.merging(["x-cocxy-signature": "forged"]) { $1 },
            body: forged.body
        )
        let forgedReply = try response(from: await paired.router.route(
            request: forged,
            identity: paired.identity
        ))
        #expect(forgedReply.status == 403)
        #expect(try Self.decode(forgedReply).code == "credential-invalid")

        let missingCookie = try response(from: await paired.router.route(
            request: request(path: "/mobile/api/state"),
            identity: paired.identity
        ))
        let missingCookiePayload = try Self.decode(missingCookie)
        #expect(missingCookie.status == 401)
        #expect(missingCookiePayload.code == "session-expired")
        #expect(missingCookiePayload.error
            == "Escanea un nuevo código QR en el Mac para volver a conectarte")
    }

    @Test("a skewed phone clock gets actionable guidance instead of a replay alarm")
    func skewedClockIsActionable() async throws {
        let paired = try PairedMirrorRouter.make(localization: webLocalization(.spanish)) { _ in
            .empty
        }
        let skewed = String(UInt64(Date().timeIntervalSince1970) - 3_600)

        for _ in 0..<14 {
            let reply = try await paired.post(Self.scrollAction, sequence: 0, timestamp: skewed)
            #expect(reply.status == 400)
            #expect(reply.payload.code == "invalid-request")
            #expect(reply.payload.error == "El reloj de este teléfono no coincide con el del Mac. "
                + "Activa la fecha y la hora automáticas y vuelve a intentarlo.")
        }
        #expect(await paired.rejections.reasons.map(\.rawValue)
            == Array(repeating: "clock-skew", count: 14))

        let corrected = try await paired.post(Self.scrollAction, sequence: 0)
        #expect(corrected.status == 200)
    }

    @Test("every protocol-level error response carries a contract code in the phone language")
    func protocolErrorsCarryCodes() async throws {
        let paired = try PairedMirrorRouter.make(localization: webLocalization(.spanish)) { _ in
            .empty
        }
        let cookie = ["cookie": "cocxy_mobile=\(paired.cookie)"]
        let cases: [(MobileMirrorHTTPRequest, Int, String)] = [
            (request(path: "/mobile/api/state", host: "evil.example:43120"), 403, "invalid-request"),
            (request(path: "/pair"), 400, "invalid-request"),
            (request(method: "POST", path: "/mobile/api/state", headers: cookie), 400, "invalid-request"),
            (request(path: "/private/file.txt", headers: cookie), 404, "invalid-request"),
            (request(path: "/terminal/\(UUID().uuidString)/ws", headers: cookie), 404, "target-unavailable"),
            (request(path: "/ws", headers: cookie), 503, "target-unavailable"),
        ]

        for (candidate, status, code) in cases {
            let reply = try response(from: await paired.router.route(
                request: candidate,
                identity: paired.identity
            ))
            let payload = try Self.decode(reply)
            #expect(reply.status == status, "\(candidate.path)")
            #expect(payload.code == code, "\(candidate.path)")
            #expect(payload.ok == false)
            #expect(!Self.englishProtocolLiterals.contains(payload.error ?? ""), "\(candidate.path)")
        }
    }

    @Test("rate limiting answers rate-limited in the phone language")
    func rateLimitIsCodedAndLocalized() async throws {
        let paired = try PairedMirrorRouter.make(localization: webLocalization(.spanish)) { _ in
            .empty
        }
        let base = try paired.signedRequest(Self.scrollAction, sequence: 0)
        let forged = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: base.headers.merging(["x-cocxy-signature": "forged"]) { $1 },
            body: base.body
        )

        var statuses: [Int] = []
        var limited: MobileMirrorHTTPResponse?
        for _ in 0..<13 {
            let reply = try response(from: await paired.router.route(
                request: forged,
                identity: paired.identity
            ))
            statuses.append(reply.status)
            if reply.status == 429 { limited = reply }
        }
        #expect(statuses == Array(repeating: 403, count: 12) + [429])
        let payload = try Self.decode(try #require(limited))
        #expect(payload.code == "rate-limited")
        #expect(payload.error == "Demasiadas solicitudes. Espera un momento y vuelve a intentarlo.")
    }

    @Test("every mirror error maps to one contract code, status and limiter decision")
    func everyMirrorErrorHasAContract() throws {
        let spanish = try webLocalization(.spanish)
        for contractCase in ContractCase.allCases {
            let error = contractCase.sample
            #expect(ContractCase(error) == contractCase)
            let expected = contractCase.expected
            let failure = MobileMirrorFailure(error)
            #expect(failure.status == expected.status, "\(error)")
            #expect(failure.code.rawValue == expected.code, "\(error)")
            #expect(failure.countsAsAuthenticationFailure == expected.counts, "\(error)")

            let payload = try Self.decode(failure.response(using: spanish))
            #expect(payload.ok == false)
            #expect(payload.code == expected.code, "\(error)")
            #expect(payload.error == error.localizedDescription(using: spanish), "\(error)")
            let entry = error.localizationEntry
            #expect(spanish.catalog[entry.key] != nil, "\(entry.key)")
            #expect(MobileMirrorWebLocalization.english.text(entry.key) == entry.fallback)
        }
        #expect(Set(ContractCase.allCases.map(\.expected.code))
            .isSubset(of: Set(MobileMirrorResponseCode.allCases.map(\.rawValue))))

        let cancelled = MobileMirrorFailure(CancellationError())
        #expect(cancelled.status == 504)
        #expect(cancelled.code == .unavailable)
        #expect(!cancelled.countsAsAuthenticationFailure)
        let foreign = MobileMirrorFailure(CocoaError(.fileReadNoPermission, userInfo: [
            NSFilePathErrorKey: "/Users/owner/private",
        ]))
        #expect(foreign.status == 503)
        #expect(foreign.code == .unavailable)
        #expect(!foreign.countsAsAuthenticationFailure)
        #expect(try Self.decode(foreign.response(using: spanish)).error
            == "El espejo móvil no está disponible.")
    }

    @Test("every protocol-level failure resolves through the phone catalog")
    func protocolFailuresResolveThroughCatalog() throws {
        let spanish = try webLocalization(.spanish)
        let failures: [MobileMirrorFailure] = [
            .rateLimited, .timedOut, .unexpected, .auditUnavailable, .missingSession,
            .invalidHost, .unsignedAction, .invalidTerminalOrigin, .malformedRequest,
            .notFound, .missingTerminalStream, .noTerminalStream, .terminalProxyUnavailable,
        ]
        for failure in failures {
            let translated = try #require(spanish.catalog[failure.messageKey], "\(failure.messageKey)")
            #expect(translated != MobileMirrorWebLocalization.english.text(failure.messageKey))
        }
    }

    private static let scrollAction = MobileMirrorAction(
        kind: .terminalControl,
        sessionID: UUID().uuidString,
        surfaceID: UUID().uuidString,
        controlType: "viewport-scroll",
        scrollDelta: 2
    )

    private static let englishProtocolLiterals: Set<String> = [
        "Invalid local host.", "Invalid pairing request.", "Method not allowed.", "Not found.",
        "Terminal stream is unavailable.", "No local terminal stream is available.",
        "Too many local requests.", "Local request timed out.", "Invalid signed action.",
    ]

    fileprivate static func decode(
        _ response: MobileMirrorHTTPResponse
    ) throws -> MobileMirrorActionResponse {
        try JSONDecoder().decode(MobileMirrorActionResponse.self, from: response.body)
    }
}

/// Mirrors every `MobileMirrorError` case. Both switches are exhaustive: a new
/// production case stops compiling here until it gets a mirror case, and a new
/// mirror case stops compiling until it gets a sample and an expected contract.
private enum ContractCase: CaseIterable {
    case unavailable, noPrivateNetwork, invalidPairingToken, pairingExpired, pairingPending
    case pairingDenied, sessionExpired, invalidSignature, replayDetected, clockSkew
    case invalidAction, targetUnavailable, authorizationDenied, projectCreationUnavailable
    case invalidProjectName, projectAlreadyExists, projectCreationFailed

    init(_ error: MobileMirrorError) {
        switch error {
        case .unavailable: self = .unavailable
        case .noPrivateNetwork: self = .noPrivateNetwork
        case .invalidPairingToken: self = .invalidPairingToken
        case .pairingExpired: self = .pairingExpired
        case .pairingPending: self = .pairingPending
        case .pairingDenied: self = .pairingDenied
        case .sessionExpired: self = .sessionExpired
        case .invalidSignature: self = .invalidSignature
        case .replayDetected: self = .replayDetected
        case .clockSkew: self = .clockSkew
        case .invalidAction: self = .invalidAction
        case .targetUnavailable: self = .targetUnavailable
        case .authorizationDenied: self = .authorizationDenied
        case .projectCreationUnavailable: self = .projectCreationUnavailable
        case .invalidProjectName: self = .invalidProjectName
        case .projectAlreadyExists: self = .projectAlreadyExists
        case .projectCreationFailed: self = .projectCreationFailed
        }
    }

    var sample: MobileMirrorError {
        switch self {
        case .unavailable: .unavailable
        case .noPrivateNetwork: .noPrivateNetwork
        case .invalidPairingToken: .invalidPairingToken
        case .pairingExpired: .pairingExpired
        case .pairingPending: .pairingPending
        case .pairingDenied: .pairingDenied
        case .sessionExpired: .sessionExpired
        case .invalidSignature: .invalidSignature
        case .replayDetected: .replayDetected
        case .clockSkew: .clockSkew
        case .invalidAction: .invalidAction
        case .targetUnavailable: .targetUnavailable
        case .authorizationDenied: .authorizationDenied
        case .projectCreationUnavailable: .projectCreationUnavailable
        case .invalidProjectName: .invalidProjectName
        case .projectAlreadyExists: .projectAlreadyExists
        case .projectCreationFailed: .projectCreationFailed("/Users/owner/private")
        }
    }

    var expected: (status: Int, code: String, counts: Bool) {
        switch self {
        case .invalidPairingToken, .invalidSignature: (403, "credential-invalid", true)
        case .pairingExpired, .sessionExpired: (401, "session-expired", true)
        case .replayDetected: (409, "replay-detected", true)
        case .clockSkew, .invalidAction, .invalidProjectName: (400, "invalid-request", false)
        case .projectAlreadyExists: (409, "project-exists", false)
        case .authorizationDenied, .pairingDenied: (403, "authorization-denied", false)
        case .targetUnavailable: (503, "target-unavailable", false)
        case .unavailable, .noPrivateNetwork, .pairingPending, .projectCreationUnavailable,
             .projectCreationFailed: (503, "unavailable", false)
        }
    }
}

final class MobileMirrorManualMonotonicClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 1_000

    var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value += interval
        lock.unlock()
    }
}

struct PairedMirrorRouter: MobileMirrorRouterTestSupport {
    let router: MobileMirrorRequestRouter
    let authority: MobileMirrorPairingAuthority
    let cookie: String
    let keys: MobileMirrorSessionKeys
    let identity: MobileMirrorClientIdentity
    let rejections: MobileMirrorRejectionRecorder
    let clock: MobileMirrorManualMonotonicClock

    static func make(
        localization: MobileMirrorWebLocalization,
        actionHandler: @escaping @Sendable (MobileMirrorAction) async throws -> MobileMirrorSnapshot
    ) throws -> PairedMirrorRouter {
        let authority = MobileMirrorPairingAuthority()
        let identity = MobileMirrorClientIdentity(
            remoteAddress: "192.168.1.44",
            userAgent: "Contract Phone"
        )
        let offer = authority.makeOffer()
        let pending = try authority.consumeOffer(token: offer.token, identity: identity)
        _ = try authority.decide(pendingID: pending.id, approve: true)
        guard case .confirmed(let cookie) = try authority.poll(
            pendingID: pending.id,
            identity: identity
        ) else {
            throw MobileMirrorRouterTestError.expectedResponse
        }
        let rejections = MobileMirrorRejectionRecorder()
        let clock = MobileMirrorManualMonotonicClock()
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .localTLS,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            localization: localization,
            monotonicNow: { clock.now },
            snapshotProvider: { _ in .empty },
            actionHandler: { action, _, _, _ in try await actionHandler(action) },
            rejectionAuditor: { reason, channelID, identity in
                await rejections.record(reason, channelID: channelID, identity: identity)
            },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(43120)
        return PairedMirrorRouter(
            router: router,
            authority: authority,
            cookie: cookie,
            keys: try MobileMirrorEncryptedActionTestSupport.sessionKeys(for: offer),
            identity: identity,
            rejections: rejections,
            clock: clock
        )
    }

    func signedRequest(
        _ action: MobileMirrorAction,
        sequence: UInt64,
        timestamp: String = String(UInt64(Date().timeIntervalSince1970))
    ) throws -> MobileMirrorHTTPRequest {
        let body = try MobileMirrorEncryptedActionTestSupport.requestBody(
            action: action,
            key: keys.terminalInputEncryptionKey,
            sequence: sequence
        )
        return request(
            method: "POST",
            path: "/mobile/api/action",
            headers: MobileMirrorEncryptedActionTestSupport.signedHeaders(
                body: body,
                actionToken: keys.actionToken,
                cookie: cookie,
                origin: "https://127.0.0.1:43120",
                timestamp: timestamp
            ),
            body: body
        )
    }

    func post(
        _ action: MobileMirrorAction,
        sequence: UInt64,
        timestamp: String = String(UInt64(Date().timeIntervalSince1970))
    ) async throws -> (status: Int, payload: MobileMirrorActionResponse) {
        let reply = try response(from: await router.route(
            request: signedRequest(action, sequence: sequence, timestamp: timestamp),
            identity: identity
        ))
        return (
            reply.status,
            try JSONDecoder().decode(MobileMirrorActionResponse.self, from: reply.body)
        )
    }
}
