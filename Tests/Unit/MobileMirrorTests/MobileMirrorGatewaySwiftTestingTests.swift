// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror gateway")
struct MobileMirrorGatewaySwiftTestingTests {
    @Test("listener serves only through its exact requested address")
    func listenerServesExactAddress() async throws {
        let gateway = MobileMirrorGateway(
            bindAddress: "127.0.0.1",
            allowsLoopbackForTesting: true
        ) { request, identity in
            #expect(request.path == "/health")
            #expect(identity.remoteAddress == "127.0.0.1")
            return .response(.json(["status": "ok"]))
        }
        let port = try gateway.start()
        defer { gateway.stop() }

        let (data, response) = try await URLSession.shared.data(
            from: try #require(URL(string: "http://127.0.0.1:\(port)/health"))
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self).contains("\"status\":\"ok\""))
    }

    @Test("proxy strips mobile credentials and injects loopback bearer")
    func proxyRewritesSecurityHeaders() async throws {
        let upstream = try MobileMirrorCaptureServer()
        defer { upstream.stop() }
        let gateway = MobileMirrorGateway(
            bindAddress: "127.0.0.1",
            allowsLoopbackForTesting: true
        ) { _, _ in
            .proxy(MobileMirrorProxyTarget(
                port: upstream.port,
                bearerToken: "engine-secret",
                rewrittenPath: "/ws"
            ))
        }
        let port = try gateway.start()
        defer { gateway.stop() }

        var request = URLRequest(
            url: try #require(URL(string: "http://127.0.0.1:\(port)/terminal/session/ws"))
        )
        request.setValue("mobile-secret", forHTTPHeaderField: "Cookie")
        request.setValue("signed-action", forHTTPHeaderField: "X-Cocxy-Signature")
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "pong")

        let received = try upstream.waitForRequest()
        #expect(received.hasPrefix("GET /ws HTTP/1.1\r\n"))
        #expect(received.contains("Authorization: Bearer engine-secret\r\n"))
        #expect(received.contains("Origin: http://127.0.0.1:\(upstream.port)\r\n"))
        #expect(received.localizedCaseInsensitiveContains("mobile-secret") == false)
        #expect(received.localizedCaseInsensitiveContains("signed-action") == false)
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
