// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPMuxSession.swift - Attested OpenSSH MUX session used by the SFTP helper.

import Darwin
import Foundation

struct SFTPMuxSessionConfiguration: Equatable, Sendable {
    let controlPath: String
    let attestation: SSHControlSocketAttestation
    let request: SFTPMuxSessionRequest
}

enum SFTPMuxSessionRequest: Equatable, Sendable {
    case subsystem(String)
    case command(String)
}

enum SFTPMuxSessionContract {
    static let modeKey = "COCXY_INTERNAL_MODE"
    static let modeValue = "sftp-mux-session-v1"
    static let controlPathKey = "COCXY_SFTP_MUX_CONTROL_PATH"
    static let deviceKey = "COCXY_SFTP_MUX_DEVICE"
    static let inodeKey = "COCXY_SFTP_MUX_INODE"
    static let peerProcessIDKey = "COCXY_SFTP_MUX_PEER_PID"

    static func environment(
        authorization: SFTPConnectionAuthorization,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        let allowedKeys: Set<String> = [
            "HOME", "LANG", "LC_ALL", "LC_CTYPE", "LOGNAME", "PATH", "SHELL",
            "TMPDIR", "USER", "__CF_USER_TEXT_ENCODING",
        ]
        var result = base.filter { key, _ in
            allowedKeys.contains(key) || key.hasPrefix("LC_")
        }
        result[modeKey] = modeValue
        result[controlPathKey] = authorization.controlPath
        result[deviceKey] = String(authorization.controlSocketAttestation.device)
        result[inodeKey] = String(authorization.controlSocketAttestation.inode)
        result[peerProcessIDKey] = String(
            authorization.controlSocketAttestation.peerProcessID
        )
        return result
    }

    static func configuration(
        environment: [String: String]
    ) throws -> SFTPMuxSessionConfiguration? {
        guard environment[modeKey] == modeValue else { return nil }
        guard let controlPath = environment[controlPathKey],
              controlPath.first == "/",
              controlPath.utf8.count < 104,
              !controlPath.unicodeScalars.contains(
                  where: CharacterSet.controlCharacters.contains
              ),
              let deviceValue = environment[deviceKey],
              let device = UInt64(deviceValue),
              device != 0,
              let inodeValue = environment[inodeKey],
              let inode = UInt64(inodeValue),
              inode != 0,
              let peerProcessIDValue = environment[peerProcessIDKey],
              let peerProcessID = Int32(peerProcessIDValue),
              peerProcessID > 1 else {
            throw SFTPMuxSessionError.invalidConfiguration
        }
        return SFTPMuxSessionConfiguration(
            controlPath: controlPath,
            attestation: SSHControlSocketAttestation(
                device: device,
                inode: inode,
                peerProcessID: peerProcessID
            ),
            request: .subsystem("sftp")
        )
    }
}

enum SFTPMuxSessionArgumentContract {
    static let modeArgument = "--cocxy-internal-mux-session-v1"
    private static let maximumCommandBytes = 64 * 1_024

    static func arguments(
        controlPath: String,
        attestation: SSHControlSocketAttestation,
        command: String
    ) throws -> [String] {
        guard !command.utf8.contains(0),
              command.utf8.count <= maximumCommandBytes else {
            throw SFTPMuxSessionError.invalidConfiguration
        }
        return [
            modeArgument,
            controlPath,
            String(attestation.device),
            String(attestation.inode),
            String(attestation.peerProcessID),
            Data(command.utf8).base64EncodedString(),
        ]
    }

    static func configuration(
        arguments: [String]
    ) throws -> SFTPMuxSessionConfiguration? {
        guard arguments.first == modeArgument else { return nil }
        guard arguments.count == 6,
              arguments[1].first == "/",
              arguments[1].utf8.count < 104,
              !arguments[1].unicodeScalars.contains(
                  where: CharacterSet.controlCharacters.contains
              ),
              let device = UInt64(arguments[2]),
              device != 0,
              let inode = UInt64(arguments[3]),
              inode != 0,
              let peerProcessID = Int32(arguments[4]),
              peerProcessID > 1,
              let commandData = Data(base64Encoded: arguments[5]),
              commandData.count <= maximumCommandBytes,
              let command = String(data: commandData, encoding: .utf8),
              !command.utf8.contains(0) else {
            throw SFTPMuxSessionError.invalidConfiguration
        }
        return SFTPMuxSessionConfiguration(
            controlPath: arguments[1],
            attestation: SSHControlSocketAttestation(
                device: device,
                inode: inode,
                peerProcessID: peerProcessID
            ),
            request: .command(command)
        )
    }
}

enum SFTPMuxSessionEntry {
    static func runIfRequested(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int32? {
        let environmentRequested = environment[SFTPMuxSessionContract.modeKey]
            == SFTPMuxSessionContract.modeValue
        let argumentRequested = arguments.first
            == SFTPMuxSessionArgumentContract.modeArgument
        guard environmentRequested || argumentRequested else {
            return nil
        }
        do {
            let configuration = environmentRequested
                ? try SFTPMuxSessionContract.configuration(environment: environment)
                : try SFTPMuxSessionArgumentContract.configuration(arguments: arguments)
            guard let configuration else {
                return nil
            }
            return try SFTPMuxSession.run(configuration: configuration)
        } catch {
            let message = "Cocxy could not open the verified SSH session.\n"
            FileHandle.standardError.write(Data(message.utf8))
            return 255
        }
    }
}

enum SFTPMuxSessionError: Error, Equatable {
    case invalidConfiguration
    case controlSocketRejected
    case protocolViolation
    case connectionClosed
    case sessionRejected
}

enum SFTPMuxSession {
    private struct PacketReader {
        let data: Data
        private(set) var offset = 0

        var isAtEnd: Bool { offset == data.count }

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
            let result = Data(data[offset..<(offset + count)])
            offset += count
            return result
        }
    }

    private struct SocketIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private static let muxMessageHello: UInt32 = 0x0000_0001
    private static let muxClientNewSession: UInt32 = 0x1000_0002
    private static let muxClientAliveCheck: UInt32 = 0x1000_0004
    private static let muxServerPermissionDenied: UInt32 = 0x8000_0002
    private static let muxServerFailure: UInt32 = 0x8000_0003
    private static let muxServerExitMessage: UInt32 = 0x8000_0004
    private static let muxServerAlive: UInt32 = 0x8000_0005
    private static let muxServerSessionOpened: UInt32 = 0x8000_0006
    private static let muxServerTTYAllocationFailed: UInt32 = 0x8000_0008
    private static let muxVersion: UInt32 = 4
    private static let maximumPacketBytes = 256 * 1_024

    static func run(
        configuration: SFTPMuxSessionConfiguration,
        standardInput: Int32 = STDIN_FILENO,
        standardOutput: Int32 = STDOUT_FILENO,
        standardError: Int32 = STDERR_FILENO
    ) throws -> Int32 {
        guard configuration.controlPath.first == "/",
              configuration.controlPath.utf8.count < 104,
              configuration.attestation.peerProcessID > 1,
              configuration.attestation.device != 0,
              configuration.attestation.inode != 0 else {
            throw SFTPMuxSessionError.invalidConfiguration
        }
        let expectedIdentity = SocketIdentity(
            device: configuration.attestation.device,
            inode: configuration.attestation.inode
        )
        guard try protectedSocketIdentity(at: configuration.controlPath)
                == expectedIdentity else {
            throw SFTPMuxSessionError.controlSocketRejected
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw SFTPMuxSessionError.connectionClosed
        }
        defer { Darwin.close(descriptor) }
        try configureSocket(descriptor)
        try connect(descriptor: descriptor, path: configuration.controlPath)

        guard try peerProcessID(for: descriptor)
                == configuration.attestation.peerProcessID,
              try protectedSocketIdentity(at: configuration.controlPath)
                == expectedIdentity else {
            throw SFTPMuxSessionError.controlSocketRejected
        }

        try writePacket(
            packetBody(uint32Values: [muxMessageHello, muxVersion]),
            to: descriptor
        )
        try validateHello(try readRequiredPacket(from: descriptor))

        let aliveRequestID: UInt32 = 0
        try writePacket(
            packetBody(uint32Values: [muxClientAliveCheck, aliveRequestID]),
            to: descriptor
        )
        try validateAliveReply(
            try readRequiredPacket(from: descriptor),
            requestID: aliveRequestID,
            expectedProcessID: configuration.attestation.peerProcessID
        )

        let sessionRequestID: UInt32 = 1
        let subsystemFlag: UInt32
        let commandData: Data
        switch configuration.request {
        case .subsystem(let subsystem):
            guard !subsystem.isEmpty,
                  subsystem.utf8.count <= 1_024,
                  !subsystem.utf8.contains(0) else {
                throw SFTPMuxSessionError.invalidConfiguration
            }
            subsystemFlag = 1
            commandData = Data(subsystem.utf8)
        case .command(let command):
            guard command.utf8.count <= 64 * 1_024,
                  !command.utf8.contains(0) else {
                throw SFTPMuxSessionError.invalidConfiguration
            }
            subsystemFlag = 0
            commandData = Data(command.utf8)
        }
        var request = Data()
        appendUInt32(muxClientNewSession, to: &request)
        appendUInt32(sessionRequestID, to: &request)
        appendString(Data(), to: &request)
        appendUInt32(0, to: &request) // no TTY
        appendUInt32(0, to: &request) // no X11 forwarding
        appendUInt32(0, to: &request) // no agent forwarding
        appendUInt32(subsystemFlag, to: &request)
        appendUInt32(UInt32.max, to: &request) // no escape character
        appendString(Data(), to: &request)
        appendString(commandData, to: &request)
        try writePacket(request, to: descriptor)
        try sendFileDescriptor(standardInput, to: descriptor)
        try sendFileDescriptor(standardOutput, to: descriptor)
        try sendFileDescriptor(standardError, to: descriptor)

        let sessionID = try validateSessionReply(
            try readRequiredPacket(from: descriptor),
            requestID: sessionRequestID
        )
        var exitCode: UInt32?
        while let packet = try readPacket(from: descriptor) {
            var reader = PacketReader(data: packet)
            let type = try reader.readUInt32()
            switch type {
            case muxServerExitMessage:
                guard try reader.readUInt32() == sessionID,
                      exitCode == nil else {
                    throw SFTPMuxSessionError.protocolViolation
                }
                exitCode = try reader.readUInt32()
                guard reader.isAtEnd else {
                    throw SFTPMuxSessionError.protocolViolation
                }
            case muxServerTTYAllocationFailed:
                guard try reader.readUInt32() == sessionID,
                      reader.isAtEnd else {
                    throw SFTPMuxSessionError.protocolViolation
                }
            default:
                throw SFTPMuxSessionError.protocolViolation
            }
        }
        guard let exitCode, exitCode <= 255 else {
            throw SFTPMuxSessionError.connectionClosed
        }
        return Int32(exitCode)
    }

    private static func configureSocket(_ descriptor: Int32) throws {
        guard Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw SFTPMuxSessionError.connectionClosed
        }
        var enabled: Int32 = 1
        guard Darwin.setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw SFTPMuxSessionError.connectionClosed
        }
    }

    private static func protectedSocketIdentity(at path: String) throws -> SocketIdentity {
        var metadata = stat()
        let result = path.withCString { Darwin.lstat($0, &metadata) }
        guard result == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK),
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              metadata.st_mode & 0o077 == 0 else {
            throw SFTPMuxSessionError.controlSocketRejected
        }
        return SocketIdentity(
            device: UInt64(truncatingIfNeeded: metadata.st_dev),
            inode: UInt64(truncatingIfNeeded: metadata.st_ino)
        )
    }

    private static func connect(descriptor: Int32, path: String) throws {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else {
            throw SFTPMuxSessionError.controlSocketRejected
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                    destination in
                    _ = memset(destination, 0, capacity)
                    _ = memcpy(destination, source, pathBytes.count)
                }
            }
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        guard result == 0 else {
            throw SFTPMuxSessionError.controlSocketRejected
        }
    }

    private static func peerProcessID(for descriptor: Int32) throws -> Int32 {
        var processID: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard Darwin.getsockopt(
            descriptor,
            SOL_LOCAL,
            LOCAL_PEERPID,
            &processID,
            &length
        ) == 0,
        processID > 0 else {
            throw SFTPMuxSessionError.controlSocketRejected
        }
        return processID
    }

    private static func writePacket(_ body: Data, to descriptor: Int32) throws {
        guard body.count <= maximumPacketBytes else {
            throw SFTPMuxSessionError.protocolViolation
        }
        var frame = Data()
        appendUInt32(UInt32(body.count), to: &frame)
        frame.append(body)
        try writeAll(frame, to: descriptor)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset,
                    0
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    throw SFTPMuxSessionError.connectionClosed
                }
            }
        }
    }

    private static func readRequiredPacket(from descriptor: Int32) throws -> Data {
        guard let packet = try readPacket(from: descriptor) else {
            throw SFTPMuxSessionError.connectionClosed
        }
        return packet
    }

    private static func readPacket(from descriptor: Int32) throws -> Data? {
        guard let header = try readExactly(
            4,
            from: descriptor,
            permitsInitialEOF: true
        ) else {
            return nil
        }
        var reader = PacketReader(data: header)
        let count = Int(try reader.readUInt32())
        guard count <= maximumPacketBytes else {
            throw SFTPMuxSessionError.protocolViolation
        }
        return try readExactly(count, from: descriptor, permitsInitialEOF: false)
    }

    private static func readExactly(
        _ count: Int,
        from descriptor: Int32,
        permitsInitialEOF: Bool
    ) throws -> Data? {
        if count == 0 { return Data() }
        var result = Data(count: count)
        var offset = 0
        try result.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            while offset < count {
                let received = Darwin.recv(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset,
                    0
                )
                if received > 0 {
                    offset += received
                } else if received == 0, permitsInitialEOF, offset == 0 {
                    return
                } else if received < 0, errno == EINTR {
                    continue
                } else {
                    throw SFTPMuxSessionError.connectionClosed
                }
            }
        }
        if permitsInitialEOF, offset == 0 { return nil }
        guard offset == count else {
            throw SFTPMuxSessionError.connectionClosed
        }
        return result
    }

    private static func sendFileDescriptor(
        _ passedDescriptor: Int32,
        to controlDescriptor: Int32
    ) throws {
        guard passedDescriptor >= 0 else {
            throw SFTPMuxSessionError.invalidConfiguration
        }
        let alignment = max(
            MemoryLayout<cmsghdr>.alignment,
            MemoryLayout<Int32>.alignment
        )
        let descriptorOffset = alignedSize(
            MemoryLayout<cmsghdr>.size,
            to: alignment
        )
        let messageLength = descriptorOffset + MemoryLayout<Int32>.size
        let controlSize = alignedSize(messageLength, to: alignment)
        let control = UnsafeMutableRawPointer.allocate(
            byteCount: controlSize,
            alignment: alignment
        )
        defer { control.deallocate() }
        _ = memset(control, 0, controlSize)

        let header = control.bindMemory(to: cmsghdr.self, capacity: 1)
        header.pointee.cmsg_len = socklen_t(messageLength)
        header.pointee.cmsg_level = SOL_SOCKET
        header.pointee.cmsg_type = SCM_RIGHTS
        control.advanced(by: descriptorOffset).storeBytes(
            of: passedDescriptor,
            as: Int32.self
        )

        var payload: UInt8 = 0
        try withUnsafeMutablePointer(to: &payload) { payloadPointer in
            var vector = iovec(
                iov_base: UnsafeMutableRawPointer(payloadPointer),
                iov_len: 1
            )
            try withUnsafeMutablePointer(to: &vector) { vectorPointer in
                var message = msghdr()
                message.msg_iov = vectorPointer
                message.msg_iovlen = 1
                message.msg_control = control
                message.msg_controllen = socklen_t(controlSize)
                while true {
                    let sent = Darwin.sendmsg(controlDescriptor, &message, 0)
                    if sent == 1 { return }
                    if sent < 0, errno == EINTR { continue }
                    throw SFTPMuxSessionError.connectionClosed
                }
            }
        }
    }

    private static func validateHello(_ data: Data) throws {
        var reader = PacketReader(data: data)
        guard try reader.readUInt32() == muxMessageHello,
              try reader.readUInt32() == muxVersion else {
            throw SFTPMuxSessionError.protocolViolation
        }
        while !reader.isAtEnd {
            _ = try reader.readString()
            _ = try reader.readString()
        }
    }

    private static func validateAliveReply(
        _ data: Data,
        requestID: UInt32,
        expectedProcessID: Int32
    ) throws {
        var reader = PacketReader(data: data)
        guard try reader.readUInt32() == muxServerAlive,
              try reader.readUInt32() == requestID,
              try reader.readUInt32() == UInt32(expectedProcessID),
              reader.isAtEnd else {
            throw SFTPMuxSessionError.controlSocketRejected
        }
    }

    private static func validateSessionReply(
        _ data: Data,
        requestID: UInt32
    ) throws -> UInt32 {
        var reader = PacketReader(data: data)
        let type = try reader.readUInt32()
        guard try reader.readUInt32() == requestID else {
            throw SFTPMuxSessionError.protocolViolation
        }
        switch type {
        case muxServerSessionOpened:
            let sessionID = try reader.readUInt32()
            guard reader.isAtEnd else {
                throw SFTPMuxSessionError.protocolViolation
            }
            return sessionID
        case muxServerPermissionDenied, muxServerFailure:
            _ = try reader.readString()
            throw SFTPMuxSessionError.sessionRejected
        default:
            throw SFTPMuxSessionError.protocolViolation
        }
    }

    private static func packetBody(uint32Values: [UInt32]) -> Data {
        var result = Data()
        for value in uint32Values { appendUInt32(value, to: &result) }
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

    private static func alignedSize(_ size: Int, to alignment: Int) -> Int {
        (size + alignment - 1) & ~(alignment - 1)
    }
}
