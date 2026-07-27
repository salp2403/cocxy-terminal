// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

private struct MUXTestPacketReader {
    let data: Data
    private(set) var offset = 0

    mutating func readUInt32() throws -> UInt32 {
        guard data.count - offset >= 4 else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        offset += 4
        return value
    }

    mutating func readString() throws -> Data {
        let length = Int(try readUInt32())
        guard length <= data.count - offset else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        let value = Data(data[offset..<(offset + length)])
        offset += length
        return value
    }
}

private struct MUXDescriptorControlMessage {
    var header = cmsghdr()
    var descriptor: Int32 = -1
}

private final class MUXTestServer: @unchecked Sendable {
    enum Behavior {
        case echo
        case reject
        case stall
    }

    private static let muxMessageHello: UInt32 = 0x0000_0001
    private static let muxClientAliveCheck: UInt32 = 0x1000_0004
    private static let muxClientNewStdioForward: UInt32 = 0x1000_0008
    private static let muxServerFailure: UInt32 = 0x8000_0003
    private static let muxServerAlive: UInt32 = 0x8000_0005
    private static let muxServerSessionOpened: UInt32 = 0x8000_0006

    let controlPath: String
    let attestation: SSHControlSocketAttestation

    private let behavior: Behavior
    private let directory: URL
    private let queue = DispatchQueue(label: "com.cocxy.tests.mux-server")
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var listenerDescriptor: Int32
    private var acceptedDescriptor: Int32 = -1
    private var stopped = false
    private var receivedTargetStorage: ProxyTarget?

    var receivedTarget: ProxyTarget? {
        lock.lock()
        defer { lock.unlock() }
        return receivedTargetStorage
    }

    init(behavior: Behavior) throws {
        self.behavior = behavior
        directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(
                "cxy-mux-\(UUID().uuidString.prefix(12))",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        controlPath = directory.appendingPathComponent("control.sock").path

        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        listenerDescriptor = listener
        do {
            try Self.bindUnixListener(listener, path: controlPath)
            guard Darwin.listen(listener, 4) == 0,
                  Darwin.chmod(controlPath, 0o600) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            attestation = try Self.attestation(at: controlPath, processID: getpid())
        } catch {
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        group.enter()
        queue.async { [weak self] in
            defer { self?.group.leave() }
            self?.run()
        }
    }

    deinit {
        stop()
    }

    func stop() {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let listener = listenerDescriptor
        listenerDescriptor = -1
        let accepted = acceptedDescriptor
        acceptedDescriptor = -1
        lock.unlock()

        if accepted >= 0 {
            _ = Darwin.shutdown(accepted, SHUT_RDWR)
            Darwin.close(accepted)
        }
        if listener >= 0 {
            _ = Darwin.shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
        }
        _ = group.wait(timeout: .now() + 1)
        _ = Darwin.unlink(controlPath)
        try? FileManager.default.removeItem(at: directory)
    }

    private func run() {
        lock.lock()
        let listener = listenerDescriptor
        lock.unlock()
        guard listener >= 0 else { return }

        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        var noSigPipe: Int32 = 1
        _ = Darwin.setsockopt(
            client,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        lock.lock()
        guard !stopped else {
            lock.unlock()
            Darwin.close(client)
            return
        }
        acceptedDescriptor = client
        lock.unlock()
        defer { closeAcceptedDescriptor(client) }

        do {
            let hello = try Self.readPacket(from: client)
            var helloReader = MUXTestPacketReader(data: hello)
            guard try helloReader.readUInt32() == Self.muxMessageHello,
                  try helloReader.readUInt32() == 4 else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
            if behavior == .stall {
                var byte: UInt8 = 0
                _ = Darwin.recv(client, &byte, 1, 0)
                return
            }
            try Self.writePacket(
                Self.packetBody([Self.muxMessageHello, 4]),
                to: client
            )

            let alive = try Self.readPacket(from: client)
            var aliveReader = MUXTestPacketReader(data: alive)
            guard try aliveReader.readUInt32() == Self.muxClientAliveCheck else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
            let aliveRequestID = try aliveReader.readUInt32()
            try Self.writePacket(
                Self.packetBody([
                    Self.muxServerAlive,
                    aliveRequestID,
                    UInt32(getpid()),
                ]),
                to: client
            )

            let request = try Self.readPacket(from: client)
            var requestReader = MUXTestPacketReader(data: request)
            guard try requestReader.readUInt32() == Self.muxClientNewStdioForward else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
            let requestID = try requestReader.readUInt32()
            _ = try requestReader.readString()
            let hostData = try requestReader.readString()
            let port = Int(try requestReader.readUInt32())
            guard let host = String(data: hostData, encoding: .utf8) else {
                throw ProxyUpstreamTransportError.protocolViolation
            }
            let target = try ProxyTarget(host: host, port: port)
            lock.lock()
            receivedTargetStorage = target
            lock.unlock()

            let input = try Self.receiveFileDescriptor(from: client)
            let output = try Self.receiveFileDescriptor(from: client)
            defer {
                Darwin.close(input)
                Darwin.close(output)
            }

            if behavior == .reject {
                var failure = Self.packetBody([Self.muxServerFailure, requestID])
                Self.appendString(Data("rejected".utf8), to: &failure)
                try Self.writePacket(failure, to: client)
                return
            }

            try Self.writePacket(
                Self.packetBody([
                    Self.muxServerSessionOpened,
                    requestID,
                    7,
                ]),
                to: client
            )
            try Self.echo(input: input, output: output)
        } catch {
            return
        }
    }

    private func closeAcceptedDescriptor(_ descriptor: Int32) {
        lock.lock()
        guard acceptedDescriptor == descriptor else {
            lock.unlock()
            return
        }
        acceptedDescriptor = -1
        lock.unlock()
        Darwin.close(descriptor)
    }

    private static func bindUnixListener(_ descriptor: Int32, path: String) throws {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            throw ProxyUpstreamTransportError.controlSocketRejected
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                    _ = memset(destination, 0, capacity)
                    _ = memcpy(destination, source, bytes.count)
                }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    fileprivate static func attestation(
        at path: String,
        processID: Int32
    ) throws -> SSHControlSocketAttestation {
        var metadata = stat()
        guard path.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return SSHControlSocketAttestation(
            device: UInt64(truncatingIfNeeded: metadata.st_dev),
            inode: UInt64(truncatingIfNeeded: metadata.st_ino),
            peerProcessID: processID
        )
    }

    private static func echo(input: Int32, output: Int32) throws {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = Darwin.read(input, &buffer, buffer.count)
            if count == 0 { return }
            if count < 0 {
                if errno == EINTR { continue }
                throw ProxyUpstreamTransportError.closed
            }
            var sent = 0
            while sent < count {
                let written = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        output,
                        bytes.baseAddress?.advanced(by: sent),
                        count - sent
                    )
                }
                if written > 0 {
                    sent += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    throw ProxyUpstreamTransportError.closed
                }
            }
        }
    }

    private static func readPacket(from descriptor: Int32) throws -> Data {
        let header = try readExactly(4, from: descriptor)
        var reader = MUXTestPacketReader(data: header)
        let length = Int(try reader.readUInt32())
        guard length <= 256 * 1_024 else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        return try readExactly(length, from: descriptor)
    }

    private static func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var result = Data(count: count)
        var offset = 0
        try result.withUnsafeMutableBytes { buffer in
            while offset < count {
                let next = Darwin.read(
                    descriptor,
                    buffer.baseAddress?.advanced(by: offset),
                    count - offset
                )
                if next > 0 {
                    offset += next
                } else if next < 0, errno == EINTR {
                    continue
                } else {
                    throw ProxyUpstreamTransportError.closed
                }
            }
        }
        return result
    }

    private static func writePacket(_ body: Data, to descriptor: Int32) throws {
        var frame = Data()
        appendUInt32(UInt32(body.count), to: &frame)
        frame.append(body)
        var sent = 0
        try frame.withUnsafeBytes { buffer in
            while sent < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    buffer.baseAddress?.advanced(by: sent),
                    buffer.count - sent
                )
                if count > 0 {
                    sent += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw ProxyUpstreamTransportError.closed
                }
            }
        }
    }

    private static func receiveFileDescriptor(from descriptor: Int32) throws -> Int32 {
        guard let descriptorOffset = MemoryLayout<MUXDescriptorControlMessage>.offset(
            of: \.descriptor
        ) else {
            throw ProxyUpstreamTransportError.protocolViolation
        }
        var control = MUXDescriptorControlMessage()
        var payload: UInt8 = 0

        return try withUnsafeMutablePointer(to: &control) { controlPointer in
            try withUnsafeMutablePointer(to: &payload) { payloadPointer in
                var vector = iovec(
                    iov_base: UnsafeMutableRawPointer(payloadPointer),
                    iov_len: 1
                )
                return try withUnsafeMutablePointer(to: &vector) { vectorPointer in
                    var message = msghdr()
                    message.msg_iov = vectorPointer
                    message.msg_iovlen = 1
                    message.msg_control = UnsafeMutableRawPointer(controlPointer)
                    message.msg_controllen = socklen_t(
                        MemoryLayout<MUXDescriptorControlMessage>.size
                    )

                    let count = Darwin.recvmsg(descriptor, &message, 0)
                    guard count == 1, payloadPointer.pointee == 0 else {
                        throw ProxyUpstreamTransportError.protocolViolation
                    }
                    let header = controlPointer.pointee.header
                    guard header.cmsg_level == SOL_SOCKET,
                          header.cmsg_type == SCM_RIGHTS,
                          header.cmsg_len >= socklen_t(
                            descriptorOffset + MemoryLayout<Int32>.size
                          ) else {
                        throw ProxyUpstreamTransportError.protocolViolation
                    }
                    return controlPointer.pointee.descriptor
                }
            }
        }
    }

    private static func packetBody(_ values: [UInt32]) -> Data {
        var result = Data()
        for value in values {
            appendUInt32(value, to: &result)
        }
        return result
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private static func appendString(_ value: Data, to data: inout Data) {
        appendUInt32(UInt32(value.count), to: &data)
        data.append(value)
    }
}

private final class UnixListenerProcess: @unchecked Sendable {
    let path: String
    let process: Process
    private let stdout = Pipe()
    private let stderr = Pipe()

    var processIdentifier: Int32 { process.processIdentifier }

    init(path: String) throws {
        self.path = path
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        process.arguments = ["-lU", path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: path) { break }
            usleep(5_000)
        }
        guard FileManager.default.fileExists(atPath: path),
              Darwin.chmod(path, 0o600) == 0 else {
            stop()
            throw ProxyUpstreamTransportError.controlSocketRejected
        }
    }

    deinit {
        stop()
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        _ = Darwin.unlink(path)
    }
}

@Suite("Proxy transport security", .serialized)
struct ProxyTransportTests {
    @Test("Generated credentials are high entropy and rotate")
    func generatedCredentialsRotate() {
        let first = ProxyCredentials.generate()
        let second = ProxyCredentials.generate()

        #expect(first.password.utf8.count >= 43)
        #expect(first != second)
        #expect(first.matches(
            username: Data(ProxyCredentials.username.utf8),
            password: Data(first.password.utf8)
        ))
        #expect(!first.matches(
            username: Data(ProxyCredentials.username.utf8),
            password: Data(second.password.utf8)
        ))
        #expect(!first.matches(
            username: Data("wrong".utf8),
            password: Data(first.password.utf8)
        ))
    }

    @Test("Basic authentication accepts only the exact credential")
    func basicAuthenticationIsExact() {
        let credentials = ProxyCredentials(password: "test-capability")
        #expect(credentials.matchesBasicAuthorization(credentials.basicAuthorizationValue))
        #expect(!credentials.matchesBasicAuthorization("not-base64"))
        #expect(!credentials.matchesBasicAuthorization(
            Data("cocxy:wrong".utf8).base64EncodedString()
        ))
    }

    @Test("Proxy targets validate host and port as one MUX destination")
    func targetValidation() throws {
        let domain = try ProxyTarget(host: "example.com", port: 443)
        #expect(domain.host == "example.com")
        #expect(domain.port == 443)

        let ipv6 = try ProxyTarget(host: "::1", port: 8_443)
        #expect(ipv6.host == "::1")
        #expect(ipv6.port == 8_443)
        #expect(throws: ProxyTargetError.self) {
            _ = try ProxyTarget(host: "-oProxyCommand=bad", port: 443)
        }
        #expect(throws: ProxyTargetError.self) {
            _ = try ProxyTarget(host: "example.com", port: 0)
        }
    }

    @Test("Attested MUX transport relays bytes and preserves half-close")
    func muxRoundTrip() async throws {
        let server = try MUXTestServer(behavior: .echo)
        defer { server.stop() }
        let target = try ProxyTarget(host: "internal.example", port: 443)
        let transport = try SSHDirectTCPTransport(
            controlPath: server.controlPath,
            target: target,
            expectedAttestation: server.attestation
        )
        defer { transport.cancel() }

        try await transport.waitUntilReady()
        #expect(transport.processIdentifier == getpid())
        #expect(transport.isRunning)
        #expect(server.receivedTarget == target)

        let payload = Data("mux-round-trip".utf8)
        try await send(payload, through: transport)
        #expect(try await receive(from: transport) == payload)

        transport.closeWrite()
        #expect(try await receive(from: transport) == nil)
        try await waitUntilStopped(transport)
        #expect(transport.diagnosticOutput.isEmpty)
    }

    @Test("Exact LOCAL_PEERPID is required before the destination is sent")
    func rejectsUnexpectedPeerBeforeDestination() async throws {
        let server = try MUXTestServer(behavior: .echo)
        defer { server.stop() }
        let wrongAttestation = SSHControlSocketAttestation(
            device: server.attestation.device,
            inode: server.attestation.inode,
            peerProcessID: getpid() + 10_000
        )
        let transport = try SSHDirectTCPTransport(
            controlPath: server.controlPath,
            target: ProxyTarget(host: "must-not-leak.example", port: 443),
            expectedAttestation: wrongAttestation
        )
        defer { transport.cancel() }

        await #expect(throws: ProxyUpstreamTransportError.controlSocketRejected) {
            try await transport.waitUntilReady()
        }
        #expect(server.receivedTarget == nil)
    }

    @Test("MUX failure is returned before proxy success")
    func rejectsFailedChannelOpen() async throws {
        let server = try MUXTestServer(behavior: .reject)
        defer { server.stop() }
        let target = try ProxyTarget(host: "unavailable.example", port: 443)
        let transport = try SSHDirectTCPTransport(
            controlPath: server.controlPath,
            target: target,
            expectedAttestation: server.attestation
        )
        defer { transport.cancel() }

        await #expect(throws: ProxyUpstreamTransportError.unavailable) {
            try await transport.waitUntilReady()
        }
        #expect(server.receivedTarget == target)
    }

    @Test("MUX readiness timeout is bounded")
    func readinessTimeoutIsBounded() async throws {
        let server = try MUXTestServer(behavior: .stall)
        defer { server.stop() }
        let transport = try SSHDirectTCPTransport(
            controlPath: server.controlPath,
            target: ProxyTarget(host: "internal.example", port: 443),
            expectedAttestation: server.attestation,
            handshakeTimeout: 0.1
        )
        defer { transport.cancel() }

        await #expect(throws: ProxyUpstreamTransportError.readinessTimedOut) {
            try await transport.waitUntilReady()
        }
        #expect(!transport.isRunning)
    }

    @Test("Cancelling a stalled handshake releases its exact control descriptor")
    func cancelStalledHandshake() async throws {
        let server = try MUXTestServer(behavior: .stall)
        defer { server.stop() }
        let transport = try SSHDirectTCPTransport(
            controlPath: server.controlPath,
            target: ProxyTarget(host: "internal.example", port: 443),
            expectedAttestation: server.attestation,
            connectionHooks: SSHDirectTCPTransport.ConnectionHooks(
                afterSocketConfigured: { descriptor in
                    let flags = Darwin.fcntl(descriptor, F_GETFL)
                    guard flags >= 0, flags & O_NONBLOCK != 0 else {
                        throw ProxyUpstreamTransportError.protocolViolation
                    }
                }
            ),
            handshakeTimeout: 2
        )
        let waiter = Task {
            try await transport.waitUntilReady()
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        transport.cancel()

        await #expect(throws: ProxyUpstreamTransportError.closed) {
            try await waiter.value
        }
        #expect(!transport.isRunning)
    }

    @Test("Immediate cancellation after readiness closes the monitored channel")
    func cancelImmediatelyAfterReadiness() async throws {
        let server = try MUXTestServer(behavior: .echo)
        defer { server.stop() }
        let transport = try SSHDirectTCPTransport(
            controlPath: server.controlPath,
            target: ProxyTarget(host: "internal.example", port: 443),
            expectedAttestation: server.attestation
        )

        try await transport.waitUntilReady()
        transport.cancel()

        #expect(!transport.isRunning)
        await #expect(throws: ProxyUpstreamTransportError.closed) {
            _ = try await receive(from: transport)
        }
    }

    @Test("A-B-A socket replacement cannot redirect the exact MUX descriptor")
    func rejectsABASocketReplacement() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent(
                "cxy-aba-\(UUID().uuidString.prefix(12))",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let controlPath = directory.appendingPathComponent("control.sock").path
        let attackerPath = directory.appendingPathComponent("attacker.sock").path
        let savedOwnerPath = directory.appendingPathComponent("owner.saved").path
        let savedAttackerPath = directory.appendingPathComponent("attacker.saved").path
        let owner = try UnixListenerProcess(path: controlPath)
        let attacker = try UnixListenerProcess(path: attackerPath)
        defer {
            owner.stop()
            attacker.stop()
            _ = Darwin.unlink(savedOwnerPath)
            _ = Darwin.unlink(savedAttackerPath)
        }
        let expected = try MUXTestServer.attestation(
            at: controlPath,
            processID: owner.processIdentifier
        )
        let hooks = SSHDirectTCPTransport.ConnectionHooks(
            beforeConnect: {
                guard Darwin.rename(controlPath, savedOwnerPath) == 0,
                      Darwin.rename(attackerPath, controlPath) == 0 else {
                    throw ProxyUpstreamTransportError.controlSocketRejected
                }
            },
            afterConnect: {
                guard Darwin.rename(controlPath, savedAttackerPath) == 0,
                      Darwin.rename(savedOwnerPath, controlPath) == 0 else {
                    throw ProxyUpstreamTransportError.controlSocketRejected
                }
            }
        )
        let transport = try SSHDirectTCPTransport(
            controlPath: controlPath,
            target: ProxyTarget(host: "must-not-reach-attacker.example", port: 443),
            expectedAttestation: expected,
            connectionHooks: hooks
        )
        defer { transport.cancel() }

        await #expect(throws: ProxyUpstreamTransportError.controlSocketRejected) {
            try await transport.waitUntilReady()
        }
        let restored = try MUXTestServer.attestation(
            at: controlPath,
            processID: owner.processIdentifier
        )
        #expect(restored == expected)
        #expect(attacker.processIdentifier != owner.processIdentifier)
    }

    private func send(
        _ data: Data,
        through transport: SSHDirectTCPTransport
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            transport.send(data) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func receive(from transport: SSHDirectTCPTransport) async throws -> Data? {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Data?, any Error>) in
            transport.receive(maximumLength: 65_536) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func waitUntilStopped(_ transport: SSHDirectTCPTransport) async throws {
        for _ in 0..<100 {
            if !transport.isRunning { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        Issue.record("MUX transport did not observe channel closure")
    }
}
