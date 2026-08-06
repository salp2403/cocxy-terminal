// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Security
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror private relay", .serialized)
struct MobileMirrorLocalRelaySwiftTestingTests {
    @Test("private address policy accepts only RFC 1918 IPv4")
    func privateAddressPolicy() {
        for address in ["10.1.2.3", "172.16.0.1", "172.31.255.254", "192.168.1.5"] {
            #expect(MobileMirrorPrivateNetworkAddress.isPrivateIPv4(address))
        }
        for address in ["127.0.0.1", "169.254.1.1", "172.32.0.1", "8.8.8.8", "::1"] {
            #expect(!MobileMirrorPrivateNetworkAddress.isPrivateIPv4(address))
        }
    }

    @Test("peer addresses are formatted from exactly four network bytes")
    func peerAddressFormatting() {
        #expect(MobileMirrorLocalRelay.numericIPv4(bytes: Data([10, 0, 0, 3])) == "10.0.0.3")
        #expect(MobileMirrorLocalRelay.numericIPv4(bytes: Data([192, 168, 255, 1])) == "192.168.255.1")
        #expect(MobileMirrorLocalRelay.numericIPv4(bytes: Data([10, 0, 0])) == nil)
        #expect(MobileMirrorLocalRelay.numericIPv4(bytes: Data([10, 0, 0, 3, 4])) == nil)
    }

    @Test("authenticated relay preamble is fragmented safely and consumed once")
    func relayPreambleAuthentication() throws {
        let secret = "private-relay-secret"
        let request = Data("GET /health HTTP/1.1\r\nHost: local\r\n\r\n".utf8)
        let preamble = MobileMirrorRelayPreamble.encode(
            secret: secret,
            remoteAddress: "192.168.4.22"
        )
        var partial = Data(preamble.prefix(8))
        #expect(try MobileMirrorRelayPreamble.consumeIfComplete(
            from: &partial,
            expectedSecret: secret
        ) == nil)
        partial.append(preamble.dropFirst(8))
        partial.append(request)

        #expect(try MobileMirrorRelayPreamble.consumeIfComplete(
            from: &partial,
            expectedSecret: secret
        ) == "192.168.4.22")
        #expect(partial == request)

        var forged = preamble + request
        #expect(throws: MobileMirrorRelayPreambleError.invalidSecret) {
            try MobileMirrorRelayPreamble.consumeIfComplete(
                from: &forged,
                expectedSecret: "another-secret"
            )
        }
    }

    @Test("authenticated relay preamble enforces its full line bound")
    func relayPreambleLengthBound() {
        let terminator = Data("\r\n".utf8)
        var oversized = Data(repeating: UInt8(ascii: "x"), count: MobileMirrorRelayPreamble.maximumBytes - 1)
        oversized.append(terminator)

        #expect(throws: MobileMirrorRelayPreambleError.malformed) {
            try MobileMirrorRelayPreamble.consumeIfComplete(
                from: &oversized,
                expectedSecret: "unused"
            )
        }
    }

    @Test("ephemeral TLS identity is scoped to its private address and removed")
    func ephemeralTLSIdentityLifecycle() throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let verificationDate = Date(timeIntervalSince1970: 1_786_000_000)
        let tlsIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            validFor: 600,
            now: verificationDate,
            keychain: keychain.reference
        )
        let expectedFingerprint = testCertificateFingerprint(tlsIdentity.certificateDER)
        #expect(tlsIdentity.fingerprint == expectedFingerprint)

        let policy = SecPolicyCreateSSL(true, "127.0.0.1" as CFString)
        var trust: SecTrust?
        #expect(SecTrustCreateWithCertificates(
            tlsIdentity.certificate,
            policy,
            &trust
        ) == errSecSuccess)
        let resolvedTrust = try #require(trust)
        #expect(SecTrustSetAnchorCertificates(
            resolvedTrust,
            [tlsIdentity.certificate] as CFArray
        ) == errSecSuccess)
        #expect(SecTrustSetAnchorCertificatesOnly(resolvedTrust, true) == errSecSuccess)
        #expect(SecTrustSetVerifyDate(resolvedTrust, verificationDate as CFDate) == errSecSuccess)
        #expect(SecTrustEvaluateWithError(resolvedTrust, nil))

        tlsIdentity.removeFromKeychain()
        var storedCertificate: CFTypeRef?
        let lookupStatus = SecItemCopyMatching([
            kSecClass as String: kSecClassCertificate,
            kSecAttrPublicKeyHash as String: tlsIdentity.storageCertificatePublicKeyHash,
            kSecMatchSearchList as String: [keychain.reference],
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &storedCertificate)
        #expect(lookupStatus == errSecItemNotFound)
        var storedKey: CFTypeRef?
        let keyLookupStatus = SecItemCopyMatching([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tlsIdentity.storageKeyTag,
            kSecMatchSearchList as String: [keychain.reference],
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &storedKey)
        #expect(keyLookupStatus == errSecItemNotFound)
    }

    @Test("startup sweep removes stale relay identities and preserves unrelated keys")
    func staleTLSIdentitySweep() throws {
        let keychain = try TemporaryMobileMirrorKeychain()
        let staleOwner: pid_t = 91_001
        let activeOwner: pid_t = 91_002
        let staleIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: staleOwner
        )
        let activeIdentity = try MobileMirrorEphemeralTLSIdentity.generate(
            bindAddress: "127.0.0.1",
            keychain: keychain.reference,
            ownerProcessIdentifier: activeOwner
        )
        let unrelatedTag = Data("dev.cocxy.tests.unrelated.\(UUID().uuidString)".utf8)
        var keyError: Unmanaged<CFError>?
        let unrelatedKey = try #require(SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecUseKeychain as String: keychain.reference,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: unrelatedTag,
            ],
        ] as CFDictionary, &keyError))
        _ = unrelatedKey
        defer {
            SecItemDelete([
                kSecClass as String: kSecClassKey,
                kSecAttrApplicationTag as String: unrelatedTag,
                kSecMatchSearchList as String: [keychain.reference],
            ] as CFDictionary)
        }

        #expect(Self.keychainStatus(
            itemClass: kSecClassCertificate,
            attribute: kSecAttrPublicKeyHash,
            value: staleIdentity.storageCertificatePublicKeyHash,
            keychain: keychain.reference
        ) == errSecSuccess)
        #expect(Self.keychainStatus(
            itemClass: kSecClassKey,
            attribute: kSecAttrApplicationTag,
            value: staleIdentity.storageKeyTag,
            keychain: keychain.reference
        ) == errSecSuccess)

        let result = MobileMirrorEphemeralTLSIdentity.removeStaleKeychainItems(
            keychain: keychain.reference,
            processIsAlive: { $0 == activeOwner }
        )

        #expect(result.matchedIdentityCount == 1)
        #expect(Self.keychainStatus(
            itemClass: kSecClassCertificate,
            attribute: kSecAttrPublicKeyHash,
            value: staleIdentity.storageCertificatePublicKeyHash,
            keychain: keychain.reference
        ) == errSecItemNotFound)
        #expect(Self.keychainStatus(
            itemClass: kSecClassKey,
            attribute: kSecAttrApplicationTag,
            value: staleIdentity.storageKeyTag,
            keychain: keychain.reference
        ) == errSecItemNotFound)
        #expect(Self.keychainStatus(
            itemClass: kSecClassCertificate,
            attribute: kSecAttrPublicKeyHash,
            value: activeIdentity.storageCertificatePublicKeyHash,
            keychain: keychain.reference
        ) == errSecSuccess)
        #expect(Self.keychainStatus(
            itemClass: kSecClassKey,
            attribute: kSecAttrApplicationTag,
            value: activeIdentity.storageKeyTag,
            keychain: keychain.reference
        ) == errSecSuccess)
        #expect(Self.keychainStatus(
            itemClass: kSecClassKey,
            attribute: kSecAttrApplicationTag,
            value: unrelatedTag,
            keychain: keychain.reference
        ) == errSecSuccess)
    }

    @Test("relay startup errors follow the configured language")
    func relayErrorsAreLocalized() throws {
        let bundle = try #require(Bundle(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Localization", isDirectory: true)))
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(MobileMirrorLocalRelayError.invalidGatewayPort.localizedDescription(using: spanish) == "El puerto del gateway móvil local no es válido.")
        #expect(MobileMirrorLocalRelayError.alreadyStarting.localizedDescription(using: spanish) == "El relay móvil privado ya se está iniciando.")
        #expect(MobileMirrorLocalRelayError.tlsIdentityUnavailable.localizedDescription(using: spanish) == "No se pudo crear el cifrado para el relay móvil privado.")
        #expect(MobileMirrorLocalRelayError.listenerUnavailable.localizedDescription(using: spanish) == "No se pudo iniciar el relay móvil privado.")
    }

    @Test("local pairing URL carries a one-use application key")
    func localPairingURLContract() throws {
        let url = try #require(MobileMirrorPairingURL.local(
            address: "192.168.1.8",
            port: 4_242,
            token: "one-use-token",
            pairingSecret: "pairing-secret"
        ))

        #expect(url.absoluteString == "https://192.168.1.8:4242/pair?token=one-use-token#pairing-key=pairing-secret")
        #expect(MobileMirrorPairingURL.pairingSecret(from: url) == "pairing-secret")

        let tunneled = try #require(MobileMirrorPairingURL.sshTunnel(
            address: "127.0.0.1",
            port: 4_243,
            token: "tunnel-token",
            pairingSecret: "tunnel-secret"
        ))
        #expect(tunneled.absoluteString == "http://127.0.0.1:4243/pair?token=tunnel-token#pairing-key=tunnel-secret")
        #expect(MobileMirrorPairingURL.pairingSecret(from: tunneled) == "tunnel-secret")
    }

    @Test("private relay reaches the loopback gateway and preserves client identity")
    func localRelayEndToEnd() async throws {
        let relayedAddress = "192.168.42.23"
        let secret = "live-private-relay-secret"
        let gateway = MobileMirrorGateway(trustedRelaySecret: secret) { request, identity in
            #expect(request.path == "/health")
            #expect(identity.remoteAddress == relayedAddress)
            return .response(.json(["status": "ok"]))
        }
        let gatewayPort = try gateway.start()
        let relay = MobileMirrorLocalRelay(
            gatewayPort: gatewayPort,
            preambleSecret: secret,
            addressProvider: { MobileMirrorGateway.loopbackAddress },
            bindAddressPolicy: { $0 == MobileMirrorGateway.loopbackAddress },
            peerAddressNormalizer: { address in
                guard address == MobileMirrorGateway.loopbackAddress else { return nil }
                return relayedAddress
            }
        )
        let lease = try await relay.start()
        defer {
            relay.stop()
            gateway.stop()
        }

        let response = try await Self.request(
            address: lease.address,
            port: lease.port,
            path: "/health",
            certificateFingerprint: lease.certificateFingerprint
        )
        let text = String(decoding: response, as: UTF8.self)
        #expect(text == "{\"status\":\"ok\"}")

    }

    @Test("production relay binds its exact RFC 1918 interface")
    func productionRelayBindsPrivateInterface() async throws {
        guard let address = MobileMirrorPrivateNetworkAddress.current() else {
            withKnownIssue("No RFC 1918 interface is available on this test host") {
                Issue.record("Production relay binding requires a private network interface")
            }
            return
        }
        let relay = MobileMirrorLocalRelay(
            gatewayPort: 1,
            preambleSecret: "private-bind-test",
            addressProvider: { address }
        )
        let lease = try await relay.start()
        defer { relay.stop() }

        #expect(lease.address == address)
        #expect(lease.port > 0)
    }

    @Test("relay rejects a non-private peer before forwarding bytes")
    func relayRejectsNonPrivatePeer() async throws {
        let gatewayProbe = try LoopbackConnectionProbe()
        let relay = MobileMirrorLocalRelay(
            gatewayPort: gatewayProbe.port,
            preambleSecret: "non-private-peer-test",
            addressProvider: { MobileMirrorGateway.loopbackAddress },
            bindAddressPolicy: { $0 == MobileMirrorGateway.loopbackAddress }
        )
        let lease = try await relay.start()
        defer {
            relay.stop()
            gatewayProbe.stop()
        }

        let attempt = Task {
            try? await Self.request(
                address: lease.address,
                port: lease.port,
                path: "/health",
                certificateFingerprint: lease.certificateFingerprint
            )
        }
        let forwarded = await gatewayProbe.waitForConnection(timeout: 1)
        attempt.cancel()
        _ = await attempt.value
        #expect(!forwarded)
    }

    @Test("relay enforces per-peer slots and releases them when either side closes")
    func relayConnectionSlotsRecover() async throws {
        let secret = "relay-slot-test"
        let relayedAddress = "192.168.42.44"
        let limits = MobileMirrorConnectionLimits(
            maximumTotal: 2,
            maximumPerAddress: 1,
            maximumStartsPerWindow: 4,
            maximumFailuresPerWindow: 2,
            rateWindow: 10
        )
        let gateway = MobileMirrorGateway(
            trustedRelaySecret: secret,
            connectionLimits: limits
        ) { request, _ in
            request.path == "/events"
                ? .eventStream
                : .response(.json(["status": "ok"]))
        }
        let gatewayPort = try gateway.start()
        let relay = MobileMirrorLocalRelay(
            gatewayPort: gatewayPort,
            preambleSecret: secret,
            addressProvider: { MobileMirrorGateway.loopbackAddress },
            bindAddressPolicy: { $0 == MobileMirrorGateway.loopbackAddress },
            peerAddressNormalizer: { _ in relayedAddress },
            connectionLimits: limits
        )
        let lease = try await relay.start()
        defer {
            relay.stop()
            gateway.stop()
        }

        let held = try Self.connect(address: lease.address, port: lease.port)
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await Self.request(
                address: lease.address,
                port: lease.port,
                path: "/health",
                certificateFingerprint: lease.certificateFingerprint
            )
            Issue.record("A second connection from an exhausted peer reached the gateway")
        } catch {
            // The peer owns its only slot until the held connection closes.
        }
        Darwin.close(held)

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var recovered = false
        repeat {
            do {
                let response = try await Self.request(
                    address: lease.address,
                    port: lease.port,
                    path: "/health",
                    certificateFingerprint: lease.certificateFingerprint
                )
                recovered = String(decoding: response, as: UTF8.self)
                    .contains("\"status\":\"ok\"")
            } catch {
                recovered = false
            }
            if !recovered { try await Task.sleep(nanoseconds: 20_000_000) }
        } while !recovered && ContinuousClock.now < deadline
        #expect(recovered)
    }

    @Test("compiled mobile shell starts without a terminal surface")
    @MainActor
    func staticAssetsNeedNoTerminal() async throws {
        let server = MobileMirrorStaticAssetServer()
        let endpoint = try server.start()
        defer { server.stop() }
        var request = URLRequest(url: try #require(URL(
            string: "http://127.0.0.1:\(endpoint.port)/mobile_ui.js"
        )))
        request.setValue("Bearer \(endpoint.bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("renderMobileProjects"))
    }

    private static func request(
        address: String,
        port: UInt16,
        path: String,
        certificateFingerprint: String
    ) async throws -> Data {
        let delegate = MobileMirrorPinnedTLSDelegate(
            expectedFingerprint: certificateFingerprint
        )
        return try await request(
            address: address,
            port: port,
            path: path,
            delegate: delegate
        )
    }

    private static func keychainStatus(
        itemClass: CFString,
        attribute: CFString,
        value: Any,
        keychain: SecKeychain
    ) -> OSStatus {
        var item: CFTypeRef?
        return SecItemCopyMatching([
            kSecClass as String: itemClass,
            attribute as String: value,
            kSecMatchSearchList as String: [keychain],
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &item)
    }

    private static func request(
        address: String,
        port: UInt16,
        path: String,
        delegate: MobileMirrorPinnedTLSDelegate
    ) async throws -> Data {
        let url = try #require(URL(string: "https://\(address):\(port)\(path)"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        return data
    }

    private static func connect(address: String, port: UInt16) throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = port.bigEndian
        guard inet_pton(AF_INET, address, &socketAddress.sin_addr) == 1 else {
            Darwin.close(descriptor)
            throw POSIXError(.EINVAL)
        }
        let connected = withUnsafePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw POSIXError(.init(rawValue: code) ?? .ECONNREFUSED)
        }
        return descriptor
    }

    private static func requestData(path: String, host: String = "local") -> Data {
        Data("GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\n\r\n".utf8)
    }

    private static func receiveHTTPHead(from descriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            if count < 0, errno == EINTR { continue }
            break
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func sendAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var sent = 0
            while sent < bytes.count {
                let result = Darwin.send(
                    descriptor,
                    base.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                sent += result
            }
            return true
        }
    }
}
