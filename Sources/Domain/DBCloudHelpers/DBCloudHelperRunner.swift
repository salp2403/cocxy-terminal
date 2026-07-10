// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperRunner.swift - Bounded asynchronous execution for DB/cloud helper actions.

import Darwin
import Foundation

enum DBCloudHelperExecutionError: Error, LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case timedOut(seconds: TimeInterval)
    case credentialStorageUnavailable
    case standardInputWriteFailed
    case outputReadFailed
    case processDidNotTerminate

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "The helper execution limits are invalid."
        case .timedOut(let seconds):
            return "The helper timed out after \(Self.formatted(seconds)) seconds."
        case .credentialStorageUnavailable:
            return "A protected PostgreSQL credential file could not be prepared."
        case .standardInputWriteFailed:
            return "The query could not be sent to the helper."
        case .outputReadFailed:
            return "The helper output could not be read safely."
        case .processDidNotTerminate:
            return "The helper process did not terminate cleanly."
        }
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        seconds.rounded() == seconds ? String(Int(seconds)) : String(format: "%.1f", seconds)
    }
}

struct DBCloudHelperRunnerConfiguration: Equatable, Sendable {
    static let defaultTimeoutSeconds: TimeInterval = 30
    static let defaultMaximumRetainedBytesPerStream = 1 * 1_024 * 1_024

    let timeoutSeconds: TimeInterval
    let terminationGracePeriodSeconds: TimeInterval
    let maximumRetainedBytesPerStream: Int
    let credentialTemporaryDirectory: URL?

    init(
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
        terminationGracePeriodSeconds: TimeInterval = 1,
        maximumRetainedBytesPerStream: Int = defaultMaximumRetainedBytesPerStream,
        credentialTemporaryDirectory: URL? = nil
    ) {
        self.timeoutSeconds = timeoutSeconds
        self.terminationGracePeriodSeconds = terminationGracePeriodSeconds
        self.maximumRetainedBytesPerStream = maximumRetainedBytesPerStream
        self.credentialTemporaryDirectory = credentialTemporaryDirectory
    }

    var isValid: Bool {
        timeoutSeconds.isFinite
            && timeoutSeconds > 0
            && terminationGracePeriodSeconds.isFinite
            && terminationGracePeriodSeconds > 0
            && maximumRetainedBytesPerStream > 0
    }
}

struct LocalDBCloudHelperRunner: Sendable {
    private static let maximumIOBytesPerCycle = 256 * 1_024
    private static let executionQueue = DispatchQueue(
        label: "dev.cocxy.db-cloud-helper-runner",
        qos: .userInitiated,
        attributes: .concurrent
    )

    let configuration: DBCloudHelperRunnerConfiguration

    init(configuration: DBCloudHelperRunnerConfiguration = DBCloudHelperRunnerConfiguration()) {
        self.configuration = configuration
    }

    func run(_ command: DBCloudHelperCommand) async throws -> DBCloudHelperRunResult {
        guard configuration.isValid else {
            throw DBCloudHelperExecutionError.invalidConfiguration
        }
        if let input = command.standardInput,
           input.count > DBCloudHelperCommand.maximumStandardInputBytes {
            throw DBCloudHelperError.queryTooLarge(
                limitBytes: DBCloudHelperCommand.maximumStandardInputBytes
            )
        }

        let cancellation = DBCloudHelperCancellationState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                Self.executionQueue.async {
                    do {
                        continuation.resume(
                            returning: try Self.execute(
                                command,
                                configuration: configuration,
                                cancellation: cancellation
                            )
                        )
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func execute(
        _ command: DBCloudHelperCommand,
        configuration: DBCloudHelperRunnerConfiguration,
        cancellation: DBCloudHelperCancellationState
    ) throws -> DBCloudHelperRunResult {
        if cancellation.isCancelled {
            throw CancellationError()
        }

        let credentialFile = try DBCloudHelperCredentialFile.create(
            for: command.credentialMaterial,
            baseDirectory: configuration.credentialTemporaryDirectory
        )
        defer { credentialFile?.remove() }

        let process = Process()
        if command.executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
        }

        var environment = ProcessInfo.processInfo.environment
        if command.executable == "psql"
            || URL(fileURLWithPath: command.executable).lastPathComponent == "psql" {
            environment.removeValue(forKey: "PGPASSWORD")
        }
        if let credentialFile {
            environment.removeValue(forKey: "PGPASSWORD")
            environment["PGPASSFILE"] = credentialFile.fileURL.path
        }
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = command.standardInput.map { _ in Pipe() }
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe ?? FileHandle.nullDevice

        let stdoutRead = stdoutPipe.fileHandleForReading
        let stdoutWrite = stdoutPipe.fileHandleForWriting
        let stderrRead = stderrPipe.fileHandleForReading
        let stderrWrite = stderrPipe.fileHandleForWriting
        let stdinRead = stdinPipe?.fileHandleForReading
        let stdinWrite = stdinPipe?.fileHandleForWriting

        defer {
            try? stdoutRead.close()
            try? stdoutWrite.close()
            try? stderrRead.close()
            try? stderrWrite.close()
            try? stdinRead?.close()
            try? stdinWrite?.close()
        }

        try setNonBlocking(stdoutRead.fileDescriptor)
        try setNonBlocking(stderrRead.fileDescriptor)
        if let stdinWrite {
            try setNonBlocking(stdinWrite.fileDescriptor)
            guard fcntl(stdinWrite.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else {
                throw DBCloudHelperExecutionError.invalidConfiguration
            }
        }

        let termination = DBCloudHelperTerminationState()
        process.terminationHandler = { _ in termination.markTerminated() }

        if cancellation.isCancelled {
            throw CancellationError()
        }
        do {
            try process.run()
        } catch {
            try? stdoutWrite.close()
            try? stderrWrite.close()
            try? stdinRead?.close()
            throw error
        }

        try? stdoutWrite.close()
        try? stderrWrite.close()
        try? stdinRead?.close()

        var stdoutCapture = DBCloudHelperCapturedStream()
        var stderrCapture = DBCloudHelperCapturedStream()
        var stdoutBuffer = [UInt8](repeating: 0, count: 32 * 1_024)
        var stderrBuffer = [UInt8](repeating: 0, count: 32 * 1_024)
        var stdoutOpen = true
        var stderrOpen = true
        var stdinOpen = stdinWrite != nil
        var inputOffset = 0
        var inputWriteFailed = false
        let input = command.standardInput ?? Data()

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let executionDeadline = adding(
            nanoseconds(configuration.timeoutSeconds),
            to: startedAt
        )
        let graceNanoseconds = nanoseconds(configuration.terminationGracePeriodSeconds)
        var stopReason: DBCloudHelperStopReason?
        var terminateDeadline: UInt64?
        var sentKill = false
        var postExitDeadline: UInt64?

        while true {
            let now = DispatchTime.now().uptimeNanoseconds

            if stopReason == nil {
                if cancellation.isCancelled {
                    stopReason = .cancelled
                } else if now >= executionDeadline {
                    stopReason = .timedOut
                }
            }

            let didTerminate = termination.isTerminated
            if didTerminate {
                if stdinOpen {
                    try? stdinWrite?.close()
                    stdinOpen = false
                }
                if postExitDeadline == nil {
                    postExitDeadline = adding(graceNanoseconds, to: now)
                }
            } else if stopReason != nil, terminateDeadline == nil {
                if stdinOpen {
                    try? stdinWrite?.close()
                    stdinOpen = false
                }
                process.terminate()
                terminateDeadline = adding(graceNanoseconds, to: now)
            } else if let deadline = terminateDeadline, now >= deadline, !sentKill {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                sentKill = true
                terminateDeadline = adding(graceNanoseconds, to: now)
            } else if let deadline = terminateDeadline,
                      now >= deadline,
                      sentKill,
                      !didTerminate {
                if stdoutOpen { try? stdoutRead.close() }
                if stderrOpen { try? stderrRead.close() }
                throw DBCloudHelperExecutionError.processDidNotTerminate
            }

            if didTerminate, !stdoutOpen, !stderrOpen {
                break
            }
            if didTerminate,
               let deadline = postExitDeadline,
               now >= deadline {
                if stdoutOpen { try? stdoutRead.close(); stdoutOpen = false }
                if stderrOpen { try? stderrRead.close(); stderrOpen = false }
                break
            }

            var descriptors = [
                pollfd(
                    fd: stdoutOpen ? stdoutRead.fileDescriptor : -1,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                ),
                pollfd(
                    fd: stderrOpen ? stderrRead.fileDescriptor : -1,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                ),
                pollfd(
                    fd: stdinOpen ? (stdinWrite?.fileDescriptor ?? -1) : -1,
                    events: stdinOpen ? Int16(POLLOUT | POLLHUP | POLLERR) : 0,
                    revents: 0
                ),
            ]

            let pollResult = descriptors.withUnsafeMutableBufferPointer { buffer in
                Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), 20)
            }
            if pollResult < 0 {
                if errno == EINTR { continue }
                stopReason = .failed(.outputReadFailed)
                continue
            }
            guard pollResult > 0 else { continue }

            if stdoutOpen, descriptors[0].revents != 0 {
                switch readAvailable(
                    from: stdoutRead.fileDescriptor,
                    into: &stdoutCapture,
                    buffer: &stdoutBuffer,
                    retainingAtMost: configuration.maximumRetainedBytesPerStream
                ) {
                case .open:
                    break
                case .closed:
                    try? stdoutRead.close()
                    stdoutOpen = false
                case .failed:
                    stopReason = stopReason ?? .failed(.outputReadFailed)
                }
            }

            if stderrOpen, descriptors[1].revents != 0 {
                switch readAvailable(
                    from: stderrRead.fileDescriptor,
                    into: &stderrCapture,
                    buffer: &stderrBuffer,
                    retainingAtMost: configuration.maximumRetainedBytesPerStream
                ) {
                case .open:
                    break
                case .closed:
                    try? stderrRead.close()
                    stderrOpen = false
                case .failed:
                    stopReason = stopReason ?? .failed(.outputReadFailed)
                }
            }

            if stdinOpen, descriptors[2].revents != 0 {
                if descriptors[2].revents & Int16(POLLOUT) != 0,
                   inputOffset < input.count {
                    switch writeAvailable(
                        input,
                        offset: &inputOffset,
                        to: stdinWrite?.fileDescriptor ?? -1
                    ) {
                    case .open:
                        break
                    case .closed, .failed:
                        inputWriteFailed = inputOffset < input.count
                        try? stdinWrite?.close()
                        stdinOpen = false
                    }
                }

                if inputOffset >= input.count
                    || descriptors[2].revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                    if inputOffset < input.count {
                        inputWriteFailed = true
                    }
                    try? stdinWrite?.close()
                    stdinOpen = false
                }
            }
        }

        process.waitUntilExit()

        if let stopReason {
            switch stopReason {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw DBCloudHelperExecutionError.timedOut(
                    seconds: configuration.timeoutSeconds
                )
            case .failed(let error):
                throw error
            }
        }

        if process.terminationStatus == 0,
           (inputWriteFailed || inputOffset < input.count) {
            throw DBCloudHelperExecutionError.standardInputWriteFailed
        }

        return DBCloudHelperRunResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutCapture.data, as: UTF8.self),
            stderr: String(decoding: stderrCapture.data, as: UTF8.self),
            stdoutBytesRead: stdoutCapture.totalBytes,
            stderrBytesRead: stderrCapture.totalBytes,
            stdoutTruncated: stdoutCapture.wasTruncated,
            stderrTruncated: stderrCapture.wasTruncated
        )
    }

    private static func setNonBlocking(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw DBCloudHelperExecutionError.invalidConfiguration
        }
    }

    private static func readAvailable(
        from descriptor: Int32,
        into capture: inout DBCloudHelperCapturedStream,
        buffer: inout [UInt8],
        retainingAtMost limit: Int
    ) -> DBCloudHelperDescriptorState {
        var bytesRead = 0
        while bytesRead < maximumIOBytesPerCycle {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                capture.append(buffer, count: count, retainingAtMost: limit)
                bytesRead += count
                continue
            }
            if count == 0 { return .closed }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return .open }
            return .failed
        }
        return .open
    }

    private static func writeAvailable(
        _ data: Data,
        offset: inout Int,
        to descriptor: Int32
    ) -> DBCloudHelperDescriptorState {
        guard descriptor >= 0 else { return .failed }
        var bytesWritten = 0
        while offset < data.count, bytesWritten < maximumIOBytesPerCycle {
            let count = data.withUnsafeBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset
                )
            }
            if count > 0 {
                offset += count
                bytesWritten += count
                continue
            }
            if count == 0 { return .open }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return .open }
            if errno == EPIPE { return .closed }
            return .failed
        }
        return offset >= data.count ? .closed : .open
    }

    private static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        let maximumSeconds = Double(UInt64.max) / 1_000_000_000
        return UInt64(min(seconds, maximumSeconds) * 1_000_000_000)
    }

    private static func adding(_ value: UInt64, to base: UInt64) -> UInt64 {
        base > UInt64.max - value ? UInt64.max : base + value
    }
}

private enum DBCloudHelperDescriptorState {
    case open
    case closed
    case failed
}

private enum DBCloudHelperStopReason {
    case cancelled
    case timedOut
    case failed(DBCloudHelperExecutionError)
}

private struct DBCloudHelperCapturedStream {
    private(set) var data = Data()
    private(set) var totalBytes: Int64 = 0
    private(set) var wasTruncated = false

    mutating func append(
        _ buffer: [UInt8],
        count: Int,
        retainingAtMost limit: Int
    ) {
        let count64 = Int64(count)
        totalBytes = totalBytes > Int64.max - count64 ? Int64.max : totalBytes + count64

        let remaining = max(0, limit - data.count)
        let retainedCount = min(count, remaining)
        if retainedCount > 0 {
            data.append(contentsOf: buffer.prefix(retainedCount))
        }
        if retainedCount < count {
            wasTruncated = true
        }
    }
}

private final class DBCloudHelperCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

private final class DBCloudHelperTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false

    var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }

    func markTerminated() {
        lock.lock()
        terminated = true
        lock.unlock()
    }
}

private struct DBCloudHelperCredentialFile {
    let directoryURL: URL
    let fileURL: URL

    static func create(
        for material: DBCloudHelperCredentialMaterial?,
        baseDirectory: URL?
    ) throws -> DBCloudHelperCredentialFile? {
        guard let material else { return nil }
        let contents: Data
        switch material {
        case .postgreSQLPassfile(let data):
            contents = data
        }

        let base = baseDirectory ?? FileManager.default.temporaryDirectory
        var directoryURL: URL?
        for _ in 0..<8 {
            let candidate = base.appendingPathComponent(
                "cocxy-dbcloud-\(UUID().uuidString)",
                isDirectory: true
            )
            let result = candidate.withUnsafeFileSystemRepresentation { path in
                Darwin.mkdir(path, S_IRWXU)
            }
            if result == 0 {
                directoryURL = candidate
                break
            }
            guard errno == EEXIST else {
                throw DBCloudHelperExecutionError.credentialStorageUnavailable
            }
        }

        guard let directoryURL else {
            throw DBCloudHelperExecutionError.credentialStorageUnavailable
        }

        let templateURL = directoryURL.appendingPathComponent(".pgpass.XXXXXX", isDirectory: false)
        var template = Array(templateURL.path.utf8CString)
        let descriptor = Darwin.mkstemp(&template)
        guard descriptor >= 0 else {
            _ = directoryURL.withUnsafeFileSystemRepresentation { Darwin.rmdir($0) }
            throw DBCloudHelperExecutionError.credentialStorageUnavailable
        }
        let fileURL = URL(fileURLWithPath: String(cString: template))

        var writeSucceeded = false
        defer {
            Darwin.close(descriptor)
            if !writeSucceeded {
                _ = fileURL.withUnsafeFileSystemRepresentation { Darwin.unlink($0) }
                _ = directoryURL.withUnsafeFileSystemRepresentation { Darwin.rmdir($0) }
            }
        }

        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              fchmod(descriptor, S_IRUSR | S_IWUSR) == 0,
              writeAll(contents, to: descriptor),
              fsync(descriptor) == 0 else {
            throw DBCloudHelperExecutionError.credentialStorageUnavailable
        }

        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & 0o077 == 0 else {
            throw DBCloudHelperExecutionError.credentialStorageUnavailable
        }

        writeSucceeded = true
        return DBCloudHelperCredentialFile(directoryURL: directoryURL, fileURL: fileURL)
    }

    func remove() {
        _ = fileURL.withUnsafeFileSystemRepresentation { Darwin.unlink($0) }
        _ = directoryURL.withUnsafeFileSystemRepresentation { Darwin.rmdir($0) }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}
