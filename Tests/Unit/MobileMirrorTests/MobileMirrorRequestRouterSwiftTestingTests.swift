// Copyright (c) 2026 Said Arturo Lopez. MIT License.

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
        let localization = try webLocalization(.spanish)
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .localTLS,
            authority: authority,
            routeRegistry: routes,
            localization: localization,
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
        let sessionKeys = try MobileMirrorEncryptedActionTestSupport.sessionKeys(for: offer)

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
        #expect(setCookie.contains("; Secure"))
        let cookie = try #require(setCookie
            .split(separator: ";").first?
            .split(separator: "=", maxSplits: 1).last
            .map(String.init))

        let replayedPoll = await router.route(
            request: request(
                path: "/mobile/api/pair-status",
                query: ["id": pending.id.uuidString]
            ),
            identity: identity
        )
        let replayedResponse = try response(from: replayedPoll)
        #expect(replayedResponse.status == 401)
        #expect(replayedResponse.headers["Set-Cookie"] == nil)

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
        let foreignBootstrapResponse = try response(from: foreignBootstrap)
        #expect(foreignBootstrapResponse.status == 401)
        let foreignBootstrapPayload = try #require(
            JSONSerialization.jsonObject(with: foreignBootstrapResponse.body) as? [String: Any]
        )
        #expect(foreignBootstrapPayload["error"] as? String ==
            "Escanea un nuevo código QR en el Mac para volver a conectarte")

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
        #expect(bootstrap.channelID == offer.id.uuidString.lowercased())
        #expect(bootstrap.locale == "es")
        #expect(bootstrap.direction == "ltr")
        #expect(bootstrap.catalog["mobile.web.projects.title"] == "Proyectos")
        #expect(bootstrap.catalog["mobile.web.terminal.input"] == "Escribe en el terminal")

        router.updateLocalization(try webLocalization(.arabic))
        let localizedBootstrapResult = await router.route(
            request: request(
                path: "/mobile/api/bootstrap",
                headers: ["cookie": "cocxy_mobile=\(cookie)"]
            ),
            identity: identity
        )
        let localizedBootstrap = try JSONDecoder().decode(
            MobileMirrorBootstrap.self,
            from: try response(from: localizedBootstrapResult).body
        )
        #expect(localizedBootstrap.channelID == bootstrap.channelID)
        #expect(localizedBootstrap.locale == "ar")
        #expect(localizedBootstrap.direction == "rtl")

        let stateResult = await router.route(
            request: request(
                path: "/mobile/api/state",
                headers: ["cookie": "cocxy_mobile=\(cookie)"]
            ),
            identity: identity
        )
        let state = try JSONDecoder().decode(
            MobileMirrorStatePayload.self,
            from: try response(from: stateResult).body
        )
        #expect(state.snapshot == snapshot)
        #expect(state.locale == "ar")
        #expect(state.direction == "rtl")
        #expect(state.catalog["mobile.web.projects.title"] == "المشاريع")

        let action = MobileMirrorAction(
            kind: .selectSession,
            sessionID: UUID().uuidString,
            surfaceID: UUID().uuidString
        )
        let body = try MobileMirrorEncryptedActionTestSupport.requestBody(
            action: action,
            key: sessionKeys.terminalInputEncryptionKey,
            sequence: 0
        )
        let signedRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: MobileMirrorEncryptedActionTestSupport.signedHeaders(
                body: body,
                actionToken: sessionKeys.actionToken,
                cookie: cookie,
                origin: "https://127.0.0.1:43120"
            ),
            body: body
        )
        let actionResult = await router.route(request: signedRequest, identity: identity)
        #expect(try response(from: actionResult).status == 200)
        #expect(await actionRecorder.values == [action])

        let replayResult = await router.route(request: signedRequest, identity: identity)
        #expect(try response(from: replayResult).status == 403)
        #expect(await actionRecorder.values == [action])

        var invalidSignatureHeaders = MobileMirrorEncryptedActionTestSupport.signedHeaders(
            body: body,
            actionToken: sessionKeys.actionToken,
            cookie: cookie,
            origin: "https://127.0.0.1:43120"
        )
        invalidSignatureHeaders["x-cocxy-signature"] = "bad"
        let invalidSignatureRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: invalidSignatureHeaders,
            body: body
        )
        #expect(try response(
            from: await router.route(request: invalidSignatureRequest, identity: identity)
        ).status == 403)

        let wrongKeyBody = try MobileMirrorEncryptedActionTestSupport.requestBody(
            action: action,
            key: Data(repeating: 0xA5, count: 32),
            sequence: 1
        )
        let wrongKeyRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: MobileMirrorEncryptedActionTestSupport.signedHeaders(
                body: wrongKeyBody,
                actionToken: sessionKeys.actionToken,
                cookie: cookie,
                origin: "https://127.0.0.1:43120"
            ),
            body: wrongKeyBody
        )
        #expect(try response(
            from: await router.route(request: wrongKeyRequest, identity: identity)
        ).status == 403)

        let malformedBody = try MobileMirrorEncryptedActionTestSupport.requestBody(
            plaintext: Data("{".utf8),
            key: sessionKeys.terminalInputEncryptionKey,
            sequence: 1
        )
        let malformedRequest = request(
            method: "POST",
            path: "/mobile/api/action",
            headers: MobileMirrorEncryptedActionTestSupport.signedHeaders(
                body: malformedBody,
                actionToken: sessionKeys.actionToken,
                cookie: cookie,
                origin: "https://127.0.0.1:43120"
            ),
            body: malformedBody
        )
        #expect(try response(
            from: await router.route(request: malformedRequest, identity: identity)
        ).status == 400)
        #expect(await rejectionRecorder.reasons == [
            .replayDetected,
            .invalidSignature,
            .invalidEnvelope,
            .malformedAction,
        ])

        let terminalAction = MobileMirrorAction(
            kind: .terminalControl,
            sessionID: UUID().uuidString,
            surfaceID: UUID().uuidString,
            controlType: "viewport-scroll",
            scrollDelta: 3
        )
        let terminalBody = try MobileMirrorEncryptedActionTestSupport.requestBody(
            action: terminalAction,
            key: sessionKeys.terminalInputEncryptionKey,
            sequence: 2
        )
        let terminalResult = await router.route(
            request: request(
                method: "POST",
                path: "/mobile/api/action",
                headers: MobileMirrorEncryptedActionTestSupport.signedHeaders(
                    body: terminalBody,
                    actionToken: sessionKeys.actionToken,
                    cookie: cookie,
                    origin: "https://127.0.0.1:43120"
                ),
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
        #expect(MobileMirrorStaticAssets.allowedPaths.contains("/mobile_ui.js"))
        #expect(Set(MobileMirrorStaticAssets.orderedPaths).count
            == MobileMirrorStaticAssets.orderedPaths.count)
        for path in MobileMirrorStaticAssets.orderedPaths {
            guard case .proxy(let target) = await router.route(
                request: request(path: path, headers: authenticatedHeaders),
                identity: identity
            ) else {
                Issue.record("Expected authenticated proxy for \(path)")
                continue
            }
            #expect(target.rewrittenPath == path)
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
                    "origin": "https://127.0.0.1:43120",
                    "upgrade": "websocket",
                ]
            ),
            identity: identity
        ) else {
            Issue.record("Expected authenticated terminal proxy")
            return
        }

        for index in 0..<32 {
            let sustainedBody = try MobileMirrorEncryptedActionTestSupport.requestBody(
                action: terminalAction,
                key: sessionKeys.terminalInputEncryptionKey,
                sequence: UInt64(index + 3)
            )
            let sustainedResult = await router.route(
                request: request(
                    method: "POST",
                    path: "/mobile/api/action",
                    headers: MobileMirrorEncryptedActionTestSupport.signedHeaders(
                        body: sustainedBody,
                        actionToken: sessionKeys.actionToken,
                        cookie: cookie,
                        origin: "https://127.0.0.1:43120"
                    ),
                    body: sustainedBody
                ),
                identity: identity
            )
            #expect(try response(from: sustainedResult).status == 200)
        }
        #expect(await actionRecorder.values.count == 34)
    }

    @Test("Arabic pairing page and legacy bootstrap preserve localization contracts")
    func arabicPairingPageAndLegacyBootstrap() async throws {
        let authority = MobileMirrorPairingAuthority()
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .sshTunnel,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            localization: try webLocalization(.arabic),
            snapshotProvider: { _ in .empty },
            actionHandler: { _, _, _, _ in .empty },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(43120)
        let offer = authority.makeOffer()
        let result = await router.route(
            request: request(path: "/pair", query: ["token": offer.token]),
            identity: MobileMirrorClientIdentity(remoteAddress: "10.0.0.4", userAgent: "Phone")
        )
        let html = try #require(String(data: response(from: result).body, encoding: .utf8))

        #expect(html.contains("<html lang=\"ar\" dir=\"rtl\">"))
        #expect(html.contains("تأكيد هذا الهاتف"))
        #expect(html.contains("مطلوب تأكيد من سطح المكتب"))
        #expect(html.contains("تم رفض الإقران"))

        let legacy = try JSONDecoder().decode(
            MobileMirrorBootstrap.self,
            from: Data("""
            {"snapshot":{},"actionSecret":"legacy-secret"}
            """.utf8)
        )
        #expect(legacy.locale == "en")
        #expect(legacy.direction == "ltr")
        #expect(legacy.catalog.isEmpty)
        #expect(legacy.channelID.isEmpty)
    }

    @Test("SSH tunnel session cookie remains usable over loopback HTTP")
    func SSHTunnelCookieOmitsSecureAttribute() async throws {
        let authority = MobileMirrorPairingAuthority()
        let identity = MobileMirrorClientIdentity(
            remoteAddress: "SSH workstation",
            userAgent: "Mobile Browser"
        )
        let offer = authority.makeOffer()
        let pending = try authority.consumeOffer(token: offer.token, identity: identity)
        _ = try authority.decide(pendingID: pending.id, approve: true)
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .sshTunnel,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            snapshotProvider: { _ in .empty },
            actionHandler: { _, _, _, _ in .empty },
            pendingPairingHandler: { _ in }
        )
        router.updatePublicPort(43120)

        let result = await router.route(
            request: request(
                path: "/mobile/api/pair-status",
                query: ["id": pending.id.uuidString]
            ),
            identity: identity
        )
        let setCookie = try #require(try response(from: result).headers["Set-Cookie"])
        #expect(setCookie.contains("HttpOnly"))
        #expect(!setCookie.contains("; Secure"))
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
            transport: .sshTunnel,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            localization: try webLocalization(.spanish),
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

        let failure = try response(from: result)
        #expect(failure.status == 503)
        let payload = try #require(
            JSONSerialization.jsonObject(with: failure.body) as? [String: Any]
        )
        #expect(payload["error"] as? String ==
            "El registro de auditoría local no está disponible.")
        #expect(await actionRecorder.values.isEmpty)
    }

    @Test("unpaired and internal test assets are not proxied")
    func unauthorizedAndInternalRoutesAreRejected() async throws {
        let authority = MobileMirrorPairingAuthority()
        let router = MobileMirrorRequestRouter(
            publicAddress: "127.0.0.1",
            transport: .sshTunnel,
            authority: authority,
            routeRegistry: MobileMirrorRouteRegistry(),
            staticAssetEndpoint: MobileMirrorStaticAssetEndpoint(
                port: 45678,
                bearerToken: "compiled-assets"
            ),
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
        let compiledAsset = await router.route(
            request: request(
                path: "/mobile_ui.js",
                host: "127.0.0.1:4444",
                headers: ["cookie": "cocxy_mobile=\(cookie)"]
            ),
            identity: identity
        )
        guard case .proxy(let target) = compiledAsset else {
            Issue.record("Expected the app-scoped compiled asset route")
            return
        }
        #expect(target.port == 45678)
        #expect(target.bearerToken == "compiled-assets")
        #expect(target.rewrittenPath == "/mobile_ui.js")

        let assetWebSocket = await router.route(
            request: request(
                path: "/mobile_ui.js",
                host: "127.0.0.1:4444",
                headers: [
                    "cookie": "cocxy_mobile=\(cookie)",
                    "origin": "http://127.0.0.1:4444",
                    "upgrade": "websocket",
                ]
            ),
            identity: identity
        )
        #expect(try response(from: assetWebSocket).status == 404)

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

    private func webLocalization(_ language: AppLanguage) throws -> MobileMirrorWebLocalization {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundle = try #require(Bundle(
            url: root.appendingPathComponent("Resources/Localization", isDirectory: true)
        ))
        return MobileMirrorWebLocalization(localizer: AppLocalizer(
            languagePreference: language,
            bundle: bundle
        ))
    }
}

private enum MobileMirrorRouterTestError: Error {
    case expectedResponse
}
