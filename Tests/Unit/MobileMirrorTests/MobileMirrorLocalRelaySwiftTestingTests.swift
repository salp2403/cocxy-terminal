// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror private relay")
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
            peerAddressNormalizer: { _ in relayedAddress }
        )
        let lease = try relay.start()
        defer {
            relay.stop()
            gateway.stop()
        }

        let response = try await Task.detached {
            try Self.request(address: lease.address, port: lease.port, path: "/health")
        }.value
        let text = String(decoding: response, as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("\"status\":\"ok\""))
    }

    @Test("production relay binds its exact RFC 1918 interface")
    func productionRelayBindsPrivateInterface() throws {
        guard let address = MobileMirrorPrivateNetworkAddress.current() else { return }
        let relay = MobileMirrorLocalRelay(
            gatewayPort: 1,
            preambleSecret: "private-bind-test",
            addressProvider: { address }
        )
        let lease = try relay.start()
        defer { relay.stop() }

        #expect(lease.address == address)
        #expect(lease.port > 0)
    }

    @Test("relay rejects a non-private peer before forwarding bytes")
    func relayRejectsNonPrivatePeer() throws {
        let secret = "non-private-peer-test"
        let gateway = MobileMirrorGateway(trustedRelaySecret: secret) { _, _ in
            .response(.json(["status": "unexpected"]))
        }
        let gatewayPort = try gateway.start()
        let relay = MobileMirrorLocalRelay(
            gatewayPort: gatewayPort,
            preambleSecret: secret,
            addressProvider: { MobileMirrorGateway.loopbackAddress },
            bindAddressPolicy: { $0 == MobileMirrorGateway.loopbackAddress }
        )
        let lease = try relay.start()
        defer {
            relay.stop()
            gateway.stop()
        }

        let client = try Self.connect(address: lease.address, port: lease.port)
        defer { Darwin.close(client) }
        _ = Self.sendAll(Data("GET /health HTTP/1.1\r\nHost: local\r\n\r\n".utf8), to: client)

        #expect(Self.receiveHTTPHead(from: client).isEmpty)
    }

    @Test("relay enforces per-peer slots and releases them when either side closes")
    func relayConnectionSlotsRecover() throws {
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
        let lease = try relay.start()
        defer {
            relay.stop()
            gateway.stop()
        }

        let held = try Self.connect(address: lease.address, port: lease.port)
        #expect(Self.sendAll(Self.requestData(path: "/events"), to: held))
        #expect(Self.receiveHTTPHead(from: held).hasPrefix("HTTP/1.1 200 OK\r\n"))

        let rejected = try Self.connect(address: lease.address, port: lease.port)
        defer { Darwin.close(rejected) }
        _ = Self.sendAll(Self.requestData(path: "/health"), to: rejected)
        #expect(Self.receiveHTTPHead(from: rejected).isEmpty)
        Darwin.close(held)

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var recovered = false
        repeat {
            let candidate = try Self.connect(address: lease.address, port: lease.port)
            _ = Self.sendAll(Self.requestData(path: "/health"), to: candidate)
            recovered = Self.receiveHTTPHead(from: candidate).hasPrefix("HTTP/1.1 200 OK\r\n")
            Darwin.close(candidate)
            if !recovered { Thread.sleep(forTimeInterval: 0.02) }
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

    private static func request(address: String, port: UInt16, path: String) throws -> Data {
        let descriptor = try connect(address: address, port: port)
        defer { Darwin.close(descriptor) }

        let request = requestData(path: path, host: "\(address):\(port)")
        guard sendAll(request, to: descriptor) else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 8 * 1_024)
        while true {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if count > 0 {
                response.append(buffer, count: count)
                continue
            }
            if count < 0, errno == EINTR { continue }
            guard count == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            return response
        }
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
