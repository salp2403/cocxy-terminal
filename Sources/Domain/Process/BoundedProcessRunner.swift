// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BoundedProcessRunner.swift - Shared bounded process-tree execution.

import Darwin
import Foundation

enum BoundedProcessRunnerError: Error, LocalizedError, Equatable, Sendable {
    case invalidInvocation
    case systemCallFailed(operation: String, code: Int32)
    case launchdCommandFailed(operation: String, exitCode: Int32)
    case secureBrokerFailed(String)
    case secureCleanupUnverified(String)
    case secureContainmentUnavailable
    case secureContainmentVerificationFailed
    case processTreeDidNotTerminate
    case outputDrainDidNotFinish

    var errorDescription: String? {
        switch self {
        case .invalidInvocation:
            return "The process invocation is invalid."
        case .systemCallFailed(let operation, let code):
            return "Process operation \(operation) failed: \(Self.message(for: code))."
        case .launchdCommandFailed:
            return "Secure local execution could not be started."
        case .secureBrokerFailed:
            return "Secure local execution failed and was stopped."
        case .secureCleanupUnverified:
            return "Cocxy stopped the command but could not verify complete cleanup. Restart Cocxy before running more local code."
        case .secureContainmentUnavailable:
            return "Secure process containment is unavailable."
        case .secureContainmentVerificationFailed:
            return "Secure process containment could not be verified."
        case .processTreeDidNotTerminate:
            return "The process tree did not terminate cleanly."
        case .outputDrainDidNotFinish:
            return "The process output did not close after teardown."
        }
    }

    var diagnosticDescription: String {
        if case .secureBrokerFailed(let reason) = self { return reason }
        if case .secureCleanupUnverified(let reason) = self { return reason }
        if case .launchdCommandFailed(let operation, let exitCode) = self {
            return "\(operation) failed with exit code \(exitCode)"
        }
        return errorDescription ?? String(describing: self)
    }

    static func contextual(_ operation: String, error: Error) -> BoundedProcessRunnerError {
        if let bounded = error as? BoundedProcessRunnerError {
            switch bounded {
            case .secureCleanupUnverified:
                return .secureCleanupUnverified(
                    "\(operation): \(bounded.diagnosticDescription)"
                )
            case .secureContainmentUnavailable:
                return .secureContainmentUnavailable
            default:
                break
            }
        }
        let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
            ?? error.localizedDescription
        return .secureBrokerFailed("\(operation): \(detail)")
    }

    private static func message(for code: Int32) -> String {
        guard let message = strerror(code) else { return "POSIX error \(code)" }
        return String(cString: message)
    }
}

struct BoundedProcessResult: Codable, Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let stdoutWasTruncated: Bool
    let stderrWasTruncated: Bool
    let timedOut: Bool

    static func timeoutResult(
        diagnostic: String?,
        maximumRetainedBytesPerStream: Int
    ) -> BoundedProcessResult {
        let stderrCapture = BoundedCapturedStream(
            limit: maximumRetainedBytesPerStream
        )
        return BoundedProcessResult(
            exitCode: 124,
            stdout: "",
            stderr: stderrCapture.rendered(diagnostic: diagnostic),
            stdoutWasTruncated: false,
            stderrWasTruncated: stderrCapture.renderedWasTruncated(
                diagnostic: diagnostic
            ),
            timedOut: true
        )
    }
}

/// Runs a process in an isolated session while bounding time, output, and descendants.
/// Bounded execution for fixed, trusted infrastructure utilities only.
///
/// Snapshot-based tracking cannot contain project-controlled code that can
/// double-fork and create a new session. Use `LaunchdProcessBrokerClient` for
/// hooks, shells, interpreters, or any executable selected by untrusted input.
struct BoundedProcessRunner: Sendable {
    private static let pollIntervalMilliseconds: Int32 = 20
    private static let terminationGracePeriodSeconds: TimeInterval = 0.2
    private static let killWaitSeconds: TimeInterval = 1
    private static let outputDrainWaitSeconds: TimeInterval = 0.5

    let maximumRetainedBytesPerStream: Int
    let observesTaskCancellation: Bool
    let externalCancellationRequested: @Sendable () -> Bool

    init(
        maximumRetainedBytesPerStream: Int,
        observesTaskCancellation: Bool = true,
        externalCancellationRequested: @escaping @Sendable () -> Bool = { false }
    ) {
        self.maximumRetainedBytesPerStream = maximumRetainedBytesPerStream
        self.observesTaskCancellation = observesTaskCancellation
        self.externalCancellationRequested = externalCancellationRequested
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval?,
        timeoutDiagnostic: String? = nil
    ) throws -> BoundedProcessResult {
        try checkCancellation()
        guard maximumRetainedBytesPerStream > 0 else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        if let timeoutSeconds, (!timeoutSeconds.isFinite || timeoutSeconds < 0) {
            throw BoundedProcessRunnerError.invalidInvocation
        }

        let deadline = Self.deadline(for: timeoutSeconds)
        if let deadline, BoundedMonotonicClock.now() >= deadline {
            return .timeoutResult(
                diagnostic: timeoutDiagnostic,
                maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
            )
        }
        let execution: BoundedProcessExecution
        do {
            execution = try BoundedProcessExecution.spawn(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                retainedBytesPerStream: maximumRetainedBytesPerStream,
                deadline: deadline,
                cancellationRequested: { [self] in isCancellationRequested() }
            )
        } catch BoundedProcessBoundaryError.deadlineExceeded {
            return .timeoutResult(
                diagnostic: timeoutDiagnostic,
                maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
            )
        }
        var completedCleanup = false
        do {
            var stopReason: BoundedProcessStopReason?
            var terminationStatus: Int32?

            while terminationStatus == nil, stopReason == nil {
                try execution.drainAvailableOutput()
                try execution.refreshProcessTree()
                terminationStatus = try execution.observedTerminationStatus()
                if terminationStatus != nil { break }

                if isCancellationRequested() {
                    stopReason = .cancelled
                } else if let deadline, BoundedMonotonicClock.now() >= deadline {
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
            try execution.reapLeader(timeoutSeconds: Self.killWaitSeconds)
            completedCleanup = true

            switch stopReason {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                return BoundedProcessResult(
                    exitCode: 124,
                    stdout: execution.stdoutString(),
                    stderr: execution.stderrString(diagnostic: timeoutDiagnostic),
                    stdoutWasTruncated: execution.stdoutWasTruncated,
                    stderrWasTruncated: execution.stderrWasTruncated(
                        diagnostic: timeoutDiagnostic
                    ),
                    timedOut: true
                )
            case nil:
                return BoundedProcessResult(
                    exitCode: terminationStatus ?? 1,
                    stdout: execution.stdoutString(),
                    stderr: execution.stderrString(),
                    stdoutWasTruncated: execution.stdoutWasTruncated,
                    stderrWasTruncated: execution.stderrWasTruncated(),
                    timedOut: false
                )
            }
        } catch let originalError {
            if !completedCleanup {
                do {
                    try execution.verifiedCleanup()
                } catch {
                    throw BoundedProcessRunnerError.contextual(
                        "bounded process fallback cleanup",
                        error: error
                    )
                }
            }
            throw originalError
        }
    }

    private static func deadline(for timeoutSeconds: TimeInterval?) -> UInt64? {
        guard let timeoutSeconds else { return nil }
        return BoundedMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: BoundedMonotonicClock.now()
        )
    }

    private func checkCancellation() throws {
        if isCancellationRequested() { throw CancellationError() }
    }

    private func isCancellationRequested() -> Bool {
        (observesTaskCancellation && Task.isCancelled) || externalCancellationRequested()
    }
}

struct NotebookProcessRunner: AgentProcessRunning {
    static let maximumRetainedBytesPerStream = 1 * 1_024 * 1_024

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: TimeInterval?
    ) throws -> AgentProcessResult {
        let seconds = String(
            format: "%.0f",
            (timeoutSeconds ?? 0).rounded(.towardZero)
        )
        let result = try LaunchdProcessBrokerClient(
            maximumRetainedBytesPerStream: Self.maximumRetainedBytesPerStream
        ).run(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            timeoutSeconds: timeoutSeconds,
            timeoutDiagnostic: "Command timed out after \(seconds) seconds."
        )
        return AgentProcessResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}

private enum BoundedProcessStopReason {
    case cancelled
    case timedOut
}

private enum BoundedProcessBoundaryError: Error {
    case deadlineExceeded
}

private final class BoundedProcessExecution {
    private static let maximumIOBytesPerCycle = 256 * 1_024
    private static let processTreeRefreshIntervalNanoseconds: UInt64 = 50_000_000

    let leaderPID: pid_t
    let sessionID: pid_t

    private let stdoutDescriptor: BoundedOwnedFileDescriptor
    private let stderrDescriptor: BoundedOwnedFileDescriptor
    private var stdoutCapture: BoundedCapturedStream
    private var stderrCapture: BoundedCapturedStream
    private var stdoutReachedEOF = false
    private var stderrReachedEOF = false
    private var trackedProcesses: [pid_t: BoundedProcessIdentity] = [:]
    private var cachedTerminationStatus: Int32?
    private var leaderWasReaped = false
    private var lastProcessTreeRefresh = UInt64.zero

    private init(
        leaderPID: pid_t,
        stdoutDescriptor: BoundedOwnedFileDescriptor,
        stderrDescriptor: BoundedOwnedFileDescriptor,
        retainedBytesPerStream: Int
    ) {
        self.leaderPID = leaderPID
        sessionID = leaderPID
        self.stdoutDescriptor = stdoutDescriptor
        self.stderrDescriptor = stderrDescriptor
        stdoutCapture = BoundedCapturedStream(limit: retainedBytesPerStream)
        stderrCapture = BoundedCapturedStream(limit: retainedBytesPerStream)
    }

    static func spawn(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]?,
        retainedBytesPerStream: Int,
        deadline: UInt64?,
        cancellationRequested: @Sendable () -> Bool
    ) throws -> BoundedProcessExecution {
        guard executableURL.path.hasPrefix("/"),
              !executableURL.path.utf8.contains(0),
              !workingDirectory.path.utf8.contains(0),
              arguments.allSatisfy({ !$0.utf8.contains(0) }),
              environment?.allSatisfy({ key, value in
                  !key.isEmpty
                      && !key.contains("=")
                      && !key.utf8.contains(0)
                      && !value.utf8.contains(0)
              }) ?? true else {
            throw BoundedProcessRunnerError.invalidInvocation
        }

        let stdoutPipe = try BoundedPipe.make()
        let stderrPipe = try BoundedPipe.make()
        try stdoutPipe.read.setNonBlocking()
        try stderrPipe.read.setNonBlocking()

        var fileActions: posix_spawn_file_actions_t?
        try BoundedPOSIX.check(
            posix_spawn_file_actions_init(&fileActions),
            operation: "posix_spawn_file_actions_init"
        )
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        try BoundedPOSIX.check(
            posix_spawn_file_actions_addopen(
                &fileActions,
                STDIN_FILENO,
                "/dev/null",
                O_RDONLY,
                0
            ),
            operation: "posix_spawn_file_actions_addopen"
        )
        try BoundedPOSIX.check(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                stdoutPipe.write.rawValue,
                STDOUT_FILENO
            ),
            operation: "posix_spawn_file_actions_adddup2"
        )
        try BoundedPOSIX.check(
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
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addclose(&fileActions, descriptor),
                operation: "posix_spawn_file_actions_addclose"
            )
        }
        try workingDirectory.path.withCString { path in
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addchdir_np(&fileActions, path),
                operation: "posix_spawn_file_actions_addchdir_np"
            )
        }

        var attributes: posix_spawnattr_t?
        try BoundedPOSIX.check(
            posix_spawnattr_init(&attributes),
            operation: "posix_spawnattr_init"
        )
        defer { posix_spawnattr_destroy(&attributes) }

        var emptySignalMask = sigset_t()
        sigemptyset(&emptySignalMask)
        try BoundedPOSIX.check(
            posix_spawnattr_setsigmask(&attributes, &emptySignalMask),
            operation: "posix_spawnattr_setsigmask"
        )

        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        try BoundedPOSIX.check(
            posix_spawnattr_setsigdefault(&attributes, &defaultSignals),
            operation: "posix_spawnattr_setsigdefault"
        )

        let rawFlags = POSIX_SPAWN_CLOEXEC_DEFAULT
            | POSIX_SPAWN_SETSID
            | POSIX_SPAWN_START_SUSPENDED
            | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        try BoundedPOSIX.check(
            posix_spawnattr_setflags(&attributes, Int16(rawFlags)),
            operation: "posix_spawnattr_setflags"
        )

        var pid: pid_t = 0
        let invocation = [executableURL.path] + arguments
        let spawnCode = try BoundedCStringArray.withMutablePointers(invocation) { argv in
            try executableURL.path.withCString { executablePath in
                if let environment {
                    let entries = environment
                        .map { "\($0.key)=\($0.value)" }
                        .sorted()
                    return try BoundedCStringArray.withMutablePointers(entries) { envp in
                        posix_spawn(
                            &pid,
                            executablePath,
                            &fileActions,
                            &attributes,
                            argv,
                            envp
                        )
                    }
                }
                return posix_spawn(
                    &pid,
                    executablePath,
                    &fileActions,
                    &attributes,
                    argv,
                    environ
                )
            }
        }
        try BoundedPOSIX.check(spawnCode, operation: "posix_spawn")

        stdoutPipe.write.close()
        stderrPipe.write.close()

        let execution = BoundedProcessExecution(
            leaderPID: pid,
            stdoutDescriptor: stdoutPipe.read,
            stderrDescriptor: stderrPipe.read,
            retainedBytesPerStream: retainedBytesPerStream
        )
        func failAfterVerifiedCleanup(_ error: Error) throws -> Never {
            do {
                try execution.verifiedCleanup()
            } catch {
                throw BoundedProcessRunnerError.contextual(
                    "bounded process startup cleanup",
                    error: error
                )
            }
            throw error
        }
        // The suspended child cannot execute caller code until isolation is verified.
        guard getpgid(pid) == pid, getsid(pid) == pid else {
            try failAfterVerifiedCleanup(
                BoundedProcessRunnerError.processTreeDidNotTerminate
            )
        }
        guard let identity = BoundedProcessIdentity.current(for: pid) else {
            try failAfterVerifiedCleanup(
                BoundedProcessRunnerError.secureContainmentVerificationFailed
            )
        }
        execution.trackedProcesses[pid] = identity

        guard !cancellationRequested() else {
            try failAfterVerifiedCleanup(CancellationError())
        }
        if let deadline, BoundedMonotonicClock.now() >= deadline {
            try failAfterVerifiedCleanup(BoundedProcessBoundaryError.deadlineExceeded)
        }
        guard kill(pid, SIGCONT) == 0 else {
            let code = errno
            try failAfterVerifiedCleanup(
                BoundedProcessRunnerError.systemCallFailed(
                    operation: "resume",
                    code: code
                )
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
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "waitid",
                code: errno
            )
        }
    }

    func waitForObservedTermination(timeoutSeconds: TimeInterval) throws -> Int32 {
        let deadline = BoundedMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: BoundedMonotonicClock.now()
        )
        while BoundedMonotonicClock.now() < deadline {
            if let status = try observedTerminationStatus() {
                return status
            }
            try pollOutput(milliseconds: 10)
            try drainAvailableOutput()
        }
        throw BoundedProcessRunnerError.processTreeDidNotTerminate
    }

    func refreshProcessTree(force: Bool = false) throws {
        let now = BoundedMonotonicClock.now()
        if !force,
           lastProcessTreeRefresh != 0,
           now - lastProcessTreeRefresh < Self.processTreeRefreshIntervalNanoseconds {
            return
        }
        let snapshots = try BoundedProcessSnapshot.all()
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

        let termDeadline = BoundedMonotonicClock.adding(
            seconds: gracePeriodSeconds,
            to: BoundedMonotonicClock.now()
        )
        while try hasLiveTrackedProcesses() {
            if BoundedMonotonicClock.now() >= termDeadline { break }
            try drainAvailableOutput()
            try pollOutput(milliseconds: 10)
            try refreshProcessTree(force: true)
        }

        guard try hasLiveTrackedProcesses() else { return }

        let killDeadline = BoundedMonotonicClock.adding(
            seconds: killWaitSeconds,
            to: BoundedMonotonicClock.now()
        )
        while try hasLiveTrackedProcesses() {
            try signalTrackedProcessTree(SIGKILL)
            try drainAvailableOutput()
            try pollOutput(milliseconds: 10)
            try refreshProcessTree(force: true)
            if BoundedMonotonicClock.now() >= killDeadline,
               try hasLiveTrackedProcesses() {
                throw BoundedProcessRunnerError.processTreeDidNotTerminate
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
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "poll",
                code: errno
            )
        }
    }

    func drainOutputToEnd(timeoutSeconds: TimeInterval) throws {
        let deadline = BoundedMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: BoundedMonotonicClock.now()
        )
        while !stdoutReachedEOF || !stderrReachedEOF {
            try drainAvailableOutput()
            if stdoutReachedEOF, stderrReachedEOF { return }
            if BoundedMonotonicClock.now() >= deadline {
                throw BoundedProcessRunnerError.outputDrainDidNotFinish
            }
            try pollOutput(milliseconds: 10)
        }
    }

    func reapLeader(timeoutSeconds: TimeInterval) throws {
        guard !leaderWasReaped else { return }
        let deadline = BoundedMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: BoundedMonotonicClock.now()
        )
        var status: Int32 = 0
        while BoundedMonotonicClock.now() < deadline {
            let result = waitpid(leaderPID, &status, WNOHANG)
            if result == leaderPID {
                leaderWasReaped = true
                return
            }
            if result == -1, errno == ECHILD {
                leaderWasReaped = true
                return
            }
            if result == -1, errno == EINTR { continue }
            if result == -1 {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "waitpid",
                    code: errno
                )
            }
            usleep(10_000)
        }
        let finalResult = waitpid(leaderPID, &status, WNOHANG)
        if finalResult == leaderPID || (finalResult == -1 && errno == ECHILD) {
            leaderWasReaped = true
            return
        }
        if finalResult == -1, errno != EINTR {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "waitpid",
                code: errno
            )
        }
        throw BoundedProcessRunnerError.secureCleanupUnverified(
            "bounded process leader \(leaderPID) could not be reaped before the cleanup deadline"
        )
    }

    func stdoutString() -> String {
        stdoutCapture.rendered()
    }

    var stdoutWasTruncated: Bool {
        stdoutCapture.renderedWasTruncated()
    }

    func stderrString(diagnostic: String? = nil) -> String {
        stderrCapture.rendered(diagnostic: diagnostic)
    }

    func stderrWasTruncated(diagnostic: String? = nil) -> Bool {
        stderrCapture.renderedWasTruncated(diagnostic: diagnostic)
    }

    func verifiedCleanup() throws {
        var failures: [String] = []
        do {
            try terminateProcessTree(gracePeriodSeconds: 0, killWaitSeconds: 1)
        } catch {
            failures.append(Self.cleanupDetail(error))
            if kill(-leaderPID, SIGKILL) == -1, errno != ESRCH {
                failures.append("killpg fallback: \(String(cString: strerror(errno)))")
            }
            if kill(leaderPID, SIGKILL) == -1, errno != ESRCH {
                failures.append("leader kill fallback: \(String(cString: strerror(errno)))")
            }
        }
        stdoutDescriptor.close()
        stderrDescriptor.close()
        if !leaderWasReaped {
            do {
                try reapLeader(timeoutSeconds: 1)
            } catch {
                failures.append(Self.cleanupDetail(error))
            }
        }
        guard failures.isEmpty else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                failures.joined(separator: "; ")
            )
        }
    }

    private static func cleanupDetail(_ error: Error) -> String {
        (error as? BoundedProcessRunnerError)?.diagnosticDescription
            ?? error.localizedDescription
    }

    private func signalTrackedProcessTree(_ signal: Int32) throws {
        if kill(-sessionID, signal) == -1, errno != ESRCH, errno != EPERM {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "killpg",
                code: errno
            )
        }

        let snapshots = Dictionary(
            try BoundedProcessSnapshot.all().map { ($0.identity.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for identity in trackedProcesses.values {
            guard let snapshot = snapshots[identity.pid],
                  snapshot.identity == identity,
                  snapshot.status != UInt32(SZOMB) else {
                continue
            }
            if kill(identity.pid, signal) == -1, errno != ESRCH {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "kill",
                    code: errno
                )
            }
        }
    }

    private func hasLiveTrackedProcesses() throws -> Bool {
        try refreshProcessTree(force: true)
        let snapshots = Dictionary(
            try BoundedProcessSnapshot.all().map { ($0.identity.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return trackedProcesses.values.contains { identity in
            guard let snapshot = snapshots[identity.pid] else { return false }
            return snapshot.identity == identity && snapshot.status != UInt32(SZOMB)
        }
    }

    private func drain(
        descriptor: BoundedOwnedFileDescriptor,
        capture: inout BoundedCapturedStream
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
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read",
                code: errno
            )
        }
        return false
    }
}

private struct BoundedProcessIdentity: Hashable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64

    static func current(for pid: pid_t) -> BoundedProcessIdentity? {
        guard let snapshot = BoundedProcessSnapshot.current(for: pid) else { return nil }
        return snapshot.identity
    }
}

private struct BoundedProcessSnapshot {
    let identity: BoundedProcessIdentity
    let parentPID: pid_t
    let userID: uid_t
    let status: UInt32

    static func current(for pid: pid_t) -> BoundedProcessSnapshot? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout.size(ofValue: info))
        var result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        if result != expectedSize {
            result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 1, &info, expectedSize)
        }
        guard result == expectedSize else { return nil }
        return BoundedProcessSnapshot(
            identity: BoundedProcessIdentity(
                pid: pid,
                startSeconds: UInt64(info.pbi_start_tvsec),
                startMicroseconds: UInt64(info.pbi_start_tvusec)
            ),
            parentPID: pid_t(info.pbi_ppid),
            userID: info.pbi_uid,
            status: info.pbi_status
        )
    }

    static func all() throws -> [BoundedProcessSnapshot] {
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
            try BoundedPOSIX.requireProcessListBytes(bytes)

            let count = Int(bytes) / MemoryLayout<pid_t>.stride
            if count < capacity {
                return pids.prefix(count).compactMap { current(for: $0) }
            }
            capacity *= 2
        }

        throw BoundedProcessRunnerError.systemCallFailed(
            operation: "proc_listpids",
            code: EOVERFLOW
        )
    }
}

struct BoundedPipe {
    let read: BoundedOwnedFileDescriptor
    let write: BoundedOwnedFileDescriptor

    static func make() throws -> BoundedPipe {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "pipe",
                code: errno
            )
        }
        let read = BoundedOwnedFileDescriptor(descriptors[0])
        let write = BoundedOwnedFileDescriptor(descriptors[1])
        do {
            try read.relocateAboveStandardDescriptors()
            try write.relocateAboveStandardDescriptors()
            try read.setCloseOnExec()
            try write.setCloseOnExec()
        } catch {
            read.close()
            write.close()
            throw error
        }
        return BoundedPipe(read: read, write: write)
    }
}

final class BoundedOwnedFileDescriptor {
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
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "fcntl(FD_CLOEXEC)",
                code: errno
            )
        }
    }

    func relocateAboveStandardDescriptors() throws {
        guard rawValue <= STDERR_FILENO else { return }
        let duplicate = fcntl(rawValue, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
        guard duplicate >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "fcntl(F_DUPFD_CLOEXEC)",
                code: errno
            )
        }
        _ = Darwin.close(rawValue)
        rawValue = duplicate
    }

    func setNonBlocking() throws {
        let flags = fcntl(rawValue, F_GETFL)
        guard flags >= 0, fcntl(rawValue, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "fcntl(O_NONBLOCK)",
                code: errno
            )
        }
    }
}

struct BoundedCapturedStream {
    let limit: Int
    private var data = Data()
    private(set) var wasTruncated = false

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
        renderedValue(diagnostic: diagnostic).text
    }

    func renderedWasTruncated(diagnostic: String? = nil) -> Bool {
        renderedValue(diagnostic: diagnostic).wasTruncated
    }

    private func renderedValue(diagnostic: String?) -> (text: String, wasTruncated: Bool) {
        let decodedUTF8Count = String(decoding: data, as: UTF8.self).utf8.count
        let needsDiagnosticSeparator = diagnostic != nil
            && !data.isEmpty
            && data.last != UInt8(ascii: "\n")
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
        let boundedSuffix = Self.boundedUTF8String(
            decoding: suffixData.prefix(limit),
            maximumUTF8Bytes: limit
        )
        let prefixByteLimit = max(0, limit - boundedSuffix.utf8.count)
        let prefix = Self.boundedUTF8String(
            decoding: data.prefix(prefixByteLimit),
            maximumUTF8Bytes: prefixByteLimit
        )
        return (
            prefix + boundedSuffix,
            outputWasTruncated || suffixData.count > limit
        )
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

enum BoundedCStringArray {
    static func withMutablePointers<T>(
        _ strings: [String],
        _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T
    ) throws -> T {
        var allocations: [UnsafeMutablePointer<CChar>] = []
        allocations.reserveCapacity(strings.count)
        defer { allocations.forEach { free($0) } }

        for string in strings {
            guard let allocation = strdup(string) else {
                throw BoundedProcessRunnerError.systemCallFailed(
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

enum BoundedPOSIX {
    static func check(_ code: Int32, operation: String) throws {
        guard code == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: operation,
                code: code
            )
        }
    }

    static func requireProcessListBytes(
        _ byteCount: Int32,
        errorCode: Int32 = errno
    ) throws {
        guard byteCount > 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "proc_listpids",
                code: errorCode == 0 ? EIO : errorCode
            )
        }
    }
}

enum BoundedMonotonicClock {
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    static func adding(seconds: TimeInterval, to base: UInt64) -> UInt64 {
        let maximumSeconds = Double(UInt64.max) / 1_000_000_000
        guard seconds.isFinite else { return seconds.sign == .minus ? base : UInt64.max }
        guard seconds > 0 else { return base }
        guard seconds < maximumSeconds else { return UInt64.max }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        return base > UInt64.max - nanoseconds ? UInt64.max : base + nanoseconds
    }
}
