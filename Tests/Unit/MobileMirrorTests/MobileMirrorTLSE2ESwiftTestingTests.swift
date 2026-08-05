// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CryptoKit
import Foundation
import Security
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror TLS end to end")
struct MobileMirrorTLSE2ESwiftTestingTests {
    @Test("TLS relay carries a signed action and encrypted terminal stream")
    @MainActor
    func signedActionAndEncryptedStreamCrossRealRelay() async throws {
        let remoteAddress = "192.168.42.73"
        let userAgent = "Cocxy Mobile E2E"
        let relaySecret = "mobile-tls-e2e-relay"
        let identity = MobileMirrorClientIdentity(
            remoteAddress: remoteAddress,
            userAgent: userAgent
        )
        let authority = MobileMirrorPairingAuthority()
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

        let staticServer = MobileMirrorStaticAssetServer()
        let endpoint = try staticServer.start()
        defer { staticServer.stop() }
        let sessionID = UUID().uuidString
        let surfaceID = SurfaceID()
        let routes = MobileMirrorRouteRegistry()
        routes.replace(
            routes: [MobileMirrorTerminalRoute(
                sessionID: sessionID,
                surfaceID: surfaceID,
                port: endpoint.port,
                bearerToken: endpoint.bearerToken
            )],
            preferredSurfaceID: surfaceID.rawValue.uuidString
        )
        let recorder = MobileMirrorTLSActionRecorder()
        let router = MobileMirrorRequestRouter(
            publicAddress: MobileMirrorGateway.loopbackAddress,
            transport: .localTLS,
            authority: authority,
            routeRegistry: routes,
            staticAssetEndpoint: endpoint,
            snapshotProvider: { _ in .empty },
            actionHandler: { action, _, _, _ in
                await recorder.record(action)
                return .empty
            },
            pendingPairingHandler: { _ in }
        )
        let gateway = MobileMirrorGateway(trustedRelaySecret: relaySecret) { request, client in
            await router.route(request: request, identity: client)
        }
        let gatewayPort = try gateway.start()
        let relay = MobileMirrorLocalRelay(
            gatewayPort: gatewayPort,
            preambleSecret: relaySecret,
            addressProvider: { MobileMirrorGateway.loopbackAddress },
            bindAddressPolicy: { $0 == MobileMirrorGateway.loopbackAddress },
            peerAddressNormalizer: { _ in remoteAddress }
        )
        let lease = try await relay.start()
        defer {
            relay.stop()
            gateway.stop()
        }
        router.updatePublicPort(lease.port)

        let delegate = MobileMirrorE2ETLSTrustDelegate(
            expectedFingerprint: lease.certificateFingerprint
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let origin = "https://\(lease.address):\(lease.port)"

        let action = MobileMirrorAction(kind: .projectCreate, name: "Relay E2E")
        let body = try JSONEncoder().encode(action)
        let timestamp = String(UInt64(Date().timeIntervalSince1970))
        let nonce = UUID().uuidString
        let keys = MobileMirrorSessionKeys.derive(
            pairingSecret: try #require(
                MobileMirrorPairingAuthority.decodeBase64URL(offer.pairingSecret)
            ),
            channelID: offer.id
        )
        let signature = MobileMirrorPairingAuthority.base64URL(keys.actionToken.sign(
            MobileMirrorSessionKeys.canonicalActionPayload(
                method: "POST",
                path: "/mobile/api/action",
                body: body,
                timestamp: timestamp,
                nonce: nonce
            )
        ))
        var actionRequest = URLRequest(url: try #require(URL(
            string: "\(origin)/mobile/api/action"
        )))
        actionRequest.httpMethod = "POST"
        actionRequest.httpBody = body
        actionRequest.setValue(origin, forHTTPHeaderField: "Origin")
        actionRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        actionRequest.setValue(
            "\(MobileMirrorRequestRouter.cookieName)=\(cookie)",
            forHTTPHeaderField: "Cookie"
        )
        actionRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        actionRequest.setValue(timestamp, forHTTPHeaderField: "X-Cocxy-Timestamp")
        actionRequest.setValue(nonce, forHTTPHeaderField: "X-Cocxy-Nonce")
        actionRequest.setValue(signature, forHTTPHeaderField: "X-Cocxy-Signature")

        let (responseBody, response) = try await session.data(for: actionRequest)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(try JSONDecoder().decode(
            MobileMirrorActionResponse.self,
            from: responseBody
        ).ok)
        #expect(await recorder.actions == [action])

        var socketRequest = URLRequest(url: try #require(URL(
            string: "wss://\(lease.address):\(lease.port)/terminal/\(surfaceID.rawValue.uuidString)/ws"
        )))
        socketRequest.setValue(origin, forHTTPHeaderField: "Origin")
        socketRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        socketRequest.setValue(
            "\(MobileMirrorRequestRouter.cookieName)=\(cookie)",
            forHTTPHeaderField: "Cookie"
        )
        let socket = session.webSocketTask(with: socketRequest)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }

        let encrypted = try await Self.receiveData(from: socket)
        #expect(!String(decoding: encrypted, as: UTF8.self).contains("auth_ok"))
        let decrypted = try Self.decryptTerminalEnvelope(
            encrypted,
            key: keys.terminalEncryptionKey
        )
        #expect(decrypted.kind == 1)
        #expect(String(decoding: decrypted.payload, as: UTF8.self) == "{\"type\":\"auth_ok\"}")
    }

    private static func receiveData(
        from socket: URLSessionWebSocketTask
    ) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                switch try await socket.receive() {
                case .data(let data): data
                case .string: throw MobileMirrorTLSE2EError.unencryptedMessage
                @unknown default: throw MobileMirrorTLSE2EError.unencryptedMessage
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw MobileMirrorTLSE2EError.timeout
            }
            let data = try await group.next() ?? Data()
            group.cancelAll()
            return data
        }
    }

    private static func decryptTerminalEnvelope(
        _ envelope: Data,
        key: Data
    ) throws -> (kind: UInt8, payload: Data) {
        let headerLength = 18
        let tagLength = 16
        guard envelope.count >= headerLength + tagLength,
              envelope.prefix(4) == Data("CXYE".utf8),
              envelope[4] == 1,
              envelope[5] <= 1 else {
            throw MobileMirrorTLSE2EError.invalidEnvelope
        }
        let header = envelope.prefix(headerLength)
        let nonce = try AES.GCM.Nonce(data: header.suffix(12))
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: envelope[headerLength..<(envelope.count - tagLength)],
            tag: envelope.suffix(tagLength)
        )
        let plaintext = try AES.GCM.open(
            sealedBox,
            using: SymmetricKey(data: key),
            authenticating: header
        )
        return (envelope[5], plaintext)
    }
}

private actor MobileMirrorTLSActionRecorder {
    private(set) var actions: [MobileMirrorAction] = []

    func record(_ action: MobileMirrorAction) {
        actions.append(action)
    }
}

private enum MobileMirrorTLSE2EError: Error {
    case invalidEnvelope
    case timeout
    case unencryptedMessage
}

private final class MobileMirrorE2ETLSTrustDelegate: NSObject, URLSessionDelegate,
    @unchecked Sendable {
    private let expectedFingerprint: String

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod
                == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let certificate = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
              mobileMirrorE2EFingerprint(SecCertificateCopyData(certificate) as Data)
                == expectedFingerprint else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private func mobileMirrorE2EFingerprint(_ certificateData: Data) -> String {
    MobileMirrorPairingAuthority.base64URL(Data(SHA256.hash(data: certificateData)))
}
