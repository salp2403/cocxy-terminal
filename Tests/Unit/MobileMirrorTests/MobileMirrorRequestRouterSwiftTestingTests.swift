// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror request router")
struct MobileMirrorRequestRouterSwiftTestingTests {
    @Test("pairing flow sets an HTTP-only cookie and signed action is one use")
    func pairingAndSignedActionFlow() async throws {
        let authority = MobileMirrorPairingAuthority()
        let routes = MobileMirrorRouteRegistry()
        let pendingRecorder = MobileMirrorPendingRecorder()
        let actionRecorder = MobileMirrorActionRecorder()
        let rejectionRecorder = MobileMirrorRejectionRecorder()
        let snapshot = MobileMirrorSnapshot.empty
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            authority: authority,
            routeRegistry: routes,
            snapshotProvider: { _ in snapshot },
            actionHandler: { action, _, _, _ in
                await actionRecorder.record(action)
                return snapshot
            },
            rejectionAuditor: { reason, channelID, identity in
                await rejectionRecorder.record(reason, channelID: channelID, identity: identity)
            },
            pendingPairingHandler: { pending in
                await pendingRecorder.record(pending)
            }
        )
        router.updatePublicPort(43120)
        let identity = MobileMirrorClientIdentity(
            remoteAddress: "192.168.1.24",
            userAgent: "Mobile Browser"
        )
        let offer = authority.makeOffer()

        let pairResult = await router.route(
            request: request(
                path: "/pair",
                query: ["token": offer.token]
            ),
            identity: identity
        )
        let pairResponse = try response(from: pairResult)
        #expect(pairResponse.status == 200)
        let pending = try #require(await pendingRecorder.value)
        _ = try authority.decide(pendingID: pending.id, approve: true)

        let pollResult = await router.route(
            request: request(
                path: "/mobile/api/pair-status",
                query: ["id": pending.id.uuidString]
            ),
            identity: identity
        )
        let pollResponse = try response(from: pollResult)
        let setCookie = try #require(pollResponse.headers["Set-Cookie"])
        #expect(setCookie.contains("HttpOnly"))
        #expect(setCookie.contains("SameSite=Strict"))
        let cookie = try #require(setCookie
            .split(separator: ";").first?
            .split(separator: "=", maxSplits: 1).last
            .map(String.init))

        let foreignBootstrap = await router.route(
            request: request(
                path: "/mobile/api/bootstrap",
                headers: ["cookie": "cocxy_mobile=\(cookie)"]
            ),
            identity: MobileMirrorClientIdentity(
                remoteAddress: "192.168.1.25",
                userAgent: "Mobile Browser"
            )
        )
        #expect(try response(from: foreignBootstrap).status == 401)

        let bootstrapResult = await router.route(
            request: request(
                path: "/mobile/api/bootstrap",
                headers: ["cookie": "cocxy_mobile=\(cookie)"]
            ),
            identity: identity
        )
        let bootstrap = try JSONDecoder().decode(
            MobileMirrorBootstrap.self,
            from: try response(from: bootstrapResult).body
        )
        #expect(bootstrap.snapshot == snapshot)

        let action = MobileMirrorAction(
            kind: .selectSession,
            sessionID: UUID().uuidString,
            surfaceID: UUID().uuidString
        )
        let body = try JSONEncoder().encode(action)
        let timestamp = String(UInt64(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        let signedActionSignature = try signature(
            body: body,
            timestamp: timestamp,
            nonce: nonce,
            secret: bootstrap.actionSecret
        )
        let signedRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: [
                "cookie": "cocxy_mobile=\(cookie)",
                "origin": "http://127.0.0.1:43120",
                "content-type": "application/json",
                "x-cocxy-timestamp": timestamp,
                "x-cocxy-nonce": nonce,
                "x-cocxy-signature": signedActionSignature,
            ],
            body: body
        )
        let actionResult = await router.route(request: signedRequest, identity: identity)
        #expect(try response(from: actionResult).status == 200)
        #expect(await actionRecorder.values == [action])

        let replayResult = await router.route(request: signedRequest, identity: identity)
        #expect(try response(from: replayResult).status == 403)
        #expect(await actionRecorder.values == [action])

        let invalidSignatureRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: [
                "cookie": "cocxy_mobile=\(cookie)",
                "origin": "http://127.0.0.1:43120",
                "content-type": "application/json",
                "x-cocxy-timestamp": String(UInt64(Date().timeIntervalSince1970)),
                "x-cocxy-nonce": UUID().uuidString,
                "x-cocxy-signature": "bad",
            ],
            body: body
        )
        #expect(try response(
            from: await router.route(request: invalidSignatureRequest, identity: identity)
        ).status == 403)

        let malformedBody = Data("{".utf8)
        let malformedTimestamp = String(UInt64(Date().timeIntervalSince1970))
        let malformedNonce = UUID().uuidString
        let malformedRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: [
                "cookie": "cocxy_mobile=\(cookie)",
                "origin": "http://127.0.0.1:43120",
                "content-type": "application/json",
                "x-cocxy-timestamp": malformedTimestamp,
                "x-cocxy-nonce": malformedNonce,
                "x-cocxy-signature": try signature(
                    body: malformedBody,
                    timestamp: malformedTimestamp,
                    nonce: malformedNonce,
                    secret: bootstrap.actionSecret
                ),
            ],
            body: malformedBody
        )
        #expect(try response(
            from: await router.route(request: malformedRequest, identity: identity)
        ).status == 400)
        #expect(await rejectionRecorder.reasons == [
            .replayDetected,
            .invalidSignature,
            .malformedAction,
        ])

        let terminalAction = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            surfaceID: UUID().uuidString,
            controlType: "viewport-scroll",
            scrollDelta: 3
        )
        let terminalBody = try JSONEncoder().encode(terminalAction)
        let terminalTimestamp = String(UInt64(Date().timeIntervalSince1970))
        let terminalNonce = UUID().uuidString
        let terminalResult = await router.route(
            request: request(
                method: "POST",
                path: "/mobile/api/action",
                headers: [
                    "cookie": "cocxy_mobile=\(cookie)",
                    "origin": "http://127.0.0.1:43120",
                    "content-type": "application/json",
                    "x-cocxy-timestamp": terminalTimestamp,
                    "x-cocxy-nonce": terminalNonce,
                    "x-cocxy-signature": try self.signature(
                        body: terminalBody,
                        timestamp: terminalTimestamp,
                        nonce: terminalNonce,
                        secret: bootstrap.actionSecret
                    ),
                ],
                body: terminalBody
            ),
            identity: identity
        )
        let terminalResponse = try JSONDecoder().decode(
            MobileMirrorActionResponse.self,
            from: try response(from: terminalResult).body
        )
        #expect(terminalResponse.ok)
        #expect(terminalResponse.snapshot == nil)
        #expect(await actionRecorder.values == [action, terminalAction])

        let terminalSessionID = UUID().uuidString
        let terminalSurfaceID = SurfaceID()
        routes.replace(
            routes: [MobileMirrorTerminalRoute(
                sessionID: terminalSessionID,
                surfaceID: terminalSurfaceID,
                port: 42_345,
                bearerToken: "stream-token"
            )],
            preferredSurfaceID: terminalSurfaceID.rawValue.uuidString
        )
        let authenticatedHeaders = ["cookie": "cocxy_mobile=\(cookie)"]
        guard case .proxy = await router.route(
            request: request(path: "/index.html", headers: authenticatedHeaders),
            identity: identity
        ) else {
            Issue.record("Expected authenticated static asset proxy")
            return
        }
        guard case .eventStream = await router.route(
            request: request(path: "/mobile/api/events", headers: authenticatedHeaders),
            identity: identity
        ) else {
            Issue.record("Expected authenticated event stream")
            return
        }
        guard case .proxy = await router.route(
            request: request(
                path: "/terminal/\(terminalSurfaceID.rawValue.uuidString)/ws",
                headers: [
                    "cookie": "cocxy_mobile=\(cookie)",
                    "origin": "http://127.0.0.1:43120",
                    "upgrade": "websocket",
                ]
            ),
            identity: identity
        ) else {
            Issue.record("Expected authenticated terminal proxy")
            return
        }

        for _ in 0..<32 {
            let sustainedBody = try JSONEncoder().encode(terminalAction)
            let sustainedTimestamp = String(UInt64(Date().timeIntervalSince1970))
            let sustainedNonce = UUID().uuidString
            let sustainedResult = await router.route(
                request: request(
                    method: "POST",
                    path: "/mobile/api/action",
                    headers: [
                        "cookie": "cocxy_mobile=\(cookie)",
                        "origin": "http://127.0.0.1:43120",
                        "content-type": "application/json",
                        "x-cocxy-timestamp": sustainedTimestamp,
                        "x-cocxy-nonce": sustainedNonce,
                        "x-cocxy-signature": try self.signature(
                            body: sustainedBody,
                            timestamp: sustainedTimestamp,
                            nonce: sustainedNonce,
                            secret: bootstrap.actionSecret
                        ),
                    ],
                    body: sustainedBody
                ),
                identity: identity
            )
            #expect(try response(from: sustainedResult).status == 200)
        }
        #expect(await actionRecorder.values.count == 34)
    }

    @Test("audit persistence failure blocks an unaudited action rejection")
    func auditFailureBlocksRejectedActionResponse() async throws {
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
        let actionRecorder = MobileMirrorActionRecorder()
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            snapshotProvider: { _ in .empty },
            actionHandler: { action, _, _, _ in
                await actionRecorder.record(action)
                return .empty
            },
            rejectionAuditor: { _, _, _ in
                throw RelayAuditWriterTestFailure.injected
            },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(43120)

        let result = await router.route(
            request: request(
                method: "POST",
                path: "/mobile/api/action",
                headers: [
                    "cookie": "cocxy_mobile=\(cookie)",
                    "origin": "http://127.0.0.1:43120",
                    "content-type": "application/json",
                ]
            ),
            identity: identity
        )

        #expect(try response(from: result).status == 503)
        #expect(await actionRecorder.values.isEmpty)
    }

    @Test("unpaired and internal test assets are not proxied")
    func unauthorizedAndInternalRoutesAreRejected() async throws {
        let authority = MobileMirrorPairingAuthority()
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            snapshotProvider: { _ in .empty },
            actionHandler: { _, _, _, _ in .empty },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(4444)
        let identity = MobileMirrorClientIdentity(remoteAddress: "10.0.0.3", userAgent: "Phone")

        let unauthorized = await router.route(
            request: request(path: "/index.html", host: "127.0.0.1:4444"),
            identity: identity
        )
        #expect(try response(from: unauthorized).status == 401)

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
        let internalAsset = await router.route(
            request: request(
                path: "/tests/render-smoke.html",
                host: "127.0.0.1:4444",
                headers: ["cookie": "cocxy_mobile=\(cookie)"]
            ),
            identity: identity
        )
        #expect(try response(from: internalAsset).status == 404)
    }

    private func request(
        method: String = "GET",
        path: String,
        host: String = "127.0.0.1:43120",
        query: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data = Data()
    ) -> MobileMirrorHTTPRequest {
        let queryText = query.isEmpty
            ? ""
            : "?" + query.keys.sorted().map { "\($0)=\(query[$0] ?? "")" }.joined(separator: "&")
        var resolvedHeaders = headers
        resolvedHeaders["host"] = host
        return MobileMirrorHTTPRequest(
            method: method,
            target: path + queryText,
            path: path,
            query: query,
            version: "HTTP/1.1",
            headers: resolvedHeaders,
            body: body
        )
    }

    private func response(
        from result: MobileMirrorHTTPRouteResult
    ) throws -> MobileMirrorHTTPResponse {
        guard case .response(let response) = result else {
            throw MobileMirrorRouterTestError.expectedResponse
        }
        return response
    }

    private func signature(
        body: Data,
        timestamp: String,
        nonce: String,
        secret: String
    ) throws -> String {
        let secretData = try #require(MobileMirrorPairingAuthority.decodeBase64URL(secret))
        let key = SymmetricKey(data: secretData)
        let payload = Data("\(timestamp)\n\(nonce)\n".utf8) + body
        return MobileMirrorPairingAuthority.base64URL(
            Data(HMAC<SHA256>.authenticationCode(for: payload, using: key))
        )
    }
}

private enum MobileMirrorRouterTestError: Error {
    case expectedResponse
}

private actor MobileMirrorPendingRecorder {
    private(set) var value: MobileMirrorPendingPairing?
    func record(_ pending: MobileMirrorPendingPairing) { value = pending }
}

private actor MobileMirrorActionRecorder {
    private(set) var values: [MobileMirrorAction] = []
    func record(_ action: MobileMirrorAction) { values.append(action) }
}

private actor MobileMirrorRejectionRecorder {
    private(set) var reasons: [MobileMirrorActionAudit.RejectionReason] = []

    func record(
        _ reason: MobileMirrorActionAudit.RejectionReason,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) {
        _ = channelID
        _ = identity
        reasons.append(reason)
    }
}

private enum RelayAuditWriterTestFailure: Error {
    case injected
}
