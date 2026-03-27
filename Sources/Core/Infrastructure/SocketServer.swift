// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketServer.swift - Unix Domain Socket server for CLI companion.

import Foundation

// MARK: - Socket Server

/// Concrete implementation of `CLISocketServing` using Unix Domain Sockets.
///
/// Security measures (see ADR-006 and THREAT-MODEL.md):
/// - Socket file permissions: `0600` (owner-only read/write).
/// - UID verification via `getpeereid()` on every connection.
/// - Closed command enum — no eval, no arbitrary execution.
/// - Stale socket cleanup on startup.
/// - Maximum 64 KB message size to prevent DoS.
/// - Maximum 10 concurrent connections.
/// - 30-second connection timeout.
///
/// ## Wire protocol
///
/// ```
/// [4 bytes: payload length, big-endian UInt32][N bytes: JSON payload]
/// ```
///
/// The server reads a `SocketRequest`, validates the command against
/// `CLICommandName`, dispatches to a `SocketCommandHandling` handler,
/// and sends back a `SocketResponse`.
///
/// ## Thread model
///
/// - The accept loop runs on a dedicated background `DispatchQueue`.
/// - Each client connection is handled on a separate concurrent queue.
/// - Command handling is delegated to the `SocketCommandHandling`
///   implementation, which is responsible for its own thread safety.
/// - Responses are written back on the connection's queue.
///
/// - SeeAlso: `CLISocketServing` protocol
/// - SeeAlso: `SocketCommandHandling` for command dispatch
/// - SeeAlso: ADR-006 (CLI communication)
@MainActor
final class SocketServerImpl: CLISocketServing {

    // MARK: - Properties

    /// Path to the Unix Domain Socket file.
    let socketPath: String

    /// Handler that processes validated commands.
    private let commandHandler: SocketCommandHandling

    /// The server socket file descriptor. -1 when not running.
    private var serverFD: Int32 = -1

    /// Whether the accept loop should continue.
    ///
    /// Uses `LockedValue` instead of a plain `Bool` because the accept loop
    /// checks this flag from a background thread via `shouldContinue()`.
    /// Using `DispatchQueue.main.sync` for this check caused contention
    /// when the main actor performed deallocation while the background
    /// loop was blocked waiting for main-thread access. (T-053)
    private let shouldAcceptConnectionsFlag = LockedValue<Bool>(false)

    /// Background queue for the accept loop.
    private let acceptQueue = DispatchQueue(
        label: "com.cocxy.socket.accept",
        qos: .utility
    )

    /// Tracks the number of active connections. Accessed from multiple threads.
    private let activeConnectionCount = LockedValue<Int>(0)

    /// Registered command handlers (from CLISocketServing protocol).
    private var registeredHandlers: [String: @Sendable (Data) -> CLIResponse] = [:]

    // MARK: - CLISocketServing: isRunning

    /// Whether the server is currently listening for connections.
    private(set) var isRunning: Bool = false

    // MARK: - Initialization

    /// Creates a socket server.
    ///
    /// - Parameters:
    ///   - socketPath: Path to the Unix Domain Socket file.
    ///     Defaults to `SocketServerConstants.socketPath`.
    ///   - commandHandler: The handler that processes validated commands.
    init(
        socketPath: String = SocketServerConstants.socketPath,
        commandHandler: SocketCommandHandling
    ) {
        self.socketPath = socketPath
        self.commandHandler = commandHandler
    }

    deinit {
        // Safety net: ensure resources are released even if stop() was not called.
        // This prevents socket file leaks and orphaned accept loops on deallocation.
        if isRunning {
            shouldAcceptConnectionsFlag.withLock { $0 = false }
            if serverFD >= 0 {
                Darwin.shutdown(serverFD, SHUT_RDWR)
                Darwin.close(serverFD)
            }
            removeStaleSocketFile()
        }
    }

    // MARK: - CLISocketServing: start

    /// Starts listening on the Unix Domain Socket.
    ///
    /// 1. Creates the socket directory if it does not exist.
    /// 2. Removes any stale socket file from a previous crash.
    /// 3. Creates the AF_UNIX socket.
    /// 4. Binds to the socket path with permissions `0600`.
    /// 5. Begins accepting connections in a background loop.
    ///
    /// - Throws: `CLISocketError.bindFailed` if the socket cannot be created.
    func start() throws {
        guard !isRunning else { return }

        try createSocketDirectory()
        removeStaleSocketFile()
        try bindSocket()
        startAcceptLoop()

        isRunning = true
    }

    // MARK: - CLISocketServing: stop

    /// Stops the server and removes the socket file.
    ///
    /// Closes the listening socket and removes the socket file from disk.
    /// Active connections are terminated when their next read/write fails.
    func stop() {
        guard isRunning else { return }

        shouldAcceptConnectionsFlag.withLock { $0 = false }

        if serverFD >= 0 {
            // Shutdown will cause the accept() call to return with an error,
            // breaking the accept loop.
            Darwin.shutdown(serverFD, SHUT_RDWR)
            Darwin.close(serverFD)
            serverFD = -1
        }

        removeStaleSocketFile()
        isRunning = false
    }

    // MARK: - CLISocketServing: registerHandler

    /// Registers a handler for a specific CLI command type.
    ///
    /// - Parameters:
    ///   - commandName: The command name string (e.g., "notify", "new-tab").
    ///   - handler: Closure that processes the command and returns a response.
    func registerHandler(
        for commandName: String,
        handler: @escaping @Sendable (Data) -> CLIResponse
    ) {
        registeredHandlers[commandName] = handler
    }

    // MARK: - Private: Socket Setup

    /// Creates the socket directory if it does not exist.
    private func createSocketDirectory() throws {
        let directory = (socketPath as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory) {
            try FileManager.default.createDirectory(
                atPath: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    /// Removes a stale socket file left from a previous crash.
    private nonisolated func removeStaleSocketFile() {
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    /// Creates, binds, and starts listening on the AF_UNIX socket.
    private func bindSocket() throws {
        // 1. Create socket.
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLISocketError.bindFailed(
                path: socketPath,
                reason: "socket() failed: \(String(cString: strerror(errno)))"
            )
        }

        // 2. Build the sockaddr_un structure.
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw CLISocketError.bindFailed(
                path: socketPath,
                reason: "Socket path exceeds maximum length"
            )
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr)
            pathBytes.withUnsafeBufferPointer { buffer in
                rawPtr.copyMemory(from: buffer.baseAddress!, byteCount: buffer.count)
            }
        }

        // 3. Set umask before bind to prevent TOCTOU race on socket permissions.
        //    The socket file is created by bind() with (0777 & ~umask) permissions.
        //    By setting umask to 0o177, the socket is created with 0600 directly.
        let previousUmask = Darwin.umask(0o177)

        // 4. Bind the socket (creates file with 0600 permissions due to umask).
        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, addrLen)
            }
        }

        // Restore previous umask immediately after bind.
        Darwin.umask(previousUmask)

        guard bindResult == 0 else {
            Darwin.close(fd)
            throw CLISocketError.bindFailed(
                path: socketPath,
                reason: "bind() failed: \(String(cString: strerror(errno)))"
            )
        }

        // 5. Explicit chmod as defense-in-depth (socket already created with 0600 via umask).
        chmod(socketPath, SocketServerConstants.socketPermissions)

        // 5. Start listening.
        guard Darwin.listen(fd, SocketServerConstants.listenBacklog) == 0 else {
            Darwin.close(fd)
            throw CLISocketError.bindFailed(
                path: socketPath,
                reason: "listen() failed: \(String(cString: strerror(errno)))"
            )
        }

        serverFD = fd
    }

    // MARK: - Private: Accept Loop

    /// Starts the background accept loop.
    private func startAcceptLoop() {
        shouldAcceptConnectionsFlag.withLock { $0 = true }
        let fd = serverFD
        let path = socketPath
        let handler = commandHandler
        let connCount = activeConnectionCount
        let flagRef = shouldAcceptConnectionsFlag

        acceptQueue.async {
            SocketConnectionHandler.acceptLoop(
                serverFD: fd,
                socketPath: path,
                commandHandler: handler,
                activeConnectionCount: connCount,
                shouldContinue: {
                    // Thread-safe read without main-thread synchronization.
                    // This avoids the deadlock risk of DispatchQueue.main.sync
                    // when the main actor is simultaneously deallocating this object.
                    flagRef.withLock { $0 }
                }
            )
        }
    }
}

// MARK: - Locked Value

/// A thread-safe wrapper for a value, using an NSLock.
///
/// Used for the connection count which is accessed from multiple
/// dispatch queues concurrently.
final class LockedValue<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

// MARK: - Connection Handler

/// Encapsulates the logic for handling socket connections.
///
/// This is a separate `nonisolated` enum to avoid `@MainActor` isolation
/// issues when running on background dispatch queues. All socket I/O
/// and connection lifecycle runs off the main actor.
///
/// Command dispatch to the `@MainActor`-isolated `SocketCommandHandling`
/// is done via `DispatchQueue.main.sync`.
enum SocketConnectionHandler {

    /// Runs the accept loop on a background queue.
    ///
    /// - Parameters:
    ///   - serverFD: The listening socket file descriptor.
    ///   - socketPath: The socket path (for context in error messages).
    ///   - commandHandler: The command handler to dispatch validated commands to.
    ///   - activeConnectionCount: Thread-safe connection counter.
    ///   - shouldContinue: Closure that returns whether to keep accepting.
    static func acceptLoop(
        serverFD: Int32,
        socketPath: String,
        commandHandler: SocketCommandHandling,
        activeConnectionCount: LockedValue<Int>,
        shouldContinue: @escaping () -> Bool
    ) {
        let connectionQueue = DispatchQueue(
            label: "com.cocxy.socket.connections",
            qos: .utility,
            attributes: .concurrent
        )

        while true {
            // Accept a new connection.
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.accept(serverFD, sockaddrPtr, &clientAddrLen)
                }
            }

            // Check if we should stop.
            guard shouldContinue() else { return }

            guard clientFD >= 0 else {
                // accept() failed -- server shutting down or transient error.
                continue
            }

            // Check connection limit.
            let canAccept = activeConnectionCount.withLock { count -> Bool in
                guard count < SocketServerConstants.maxConcurrentConnections else {
                    return false
                }
                count += 1
                return true
            }

            guard canAccept else {
                Darwin.close(clientFD)
                continue
            }

            // Handle the connection on a background queue.
            connectionQueue.async {
                handleConnection(
                    clientFD: clientFD,
                    commandHandler: commandHandler
                )
                activeConnectionCount.withLock { count in
                    count -= 1
                }
            }
        }
    }

    /// Handles a single client connection.
    ///
    /// 1. Verifies the peer's UID matches our UID.
    /// 2. Reads messages in a loop until the client disconnects.
    /// 3. Validates commands against `CLICommandName`.
    /// 4. Dispatches valid commands to the handler.
    /// 5. Sends responses back.
    static func handleConnection(
        clientFD: Int32,
        commandHandler: SocketCommandHandling
    ) {
        defer { Darwin.close(clientFD) }

        // CRITICAL SECURITY: Verify peer UID.
        guard authenticatePeer(clientFD: clientFD) else {
            return
        }

        // Set socket receive timeout.
        var timeout = timeval(
            tv_sec: Int(SocketServerConstants.connectionTimeoutSeconds),
            tv_usec: 0
        )
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        // Message read loop: supports multiple requests per connection.
        while true {
            // Read the 4-byte length header.
            guard let headerData = readExactly(fd: clientFD, count: SocketMessageFraming.headerSize) else {
                return // Client disconnected or read error.
            }

            guard let payloadLength = SocketMessageFraming.decodeLength(headerData) else {
                return
            }

            // Security: reject oversized messages.
            guard payloadLength > 0, payloadLength <= SocketMessageFraming.maxPayloadSize else {
                return
            }

            // Read the JSON payload.
            guard let payloadData = readExactly(fd: clientFD, count: Int(payloadLength)) else {
                return
            }

            // Try to decode the request. If JSON is malformed, send an error response.
            let response: SocketResponse
            if let request = try? JSONDecoder().decode(SocketRequest.self, from: payloadData) {
                response = processRequest(request, commandHandler: commandHandler)
            } else {
                response = SocketResponse.failure(
                    id: "unknown",
                    error: "Malformed JSON in request"
                )
            }

            // Write the response back.
            guard writeResponse(response, to: clientFD) else {
                return // Write failed -- client disconnected.
            }
        }
    }

    /// Verifies that the connecting peer has the same UID as this process.
    ///
    /// Uses `getpeereid()` to obtain the peer's effective UID and GID.
    /// If the UID does not match, the connection is rejected.
    ///
    /// - Parameter clientFD: The client socket file descriptor.
    /// - Returns: `true` if the peer is authenticated, `false` otherwise.
    private static func authenticatePeer(clientFD: Int32) -> Bool {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        let result = getpeereid(clientFD, &peerUID, &peerGID)

        guard result == 0 else {
            return false
        }

        let myUID = getuid()
        guard peerUID == myUID else {
            return false
        }

        return true
    }

    /// Reads exactly `count` bytes from a file descriptor.
    ///
    /// Handles partial reads by looping until all bytes are received.
    ///
    /// - Parameters:
    ///   - fd: The file descriptor to read from.
    ///   - count: The exact number of bytes to read.
    /// - Returns: The read data, or `nil` on error/disconnect.
    private static func readExactly(fd: Int32, count: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: count)
        var totalRead = 0

        while totalRead < count {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { bufferPtr in
                Darwin.read(fd, bufferPtr.baseAddress! + totalRead, count - totalRead)
            }
            if bytesRead <= 0 {
                return nil
            }
            totalRead += bytesRead
        }

        return Data(buffer)
    }

    /// Processes a request and returns a response.
    ///
    /// Validates the command against the closed `CLICommandName` enum.
    /// Unknown commands produce an error response, never a crash.
    ///
    /// The handler itself is `Sendable` and thread-safe. If the concrete
    /// handler needs main-actor access (e.g., to TabManager), it dispatches
    /// internally.
    private static func processRequest(
        _ request: SocketRequest,
        commandHandler: SocketCommandHandling
    ) -> SocketResponse {
        // Validate command against the closed enum.
        guard CLICommandName(rawValue: request.command) != nil else {
            return .failure(
                id: request.id,
                error: "Unknown command: \(request.command)"
            )
        }

        return commandHandler.handleCommand(request)
    }

    /// Writes a length-prefixed JSON response to a socket.
    ///
    /// - Parameters:
    ///   - response: The response to send.
    ///   - fd: The socket file descriptor to write to.
    /// - Returns: `true` if the write succeeded, `false` on error.
    private static func writeResponse(_ response: SocketResponse, to fd: Int32) -> Bool {
        guard let framedData = try? SocketMessageFraming.frame(response) else {
            return false
        }

        return writeAll(framedData, to: fd)
    }

    /// Writes all bytes to a file descriptor, handling short writes.
    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        var totalWritten = 0
        let count = data.count
        while totalWritten < count {
            let written = data.withUnsafeBytes { bufferPtr in
                let ptr = bufferPtr.baseAddress!.advanced(by: totalWritten)
                return Darwin.write(fd, ptr, count - totalWritten)
            }
            if written <= 0 {
                return false  // Error or connection closed
            }
            totalWritten += written
        }
        return true
    }
}
