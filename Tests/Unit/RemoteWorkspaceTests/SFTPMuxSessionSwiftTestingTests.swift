// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

private struct SFTPMUXPacketReader {
    let data: Data
    private(set) var offset = 0

    mutating func readUInt32() throws -> UInt32 {
        guard data.count - offset >= 4 else {
            throw SFTPMuxSessionError.protocolViolation
        }
        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
        offset += 4
        return value
    }

    mutating func readString() throws -> Data {
        let count = Int(try readUInt32())
        guard count <= data.count - offset else {
            throw SFTPMuxSessionError.protocolViolation
        }
        let value = Data(data[offset..<(offset + count)])
        offset += count
        return value
    }
}

private struct SFTPMUXDescriptorMessage {
    var header = cmsghdr()
    var descriptor: Int32 = -1
}

private final class SFTPMUXTestServer: @unchecked Sendable {
    private static let hello: UInt32 = 0x0000_0001
    private static let alive: UInt32 = 0x1000_0004
    private static let newSession: UInt32 = 0x1000_0002
    private static let serverAlive: UInt32 = 0x8000_0005
    private static let sessionOpened: UInt32 = 0x8000_0006
    private static let exitMessage: UInt32 = 0x8000_0004

    let configuration: SFTPMuxSessionConfiguration

    private let directory: URL
    private let queue = DispatchQueue(label: "com.cocxy.tests.sftp-mux")
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var listener: Int32
    private var accepted: Int32 = -1
    private var stopped = false
    private var commandStorage: String?
    private var subsystemFlagStorage: UInt32?
    private var receivedDescriptorCountStorage = 0

    var command: String? { lock.withLock { commandStorage } }
    var subsystemFlag: UInt32? { lock.withLock { subsystemFlagStorage } }
    var receivedDescriptorCount: Int { lock.withLock { receivedDescriptorCountStorage } }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-sftp-mux-tests-\(UUID().uuidString.prefix(12))",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let controlPath = directory.appendingPathComponent("control.sock").path
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw SFTPMuxSessionError.connectionClosed
        }
        do {
            try Self.bind(listener, path: controlPath)
            guard Darwin.listen(listener, 1) == 0,
                  Darwin.chmod(controlPath, 0o600) == 0 else {
                throw SFTPMuxSessionError.connectionClosed
            }
            var metadata = stat()
            guard controlPath.withCString({ Darwin.lstat($0, &metadata) }) == 0 else {
                throw SFTPMuxSessionError.connectionClosed
            }
            configuration = SFTPMuxSessionConfiguration(
                controlPath: controlPath,
                attestation: SSHControlSocketAttestation(
                    device: UInt64(truncatingIfNeeded: metadata.st_dev),
                    inode: UInt64(truncatingIfNeeded: metadata.st_ino),
                    peerProcessID: getpid()
                ),
                request: .subsystem("sftp")
            )
        } catch {
            Darwin.close(listener)
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        group.enter()
        queue.async { [weak self] in
            defer { self?.group.leave() }
            self?.serve()
        }
    }

    deinit { stop() }

    func stop() {
        let descriptors = lock.withLock { () -> (Int32, Int32)? in
            guard !stopped else { return nil }
            stopped = true
            let result = (listener, accepted)
            listener = -1
            accepted = -1
            return result
        }
        guard let descriptors else { return }
        if descriptors.1 >= 0 {
            _ = Darwin.shutdown(descriptors.1, SHUT_RDWR)
            Darwin.close(descriptors.1)
        }
        if descriptors.0 >= 0 {
            _ = Darwin.shutdown(descriptors.0, SHUT_RDWR)
            Darwin.close(descriptors.0)
        }
        _ = group.wait(timeout: .now() + 1)
        _ = Darwin.unlink(configuration.controlPath)
        try? FileManager.default.removeItem(at: directory)
    }

    private func serve() {
        let listener = lock.withLock { self.listener }
        guard listener >= 0 else { return }
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        lock.withLock { accepted = client }
        defer { closeAccepted(client) }

        do {
            var helloReader = SFTPMUXPacketReader(data: try Self.readPacket(client))
            guard try helloReader.readUInt32() == Self.hello,
                  try helloReader.readUInt32() == 4 else {
                throw SFTPMuxSessionError.protocolViolation
            }
            try Self.writePacket(Self.packet([Self.hello, 4]), client)

            var aliveReader = SFTPMUXPacketReader(data: try Self.readPacket(client))
            guard try aliveReader.readUInt32() == Self.alive else {
                throw SFTPMuxSessionError.protocolViolation
            }
            let aliveID = try aliveReader.readUInt32()
            try Self.writePacket(
                Self.packet([Self.serverAlive, aliveID, UInt32(getpid())]),
                client
            )

            var request = SFTPMUXPacketReader(data: try Self.readPacket(client))
            guard try request.readUInt32() == Self.newSession else {
                throw SFTPMuxSessionError.protocolViolation
            }
            let requestID = try request.readUInt32()
            _ = try request.readString()
            guard try request.readUInt32() == 0,
                  try request.readUInt32() == 0,
                  try request.readUInt32() == 0 else {
                throw SFTPMuxSessionError.protocolViolation
            }
            let subsystemFlag = try request.readUInt32()
            guard subsystemFlag <= 1,
                  try request.readUInt32() == UInt32.max else {
                throw SFTPMuxSessionError.protocolViolation
            }
            _ = try request.readString()
            let commandData = try request.readString()
            let descriptors = try (0..<3).map { _ in
                try Self.receiveDescriptor(client)
            }
            descriptors.forEach { Darwin.close($0) }
            lock.withLock {
                commandStorage = String(data: commandData, encoding: .utf8)
                subsystemFlagStorage = subsystemFlag
                receivedDescriptorCountStorage = descriptors.count
            }

            let sessionID: UInt32 = 9
            try Self.writePacket(
                Self.packet([Self.sessionOpened, requestID, sessionID]),
                client
            )
            try Self.writePacket(
                Self.packet([Self.exitMessage, sessionID, 0]),
                client
            )
            _ = Darwin.shutdown(client, SHUT_RDWR)
        } catch {
            return
        }
    }

    private func closeAccepted(_ descriptor: Int32) {
        let shouldClose = lock.withLock { () -> Bool in
            guard accepted == descriptor else { return false }
            accepted = -1
            return true
        }
        if shouldClose { Darwin.close(descriptor) }
    }

    private static func bind(_ descriptor: Int32, path: String) throws {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            throw SFTPMuxSessionError.invalidConfiguration
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    destination in
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
        guard result == 0 else { throw SFTPMuxSessionError.connectionClosed }
    }

    private static func readPacket(_ descriptor: Int32) throws -> Data {
        let header = try readExactly(4, descriptor)
        var reader = SFTPMUXPacketReader(data: header)
        let count = Int(try reader.readUInt32())
        guard count <= 256 * 1_024 else {
            throw SFTPMuxSessionError.protocolViolation
        }
        return try readExactly(count, descriptor)
    }

    private static func readExactly(_ count: Int, _ descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { bytes in
            while offset < count {
                let received = Darwin.read(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    count - offset
                )
                if received > 0 {
                    offset += received
                } else if received < 0, errno == EINTR {
                    continue
                } else {
                    throw SFTPMuxSessionError.connectionClosed
                }
            }
        }
        return data
    }

    private static func writePacket(_ body: Data, _ descriptor: Int32) throws {
        var frame = Data()
        appendUInt32(UInt32(body.count), to: &frame)
        frame.append(body)
        var offset = 0
        try frame.withUnsafeBytes { bytes in
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    bytes.baseAddress?.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    throw SFTPMuxSessionError.connectionClosed
                }
            }
        }
    }

    private static func receiveDescriptor(_ socket: Int32) throws -> Int32 {
        guard let descriptorOffset = MemoryLayout<SFTPMUXDescriptorMessage>.offset(
            of: \.descriptor
        ) else {
            throw SFTPMuxSessionError.protocolViolation
        }
        var control = SFTPMUXDescriptorMessage()
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
                        MemoryLayout<SFTPMUXDescriptorMessage>.size
                    )
                    guard Darwin.recvmsg(socket, &message, 0) == 1 else {
                        throw SFTPMuxSessionError.connectionClosed
                    }
                    let header = controlPointer.pointee.header
                    guard header.cmsg_level == SOL_SOCKET,
                          header.cmsg_type == SCM_RIGHTS,
                          header.cmsg_len >= socklen_t(
                            descriptorOffset + MemoryLayout<Int32>.size
                          ) else {
                        throw SFTPMuxSessionError.protocolViolation
                    }
                    return controlPointer.pointee.descriptor
                }
            }
        }
    }

    private static func packet(_ values: [UInt32]) -> Data {
        var data = Data()
        values.forEach { appendUInt32($0, to: &data) }
        return data
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }
}

@Suite("SFTP attested MUX session", .serialized)
struct SFTPMuxSessionSwiftTestingTests {
    @Test("helper opens the SFTP subsystem on the attested connected peer")
    func opensSubsystemOnAttestedPeer() throws {
        let server = try SFTPMUXTestServer()
        defer { server.stop() }

        let exitCode = try SFTPMuxSession.run(configuration: server.configuration)

        #expect(exitCode == 0)
        #expect(server.command == "sftp")
        #expect(server.subsystemFlag == 1)
        #expect(server.receivedDescriptorCount == 3)
    }

    @Test("helper sends remote commands as non-subsystem MUX sessions")
    func opensCommandOnAttestedPeer() throws {
        let server = try SFTPMUXTestServer()
        defer { server.stop() }
        let command = "printf 'line one\\nline two'"
        let configuration = SFTPMuxSessionConfiguration(
            controlPath: server.configuration.controlPath,
            attestation: server.configuration.attestation,
            request: .command(command)
        )

        let exitCode = try SFTPMuxSession.run(configuration: configuration)

        #expect(exitCode == 0)
        #expect(server.command == command)
        #expect(server.subsystemFlag == 0)
        #expect(server.receivedDescriptorCount == 3)
    }

    @Test("argument contract preserves command and rejects unsafe paths")
    func commandArgumentContract() throws {
        let command = "printf 'caf\u{00E9}\\n'"
        let attestation = SSHControlSocketAttestation(
            device: 41,
            inode: 42,
            peerProcessID: 43
        )
        let arguments = try SFTPMuxSessionArgumentContract.arguments(
            controlPath: "/tmp/cocxy-control.sock",
            attestation: attestation,
            command: command
        )

        let configuration = try #require(
            try SFTPMuxSessionArgumentContract.configuration(arguments: arguments)
        )
        #expect(configuration.controlPath == "/tmp/cocxy-control.sock")
        #expect(configuration.attestation == attestation)
        #expect(configuration.request == .command(command))

        var unsafeArguments = arguments
        unsafeArguments[1] = "relative.sock"
        #expect(throws: SFTPMuxSessionError.invalidConfiguration) {
            _ = try SFTPMuxSessionArgumentContract.configuration(
                arguments: unsafeArguments
            )
        }
    }

    @Test("connected peer PID mismatch is rejected")
    func rejectsWrongConnectedPeer() throws {
        let server = try SFTPMUXTestServer()
        defer { server.stop() }
        let wrongConfiguration = SFTPMuxSessionConfiguration(
            controlPath: server.configuration.controlPath,
            attestation: SSHControlSocketAttestation(
                device: server.configuration.attestation.device,
                inode: server.configuration.attestation.inode,
                peerProcessID: getpid() == Int32.max ? getpid() - 1 : getpid() + 1
            ),
            request: .subsystem("sftp")
        )

        #expect(throws: SFTPMuxSessionError.controlSocketRejected) {
            _ = try SFTPMuxSession.run(configuration: wrongConfiguration)
        }
    }

    @Test("malformed helper environment fails closed")
    func malformedEnvironmentFailsClosed() {
        #expect(throws: SFTPMuxSessionError.invalidConfiguration) {
            _ = try SFTPMuxSessionContract.configuration(environment: [
                SFTPMuxSessionContract.modeKey: SFTPMuxSessionContract.modeValue,
                SFTPMuxSessionContract.controlPathKey: "relative.sock",
            ])
        }
    }
}
