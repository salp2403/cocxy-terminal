// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorRequestRouter.swift - Authenticated gateway request routing.

import Foundation

final class MobileMirrorRequestRouter: @unchecked Sendable {
    typealias SnapshotProvider = @Sendable (String) async throws -> MobileMirrorSnapshot
    typealias ActionHandler = @Sendable (
        MobileMirrorAction,
        String,
        UUID,
        MobileMirrorClientIdentity
    ) async throws -> MobileMirrorSnapshot
    typealias PendingPairingHandler = @Sendable (MobileMirrorPendingPairing) async -> Void

    static let cookieName = "cocxy_mobile"

    let authority: MobileMirrorPairingAuthority
    let routeRegistry: MobileMirrorRouteRegistry

    private let publicAddress: String
    private let snapshotProvider: SnapshotProvider
    private let actionHandler: ActionHandler
    private let pendingPairingHandler: PendingPairingHandler
    private let monotonicNow: @Sendable () -> TimeInterval
    private let endpointLock = NSLock()
    private let requestRateLock = NSLock()
    private var gatewayPort: UInt16?
    private var requestRatePolicy: MobileMirrorRequestRatePolicy

    init(
        publicAddress: String,
        authority: MobileMirrorPairingAuthority,
        routeRegistry: MobileMirrorRouteRegistry,
        connectionLimits: MobileMirrorConnectionLimits = .default,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        snapshotProvider: @escaping SnapshotProvider,
        actionHandler: @escaping ActionHandler,
        pendingPairingHandler: @escaping PendingPairingHandler
    ) {
        self.publicAddress = publicAddress
        self.authority = authority
        self.routeRegistry = routeRegistry
        self.monotonicNow = monotonicNow
        self.snapshotProvider = snapshotProvider
        self.actionHandler = actionHandler
        self.pendingPairingHandler = pendingPairingHandler
        self.requestRatePolicy = MobileMirrorRequestRatePolicy(limits: connectionLimits)
    }

    func updatePublicPort(_ port: UInt16) {
        endpointLock.lock()
        gatewayPort = port
        endpointLock.unlock()
    }

    var baseURL: String? {
        endpointLock.lock()
        defer { endpointLock.unlock() }
        return gatewayPort.map { "http://\(publicAddress):\($0)" }
    }

    func route(
        request: MobileMirrorHTTPRequest,
        identity: MobileMirrorClientIdentity
    ) async -> MobileMirrorHTTPRouteResult {
        guard let baseURL, request.host == String(baseURL.dropFirst("http://".count)) else {
            return rejected(
                .error("Invalid local host.", status: 403),
                identity: identity
            )
        }

        if request.path == "/pair" {
            guard admitPreAuthentication(identity: identity) else { return rateLimited() }
            return await pair(request: request, identity: identity)
        }
        if request.path == "/mobile/api/pair-status" {
            guard admitPreAuthentication(identity: identity) else { return rateLimited() }
            return pairStatus(request: request, identity: identity)
        }

        guard let cookie = request.cookie(named: Self.cookieName) else {
            return rejected(
                .error("Pair this device from Cocxy Terminal.", status: 401),
                identity: identity
            )
        }
        guard authority.activePairing(cookie: cookie)?.identity.fingerprint == identity.fingerprint else {
            return rejected(
                .error(MobileMirrorError.sessionExpired.localizedDescription, status: 401),
                identity: identity
            )
        }

        switch request.path {
        case "/mobile/api/bootstrap":
            guard request.method == "GET" else { return methodNotAllowed() }
            do {
                let credentials = try authority.credentials(cookie: cookie)
                let snapshot = try await snapshotProvider(cookie)
                return .response(.json(MobileMirrorBootstrap(
                    snapshot: snapshot,
                    actionSecret: credentials.actionSecret
                )))
            } catch {
                return errorResponse(error)
            }
        case "/mobile/api/state":
            guard request.method == "GET" else { return methodNotAllowed() }
            do {
                return .response(.json(try await snapshotProvider(cookie)))
            } catch {
                return errorResponse(error)
            }
        case "/mobile/api/action":
            return await action(request: request, cookie: cookie, identity: identity)
        case "/mobile/api/events":
            guard request.method == "GET" else { return methodNotAllowed() }
            return .eventStream
        default:
            return proxy(
                request: request,
                cookie: cookie,
                baseURL: baseURL,
                identity: identity
            )
        }
    }

    private func pair(
        request: MobileMirrorHTTPRequest,
        identity: MobileMirrorClientIdentity
    ) async -> MobileMirrorHTTPRouteResult {
        guard request.method == "GET", let token = request.query["token"] else {
            return .response(.error("Invalid pairing request.", status: 400))
        }
        do {
            let pending = try authority.consumeOffer(token: token, identity: identity)
            await pendingPairingHandler(pending)
            return .response(pairingPage(pendingID: pending.id))
        } catch {
            return errorResponse(error, identity: identity, authenticationFailure: true)
        }
    }

    private func pairStatus(
        request: MobileMirrorHTTPRequest,
        identity: MobileMirrorClientIdentity
    ) -> MobileMirrorHTTPRouteResult {
        guard request.method == "GET",
              let rawID = request.query["id"],
              let pendingID = UUID(uuidString: rawID) else {
            return .response(.error("Invalid pairing request.", status: 400))
        }
        do {
            switch try authority.poll(pendingID: pendingID, identity: identity) {
            case .pending:
                return .response(.json(["status": "pending"], status: 202))
            case .denied:
                return .response(.json(["status": "denied"], status: 403))
            case .confirmed(let cookie):
                let maxAge = Int(MobileMirrorPairingAuthority.sessionTTL)
                return .response(.json(
                    ["status": "confirmed", "redirect": "/"],
                    headers: [
                        "Set-Cookie": "\(Self.cookieName)=\(cookie); Path=/; HttpOnly; SameSite=Strict; Max-Age=\(maxAge)",
                    ]
                ))
            }
        } catch {
            return errorResponse(error, identity: identity, authenticationFailure: true)
        }
    }

    private func action(
        request: MobileMirrorHTTPRequest,
        cookie: String,
        identity: MobileMirrorClientIdentity
    ) async -> MobileMirrorHTTPRouteResult {
        guard request.method == "POST",
              request.origin == baseURL,
              request.headers["content-type"]?
                .lowercased()
                .hasPrefix("application/json") == true,
              let timestamp = request.headers["x-cocxy-timestamp"],
              let nonce = request.headers["x-cocxy-nonce"],
              let signature = request.headers["x-cocxy-signature"] else {
            return rejected(
                .error("Invalid signed action.", status: 403),
                identity: identity
            )
        }
        do {
            let channelID = try authority.validateAction(
                cookie: cookie,
                timestamp: timestamp,
                nonce: nonce,
                signature: signature,
                body: request.body
            )
            let action = try JSONDecoder().decode(MobileMirrorAction.self, from: request.body)
            try action.validate()
            let snapshot = try await actionHandler(action, cookie, channelID, identity)
            let responseSnapshot = action.kind == .terminalControl ? nil : snapshot
            return .response(.json(MobileMirrorActionResponse.success(
                snapshot: responseSnapshot
            )))
        } catch {
            return errorResponse(error, identity: identity, authenticationFailure: true)
        }
    }

    private func proxy(
        request: MobileMirrorHTTPRequest,
        cookie: String,
        baseURL: String,
        identity: MobileMirrorClientIdentity
    ) -> MobileMirrorHTTPRouteResult {
        guard request.method == "GET" else { return methodNotAllowed() }
        let isWebSocket = request.headers["upgrade"]?.lowercased() == "websocket"
        if isWebSocket, request.origin != baseURL {
            return rejected(
                .error("Invalid terminal origin.", status: 403),
                identity: identity
            )
        }

        if let surfaceID = Self.terminalSessionID(from: request.path) {
            guard UUID(uuidString: surfaceID) != nil,
                  let route = routeRegistry.route(forSurfaceID: surfaceID) else {
                return .response(.error("Terminal stream is unavailable.", status: 404))
            }
            return .proxy(MobileMirrorProxyTarget(
                port: route.port,
                bearerToken: route.bearerToken,
                rewrittenPath: "/ws"
            ))
        }

        let allowedStaticPaths = Set([
            "/", "/index.html", "/terminal.js", "/mobile.js", "/mobile_crypto.js",
            "/protocol.js",
            "/decoder.js", "/input.js", "/atlas.js", "/renderer.js", "/shaders.js",
            "/style.css",
        ])
        guard request.path == "/ws" || allowedStaticPaths.contains(request.path) else {
            return .response(.error("Not found.", status: 404))
        }
        let selectedSurfaceID = authority.selectedTerminal(cookie: cookie)?.surfaceID
        let route = selectedSurfaceID.flatMap(routeRegistry.route(forSurfaceID:))
            ?? routeRegistry.defaultRoute()
        guard let route else {
            return .response(.error("No local terminal stream is available.", status: 503))
        }
        let rewrittenPath = request.path == "/ws" ? "/ws" : request.target
        return .proxy(MobileMirrorProxyTarget(
            port: route.port,
            bearerToken: route.bearerToken,
            rewrittenPath: rewrittenPath
        ))
    }

    private func pairingPage(pendingID: UUID) -> MobileMirrorHTTPResponse {
        let nonce = MobileMirrorPairingAuthority.base64URL(RelayToken.generate().secret)
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
          <meta name="color-scheme" content="light dark">
          <title>Cocxy Terminal</title>
          <style nonce="\(nonce)">
            :root{font-family:-apple-system,BlinkMacSystemFont,sans-serif;color-scheme:light dark}
            body{margin:0;min-height:100dvh;display:grid;place-items:center;background:#101217;color:#f5f7fa}
            main{width:min(28rem,calc(100% - 2rem));text-align:center}svg{width:3rem;height:3rem;color:#50d890}
            h1{font-size:1.35rem;letter-spacing:0;margin:1rem 0 .5rem}p{color:#aab1bc;line-height:1.5}
            .pulse{width:.55rem;height:.55rem;border-radius:50%;background:#50d890;display:inline-block;margin-right:.5rem;animation:p 1.4s infinite}
            @keyframes p{50%{opacity:.25}}@media(prefers-color-scheme:light){body{background:#f5f6f8;color:#17191d}p{color:#59606b}}
          </style>
        </head>
        <body><main>
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="4" y="2" width="16" height="20" rx="3"/><path d="M9 18h6"/></svg>
          <h1><span class="pulse"></span>Confirm on your Mac</h1>
          <p id="status" role="status">Waiting for approval</p>
        </main><script nonce="\(nonce)">
          const status=document.getElementById('status');
          const poll=async()=>{try{const r=await fetch('/mobile/api/pair-status?id=\(pendingID.uuidString)',{cache:'no-store'});const v=await r.json();if(v.status==='confirmed'){location.replace(v.redirect||'/');return}if(v.status==='denied'){status.textContent='Pairing denied';return}}catch{}setTimeout(poll,900)};poll();
        </script></body></html>
        """
        return MobileMirrorHTTPResponse(
            status: 200,
            headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Security-Policy": "default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'nonce-\(nonce)'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'",
            ],
            body: Data(html.utf8)
        )
    }

    private func methodNotAllowed() -> MobileMirrorHTTPRouteResult {
        .response(.error("Method not allowed.", status: 400))
    }

    private func errorResponse(
        _ error: Error,
        identity: MobileMirrorClientIdentity? = nil,
        authenticationFailure: Bool = false
    ) -> MobileMirrorHTTPRouteResult {
        let status: Int
        switch error {
        case MobileMirrorError.invalidPairingToken,
             MobileMirrorError.invalidSignature,
             MobileMirrorError.replayDetected:
            status = 403
        case MobileMirrorError.pairingExpired,
             MobileMirrorError.sessionExpired:
            status = 401
        case MobileMirrorError.invalidAction,
             MobileMirrorError.invalidProjectName:
            status = 400
        case MobileMirrorError.projectAlreadyExists:
            status = 409
        case MobileMirrorError.authorizationDenied:
            status = 403
        default:
            status = 503
        }
        let response = MobileMirrorHTTPResponse.error(error.localizedDescription, status: status)
        if authenticationFailure, let identity {
            return rejected(response, identity: identity)
        }
        return .response(response)
    }

    private func admitPreAuthentication(identity: MobileMirrorClientIdentity) -> Bool {
        requestRateLock.lock()
        defer { requestRateLock.unlock() }
        return requestRatePolicy.admitPreAuthentication(
            address: identity.remoteAddress,
            now: monotonicNow()
        )
    }

    private func rejected(
        _ response: MobileMirrorHTTPResponse,
        identity: MobileMirrorClientIdentity
    ) -> MobileMirrorHTTPRouteResult {
        requestRateLock.lock()
        let allowed = requestRatePolicy.recordAuthenticationFailure(
            address: identity.remoteAddress,
            now: monotonicNow()
        )
        requestRateLock.unlock()
        return allowed ? .response(response) : rateLimited()
    }

    private func rateLimited() -> MobileMirrorHTTPRouteResult {
        .response(.error("Too many local requests.", status: 429))
    }

    private static func terminalSessionID(from path: String) -> String? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 3,
              components[0] == "terminal",
              components[2] == "ws" else {
            return nil
        }
        return String(components[1])
    }
}
