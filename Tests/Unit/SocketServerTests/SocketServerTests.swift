// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketServerTests.swift - Tests for the Unix Domain Socket server.

import XCTest
@testable import CocxyTerminal

// MARK: - Mock Command Handler

/// Thread-safe spy that records commands and returns configurable responses.
///
/// Uses a lock to protect shared state because the handler is called
/// from a background thread (the socket connection queue) while the
/// test assertions read from the main thread.
final class MockSocketCommandHandler: SocketCommandHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var _receivedRequests: [SocketRequest] = []
    private var _stubbedResponse: SocketResponse?

    var receivedRequests: [SocketRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedRequests
    }

    var stubbedResponse: SocketResponse? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _stubbedResponse
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _stubbedResponse = newValue
        }
    }

    func handleCommand(_ request: SocketRequest) -> SocketResponse {
        lock.lock()
        _receivedRequests.append(request)
        let stubbed = _stubbedResponse
        lock.unlock()

        if let stubbed {
            return stubbed
        }
        return .ok(id: request.id, data: ["handled": "true"])
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        _receivedRequests.removeAll()
        _stubbedResponse = nil
    }
}

// MARK: - Socket Test Client

/// Helper that performs socket I/O on a background thread.
///
/// All socket operations (connect, send, read) are performed off the
/// main thread to avoid deadlocks with the server's accept loop.
enum SocketTestClient {

    /// Connects to the socket at the given path.
    ///
    /// - Parameter socketPath: Path to the Unix Domain Socket.
    /// - Returns: The connected file descriptor.
    static func connect(to socketPath: String) throws -> Int32 {
        let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientFD >= 0 else {
            throw NSError(domain: "test", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create client socket"
            ])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
            let rawPtr = UnsafeMutableRawPointer(sunPathPtr)
            pathBytes.withUnsafeBufferPointer { buffer in
                rawPtr.copyMemory(from: buffer.baseAddress!, byteCount: buffer.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(clientFD, sockaddrPtr, addrLen)
            }
        }

        guard result == 0 else {
            close(clientFD)
            throw NSError(domain: "test", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "Failed to connect: \(String(cString: strerror(errno)))"
            ])
        }

        return clientFD
    }

    /// Sends a framed request and reads the framed response from a socket FD.
    static func sendRequest(_ request: SocketRequest, on fd: Int32) throws -> SocketResponse {
        let framedRequest = try SocketMessageFraming.frame(request)

        // Write the framed request.
        let writeResult = framedRequest.withUnsafeBytes { bufferPtr in
            Darwin.write(fd, bufferPtr.baseAddress!, bufferPtr.count)
        }
        guard writeResult == framedRequest.count else {
            throw NSError(domain: "test", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Write failed"
            ])
        }

        return try readResponse(from: fd)
    }

    /// Reads a framed response from a socket FD.
    static func readResponse(from fd: Int32) throws -> SocketResponse {
        // Read the 4-byte response header.
        var headerBytes = [UInt8](repeating: 0, count: 4)
        let headerRead = Darwin.read(fd, &headerBytes, 4)
        guard headerRead == 4 else {
            throw NSError(domain: "test", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read response header (read \(headerRead))"
            ])
        }

        let payloadLength = SocketMessageFraming.decodeLength(Data(headerBytes))!

        // Read the payload.
        var payloadBytes = [UInt8](repeating: 0, count: Int(payloadLength))
        var totalRead = 0
        while totalRead < Int(payloadLength) {
            let bytesRead = payloadBytes.withUnsafeMutableBufferPointer { bufferPtr in
                Darwin.read(
                    fd,
                    bufferPtr.baseAddress! + totalRead,
                    Int(payloadLength) - totalRead
                )
            }
            guard bytesRead > 0 else {
                throw NSError(domain: "test", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to read response payload"
                ])
            }
            totalRead += bytesRead
        }

        return try JSONDecoder().decode(
            SocketResponse.self,
            from: Data(payloadBytes)
        )
    }

    /// Sends raw bytes (for testing malformed JSON) and reads the response.
    static func sendRawPayload(_ payload: Data, on fd: Int32) throws -> SocketResponse {
        let header = SocketMessageFraming.encodeLength(UInt32(payload.count))
        let framed = header + payload

        let writeResult = framed.withUnsafeBytes { bufferPtr in
            Darwin.write(fd, bufferPtr.baseAddress!, bufferPtr.count)
        }
        guard writeResult == framed.count else {
            throw NSError(domain: "test", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Write failed"
            ])
        }

        return try readResponse(from: fd)
    }

    /// Performs a complete round-trip: connect, send, read, close.
    ///
    /// Runs entirely on a background queue and returns via a completion.
    static func roundTrip(
        socketPath: String,
        request: SocketRequest,
        completion: @escaping (Result<SocketResponse, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let fd = try connect(to: socketPath)
                defer { Darwin.close(fd) }
                let response = try sendRequest(request, on: fd)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Socket Server Tests

/// Tests for `SocketServerImpl`.
///
/// Tests that need socket I/O use `SocketTestClient` to perform
/// operations on a background queue, avoiding main-thread deadlocks.
final class SocketServerTests: XCTestCase {

    private var testSocketPath: String!
    private var testSocketDirectory: String!

    override func setUp() {
        super.setUp()
        let uniqueID = UUID().uuidString.prefix(8)
        testSocketDirectory = NSTemporaryDirectory()
            .appending("cocxy-test-\(uniqueID)")
        testSocketPath = testSocketDirectory.appending("/test.sock")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testSocketPath)
        try? FileManager.default.removeItem(atPath: testSocketDirectory)
        testSocketPath = nil
        testSocketDirectory = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Creates and starts a server, returning it and the handler.
    @MainActor
    private func startServer(
        handler: MockSocketCommandHandler = MockSocketCommandHandler()
    ) throws -> (SocketServerImpl, MockSocketCommandHandler) {
        let server = SocketServerImpl(
            socketPath: testSocketPath,
            commandHandler: handler
        )
        try server.start()
        // Give the accept loop time to start.
        Thread.sleep(forTimeInterval: 0.05)
        return (server, handler)
    }

    /// Performs a round-trip request on a background queue and waits.
    private func performRoundTrip(
        request: SocketRequest,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> SocketResponse {
        let expectation = expectation(description: "Round-trip for \(request.id)")
        var result: Result<SocketResponse, Error>!

        SocketTestClient.roundTrip(
            socketPath: testSocketPath,
            request: request
        ) { r in
            result = r
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        switch result! {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    // MARK: - 1. Socket file creation with 0600 permissions

    @MainActor
    func testStartCreatesSocketFileWithCorrectPermissions() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let attributes = try FileManager.default.attributesOfItem(atPath: testSocketPath)
        let permissions = (attributes[.posixPermissions] as? Int) ?? 0
        let permBits = permissions & 0o777
        XCTAssertEqual(
            permBits, 0o600,
            "Socket permissions should be 0600 (owner-only), got \(String(permBits, radix: 8))"
        )
    }

    // MARK: - 2. Socket file cleanup on start (stale file)

    @MainActor
    func testStartRemovesStaleSocketFile() throws {
        try FileManager.default.createDirectory(
            atPath: testSocketDirectory,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: testSocketPath, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testSocketPath))

        let (server, _) = try startServer()
        defer { server.stop() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: testSocketPath))
        XCTAssertTrue(server.isRunning)
    }

    // MARK: - 3. UID authentication (same UID accepted)

    @MainActor
    func testSameUIDConnectionIsAccepted() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let request = SocketRequest(id: "uid-1", command: "status", params: nil)
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success, "Same-UID connection should be accepted")
        XCTAssertEqual(response.id, "uid-1")
    }

    // MARK: - 4. Unknown command produces error response

    @MainActor
    func testUnknownCommandReturnsErrorResponse() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let request = SocketRequest(
            id: "unk-1",
            command: "definitely-not-a-command",
            params: nil
        )
        let response = try performRoundTrip(request: request)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.id, "unk-1")
        XCTAssertNotNil(response.error)
        XCTAssertTrue(
            response.error?.contains("Unknown command") == true,
            "Error should mention unknown command, got: \(response.error ?? "nil")"
        )
    }

    // MARK: - 5. Malformed JSON produces error response

    @MainActor
    func testMalformedJSONReturnsErrorResponse() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let expectation = expectation(description: "Malformed JSON test")
        var result: Result<SocketResponse, Error>!

        DispatchQueue.global().async { [testSocketPath] in
            do {
                let fd = try SocketTestClient.connect(to: testSocketPath!)
                defer { Darwin.close(fd) }

                let badJSON = "{ this is not valid json }".data(using: .utf8)!
                let response = try SocketTestClient.sendRawPayload(badJSON, on: fd)
                result = .success(response)
            } catch {
                result = .failure(error)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        let response = try result!.get()
        XCTAssertFalse(response.success)
        XCTAssertNotNil(response.error)
    }

    // MARK: - 6. Notify command dispatched to handler

    @MainActor
    func testNotifyCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(
            id: "notify-1",
            command: "notify",
            params: ["message": "Build completed"]
        )
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)

        // Give the handler time to record.
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.count, 1)
        XCTAssertEqual(handler.receivedRequests.first?.command, "notify")
        XCTAssertEqual(handler.receivedRequests.first?.params?["message"], "Build completed")
    }

    // MARK: - 7. List-tabs command dispatched to handler

    @MainActor
    func testListTabsCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(id: "lt-1", command: "list-tabs", params: nil)
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "list-tabs")
    }

    // MARK: - 8. Status command dispatched to handler

    @MainActor
    func testStatusCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(id: "st-1", command: "status", params: nil)
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "status")
    }

    // MARK: - 9. Server lifecycle: isRunning

    @MainActor
    func testServerIsNotRunningBeforeStart() {
        let handler = MockSocketCommandHandler()
        let server = SocketServerImpl(
            socketPath: testSocketPath,
            commandHandler: handler
        )
        XCTAssertFalse(server.isRunning)
    }

    @MainActor
    func testServerIsRunningAfterStart() throws {
        let (server, _) = try startServer()
        defer { server.stop() }
        XCTAssertTrue(server.isRunning)
    }

    @MainActor
    func testServerIsNotRunningAfterStop() throws {
        let (server, _) = try startServer()
        server.stop()
        XCTAssertFalse(server.isRunning)
    }

    // MARK: - 10. Socket file cleanup on stop

    @MainActor
    func testStopRemovesSocketFile() throws {
        let (server, _) = try startServer()
        XCTAssertTrue(FileManager.default.fileExists(atPath: testSocketPath))

        server.stop()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: testSocketPath),
            "Socket file should be removed after stop"
        )
    }

    // MARK: - 11. Multiple sequential requests on same connection

    @MainActor
    func testMultipleRequestsOnSameConnection() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let expectation = expectation(description: "Multiple requests")
        var responses: [SocketResponse] = []

        DispatchQueue.global().async { [testSocketPath] in
            do {
                let fd = try SocketTestClient.connect(to: testSocketPath!)
                defer { Darwin.close(fd) }

                let req1 = SocketRequest(id: "multi-1", command: "status", params: nil)
                responses.append(try SocketTestClient.sendRequest(req1, on: fd))

                let req2 = SocketRequest(id: "multi-2", command: "notify", params: ["message": "hi"])
                responses.append(try SocketTestClient.sendRequest(req2, on: fd))
            } catch {
                XCTFail("Error: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(responses.count, 2)
        XCTAssertEqual(responses[0].id, "multi-1")
        XCTAssertTrue(responses[0].success)
        XCTAssertEqual(responses[1].id, "multi-2")
        XCTAssertTrue(responses[1].success)

        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.count, 2)
    }

    // MARK: - 12. Multiple concurrent connections

    @MainActor
    func testMultipleConcurrentConnections() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let group = DispatchGroup()
        var results: [SocketResponse] = []
        let resultsLock = NSLock()

        for i in 0..<3 {
            group.enter()
            DispatchQueue.global().async { [testSocketPath] in
                defer { group.leave() }
                do {
                    let fd = try SocketTestClient.connect(to: testSocketPath!)
                    defer { Darwin.close(fd) }

                    let req = SocketRequest(id: "conc-\(i)", command: "status", params: nil)
                    let resp = try SocketTestClient.sendRequest(req, on: fd)

                    resultsLock.lock()
                    results.append(resp)
                    resultsLock.unlock()
                } catch {
                    XCTFail("Connection \(i) failed: \(error)")
                }
            }
        }

        let expectation = expectation(description: "Concurrent connections")
        group.notify(queue: .main) { expectation.fulfill() }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy(\.success))
    }

    // MARK: - 13. Handler returning error propagates correctly

    @MainActor
    func testHandlerErrorResponsePropagatesCorrectly() throws {
        let handler = MockSocketCommandHandler()
        handler.stubbedResponse = .failure(id: "err-stub", error: "Tab not found")

        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(
            id: "err-stub",
            command: "focus-tab",
            params: ["id": "nonexistent"]
        )
        let response = try performRoundTrip(request: request)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Tab not found")
    }

    // MARK: - 14. Double start is idempotent

    @MainActor
    func testDoubleStartDoesNotCrash() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        do {
            try server.start()
        } catch {
            // Acceptable: server is already running.
        }

        XCTAssertTrue(server.isRunning)
    }

    // MARK: - 15. Double stop is safe

    @MainActor
    func testDoubleStopDoesNotCrash() throws {
        let (server, _) = try startServer()
        server.stop()
        server.stop()

        XCTAssertFalse(server.isRunning)
    }

    // MARK: - 16. Socket directory is created if missing

    @MainActor
    func testStartCreatesSocketDirectoryIfMissing() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: testSocketDirectory))

        let (server, _) = try startServer()
        defer { server.stop() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: testSocketDirectory))
        XCTAssertTrue(FileManager.default.fileExists(atPath: testSocketPath))
    }

    // MARK: - 17. New-tab command dispatched

    @MainActor
    func testNewTabCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(id: "nt-1", command: "new-tab", params: ["dir": "/tmp"])
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "new-tab")
    }

    // MARK: - 18. Focus-tab command dispatched

    @MainActor
    func testFocusTabCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(id: "ft-1", command: "focus-tab", params: ["id": "some-uuid"])
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "focus-tab")
    }

    // MARK: - 19. Close-tab command dispatched

    @MainActor
    func testCloseTabCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(id: "ct-1", command: "close-tab", params: ["id": "some-uuid"])
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "close-tab")
    }

    // MARK: - 20. Split command dispatched

    @MainActor
    func testSplitCommandIsDispatchedToHandler() throws {
        let handler = MockSocketCommandHandler()
        let (server, _) = try startServer(handler: handler)
        defer { server.stop() }

        let request = SocketRequest(
            id: "sp-1",
            command: "split",
            params: ["direction": "horizontal"]
        )
        let response = try performRoundTrip(request: request)

        XCTAssertTrue(response.success)
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(handler.receivedRequests.first?.command, "split")
    }

    // MARK: - 21. Request ID is preserved in response

    @MainActor
    func testRequestIDIsPreservedInResponse() throws {
        let (server, _) = try startServer()
        defer { server.stop() }

        let uniqueID = UUID().uuidString
        let request = SocketRequest(id: uniqueID, command: "status", params: nil)
        let response = try performRoundTrip(request: request)

        XCTAssertEqual(response.id, uniqueID)
    }

    // MARK: - 22. CLISocketError cases

    func testCLISocketErrorCases() {
        let bindError = CLISocketError.bindFailed(
            path: "/test/path",
            reason: "Permission denied"
        )
        let authError = CLISocketError.authenticationFailed(
            expectedUID: 501,
            actualUID: 502
        )
        let unknownError = CLISocketError.unknownCommand("foobar")
        let malformedError = CLISocketError.malformedMessage(reason: "Invalid JSON")

        XCTAssertNotNil(bindError as Error)
        XCTAssertNotNil(authError as Error)
        XCTAssertNotNil(unknownError as Error)
        XCTAssertNotNil(malformedError as Error)
    }
}
