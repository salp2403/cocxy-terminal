// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror gateway")
struct MobileMirrorGatewaySwiftTestingTests: MobileMirrorRouterTestSupport {
    @Test("one stalled event client cannot delay another client")
    func eventClientsAreIsolated() {
        let slowStarted = DispatchSemaphore(value: 0)
        let releaseSlow = DispatchSemaphore(value: 0)
        let fastReceived = DispatchSemaphore(value: 0)
        let hub = MobileMirrorEventHub { _, descriptor in
            if descriptor == 41 {
                slowStarted.signal()
                return releaseSlow.wait(timeout: .now() + 2) == .success
            }
            fastReceived.signal()
            return true
        }
        defer {
            releaseSlow.signal()
            hub.stop()
        }

        hub.add(descriptor: 41, close: {})
        #expect(slowStarted.wait(timeout: .now() + 1) == .success)
        hub.add(descriptor: 42, close: {})

        #expect(fastReceived.wait(timeout: .now() + 1) == .success)
    }

    @Test("event stream replays bounded notifications after the last received ID")
    func eventStreamReplaysNotifications() throws {
        let capture = MobileMirrorEventCapture()
        let hub = MobileMirrorEventHub { data, descriptor in
            capture.append(data, descriptor: descriptor)
            return true
        }
        defer { hub.stop() }

        hub.add(descriptor: 51, close: {})
        try capture.wait(for: 1, descriptor: 51)
        hub.publish(event: "notification", data: #"{"kind":"agent-finished"}"#)
        try capture.wait(for: 2, descriptor: 51)
        let notification = try #require(capture.payloads(for: 51).last)
        let notificationID = try #require(Self.eventID(in: notification))

        hub.add(descriptor: 52, afterEventID: 0, close: {})
        try capture.wait(for: 2, descriptor: 52)
        let replayed = capture.payloads(for: 52)
        #expect(replayed[0] == notification)
        #expect(Self.eventName(in: replayed[0]) == "notification")
        #expect(Self.eventName(in: replayed[1]) == "state")

        hub.add(descriptor: 53, afterEventID: notificationID, close: {})
        try capture.wait(for: 1, descriptor: 53)
        #expect(capture.payloads(for: 53).count == 1)
        #expect(Self.eventName(in: capture.payloads(for: 53)[0]) == "state")
    }

    @Test("revocation delivery is attempted before event clients stop")
    func revocationDeliveryDrains() throws {
        let capture = MobileMirrorEventCapture()
        let hub = MobileMirrorEventHub { data, descriptor in
            capture.append(data, descriptor: descriptor)
            return true
        }
        hub.add(descriptor: 61, close: {})
        try capture.wait(for: 1, descriptor: 61)

        #expect(hub.publishAndWait(event: "revoked", data: "{}"))
        hub.stop()

        let payloads = capture.payloads(for: 61)
        try #require(payloads.count == 2)
        #expect(Self.eventName(in: payloads[1]) == "revoked")
    }

    private static func eventID(in data: Data) -> UInt64? {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("id: ") })
            .flatMap { UInt64($0.dropFirst(4)) }
    }

    private static func eventName(in data: Data) -> String? {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("event: ") })
            .map { String($0.dropFirst(7)) }
    }

    @Test("listener serves only through its exact requested address")
    func listenerServesExactAddress() async throws {
        let gateway = MobileMirrorGateway(
            requestedPort: 0
        ) { request, identity in
            #expect(request.path == "/health")
            #expect(identity.remoteAddress == "127.0.0.1")
            return .response(.json(["status": "ok"]))
        }
        let port = try gateway.start()
        defer { gateway.stop() }
        #expect(gateway.bindAddress == "127.0.0.1")

        let (data, response) = try await URLSession.shared.data(
            from: try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("\"status\":\"ok\""))
    }

    @Test("route timeout closes the request and releases its connection slot")
    func routeTimeoutReleasesConnection() async throws {
        let gateway = MobileMirrorGateway(
            requestTimeout: 0.1,
            connectionLimits: MobileMirrorConnectionLimits(
                maximumTotal: 1,
                maximumPerAddress: 1,
                maximumStartsPerWindow: 4,
                maximumFailuresPerWindow: 2,
                rateWindow: 10
            )
        ) { request, _ in
            if request.path == "/stalled" {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return .response(.error("Local request timed out.", status: 504))
                }
            }
            return .response(.json(["status": "ok"]))
        }
        let port = try gateway.start()
        defer { gateway.stop() }

        let (timeoutData, timeoutResponse) = try await URLSession.shared.data(
            from: try #require(URL(string: "http://127.0.0.1:\(port)/stalled"))
        )
        #expect((timeoutResponse as? HTTPURLResponse)?.statusCode == 504)
        #expect(String(decoding: timeoutData, as: UTF8.self).contains("timed out"))

        let (healthData, healthResponse) = try await URLSession.shared.data(
            from: try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        )
        #expect((healthResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: healthData, as: UTF8.self).contains("\"status\":\"ok\""))
    }

    @Test("timeout never responds before a non-cooperative mutation finishes")
    func timeoutWaitsForNonCooperativeMutation() async throws {
        let stalled = MobileMirrorStalledRoute()
        let mutations = MobileMirrorMutationRecorder()
        let gateway = MobileMirrorGateway(requestTimeout: 0.05) { request, _ in
            if request.path == "/commit" {
                await stalled.wait()
                mutations.record()
            }
            return .response(.json(["status": "ok"]))
        }
        let port = try gateway.start()
        defer {
            stalled.release()
            gateway.stop()
        }
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/commit"))
        let request = Task { try await URLSession.shared.data(from: url) }
        #expect(stalled.waitUntilEntered())

        try await Task.sleep(for: .milliseconds(120))
        #expect(mutations.count == 0)
        stalled.release()

        let (data, response) = try await request.value
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("\"status\":\"ok\""))
        #expect(mutations.count == 1)
    }

    @Test("stop retains an admitted request until its route acknowledges cancellation")
    func stopRetainsGatewayUntilRequestClosure() async throws {
        let stalled = MobileMirrorStalledRoute()
        defer { stalled.release() }
        var gateway: MobileMirrorGateway? = MobileMirrorGateway(
            requestTimeout: 0.25
        ) { _, _ in
            await stalled.wait()
            return .response(.json(["status": "ok"]))
        }
        weak let retainedGateway = gateway
        let port = try #require(try gateway?.start())
        let stalledURL = try #require(URL(
            string: "http://127.0.0.1:\(port)/stalled"
        ))
        let request = Task {
            try? await URLSession.shared.data(from: stalledURL)
        }
        #expect(stalled.waitUntilEntered())

        gateway?.stop()
        gateway = nil
        try await Task.sleep(for: .milliseconds(20))
        #expect(retainedGateway != nil)
        stalled.release()

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while retainedGateway != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(retainedGateway == nil)
        _ = await request.value
    }

    @Test("proxy strips mobile credentials and injects loopback bearer")
    func proxyRewritesSecurityHeaders() async throws {
        let upstream = try MobileMirrorCaptureServer()
        defer { upstream.stop() }
        let encryptionKey = Data((0..<32).map(UInt8.init))
        let gateway = MobileMirrorGateway(
            requestedPort: 0
        ) { _, _ in
            .proxy(MobileMirrorProxyTarget(
                port: upstream.port,
                bearerToken: "engine-secret",
                rewrittenPath: "/ws",
                terminalEncryptionKey: encryptionKey
            ))
        }
        let port = try gateway.start()
        defer { gateway.stop() }

        var request = URLRequest(
            url: try #require(URL(string: "http://127.0.0.1:\(port)/terminal/session/ws"))
        )
        request.setValue("mobile-secret", forHTTPHeaderField: "Cookie")
        request.setValue("signed-action", forHTTPHeaderField: "X-Cocxy-Signature")
        request.setValue("attacker-key", forHTTPHeaderField: "X-Cocxy-Terminal-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "pong")

        let received = try upstream.waitForRequest()
        #expect(received.hasPrefix("GET /ws HTTP/1.1\r\n"))
        #expect(received.contains("Authorization: Bearer engine-secret\r\n"))
        #expect(received.contains("Origin: http://127.0.0.1:\(upstream.port)\r\n"))
        #expect(received.contains(
            "X-Cocxy-Terminal-Key: \(MobileMirrorPairingAuthority.base64URL(encryptionKey))\r\n"
        ))
        #expect(received.localizedCaseInsensitiveContains("mobile-secret") == false)
        #expect(received.localizedCaseInsensitiveContains("signed-action") == false)
        #expect(received.localizedCaseInsensitiveContains("attacker-key") == false)
    }

    @Test("forwarded peers receive independent gateway connection budgets")
    func forwardedPeerAdmissionUsesPreambleAddress() throws {
        let secret = "forwarded-peer-admission"
        let gateway = MobileMirrorGateway(
            trustedRelaySecret: secret,
            connectionLimits: MobileMirrorConnectionLimits(
                maximumTotal: 3,
                maximumPerAddress: 1,
                maximumStartsPerWindow: 4,
                maximumFailuresPerWindow: 2,
                rateWindow: 10
            )
        ) { _, _ in .eventStream }
        let port = try gateway.start()
        defer { gateway.stop() }

        let first = try Self.openRelayedEventStream(
            port: port,
            secret: secret,
            remoteAddress: "192.168.10.20"
        )
        defer { Darwin.close(first) }
        let second = try Self.openRelayedEventStream(
            port: port,
            secret: secret,
            remoteAddress: "192.168.10.21"
        )
        defer { Darwin.close(second) }

        let duplicate = try Self.connect(port: port)
        defer { Darwin.close(duplicate) }
        let duplicateRequest = MobileMirrorRelayPreamble.encode(
            secret: secret,
            remoteAddress: "192.168.10.20"
        ) + Data("GET /events HTTP/1.1\r\nHost: local\r\n\r\n".utf8)
        #expect(MobileMirrorGateway.sendAll(duplicateRequest, to: duplicate))
        #expect(Self.receiveHTTPHead(from: duplicate).hasPrefix("HTTP/1.1 429"))
    }

    @Test("gateway admission refusals reach the phone coded and in its language")
    func admissionRefusalIsLocalized() throws {
        let secret = "localized-admission"
        let spanish = try webLocalization(.spanish)
        let gateway = MobileMirrorGateway(
            trustedRelaySecret: secret,
            connectionLimits: MobileMirrorConnectionLimits(
                maximumTotal: 3,
                maximumPerAddress: 1,
                maximumStartsPerWindow: 4,
                maximumFailuresPerWindow: 2,
                rateWindow: 10
            ),
            localization: { spanish }
        ) { _, _ in .eventStream }
        let port = try gateway.start()
        defer { gateway.stop() }
        let first = try Self.openRelayedEventStream(
            port: port,
            secret: secret,
            remoteAddress: "192.168.10.30"
        )
        defer { Darwin.close(first) }

        let duplicate = try Self.connect(port: port)
        defer { Darwin.close(duplicate) }
        let duplicateRequest = MobileMirrorRelayPreamble.encode(
            secret: secret,
            remoteAddress: "192.168.10.30"
        ) + Data("GET /events HTTP/1.1\r\nHost: local\r\n\r\n".utf8)
        #expect(MobileMirrorGateway.sendAll(duplicateRequest, to: duplicate))
        let reply = Self.receiveUntilClosed(from: duplicate)
        #expect(reply.hasPrefix("HTTP/1.1 429"))
        let body = try #require(reply.range(of: "\r\n\r\n").map { reply[$0.upperBound...] })
        let payload = try JSONDecoder().decode(
            MobileMirrorActionResponse.self,
            from: Data(body.utf8)
        )
        #expect(payload.code == "rate-limited")
        #expect(payload.error == "Demasiadas solicitudes. Espera un momento y vuelve a intentarlo.")
    }

    private static func receiveUntilClosed(from descriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 { data.append(buffer, count: count); continue }
            if count < 0, errno == EINTR { continue }
            break
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func openRelayedEventStream(
        port: UInt16,
        secret: String,
        remoteAddress: String
    ) throws -> Int32 {
        let descriptor = try connect(port: port)
        let request = MobileMirrorRelayPreamble.encode(
            secret: secret,
            remoteAddress: remoteAddress
        ) + Data("GET /events HTTP/1.1\r\nHost: local\r\n\r\n".utf8)
        guard MobileMirrorGateway.sendAll(request, to: descriptor),
              receiveHTTPHead(from: descriptor).hasPrefix("HTTP/1.1 200 OK\r\n") else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        return descriptor
    }

    private static func connect(port: UInt16) throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, MobileMirrorGateway.loopbackAddress, &address.sin_addr)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw CocoaError(.fileReadUnknown)
        }
        return descriptor
    }

    private static func receiveHTTPHead(from descriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 { data.append(buffer, count: count); continue }
            if count < 0, errno == EINTR { continue }
            break
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class MobileMirrorStalledRoute: @unchecked Sendable {
    private let lock = NSLock()
    private let entered = DispatchSemaphore(value: 0)
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var wasReleased = false

    func wait() async {
        entered.signal()
        await withCheckedContinuation { continuation in
            lock.lock()
            if wasReleased {
                lock.unlock()
                continuation.resume()
                return
            }
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func waitUntilEntered() -> Bool {
        entered.wait(timeout: .now() + 2) == .success
    }

    func release() {
        lock.lock()
        wasReleased = true
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

private final class MobileMirrorMutationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func record() {
        lock.lock()
        value += 1
        lock.unlock()
    }
}

private final class MobileMirrorEventCapture: @unchecked Sendable {
    private let condition = NSCondition()
    private var values: [Int32: [Data]] = [:]

    func append(_ data: Data, descriptor: Int32) {
        condition.lock()
        values[descriptor, default: []].append(data)
        condition.broadcast()
        condition.unlock()
    }

    func payloads(for descriptor: Int32) -> [Data] {
        condition.lock()
        defer { condition.unlock() }
        return values[descriptor] ?? []
    }

    func wait(for count: Int, descriptor: Int32) throws {
        let deadline = Date().addingTimeInterval(2)
        condition.lock()
        defer { condition.unlock() }
        while values[descriptor, default: []].count < count {
            guard condition.wait(until: deadline) else {
                throw CocoaError(.fileReadUnknown)
            }
        }
    }
}

private final class MobileMirrorCaptureServer: @unchecked Sendable {
    let port: UInt16

    private let descriptor: Int32
    private let queue = DispatchQueue(label: "dev.cocxy.mobile.capture")
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var requestText: String?

    init() throws {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0, Darwin.listen(descriptor, 1) == 0 else {
            Darwin.close(descriptor)
            throw CocoaError(.fileWriteUnknown)
        }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &bound, { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }) == 0 else {
            Darwin.close(descriptor)
            throw CocoaError(.fileWriteUnknown)
        }
        self.descriptor = descriptor
        port = UInt16(bigEndian: bound.sin_port)
        queue.async { [weak self] in self?.captureOneRequest() }
    }

    func waitForRequest() throws -> String {
        guard semaphore.wait(timeout: .now() + 3) == .success else {
            throw CocoaError(.fileReadUnknown)
        }
        lock.lock()
        defer { lock.unlock() }
        return requestText ?? ""
    }

    func stop() {
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func captureOneRequest() {
        let client = Darwin.accept(descriptor, nil, nil)
        guard client >= 0 else { return }
        defer { Darwin.close(client) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while data.range(of: Data("\r\n\r\n".utf8)) == nil {
            let count = Darwin.recv(client, &buffer, buffer.count, 0)
            guard count > 0 else { return }
            data.append(buffer, count: count)
        }
        lock.lock()
        requestText = String(decoding: data, as: UTF8.self)
        lock.unlock()
        semaphore.signal()
        _ = MobileMirrorGateway.sendAll(
            Data("HTTP/1.1 200 OK\r\nContent-Length: 4\r\nConnection: close\r\n\r\npong".utf8),
            to: client
        )
    }
}
