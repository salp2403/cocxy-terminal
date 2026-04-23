// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketServerRegressionSwiftTestingTests.swift
//
// Regression coverage for two bugs uncovered during v0.1.82 smoke
// testing against a long-running production instance:
//
//   1. `listenBacklog = 5` dropped ~80% of concurrent connects once the
//      kernel backlog saturated. The CLI and Claude Code hooks share one
//      socket and frequently burst, so we bump the backlog to 128
//      (`SOMAXCONN` on macOS).
//
//   2. Socket `acceptQueue` / `connectionQueue` ran at QoS `.utility`,
//      which starved under sustained Aurora reconciliation, Metal render,
//      and PTY workloads. After long uptime the accept loop would not
//      run in time to serve a connect that was already in the kernel
//      queue, so the peer saw `EPIPE` on the first write. Raising the
//      queues to `.userInitiated` aligns scheduling with the interactive
//      nature of CLI requests.
//
//   3. The accept loop still accepted and immediately closed connections once
//      `maxConcurrentConnections` was reached. That bypassed the enlarged
//      listen backlog and surfaced as EPIPE for bursts larger than the active
//      worker cap. The server now waits for an active slot before accepting
//      another client, leaving excess peers queued in the kernel backlog.
//
// Both scenarios previously were invisible to the test suite because
// every existing test writes immediately after connect and uses a single
// connection at a time.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Test Infrastructure

/// Thread-safe counter used across concurrent connection attempts.
private final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int = 0
    var current: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func increment() {
        lock.lock(); defer { lock.unlock() }
        value += 1
    }
}

/// Thread-safe spy handler. Mirrors `MockSocketCommandHandler` from the
/// sibling XCTest file — replicated here to keep the Swift Testing suite
/// self-contained and avoid leaking `@testable` internals across targets.
private final class SpyCommandHandler: SocketCommandHandling, @unchecked Sendable {
    private let lock = NSLock()
    private var _count: Int = 0
    private let responseDelay: TimeInterval

    init(responseDelay: TimeInterval = 0) {
        self.responseDelay = responseDelay
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }
    func handleCommand(_ request: SocketRequest) -> SocketResponse {
        if responseDelay > 0 {
            Thread.sleep(forTimeInterval: responseDelay)
        }
        lock.lock()
        _count += 1
        lock.unlock()
        return .ok(id: request.id, data: ["handled": "true"])
    }
}

/// Utility: builds a unique temp socket path for each test case so
/// parallel tests don't collide, mirroring `SocketServerTests.setUp`.
private func uniqueSocketPath() -> (directory: String, path: String) {
    let uniqueID = UUID().uuidString.prefix(8)
    let directory = NSTemporaryDirectory()
        .appending("cocxy-swift-test-\(uniqueID)")
    let path = directory.appending("/test.sock")
    return (directory, path)
}

/// Cleans up the directory created by `uniqueSocketPath`.
private func removeTempDirectory(_ directory: String, socketPath: String) {
    try? FileManager.default.removeItem(atPath: socketPath)
    try? FileManager.default.removeItem(atPath: directory)
}

/// Client helper that connects to a Unix socket and returns the fd.
/// Runs off the main thread because socket I/O is blocking.
private func connectClient(to socketPath: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw NSError(domain: "test", code: Int(errno), userInfo: [
            NSLocalizedDescriptionKey: "socket() failed: \(String(cString: strerror(errno)))"
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
            Darwin.connect(fd, sockaddrPtr, addrLen)
        }
    }
    guard result == 0 else {
        Darwin.close(fd)
        throw NSError(domain: "test", code: Int(errno), userInfo: [
            NSLocalizedDescriptionKey: "connect() failed: \(String(cString: strerror(errno)))"
        ])
    }
    return fd
}

/// Sends a framed request and reads the framed response.
@discardableResult
private func sendFramedRequest(
    _ request: SocketRequest,
    on fd: Int32
) throws -> SocketResponse {
    let framedRequest = try SocketMessageFraming.frame(request)

    var totalWritten = 0
    let count = framedRequest.count
    while totalWritten < count {
        let written = framedRequest.withUnsafeBytes { bufferPtr -> Int in
            let ptr = bufferPtr.baseAddress!.advanced(by: totalWritten)
            return Darwin.write(fd, ptr, count - totalWritten)
        }
        guard written > 0 else {
            throw NSError(domain: "test", code: Int(errno), userInfo: [
                NSLocalizedDescriptionKey: "write() returned \(written) errno=\(errno)"
            ])
        }
        totalWritten += written
    }

    // Read 4-byte header.
    var header = [UInt8](repeating: 0, count: 4)
    let headerRead = header.withUnsafeMutableBufferPointer { bufferPtr in
        Darwin.read(fd, bufferPtr.baseAddress!, 4)
    }
    guard headerRead == 4 else {
        throw NSError(domain: "test", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to read header: read=\(headerRead)"
        ])
    }
    guard let payloadLength = SocketMessageFraming.decodeLength(Data(header)) else {
        throw NSError(domain: "test", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Invalid header"
        ])
    }

    var payload = [UInt8](repeating: 0, count: Int(payloadLength))
    var totalRead = 0
    while totalRead < Int(payloadLength) {
        let bytesRead = payload.withUnsafeMutableBufferPointer { bufferPtr in
            Darwin.read(fd, bufferPtr.baseAddress! + totalRead, Int(payloadLength) - totalRead)
        }
        guard bytesRead > 0 else {
            throw NSError(domain: "test", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read payload at \(totalRead)"
            ])
        }
        totalRead += bytesRead
    }

    return try JSONDecoder().decode(SocketResponse.self, from: Data(payload))
}

/// Waits for the socket file to exist and accept a test connect.
private func waitUntilReady(socketPath: String, timeout: TimeInterval = 2.0) throws {
    let deadline = Date().addingTimeInterval(timeout)
    var lastError: Error?
    while Date() < deadline {
        if FileManager.default.fileExists(atPath: socketPath) {
            do {
                let fd = try connectClient(to: socketPath)
                Darwin.close(fd)
                return
            } catch {
                lastError = error
            }
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    throw lastError ?? NSError(domain: "test", code: -1, userInfo: [
        NSLocalizedDescriptionKey: "Socket not ready at \(socketPath)"
    ])
}

// MARK: - Regression Suite

/// Each test suite acquires its own `SocketServerImpl` on a unique temp
/// path. `.serialized` avoids main-actor contention between suites that
/// both start a server on separate paths but share the test runner's
/// dispatch pool.
@Suite("SocketServer regression", .serialized)
@MainActor
struct SocketServerRegressionSwiftTestingTests {

    // MARK: - Bug B regression: delayed first write must not fail.

    /// Reproduces the production symptom where the CLI's Swift runtime
    /// startup introduces ~1-20ms between `connect()` and the first
    /// `write()`. Under the pre-fix `.utility` QoS, the accept loop would
    /// pick up the connection too slowly to keep the peer alive — causing
    /// the CLI to see `EPIPE`. With `.userInitiated` this passes
    /// deterministically.
    @Test("delayed first write after connect succeeds (Bug B)")
    func delayedFirstWriteAfterConnectSucceeds() async throws {
        let tempPaths = uniqueSocketPath()
        defer {
            removeTempDirectory(tempPaths.directory, socketPath: tempPaths.path)
        }

        let handler = SpyCommandHandler()
        let server = SocketServerImpl(
            socketPath: tempPaths.path,
            commandHandler: handler
        )
        try server.start()
        defer { server.stop() }
        try waitUntilReady(socketPath: tempPaths.path)

        // Run the client on a background queue and idle 100ms between
        // connect and write. 100ms exceeds any realistic CLI startup cost.
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SocketResponse, Error>) in
            let path = tempPaths.path
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fd = try connectClient(to: path)
                    defer { Darwin.close(fd) }
                    Thread.sleep(forTimeInterval: 0.100)
                    let request = SocketRequest(
                        id: "delayed-1",
                        command: "status",
                        params: nil
                    )
                    let resp = try sendFramedRequest(request, on: fd)
                    continuation.resume(returning: resp)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        #expect(response.id == "delayed-1")
        #expect(response.success == true)
    }

    // MARK: - Bug A regression: listen backlog absorbs concurrent connects.

    /// Reproduces the production symptom where bursts of hook events combined
    /// with CLI invocations exceed the active worker cap. The server must let
    /// the kernel backlog absorb the excess instead of accepting and closing
    /// connections once 10 workers are busy.
    @Test("kernel backlog absorbs bursts larger than the active worker cap (Bug A/C)")
    func backlogAbsorbsConcurrentConnects() async throws {
        // Ignore SIGPIPE so a broken write returns errno=EPIPE rather
        // than terminating the xctest process (signal 13). Signal
        // handlers are process-global, so we save the previous handler
        // and restore it on exit to keep test isolation — without this,
        // later tests that rely on the default SIGPIPE behaviour would
        // silently observe our override.
        let previousSIGPIPE = signal(SIGPIPE, SIG_IGN)
        defer { _ = signal(SIGPIPE, previousSIGPIPE) }

        let tempPaths = uniqueSocketPath()
        defer {
            removeTempDirectory(tempPaths.directory, socketPath: tempPaths.path)
        }

        let handler = SpyCommandHandler(responseDelay: 0.05)
        let server = SocketServerImpl(
            socketPath: tempPaths.path,
            commandHandler: handler
        )
        try server.start()
        defer { server.stop() }
        try waitUntilReady(socketPath: tempPaths.path)

        // Deliberately exceed `maxConcurrentConnections` (10). The extra
        // clients should wait in listenBacklog and all complete successfully.
        let concurrency = 30
        let successes = AtomicInt()
        let failures = AtomicInt()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<concurrency {
                let path = tempPaths.path
                group.addTask {
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let fd = try connectClient(to: path)
                                defer { Darwin.close(fd) }
                                let request = SocketRequest(
                                    id: "burst-\(i)",
                                    command: "status",
                                    params: nil
                                )
                                let resp = try sendFramedRequest(request, on: fd)
                                if resp.success {
                                    successes.increment()
                                } else {
                                    failures.increment()
                                }
                            } catch {
                                failures.increment()
                            }
                            continuation.resume()
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(
            successes.current == concurrency,
            "Expected \(concurrency) concurrent successes, got \(successes.current) (failures=\(failures.current)). This test fails if the accept loop closes excess clients instead of letting listenBacklog queue them."
        )
        #expect(failures.current == 0)
    }
}
