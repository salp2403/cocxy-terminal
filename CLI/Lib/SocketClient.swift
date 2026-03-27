// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketClient.swift - Unix Domain Socket client for CLI companion.

import Foundation

// MARK: - Socket Client

/// Connects to the Cocxy Terminal app via its Unix Domain Socket and sends commands.
///
/// The client uses the same length-prefixed JSON protocol as the server:
/// ```
/// [4 bytes: payload length, big-endian UInt32][N bytes: JSON payload]
/// ```
///
/// Connection lifecycle: connect, send request, read response, disconnect.
/// The client does not maintain persistent connections.
public struct SocketClient {

    /// Path to the Unix Domain Socket file.
    public let socketPath: String

    /// Connection timeout in seconds.
    public let timeoutSeconds: TimeInterval

    /// Default socket path: ~/.config/cocxy/cocxy.sock
    public static let defaultSocketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/cocxy/cocxy.sock"
    }()

    /// Creates a socket client.
    ///
    /// - Parameters:
    ///   - socketPath: Path to the socket file. Defaults to `~/.config/cocxy/cocxy.sock`.
    ///   - timeoutSeconds: Connection timeout. Defaults to 5 seconds.
    public init(socketPath: String = SocketClient.defaultSocketPath, timeoutSeconds: TimeInterval = 5) {
        self.socketPath = socketPath
        self.timeoutSeconds = timeoutSeconds
    }

    /// Sends a request and returns the response.
    ///
    /// - Parameter request: The command request to send.
    /// - Returns: The server's response.
    /// - Throws: `CLIError` on connection failure, timeout, or protocol error.
    public func send(_ request: CLISocketRequest) throws -> CLISocketResponse {
        let fd = try connectToSocket()
        defer { Darwin.close(fd) }

        try writeRequest(request, to: fd)
        return try readResponse(from: fd)
    }

    // MARK: - Private: Connection

    /// Connects to the Unix Domain Socket.
    private func connectToSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIError.connectionFailed(
                reason: "Failed to create socket: \(String(cString: strerror(errno)))"
            )
        }

        // Set send/receive timeouts.
        var timeout = timeval(
            tv_sec: Int(timeoutSeconds),
            tv_usec: 0
        )
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        // Build the sockaddr_un structure.
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw CLIError.connectionFailed(reason: "Socket path exceeds maximum length")
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr)
            pathBytes.withUnsafeBufferPointer { buffer in
                rawPtr.copyMemory(from: buffer.baseAddress!, byteCount: buffer.count)
            }
        }

        // Connect.
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, addrLen)
            }
        }

        guard result == 0 else {
            let errorCode = errno
            Darwin.close(fd)

            if errorCode == ECONNREFUSED || errorCode == ENOENT {
                throw CLIError.appNotRunning
            } else if errorCode == EACCES {
                throw CLIError.permissionDenied
            } else {
                throw CLIError.connectionFailed(
                    reason: String(cString: strerror(errorCode))
                )
            }
        }

        return fd
    }

    // MARK: - Private: Write

    /// Writes a framed request to the socket, handling short writes.
    private func writeRequest(_ request: CLISocketRequest, to fd: Int32) throws {
        let framedData = try CLIMessageFraming.frame(request)

        var totalWritten = 0
        let count = framedData.count
        while totalWritten < count {
            let written = framedData.withUnsafeBytes { bufferPtr in
                let ptr = bufferPtr.baseAddress!.advanced(by: totalWritten)
                return Darwin.write(fd, ptr, count - totalWritten)
            }
            guard written > 0 else {
                throw CLIError.connectionFailed(reason: "Failed to write request to socket")
            }
            totalWritten += written
        }
    }

    // MARK: - Private: Read

    /// Reads a framed response from the socket.
    private func readResponse(from fd: Int32) throws -> CLISocketResponse {
        // Read the 4-byte length header.
        let headerData = try readExactly(fd: fd, count: CLIMessageFraming.headerSize)

        guard let payloadLength = CLIMessageFraming.decodeLength(headerData) else {
            throw CLIError.malformedResponse(reason: "Invalid length header")
        }

        guard payloadLength > 0, payloadLength <= CLIMessageFraming.maxPayloadSize else {
            throw CLIError.malformedResponse(
                reason: "Invalid payload length: \(payloadLength)"
            )
        }

        // Read the JSON payload.
        let payloadData = try readExactly(fd: fd, count: Int(payloadLength))

        return try JSONDecoder().decode(CLISocketResponse.self, from: payloadData)
    }

    /// Reads exactly `count` bytes from a file descriptor.
    private func readExactly(fd: Int32, count: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRead = 0

        while totalRead < count {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { bufferPtr in
                Darwin.read(fd, bufferPtr.baseAddress! + totalRead, count - totalRead)
            }

            if bytesRead < 0 {
                let errorCode = errno
                if errorCode == EAGAIN || errorCode == ETIMEDOUT {
                    throw CLIError.timeout
                }
                throw CLIError.connectionFailed(
                    reason: "Read failed: \(String(cString: strerror(errorCode)))"
                )
            }

            if bytesRead == 0 {
                throw CLIError.connectionFailed(reason: "Connection closed by server")
            }

            totalRead += bytesRead
        }

        return Data(buffer)
    }
}
