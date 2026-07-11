// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookProcessRunner.swift - Bounded process-tree execution for notebook cells.

import Darwin
import Foundation

enum NotebookProcessRunnerError: Error, LocalizedError, Equatable, Sendable {
    case invalidInvocation
    case systemCallFailed(operation: String, code: Int32)
    case processTreeDidNotTerminate
    case outputDrainDidNotFinish

    var errorDescription: String? {
        switch self {
        case .invalidInvocation:
            return "The notebook process invocation is invalid."
        case .systemCallFailed(let operation, let code):
            return "Notebook process operation \(operation) failed: \(Self.message(for: code))."
        case .processTreeDidNotTerminate:
            return "The notebook process tree did not terminate cleanly."
        case .outputDrainDidNotFinish:
            return "The notebook process output did not close after teardown."
        }
    }

    private static func message(for code: Int32) -> String {
        guard let message = strerror(code) else { return "POSIX error \(code)" }
        return String(cString: message)
    }
}

struct NotebookProcessRunner: AgentProcessRunning {
    static let maximumRetainedBytesPerStream = 1 * 1_024 * 1_024

    private static let pollIntervalMilliseconds: Int32 = 20
    private static let terminationGracePeriodSeconds: TimeInterval = 0.2
    private static let killWaitSeconds: TimeInterval = 1
    private static let outputDrainWaitSeconds: TimeInterval = 0.5

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        try Task.checkCancellation()
        if let timeoutSeconds,
           (!timeoutSeconds.isFinite || timeoutSeconds < 0) {
            throw NotebookProcessRunnerError.invalidInvocation
        }

        let execution = try NotebookProcessExecution.spawn(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            retainedBytesPerStream: Self.maximumRetainedBytesPerStream
        )
        var completedCleanup = false
        defer {
            if !completedCleanup {
                execution.forceCleanup()
            }
        }

        let deadline = Self.deadline(for: timeoutSeconds)
        var stopReason: NotebookProcessStopReason?
        var terminationStatus: Int32?

        while terminationStatus == nil, stopReason == nil {
            try execution.drainAvailableOutput()
            try execution.refreshProcessTree()
            terminationStatus = try execution.observedTerminationStatus()
            if terminationStatus != nil { break }

            if Task.isCancelled {
                stopReason = .cancelled
            } else if let deadline, NotebookMonotonicClock.now() >= deadline {
                stopReason = .timedOut
            } else {
                try execution.pollOutput(milliseconds: Self.pollIntervalMilliseconds)
            }
        }

        try execution.terminateProcessTree(
            gracePeriodSeconds: Self.terminationGracePeriodSeconds,
            killWaitSeconds: Self.killWaitSeconds
        )
        try execution.drainOutputToEnd(
            timeoutSeconds: Self.outputDrainWaitSeconds
        )

        if terminationStatus == nil {
            terminationStatus = try execution.waitForObservedTermination(
                timeoutSeconds: Self.killWaitSeconds
            )
        }
        try execution.reapLeader()
        completedCleanup = true

        switch stopReason {
        case .cancelled:
            throw CancellationError()
        case .timedOut:
            let seconds = String(
                format: "%.0f",
                (timeoutSeconds ?? 0).rounded(.towardZero)
            )
            return AgentProcessResult(
                exitCode: 124,
                stdout: execution.stdoutString(),
                stderr: execution.stderrString(
                    diagnostic: "Command timed out after \(seconds) seconds."
                )
            )
        case nil:
            return AgentProcessResult(
                exitCode: terminationStatus ?? 1,
                stdout: execution.stdoutString(),
                stderr: execution.stderrString()
            )
        }
    }

    private static func deadline(for timeoutSeconds: TimeInterval?) -> UInt64? {
        guard let timeoutSeconds else { return nil }
        return NotebookMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: NotebookMonotonicClock.now()
        )
    }
}

private enum NotebookProcessStopReason {
    case cancelled
    case timedOut
}

private final class NotebookProcessExecution {
    private static let maximumIOBytesPerCycle = 256 * 1_024
    private static let processTreeRefreshIntervalNanoseconds: UInt64 = 50_000_000

    let leaderPID: pid_t
    let sessionID: pid_t

    private let stdoutDescriptor: NotebookOwnedFileDescriptor
    private let stderrDescriptor: NotebookOwnedFileDescriptor
    private var stdoutCapture: NotebookCapturedStream
    private var stderrCapture: NotebookCapturedStream
    private var stdoutReachedEOF = false
    private var stderrReachedEOF = false
    private var trackedProcesses: [pid_t: NotebookProcessIdentity] = [:]
    private var cachedTerminationStatus: Int32?
    private var leaderWasReaped = false
    private var lastProcessTreeRefresh = UInt64.zero

    private init(
        leaderPID: pid_t,
        stdoutDescriptor: NotebookOwnedFileDescriptor,
        stderrDescriptor: NotebookOwnedFileDescriptor,
        retainedBytesPerStream: Int
    ) {
        self.leaderPID = leaderPID
        sessionID = leaderPID
        self.stdoutDescriptor = stdoutDescriptor
        self.stderrDescriptor = stderrDescriptor
        stdoutCapture = NotebookCapturedStream(limit: retainedBytesPerStream)
        stderrCapture = NotebookCapturedStream(limit: retainedBytesPerStream)
    }

    static func spawn(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        retainedBytesPerStream: Int
    ) throws -> NotebookProcessExecution {
        guard executableURL.path.hasPrefix("/"),
              !executableURL.path.utf8.contains(0),
              !workingDirectory.path.utf8.contains(0),
              arguments.allSatisfy({ !$0.utf8.contains(0) }) else {
            throw NotebookProcessRunnerError.invalidInvocation
        }

        let stdoutPipe = try NotebookPipe.make()
        let stderrPipe = try NotebookPipe.make()
        try stdoutPipe.read.setNonBlocking()
        try stderrPipe.read.setNonBlocking()

        var fileActions: posix_spawn_file_actions_t?
        try NotebookPOSIX.check(
            posix_spawn_file_actions_init(&fileActions),
            operation: "posix_spawn_file_actions_init"
        )
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        try NotebookPOSIX.check(
            posix_spawn_file_actions_addopen(
                &fileActions,
                STDIN_FILENO,
                "/dev/null",
                O_RDONLY,
                0
            ),
            operation: "posix_spawn_file_actions_addopen"
        )
        try NotebookPOSIX.check(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                stdoutPipe.write.rawValue,
                STDOUT_FILENO
            ),
            operation: "posix_spawn_file_actions_adddup2"
        )
        try NotebookPOSIX.check(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                stderrPipe.write.rawValue,
                STDERR_FILENO
            ),
            operation: "posix_spawn_file_actions_adddup2"
        )
        for descriptor in [
            stdoutPipe.read.rawValue,
            stdoutPipe.write.rawValue,
            stderrPipe.read.rawValue,
            stderrPipe.write.rawValue,
        ] {
            try NotebookPOSIX.check(
                posix_spawn_file_actions_addclose(&fileActions, descriptor),
                operation: "posix_spawn_file_actions_addclose"
            )
        }
        try workingDirectory.path.withCString { path in
            try NotebookPOSIX.check(
                posix_spawn_file_actions_addchdir_np(&fileActions, path),
                operation: "posix_spawn_file_actions_addchdir_np"
            )
        }

        var attributes: posix_spawnattr_t?
        try NotebookPOSIX.check(
            posix_spawnattr_init(&attributes),
            operation: "posix_spawnattr_init"
        )
        defer { posix_spawnattr_destroy(&attributes) }

        var emptySignalMask = sigset_t()
        sigemptyset(&emptySignalMask)
        try NotebookPOSIX.check(
            posix_spawnattr_setsigmask(&attributes, &emptySignalMask),
            operation: "posix_spawnattr_setsigmask"
        )

        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        try NotebookPOSIX.check(
            posix_spawnattr_setsigdefault(&attributes, &defaultSignals),
            operation: "posix_spawnattr_setsigdefault"
        )

        let rawFlags = POSIX_SPAWN_CLOEXEC_DEFAULT
            | POSIX_SPAWN_SETSID
            | POSIX_SPAWN_START_SUSPENDED
            | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        try NotebookPOSIX.check(
            posix_spawnattr_setflags(&attributes, Int16(rawFlags)),
            operation: "posix_spawnattr_setflags"
        )

        var pid: pid_t = 0
        let invocation = [executableURL.path] + arguments
        let spawnCode = try NotebookCStringArray.withMutablePointers(invocation) { argv in
            executableURL.path.withCString { executablePath in
                posix_spawn(
                    &pid,
                    executablePath,
                    &fileActions,
                    &attributes,
                    argv,
                    environ
                )
            }
        }
        try NotebookPOSIX.check(spawnCode, operation: "posix_spawn")

        stdoutPipe.write.close()
        stderrPipe.write.close()

        let execution = NotebookProcessExecution(
            leaderPID: pid,
            stdoutDescriptor: stdoutPipe.read,
            stderrDescriptor: stderrPipe.read,
            retainedBytesPerStream: retainedBytesPerStream
        )
        // The suspended child cannot execute notebook code until isolation is verified.
        guard getpgid(pid) == pid, getsid(pid) == pid else {
            execution.forceCleanup()
            throw NotebookProcessRunnerError.processTreeDidNotTerminate
        }
        if let identity = NotebookProcessIdentity.current(for: pid) {
            execution.trackedProcesses[pid] = identity
        }

        guard !Task.isCancelled else {
            execution.forceCleanup()
            throw CancellationError()
        }
        guard kill(pid, SIGCONT) == 0 else {
            let code = errno
            execution.forceCleanup()
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "resume",
                code: code
            )
        }
        return execution
    }

    func observedTerminationStatus() throws -> Int32? {
        if let cachedTerminationStatus { return cachedTerminationStatus }

        // WNOWAIT keeps the leader PID reserved as the session identity until teardown completes.
        var info = siginfo_t()
        while true {
            let result = waitid(
                P_PID,
                id_t(leaderPID),
                &info,
                WEXITED | WNOHANG | WNOWAIT
            )
            if result == 0 {
                guard info.si_pid != 0 else { return nil }
                let status = Int32(info.si_status)
                cachedTerminationStatus = status
                return status
            }
            if errno == EINTR { continue }
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "waitid",
                code: errno
            )
        }
    }

    func waitForObservedTermination(timeoutSeconds: TimeInterval) throws -> Int32 {
        let deadline = NotebookMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: NotebookMonotonicClock.now()
        )
        while NotebookMonotonicClock.now() < deadline {
            if let status = try observedTerminationStatus() {
                return status
            }
            try pollOutput(milliseconds: 10)
            try drainAvailableOutput()
        }
        throw NotebookProcessRunnerError.processTreeDidNotTerminate
    }

    func refreshProcessTree(force: Bool = false) throws {
        let now = NotebookMonotonicClock.now()
        if !force,
           lastProcessTreeRefresh != 0,
           now - lastProcessTreeRefresh < Self.processTreeRefreshIntervalNanoseconds {
            return
        }
        let snapshots = try NotebookProcessSnapshot.all()
        let snapshotsByPID = Dictionary(
            snapshots.map { ($0.identity.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var knownPIDs = Set(trackedProcesses.compactMap { pid, identity in
            snapshotsByPID[pid]?.identity == identity ? pid : nil
        })
        knownPIDs.insert(leaderPID)
        var addedDescendant = true
        while addedDescendant {
            addedDescendant = false
            for snapshot in snapshots where knownPIDs.contains(snapshot.parentPID) {
                if knownPIDs.insert(snapshot.identity.pid).inserted {
                    trackedProcesses[snapshot.identity.pid] = snapshot.identity
                    addedDescendant = true
                }
            }
        }

        for snapshot in snapshots where snapshot.userID == getuid() {
            if snapshot.identity.pid == leaderPID || getsid(snapshot.identity.pid) == sessionID {
                trackedProcesses[snapshot.identity.pid] = snapshot.identity
            }
        }
        lastProcessTreeRefresh = now
    }

    func terminateProcessTree(
        gracePeriodSeconds: TimeInterval,
        killWaitSeconds: TimeInterval
    ) throws {
        try refreshProcessTree(force: true)
        guard try hasLiveTrackedProcesses() else { return }
        try signalTrackedProcessTree(SIGTERM)

        let termDeadline = NotebookMonotonicClock.adding(
            seconds: gracePeriodSeconds,
            to: NotebookMonotonicClock.now()
        )
        while try hasLiveTrackedProcesses() {
            if NotebookMonotonicClock.now() >= termDeadline { break }
            try drainAvailableOutput()
            try pollOutput(milliseconds: 10)
            try refreshProcessTree(force: true)
        }

        guard try hasLiveTrackedProcesses() else { return }

        let killDeadline = NotebookMonotonicClock.adding(
            seconds: killWaitSeconds,
            to: NotebookMonotonicClock.now()
        )
        while try hasLiveTrackedProcesses() {
            try signalTrackedProcessTree(SIGKILL)
            try drainAvailableOutput()
            try pollOutput(milliseconds: 10)
            try refreshProcessTree(force: true)
            if NotebookMonotonicClock.now() >= killDeadline,
               try hasLiveTrackedProcesses() {
                throw NotebookProcessRunnerError.processTreeDidNotTerminate
            }
        }
    }

    func drainAvailableOutput() throws {
        if !stdoutReachedEOF {
            stdoutReachedEOF = try drain(
                descriptor: stdoutDescriptor,
                capture: &stdoutCapture
            )
        }
        if !stderrReachedEOF {
            stderrReachedEOF = try drain(
                descriptor: stderrDescriptor,
                capture: &stderrCapture
            )
        }
    }

    func pollOutput(milliseconds: Int32) throws {
        var descriptors = [
            pollfd(
                fd: stdoutReachedEOF ? -1 : stdoutDescriptor.rawValue,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            ),
            pollfd(
                fd: stderrReachedEOF ? -1 : stderrDescriptor.rawValue,
                events: Int16(POLLIN | POLLHUP | POLLERR),
                revents: 0
            ),
        ]
        let result = descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.poll(buffer.baseAddress, nfds_t(buffer.count), milliseconds)
        }
        if result < 0, errno != EINTR {
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "poll",
                code: errno
            )
        }
    }

    func drainOutputToEnd(timeoutSeconds: TimeInterval) throws {
        let deadline = NotebookMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: NotebookMonotonicClock.now()
        )
        while !stdoutReachedEOF || !stderrReachedEOF {
            try drainAvailableOutput()
            if stdoutReachedEOF, stderrReachedEOF { return }
            if NotebookMonotonicClock.now() >= deadline {
                throw NotebookProcessRunnerError.outputDrainDidNotFinish
            }
            try pollOutput(milliseconds: 10)
        }
    }

    func reapLeader() throws {
        guard !leaderWasReaped else { return }
        var status: Int32 = 0
        while true {
            let result = waitpid(leaderPID, &status, 0)
            if result == leaderPID {
                leaderWasReaped = true
                return
            }
            if result == -1, errno == EINTR { continue }
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "waitpid",
                code: errno
            )
        }
    }

    func stdoutString() -> String {
        stdoutCapture.rendered()
    }

    func stderrString(diagnostic: String? = nil) -> String {
        stderrCapture.rendered(diagnostic: diagnostic)
    }

    func forceCleanup() {
        guard !leaderWasReaped else { return }
        try? refreshProcessTree(force: true)
        try? signalTrackedProcessTree(SIGKILL)
        _ = kill(-leaderPID, SIGKILL)
        _ = kill(leaderPID, SIGKILL)
        stdoutDescriptor.close()
        stderrDescriptor.close()

        var status: Int32 = 0
        while waitpid(leaderPID, &status, 0) == -1, errno == EINTR {}
        leaderWasReaped = true
    }

    private func signalTrackedProcessTree(_ signal: Int32) throws {
        if kill(-sessionID, signal) == -1, errno != ESRCH, errno != EPERM {
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "killpg",
                code: errno
            )
        }

        let snapshots = Dictionary(
            try NotebookProcessSnapshot.all().map { ($0.identity.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for identity in trackedProcesses.values {
            guard let snapshot = snapshots[identity.pid],
                  snapshot.identity == identity,
                  snapshot.status != UInt32(SZOMB) else {
                continue
            }
            if kill(identity.pid, signal) == -1, errno != ESRCH {
                throw NotebookProcessRunnerError.systemCallFailed(
                    operation: "kill",
                    code: errno
                )
            }
        }
    }

    private func hasLiveTrackedProcesses() throws -> Bool {
        try refreshProcessTree(force: true)
        let snapshots = Dictionary(
            try NotebookProcessSnapshot.all().map { ($0.identity.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return trackedProcesses.values.contains { identity in
            guard let snapshot = snapshots[identity.pid] else { return false }
            return snapshot.identity == identity && snapshot.status != UInt32(SZOMB)
        }
    }

    private func drain(
        descriptor: NotebookOwnedFileDescriptor,
        capture: inout NotebookCapturedStream
    ) throws -> Bool {
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        var bytesReadThisCycle = 0
        while bytesReadThisCycle < Self.maximumIOBytesPerCycle {
            let count = Darwin.read(descriptor.rawValue, &buffer, buffer.count)
            if count > 0 {
                capture.append(buffer, count: count)
                bytesReadThisCycle += count
                continue
            }
            if count == 0 {
                descriptor.close()
                return true
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return false }
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "read",
                code: errno
            )
        }
        return false
    }
}

private struct NotebookProcessIdentity: Hashable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64

    static func current(for pid: pid_t) -> NotebookProcessIdentity? {
        guard let snapshot = NotebookProcessSnapshot.current(for: pid) else { return nil }
        return snapshot.identity
    }
}

private struct NotebookProcessSnapshot {
    let identity: NotebookProcessIdentity
    let parentPID: pid_t
    let userID: uid_t
    let status: UInt32

    static func current(for pid: pid_t) -> NotebookProcessSnapshot? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout.size(ofValue: info))
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        guard result == expectedSize else { return nil }
        return NotebookProcessSnapshot(
            identity: NotebookProcessIdentity(
                pid: pid,
                startSeconds: UInt64(info.pbi_start_tvsec),
                startMicroseconds: UInt64(info.pbi_start_tvusec)
            ),
            parentPID: pid_t(info.pbi_ppid),
            userID: info.pbi_uid,
            status: info.pbi_status
        )
    }

    static func all() throws -> [NotebookProcessSnapshot] {
        var capacity = max(
            Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)) / MemoryLayout<pid_t>.stride + 64,
            256
        )

        for _ in 0..<4 {
            var pids = [pid_t](repeating: 0, count: capacity)
            let bytes = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(
                    UInt32(PROC_ALL_PIDS),
                    0,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
            guard bytes >= 0 else {
                throw NotebookProcessRunnerError.systemCallFailed(
                    operation: "proc_listpids",
                    code: errno
                )
            }

            let count = Int(bytes) / MemoryLayout<pid_t>.stride
            if count < capacity {
                return pids.prefix(count).compactMap { current(for: $0) }
            }
            capacity *= 2
        }

        throw NotebookProcessRunnerError.systemCallFailed(
            operation: "proc_listpids",
            code: EOVERFLOW
        )
    }
}

private struct NotebookPipe {
    let read: NotebookOwnedFileDescriptor
    let write: NotebookOwnedFileDescriptor

    static func make() throws -> NotebookPipe {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else {
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "pipe",
                code: errno
            )
        }
        let read = NotebookOwnedFileDescriptor(descriptors[0])
        let write = NotebookOwnedFileDescriptor(descriptors[1])
        do {
            try read.setCloseOnExec()
            try write.setCloseOnExec()
        } catch {
            read.close()
            write.close()
            throw error
        }
        return NotebookPipe(read: read, write: write)
    }
}

private final class NotebookOwnedFileDescriptor {
    private(set) var rawValue: Int32

    init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }

    deinit {
        close()
    }

    func close() {
        guard rawValue >= 0 else { return }
        _ = Darwin.close(rawValue)
        rawValue = -1
    }

    func setCloseOnExec() throws {
        guard fcntl(rawValue, F_SETFD, FD_CLOEXEC) == 0 else {
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "fcntl(FD_CLOEXEC)",
                code: errno
            )
        }
    }

    func setNonBlocking() throws {
        let flags = fcntl(rawValue, F_GETFL)
        guard flags >= 0, fcntl(rawValue, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: "fcntl(O_NONBLOCK)",
                code: errno
            )
        }
    }
}

private struct NotebookCapturedStream {
    let limit: Int
    private var data = Data()
    private var wasTruncated = false

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    mutating func append(_ buffer: [UInt8], count: Int) {
        let remaining = max(0, limit - data.count)
        let retainedCount = min(count, remaining)
        if retainedCount > 0 {
            data.append(contentsOf: buffer.prefix(retainedCount))
        }
        if retainedCount < count {
            wasTruncated = true
        }
    }

    func rendered(diagnostic: String? = nil) -> String {
        let decodedUTF8Count = String(decoding: data, as: UTF8.self).utf8.count
        let needsDiagnosticSeparator = diagnostic != nil && !data.isEmpty && data.last != UInt8(ascii: "\n")
        let diagnosticByteCount = diagnostic.map {
            $0.utf8.count + 1 + (needsDiagnosticSeparator ? 1 : 0)
        } ?? 0
        let outputWasTruncated = wasTruncated
            || decodedUTF8Count > limit
            || data.count + diagnosticByteCount > limit
        var annotations: [String] = []
        if outputWasTruncated {
            annotations.append("Output truncated at \(limit) bytes.")
        }
        if let diagnostic {
            annotations.append(diagnostic)
        }
        var suffix = annotations.isEmpty
            ? ""
            : annotations.joined(separator: "\n") + "\n"
        if !data.isEmpty, data.last != UInt8(ascii: "\n") {
            if !suffix.isEmpty {
                suffix.insert("\n", at: suffix.startIndex)
            }
        }
        let suffixData = Data(suffix.utf8)
        let prefixByteLimit = max(0, limit - suffixData.count)
        let prefix = Self.boundedUTF8String(
            decoding: data.prefix(prefixByteLimit),
            maximumUTF8Bytes: prefixByteLimit
        )
        return prefix + suffix
    }

    private static func boundedUTF8String(
        decoding data: Data.SubSequence,
        maximumUTF8Bytes: Int
    ) -> String {
        let decoded = String(decoding: data, as: UTF8.self)
        guard decoded.utf8.count > maximumUTF8Bytes else { return decoded }

        let utf8 = decoded.utf8
        var end = utf8.index(utf8.startIndex, offsetBy: maximumUTF8Bytes)
        while String.Index(end, within: decoded) == nil {
            end = utf8.index(before: end)
        }
        guard let stringEnd = String.Index(end, within: decoded) else { return "" }
        return String(decoded[..<stringEnd])
    }
}

private enum NotebookCStringArray {
    static func withMutablePointers<T>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T
    ) throws -> T {
        var allocations: [UnsafeMutablePointer<CChar>] = []
        allocations.reserveCapacity(strings.count)
        defer { allocations.forEach { free($0) } }

        for string in strings {
            guard let allocation = strdup(string) else {
                throw NotebookProcessRunnerError.systemCallFailed(
                    operation: "strdup",
                    code: ENOMEM
                )
            }
            allocations.append(allocation)
        }

        var pointers = allocations.map(Optional.some)
        pointers.append(nil)
        return try pointers.withUnsafeMutableBufferPointer { buffer in
            try body(buffer.baseAddress!)
        }
    }
}

private enum NotebookPOSIX {
    static func check(_ code: Int32, operation: String) throws {
        guard code == 0 else {
            throw NotebookProcessRunnerError.systemCallFailed(
                operation: operation,
                code: code
            )
        }
    }
}

private enum NotebookMonotonicClock {
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func adding(seconds: TimeInterval, to base: UInt64) -> UInt64 {
        let maximumSeconds = Double(UInt64.max) / 1_000_000_000
        let nanoseconds = UInt64(min(max(seconds, 0), maximumSeconds) * 1_000_000_000)
        return base > UInt64.max - nanoseconds ? UInt64.max : base + nanoseconds
    }
}
