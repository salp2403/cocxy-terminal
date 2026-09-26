// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Mobile mirror gateway WebSocket proxy", .serialized)
struct MobileMirrorGatewayWebSocketSwiftTestingTests {
    @Test("stream subprotocol crosses the gateway proxy intact in both directions")
    func streamSubprotocolPassesThrough() async throws {
        let subprotocol = "cocxy-stream.Q2hhbm5lbC1iaW5kaW5n_-9"
        let switching = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
            + "Connection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"
            + "Sec-WebSocket-Protocol: \(subprotocol)\r\n\r\n"
        let upstream = try LoopbackBulkResponder(rawResponse: Data(switching.utf8))
        let gateway = MobileMirrorGateway { _, _ in
            .proxy(MobileMirrorProxyTarget(
                port: upstream.port,
                bearerToken: "engine-secret",
                rewrittenPath: "/ws"
            ))
        }
        let port = try gateway.start()
        defer { gateway.stop() }

        let client = try Self.connect(port: port)
        defer { Darwin.close(client) }
        let upgrade = "GET /terminal/session/ws HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n"
            + "Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\n"
            + "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
            + "Sec-WebSocket-Protocol: \(subprotocol)\r\n\r\n"
        #expect(MobileMirrorGateway.sendAll(Data(upgrade.utf8), to: client))

        #expect(Self.receiveHead(from: client) == switching)
        #expect(await upstream.waitUntilWritten(timeout: 3))
        #expect(upstream.receivedRequest.contains("sec-websocket-protocol: \(subprotocol)\r\n"))
    }

    private static func connect(port: UInt16) throws -> Int32 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, MobileMirrorGateway.loopbackAddress, &address.sin_addr)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(descriptor)
            throw POSIXError(.ECONNREFUSED)
        }
        return descriptor
    }

    private static func receiveHead(from descriptor: Int32) -> String {
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
