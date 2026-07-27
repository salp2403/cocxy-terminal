// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LaunchdProcessBroker.swift - Crash-resilient ownership for contained local execution.

import Darwin
import Foundation

final class LaunchdLocalExecutionGate: @unchecked Sendable {
    static let shared = LaunchdLocalExecutionGate()
    static let stateFileName = "execution-gate.plist"

    private static let stateVersion = 1
    private static let maximumStateBytes = 64 * 1_024
    private static let maximumReasonCharacters = 4_096
    private static let defaultLockWaitSeconds: TimeInterval = 3
    private static let lockPollMicroseconds: useconds_t = 10_000

    private struct PersistentState: Codable {
        let version: Int
        let userID: UInt32
        let bootIdentity: LaunchdBootIdentity
        let blocked: Bool
        let generation: String
        let reason: String?
    }

    private let lock = NSLock()
    private var blockedReason: String?
    private let stateDirectoryURL: URL
    private let bootIdentityProvider: @Sendable () throws -> LaunchdBootIdentity
    private let lockWaitSeconds: TimeInterval

    init(
        stateDirectoryURL: URL = LaunchdProcessArtifacts.rootURL,
        bootIdentityProvider: @escaping @Sendable () throws -> LaunchdBootIdentity = {
            try LaunchdBootIdentity.current()
        },
        lockWaitSeconds: TimeInterval = LaunchdLocalExecutionGate.defaultLockWaitSeconds
    ) {
        self.stateDirectoryURL = stateDirectoryURL
        self.bootIdentityProvider = bootIdentityProvider
        self.lockWaitSeconds = lockWaitSeconds.isFinite ? max(lockWaitSeconds, 0) : 0
    }

    func check() throws {
        let persisted = try withLockedState { stateDescriptor, _ in
            try readState(descriptor: stateDescriptor)
        }
        lock.lock()
        let localReason = blockedReason
        lock.unlock()
        guard let reason = persisted?.reason ?? localReason else { return }
        throw BoundedProcessRunnerError.secureCleanupUnverified(
            "local execution remains disabled after unverified cleanup: \(reason)"
        )
    }

    func block(reason: String) throws {
        lock.lock()
        if blockedReason == nil { blockedReason = reason }
        lock.unlock()
        do {
            try withLockedState { stateDescriptor, rootDescriptor in
                let existing = try readState(descriptor: stateDescriptor)
                let firstReason = existing?.reason
                    ?? String(reason.prefix(Self.maximumReasonCharacters))
                let state = PersistentState(
                    version: Self.stateVersion,
                    userID: UInt32(geteuid()),
                    bootIdentity: try bootIdentityProvider(),
                    blocked: true,
                    generation: UUID().uuidString.lowercased(),
                    reason: firstReason
                )
                try writeState(
                    state,
                    descriptor: stateDescriptor,
                    rootDescriptor: rootDescriptor
                )
            }
        } catch {
            let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                ?? error.localizedDescription
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "failed to persist the per-user execution gate: \(detail)"
            )
        }
    }

    func reconciliationGeneration() throws -> String? {
        try withLockedState { stateDescriptor, _ in
            try readState(descriptor: stateDescriptor)?.generation
        }
    }

    func validatePersistedState() throws {
        _ = try withLockedState { stateDescriptor, _ in
            try readState(descriptor: stateDescriptor)
        }
    }

    func clearAfterVerifiedReconciliation(
        expectedGeneration: String?,
        encounteredActiveExecutions: Bool
    ) throws {
        try withLockedState { stateDescriptor, rootDescriptor in
            let current = try readState(descriptor: stateDescriptor)
            guard current?.generation == expectedGeneration else {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "the per-user execution gate changed during reconciliation"
                )
            }
            if current != nil, encounteredActiveExecutions {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "active local executions prevented reconciliation of the blocked gate"
                )
            }
            try writeState(
                nil,
                descriptor: stateDescriptor,
                rootDescriptor: rootDescriptor
            )
        }
        lock.lock()
        blockedReason = nil
        lock.unlock()
    }

    private func withLockedState<T>(
        _ body: (Int32, Int32) throws -> T
    ) throws -> T {
        if mkdir(stateDirectoryURL.path, S_IRWXU) == -1, errno != EEXIST {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "create local execution gate directory",
                code: errno
            )
        }
        var pathStatus = stat()
        guard lstat(stateDirectoryURL.path, &pathStatus) == 0,
              pathStatus.st_uid == geteuid(),
              pathStatus.st_mode & S_IFMT == S_IFDIR,
              pathStatus.st_mode & 0o777 == S_IRWXU else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate directory is not private"
            )
        }

        let rootRawDescriptor = Darwin.open(
            stateDirectoryURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootRawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open local execution gate directory",
                code: errno
            )
        }
        let rootDescriptor = LaunchdOwnedFileDescriptor(rootRawDescriptor)
        defer { rootDescriptor.close() }

        var rootStatus = stat()
        guard fstat(rootDescriptor.rawValue, &rootStatus) == 0,
              rootStatus.st_uid == geteuid(),
              rootStatus.st_mode & S_IFMT == S_IFDIR,
              rootStatus.st_mode & 0o777 == S_IRWXU,
              rootStatus.st_dev == pathStatus.st_dev,
              rootStatus.st_ino == pathStatus.st_ino else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate directory changed identity"
            )
        }

        var stateWasCreated = false
        var stateRawDescriptor = Darwin.openat(
            rootDescriptor.rawValue,
            Self.stateFileName,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW | O_EXLOCK,
            S_IRUSR | S_IWUSR
        )
        if stateRawDescriptor >= 0 {
            stateWasCreated = true
        } else if errno == EEXIST {
            stateRawDescriptor = Darwin.openat(
                rootDescriptor.rawValue,
                Self.stateFileName,
                O_RDWR | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard stateRawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open local execution gate state",
                code: errno
            )
        }
        let stateDescriptor = LaunchdOwnedFileDescriptor(stateRawDescriptor)
        defer { stateDescriptor.close() }

        let lockDeadline = LaunchdMonotonicClock.adding(
            seconds: lockWaitSeconds,
            to: LaunchdMonotonicClock.now()
        )
        // A creator already holds the lock through `O_EXLOCK`; everyone else has
        // to take it explicitly.
        if !stateWasCreated {
            try acquireStateLock(
                descriptor: stateDescriptor.rawValue,
                deadline: lockDeadline
            )
        }
        defer { _ = flock(stateDescriptor.rawValue, LOCK_UN) }
        var stateByteCount = try verifyStateFile(descriptor: stateDescriptor.rawValue)
        try verifyStateFileLink(
            descriptor: stateDescriptor.rawValue,
            rootDescriptor: rootDescriptor.rawValue
        )
        // `O_EXCL` publishes the name before `O_EXLOCK` grants the lock — measured
        // on macOS, not theoretical — so a contender can hold the lock over a file
        // whose creator has not written it yet. That emptiness is transient and the
        // only cure is to step aside: the creator is parked inside its own `open`
        // and cannot make progress while we hold the lock. Emptiness that outlives
        // the deadline is a genuinely truncated state, which `readState` still
        // rejects, so waiting here never turns a fail-closed gate into an open one.
        while !stateWasCreated,
              stateByteCount == 0,
              LaunchdMonotonicClock.now() < lockDeadline {
            guard flock(stateDescriptor.rawValue, LOCK_UN) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "yield local execution gate state",
                    code: errno
                )
            }
            usleep(Self.lockPollMicroseconds)
            try acquireStateLock(
                descriptor: stateDescriptor.rawValue,
                deadline: lockDeadline
            )
            stateByteCount = try verifyStateFile(descriptor: stateDescriptor.rawValue)
            try verifyStateFileLink(
                descriptor: stateDescriptor.rawValue,
                rootDescriptor: rootDescriptor.rawValue
            )
        }
        if stateWasCreated {
            try writeState(
                nil,
                descriptor: stateDescriptor.rawValue,
                rootDescriptor: rootDescriptor.rawValue
            )
        }
        let result = try body(stateDescriptor.rawValue, rootDescriptor.rawValue)
        try verifyStateFileLink(
            descriptor: stateDescriptor.rawValue,
            rootDescriptor: rootDescriptor.rawValue
        )
        return result
    }

    private func acquireStateLock(descriptor: Int32, deadline: UInt64) throws {
        while flock(descriptor, LOCK_EX | LOCK_NB) == -1 {
            let lockError = errno
            if lockError == EINTR { continue }
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                guard LaunchdMonotonicClock.now() < deadline else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "timed out waiting for the per-user execution gate"
                    )
                }
                usleep(Self.lockPollMicroseconds)
                continue
            }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "lock local execution gate state",
                code: lockError
            )
        }
    }

    /// Returns the state size so callers can tell a gate that is still being
    /// published apart from an established one without a second `fstat`.
    private func verifyStateFile(descriptor: Int32) throws -> off_t {
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & 0o777 == (S_IRUSR | S_IWUSR),
              status.st_nlink == 1,
              status.st_size >= 0,
              status.st_size <= Self.maximumStateBytes else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state is not authentic"
            )
        }
        return status.st_size
    }

    private func verifyStateFileLink(
        descriptor: Int32,
        rootDescriptor: Int32
    ) throws {
        var descriptorStatus = stat()
        var linkedStatus = stat()
        guard fstat(descriptor, &descriptorStatus) == 0,
              fstatat(
                  rootDescriptor,
                  Self.stateFileName,
                  &linkedStatus,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              linkedStatus.st_dev == descriptorStatus.st_dev,
              linkedStatus.st_ino == descriptorStatus.st_ino else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state changed identity"
            )
        }
    }

    private func readState(descriptor: Int32) throws -> PersistentState? {
        _ = try verifyStateFile(descriptor: descriptor)
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "prepare local execution gate state read",
                code: errno
            )
        }
        guard before.st_size > 0 else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state is truncated"
            )
        }

        let expectedCount = Int(before.st_size)
        var data = Data()
        data.reserveCapacity(expectedCount)
        var buffer = [UInt8](repeating: 0, count: min(8 * 1_024, expectedCount))
        while data.count < expectedCount {
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, expectedCount - data.count))
            if count > 0 {
                data.append(buffer, count: count)
                continue
            }
            if count == -1, errno == EINTR { continue }
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state could not be read completely"
            )
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0,
              after.st_dev == before.st_dev,
              after.st_ino == before.st_ino,
              after.st_size == before.st_size else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state changed while it was read"
            )
        }

        let state: PersistentState
        do {
            state = try PropertyListDecoder().decode(PersistentState.self, from: data)
        } catch {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state is malformed"
            )
        }
        guard state.version == Self.stateVersion,
              state.userID == UInt32(geteuid()),
              UUID(uuidString: state.generation) != nil,
              state.blocked
                ? (state.reason?.isEmpty == false
                    && (state.reason?.count ?? 0) <= Self.maximumReasonCharacters)
                : state.reason == nil else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "the per-user execution gate state failed authentication"
            )
        }
        return state.blocked ? state : nil
    }

    private func writeState(
        _ state: PersistentState?,
        descriptor: Int32,
        rootDescriptor: Int32
    ) throws {
        let persistedState: PersistentState
        if let state {
            persistedState = state
        } else {
            persistedState = PersistentState(
                version: Self.stateVersion,
                userID: UInt32(geteuid()),
                bootIdentity: try bootIdentityProvider(),
                blocked: false,
                generation: UUID().uuidString.lowercased(),
                reason: nil
            )
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(persistedState)
        guard data.count <= Self.maximumStateBytes else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        guard ftruncate(descriptor, 0) == 0,
              lseek(descriptor, 0, SEEK_SET) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "reset local execution gate state",
                code: errno
            )
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                } else if count == -1, errno == EINTR {
                    continue
                } else {
                    throw BoundedProcessRunnerError.systemCallFailed(
                        operation: "write local execution gate state",
                        code: errno == 0 ? EIO : errno
                    )
                }
            }
        }
        guard fsync(descriptor) == 0, fsync(rootDescriptor) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "synchronize local execution gate state",
                code: errno
            )
        }
    }
}

struct LaunchdBrokerRequestDeliveryState {
    private(set) var completed = false

    mutating func record<T>(_ delivery: () throws -> T) rethrows -> T {
        let value = try delivery()
        completed = true
        return value
    }

    func verifiesLeaseWasImpossible(brokerWasReaped: Bool) -> Bool {
        !completed && brokerWasReaped
    }
}

struct LaunchdProcessBrokerClient: Sendable {
    private static let brokerStartupWaitSeconds: TimeInterval = 3
    private static let brokerCleanupWaitSeconds: TimeInterval = 8
    private static let brokerStopWatchdogSeconds: TimeInterval = 2
    private static let responseGraceSeconds: TimeInterval = 8

    let maximumRetainedBytesPerStream: Int
    let executionGate: LaunchdLocalExecutionGate

    init(
        maximumRetainedBytesPerStream: Int,
        executionGate: LaunchdLocalExecutionGate = .shared
    ) {
        self.maximumRetainedBytesPerStream = maximumRetainedBytesPerStream
        self.executionGate = executionGate
    }

    func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval?,
        timeoutDiagnostic: String? = nil
    ) throws -> BoundedProcessResult {
        guard LaunchdProcessNamespace.current.isValid else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        try executionGate.check()
        do {
            return try runAfterGate(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                timeoutSeconds: timeoutSeconds,
                timeoutDiagnostic: timeoutDiagnostic
            )
        } catch {
            if let bounded = error as? BoundedProcessRunnerError,
               case .secureCleanupUnverified(let reason) = bounded {
                do {
                    try executionGate.block(reason: reason)
                } catch {
                    throw error
                }
            }
            throw error
        }
    }

    private func runAfterGate(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String]?,
        timeoutSeconds: TimeInterval?,
        timeoutDiagnostic: String?
    ) throws -> BoundedProcessResult {
        guard maximumRetainedBytesPerStream > 0,
              timeoutSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        try Task.checkCancellation()

        let deadline = timeoutSeconds.map {
            LaunchdMonotonicClock.adding(seconds: $0, to: LaunchdMonotonicClock.now())
        }
        let request = LaunchdBrokerRequest(
            executablePath: executableURL.path,
            arguments: arguments,
            workingDirectoryPath: workingDirectory.path,
            environment: LaunchdProcessEnvironment.sanitized(
                environment ?? ProcessInfo.processInfo.environment
            ),
            maximumRetainedBytesPerStream: maximumRetainedBytesPerStream,
            deadline: deadline,
            timeoutDiagnostic: timeoutDiagnostic
        )
        try request.validate()
        if let deadline, LaunchdMonotonicClock.now() >= deadline {
            return .timeoutResult(
                diagnostic: timeoutDiagnostic,
                maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
            )
        }
        let broker = try LaunchdBrokerProcess.spawn()
        var latestLease: LaunchdProcessLease?
        var cleanupVerified = false
        var cancellationSent = false
        var brokerStoppedSince: UInt64?
        var requestDelivery = LaunchdBrokerRequestDeliveryState()
        var responseDeadline = deadline.map {
            LaunchdMonotonicClock.adding(seconds: Self.responseGraceSeconds, to: $0)
        }
        let startupDeadline = min(
            deadline ?? UInt64.max,
            LaunchdMonotonicClock.adding(
                seconds: Self.brokerStartupWaitSeconds,
                to: LaunchdMonotonicClock.now()
            )
        )

        var finalized = false
        func terminateAndReapBroker(waitSeconds: TimeInterval) -> Bool {
            if !broker.isStopped, broker.waitForExit(timeoutSeconds: waitSeconds) {
                return true
            }
            return broker.forceCleanup()
        }
        func finalizeBrokerAndCleanup() throws {
            guard !finalized else { return }
            broker.connection.close()
            broker.closeOwnerLiveness()
            if cleanupVerified {
                guard terminateAndReapBroker(
                    waitSeconds: Self.responseGraceSeconds
                ) else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "broker process could not be reaped after verified payload cleanup"
                    )
                }
                finalized = true
                return
            }

            let brokerWasReaped = terminateAndReapBroker(
                waitSeconds: Self.brokerCleanupWaitSeconds
            )
            guard let latestLease else {
                if requestDelivery.verifiesLeaseWasImpossible(
                    brokerWasReaped: brokerWasReaped
                ) {
                    cleanupVerified = true
                    finalized = true
                    return
                }
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "broker ended before a cleanup lease was established"
                )
            }
            guard brokerWasReaped else {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "broker process could not be reaped before fallback cleanup"
                )
            }
            do {
                try latestLease.emergencyCleanup()
            } catch {
                let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                    ?? error.localizedDescription
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "client fallback cleanup failed: \(detail)"
                )
            }
            cleanupVerified = true
            finalized = true
        }
        defer {
            if !finalized {
                broker.connection.close()
                broker.closeOwnerLiveness()
                if broker.isStopped
                    || !broker.waitForExit(timeoutSeconds: Self.brokerCleanupWaitSeconds) {
                    broker.forceCleanup()
                }
            }
        }

        do {
            try requestDelivery.record {
                try broker.connection.writeFrame(
                    request,
                    deadline: { startupDeadline },
                    pollHook: { try Task.checkCancellation() }
                )
            }
            while true {
                let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                    deadline: { responseDeadline },
                    pollHook: {
                        if Task.isCancelled, !cancellationSent {
                            responseDeadline = LaunchdMonotonicClock.adding(
                                seconds: Self.responseGraceSeconds,
                                to: LaunchdMonotonicClock.now()
                            )
                            do {
                                try broker.connection.sendCancellation(
                                    deadline: { responseDeadline }
                                )
                                cancellationSent = true
                            } catch {
                                throw CancellationError()
                            }
                        }
                        try broker.verifyResponsive(
                            stoppedSince: &brokerStoppedSince,
                            graceSeconds: Self.brokerStopWatchdogSeconds
                        )
                    }
                )
                switch event.kind {
                case .prepared, .ready:
                    guard let lease = event.lease else {
                        throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                    }
                    latestLease = lease
                case .completed:
                    guard let result = event.result,
                          event.cleanupVerified == true else {
                        throw BoundedProcessRunnerError
                            .secureContainmentVerificationFailed
                    }
                    cleanupVerified = true
                    try finalizeBrokerAndCleanup()
                    if cancellationSent || Task.isCancelled {
                        throw CancellationError()
                    }
                    return result
                case .cancelled:
                    guard event.cleanupVerified == true else {
                        throw BoundedProcessRunnerError.secureCleanupUnverified(
                            "broker cancellation did not attest cleanup"
                        )
                    }
                    cleanupVerified = true
                    throw CancellationError()
                case .failed:
                    let detail = event.errorMessage ?? "unknown broker error"
                    if event.cleanupVerified == true { cleanupVerified = true }
                    switch event.failureKind {
                    case .cleanupUnverified:
                        guard event.cleanupVerified != true else {
                            throw BoundedProcessRunnerError
                                .secureContainmentVerificationFailed
                        }
                        throw BoundedProcessRunnerError.secureCleanupUnverified(detail)
                    case .containmentUnavailable:
                        throw BoundedProcessRunnerError.secureContainmentUnavailable
                    case .general, nil:
                        throw BoundedProcessRunnerError.secureBrokerFailed(detail)
                    }
                }
            }
        } catch let originalError {
            let cancellationWasRequested = originalError is CancellationError
                || Task.isCancelled
            let deadlineExpired = if let deadline,
                                     LaunchdMonotonicClock.now() >= deadline,
                                     let bounded = originalError as? BoundedProcessRunnerError,
                                     bounded == .secureContainmentVerificationFailed {
                true
            } else {
                false
            }
            let neededFallback = !cleanupVerified
            do {
                try finalizeBrokerAndCleanup()
            } catch {
                throw error
            }
            if cancellationWasRequested {
                throw CancellationError()
            }
            if deadlineExpired {
                return .timeoutResult(
                    diagnostic: timeoutDiagnostic,
                    maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
                )
            }
            if neededFallback,
               let bounded = originalError as? BoundedProcessRunnerError,
               case .secureCleanupUnverified = bounded {
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "\(bounded.diagnosticDescription); client fallback cleanup verified"
                )
            }
            throw originalError
        }
    }

}

enum LaunchdProcessBrokerEntry {
    static let modeArgument = "--cocxy-bounded-process-broker"

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.count >= 2, arguments[1] == modeArgument else { return nil }
        guard arguments.count == 4,
              let descriptor = Int32(arguments[2]),
              descriptor >= 0,
              let ownerLivenessDescriptor = Int32(arguments[3]),
              ownerLivenessDescriptor >= 0 else {
            return 64
        }
        let ownerLiveness = LaunchdOwnedFileDescriptor(ownerLivenessDescriptor)
        defer { ownerLiveness.close() }
        do {
            let connection = try LaunchdBrokerConnection(descriptor: descriptor)
            defer { connection.close() }
            let requestDeadline = LaunchdMonotonicClock.adding(
                seconds: 3,
                to: LaunchdMonotonicClock.now()
            )
            let request: LaunchdBrokerRequest = try connection.readFrame(
                deadline: { requestDeadline },
                pollHook: {}
            )
            try request.validate()

            let cancellationState = LaunchdBrokerCancellationState()
            try connection.startCancellationMonitor(state: cancellationState)
            let runner = LaunchdCoalitionProcessRunner(
                maximumRetainedBytesPerStream: request.maximumRetainedBytesPerStream,
                observesTaskCancellation: false,
                externalCancellationRequested: {
                    cancellationState.isCancellationRequested()
                }
            )
            do {
                let result = try runner.run(
                    executableURL: URL(fileURLWithPath: request.executablePath),
                    arguments: request.arguments,
                    workingDirectory: URL(
                        fileURLWithPath: request.workingDirectoryPath,
                        isDirectory: true
                    ),
                    environment: LaunchdProcessEnvironment.sanitized(request.environment),
                    ownerLivenessDescriptor: ownerLiveness.rawValue,
                    deadline: request.deadline,
                    timeoutDiagnostic: request.timeoutDiagnostic,
                    onPrepared: { lease in
                        try connection.writeFrame(
                            LaunchdBrokerEvent(kind: .prepared, lease: lease)
                        )
                    },
                    onReady: { lease in
                        try connection.writeFrame(
                            LaunchdBrokerEvent(kind: .ready, lease: lease)
                        )
                    }
                )
                try connection.writeFrame(
                    LaunchdBrokerEvent(
                        kind: .completed,
                        result: result,
                        cleanupVerified: true
                    )
                )
                return EXIT_SUCCESS
            } catch is CancellationError {
                try? connection.writeFrame(
                    LaunchdBrokerEvent(kind: .cancelled, cleanupVerified: true)
                )
                return EXIT_SUCCESS
            } catch {
                let boundedError = error as? BoundedProcessRunnerError
                let failureKind: LaunchdBrokerFailureKind = switch boundedError {
                case .secureCleanupUnverified:
                    .cleanupUnverified
                case .secureContainmentUnavailable:
                    .containmentUnavailable
                default:
                    .general
                }
                try? connection.writeFrame(
                    LaunchdBrokerEvent(
                        kind: .failed,
                        errorMessage: boundedError?.diagnosticDescription
                            ?? error.localizedDescription,
                        failureKind: failureKind,
                        cleanupVerified: failureKind != .cleanupUnverified
                    )
                )
                return EXIT_FAILURE
            }
        } catch {
            return EXIT_FAILURE
        }
    }
}

struct LaunchdBrokerRequest: Codable {
    private static let maximumArgumentCount = 4_096
    private static let maximumEnvironmentCount = 512
    private static let maximumDiagnosticBytes = 16 * 1_024
    private static let maximumRequestTextBytes: Int = {
        let value = sysconf(_SC_ARG_MAX)
        return value > 0 ? Int(value) : 1 * 1_024 * 1_024
    }()

    let executablePath: String
    let arguments: [String]
    let workingDirectoryPath: String
    let environment: [String: String]
    let maximumRetainedBytesPerStream: Int
    let deadline: UInt64?
    let timeoutDiagnostic: String?

    func validate() throws {
        guard executablePath.hasPrefix("/"),
              workingDirectoryPath.hasPrefix("/"),
              !executablePath.utf8.contains(0),
              !workingDirectoryPath.utf8.contains(0),
              executablePath.utf8.count < Int(PATH_MAX),
              workingDirectoryPath.utf8.count < Int(PATH_MAX),
              arguments.count <= Self.maximumArgumentCount,
              arguments.allSatisfy({ !$0.utf8.contains(0) }),
              environment.count <= Self.maximumEnvironmentCount,
              environment.allSatisfy({ key, value in
                  !key.isEmpty
                      && !key.contains("=")
                      && !key.utf8.contains(0)
                      && !value.utf8.contains(0)
              }),
              (timeoutDiagnostic?.utf8.count ?? 0) <= Self.maximumDiagnosticBytes,
              timeoutDiagnostic?.utf8.contains(0) != true,
              requestTextByteCount <= Self.maximumRequestTextBytes,
              maximumRetainedBytesPerStream > 0,
              maximumRetainedBytesPerStream <= 16 * 1_024 * 1_024 else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
    }

    private var requestTextByteCount: Int {
        executablePath.utf8.count
            + workingDirectoryPath.utf8.count
            + arguments.reduce(0) { $0 + $1.utf8.count + 1 }
            + environment.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count + 2 }
    }
}

enum LaunchdBrokerEventKind: String, Codable {
    case prepared
    case ready
    case completed
    case cancelled
    case failed
}

enum LaunchdBrokerFailureKind: String, Codable {
    case general
    case cleanupUnverified
    case containmentUnavailable
}

struct LaunchdBrokerEvent: Codable {
    let kind: LaunchdBrokerEventKind
    let lease: LaunchdProcessLease?
    let result: BoundedProcessResult?
    let errorMessage: String?
    let failureKind: LaunchdBrokerFailureKind?
    let cleanupVerified: Bool?

    init(
        kind: LaunchdBrokerEventKind,
        lease: LaunchdProcessLease? = nil,
        result: BoundedProcessResult? = nil,
        errorMessage: String? = nil,
        failureKind: LaunchdBrokerFailureKind? = nil,
        cleanupVerified: Bool? = nil
    ) {
        self.kind = kind
        self.lease = lease
        self.result = result
        self.errorMessage = errorMessage
        self.failureKind = failureKind
        self.cleanupVerified = cleanupVerified
    }
}

final class LaunchdBrokerCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false

    func requestCancellation() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    func isCancellationRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }
}

final class LaunchdBrokerConnection: @unchecked Sendable {
    private static let maximumFrameBytes = 40 * 1_024 * 1_024
    private static let maximumFrameOperationSeconds: TimeInterval = 5
    private static let maximumTransferredFileDescriptors = 8
    private static let pollIntervalMilliseconds: Int32 = 20

    private let lock = NSLock()
    private var descriptor: Int32

    init(descriptor: Int32) throws {
        guard descriptor >= 0 else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        self.descriptor = descriptor
        try Self.configure(descriptor: descriptor)
    }

    deinit { close() }

    func writeFrame<T: Encodable>(
        _ value: T,
        deadline: @escaping () -> UInt64? = { nil },
        pollHook: () throws -> Void = {}
    ) throws {
        let hardDeadline = LaunchdMonotonicClock.adding(
            seconds: Self.maximumFrameOperationSeconds,
            to: LaunchdMonotonicClock.now()
        )
        let effectiveDeadline = {
            min(deadline() ?? UInt64.max, hardDeadline)
        }
        try Self.checkBoundary(deadline: effectiveDeadline, pollHook: pollHook)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(value)
        try Self.checkBoundary(deadline: effectiveDeadline, pollHook: pollHook)
        guard payload.count <= Self.maximumFrameBytes else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        var length = UInt32(payload.count).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        try withDescriptor { descriptor in
            try Self.writeAll(
                  header,
                  to: descriptor,
                  deadline: effectiveDeadline,
                  pollHook: pollHook
              )
            try Self.writeAll(
                  payload,
                  to: descriptor,
                  deadline: effectiveDeadline,
                  pollHook: pollHook
              )
        }
    }

    func readFrame<T: Decodable>(
        deadline: @escaping () -> UInt64?,
        pollHook: () throws -> Void
    ) throws -> T {
        var transferDeadline: UInt64?
        let effectiveDeadline = {
            min(deadline() ?? UInt64.max, transferDeadline ?? UInt64.max)
        }
        try Self.checkBoundary(deadline: effectiveDeadline, pollHook: pollHook)
        let header = try readExactly(
            count: MemoryLayout<UInt32>.size,
            deadline: effectiveDeadline,
            pollHook: pollHook,
            onFirstByte: {
                transferDeadline = LaunchdMonotonicClock.adding(
                    seconds: Self.maximumFrameOperationSeconds,
                    to: LaunchdMonotonicClock.now()
                )
            }
        )
        let length = header.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
        guard length <= Self.maximumFrameBytes else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        let payload = try readExactly(
            count: Int(length),
            deadline: effectiveDeadline,
            pollHook: pollHook
        )
        // Once the authenticated peer's complete bounded frame is in memory,
        // its process may exit normally. Preserve that definitive response while
        // still enforcing the transfer deadline around synchronous decoding.
        try Self.checkBoundary(deadline: effectiveDeadline, pollHook: {})
        let value = try PropertyListDecoder().decode(T.self, from: payload)
        try Self.checkBoundary(deadline: effectiveDeadline, pollHook: {})
        return value
    }

    func sendCancellation(deadline: () -> UInt64?) throws {
        var byte: UInt8 = 1
        try withDescriptor { descriptor in
            while true {
                if let deadline = deadline(), LaunchdMonotonicClock.now() >= deadline {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                let count = Darwin.send(descriptor, &byte, 1, 0)
                if count == 1 { return }
                if count == -1, errno == EINTR { continue }
                if count == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                    try Self.wait(descriptor: descriptor, events: Int16(POLLOUT))
                    continue
                }
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "send broker cancellation",
                    code: errno
                )
            }
        }
    }

    func sendFileDescriptors(
        _ descriptors: [Int32],
        deadline: () -> UInt64?,
        pollHook: () throws -> Void
    ) throws {
        guard !descriptors.isEmpty,
              descriptors.count <= Self.maximumTransferredFileDescriptors,
              descriptors.allSatisfy({ $0 >= 0 }) else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        let alignment = max(
            MemoryLayout<cmsghdr>.alignment,
            MemoryLayout<Int32>.alignment
        )
        let descriptorOffset = Self.alignedSize(
            MemoryLayout<cmsghdr>.size,
            to: alignment
        )
        let messageLength = descriptorOffset
            + descriptors.count * MemoryLayout<Int32>.size
        let controlSize = Self.alignedSize(messageLength, to: alignment)
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
        for (index, descriptor) in descriptors.enumerated() {
            control.storeBytes(
                of: descriptor,
                toByteOffset: descriptorOffset + index * MemoryLayout<Int32>.size,
                as: Int32.self
            )
        }

        var payload: UInt8 = 1
        return try withDescriptor { controlDescriptor in
            try withUnsafeMutablePointer(to: &payload) { payloadPointer in
                var vector = iovec(
                    iov_base: UnsafeMutableRawPointer(payloadPointer),
                    iov_len: 1
                )
                try withUnsafeMutablePointer(to: &vector) { vectorPointer in
                    while true {
                        try Self.checkBoundary(deadline: deadline, pollHook: pollHook)
                        var message = msghdr()
                        message.msg_iov = vectorPointer
                        message.msg_iovlen = 1
                        message.msg_control = control
                        message.msg_controllen = socklen_t(controlSize)
                        let count = Darwin.sendmsg(controlDescriptor, &message, 0)
                        if count == 1 { return }
                        if count == -1, errno == EINTR { continue }
                        if count == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                            try Self.wait(
                                descriptor: controlDescriptor,
                                events: Int16(POLLOUT)
                            )
                            continue
                        }
                        throw BoundedProcessRunnerError.systemCallFailed(
                            operation: "send supervisor descriptors",
                            code: errno
                        )
                    }
                }
            }
        }
    }

    func receiveFileDescriptors(
        count expectedCount: Int,
        deadline: () -> UInt64?,
        pollHook: () throws -> Void
    ) throws -> [LaunchdOwnedFileDescriptor] {
        guard expectedCount > 0,
              expectedCount <= Self.maximumTransferredFileDescriptors else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        let alignment = max(
            MemoryLayout<cmsghdr>.alignment,
            MemoryLayout<Int32>.alignment
        )
        let descriptorOffset = Self.alignedSize(
            MemoryLayout<cmsghdr>.size,
            to: alignment
        )
        let singleRecordSize = Self.alignedSize(
            descriptorOffset + MemoryLayout<Int32>.size,
            to: alignment
        )
        let controlSize = singleRecordSize * Self.maximumTransferredFileDescriptors
        let control = UnsafeMutableRawPointer.allocate(
            byteCount: controlSize,
            alignment: alignment
        )
        defer { control.deallocate() }
        var payload: UInt8 = 0

        return try withDescriptor { controlDescriptor in
            return try withUnsafeMutablePointer(to: &payload) { payloadPointer in
                var vector = iovec(
                    iov_base: UnsafeMutableRawPointer(payloadPointer),
                    iov_len: 1
                )
                return try withUnsafeMutablePointer(to: &vector) { vectorPointer in
                    while true {
                        try Self.checkBoundary(deadline: deadline, pollHook: pollHook)
                        _ = memset(control, 0, controlSize)
                        var message = msghdr()
                        message.msg_iov = vectorPointer
                        message.msg_iovlen = 1
                        message.msg_control = control
                        message.msg_controllen = socklen_t(controlSize)
                        let received = Darwin.recvmsg(controlDescriptor, &message, 0)
                        if received == 1 {
                            let descriptors = try Self.decodeFileDescriptors(
                                control: control,
                                controlLength: Int(message.msg_controllen),
                                descriptorOffset: descriptorOffset,
                                expectedCount: expectedCount
                            )
                            guard message.msg_flags & MSG_CTRUNC == 0,
                                  payloadPointer.pointee == 1 else {
                                descriptors.forEach { $0.close() }
                                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                            }
                            return descriptors
                        }
                        if received == 0 {
                            throw BoundedProcessRunnerError.secureBrokerFailed(
                                "supervisor descriptor channel closed"
                            )
                        }
                        if received == -1, errno == EINTR { continue }
                        if received == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                            try Self.wait(
                                descriptor: controlDescriptor,
                                events: Int16(POLLIN)
                            )
                            continue
                        }
                        throw BoundedProcessRunnerError.systemCallFailed(
                            operation: "receive supervisor descriptors",
                            code: errno
                        )
                    }
                }
            }
        }
    }

    func startCancellationMonitor(state: LaunchdBrokerCancellationState) throws {
        let monitoredDescriptor = try withDescriptor { descriptor -> Int32 in
            let duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 0)
            guard duplicate >= 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "duplicate broker control channel",
                    code: errno
                )
            }
            return duplicate
        }
        Thread.detachNewThread {
            defer { _ = Darwin.close(monitoredDescriptor) }
            var byte: UInt8 = 0
            while true {
                var descriptor = pollfd(
                    fd: monitoredDescriptor,
                    events: Int16(POLLIN | POLLHUP | POLLERR),
                    revents: 0
                )
                let result = Darwin.poll(&descriptor, 1, 100)
                if result == -1, errno == EINTR { continue }
                if result == -1 {
                    state.requestCancellation()
                    return
                }
                if result == 0 { continue }
                let count = Darwin.read(monitoredDescriptor, &byte, 1)
                if count == 1 || count == 0 {
                    state.requestCancellation()
                    return
                }
                if count == -1, errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                    continue
                }
                state.requestCancellation()
                return
            }
        }
    }

    func peerHasClosed() throws -> Bool {
        var byte: UInt8 = 0
        return try withDescriptor { descriptor in
            let count = Darwin.recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
            if count == 0 { return true }
            if count > 0 { return false }
            if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { return false }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "inspect broker owner channel",
                code: errno
            )
        }
    }

    func hasPendingData() throws -> Bool {
        var byte: UInt8 = 0
        return try withDescriptor { descriptor in
            while true {
                let count = Darwin.recv(
                    descriptor,
                    &byte,
                    1,
                    MSG_PEEK | MSG_DONTWAIT
                )
                if count > 0 { return true }
                if count == 0 { return false }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { return false }
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "inspect buffered broker response",
                    code: errno
                )
            }
        }
    }

    func close() {
        lock.lock()
        let current = descriptor
        descriptor = -1
        lock.unlock()
        guard current >= 0 else { return }
        _ = Darwin.shutdown(current, SHUT_RDWR)
        _ = Darwin.close(current)
    }

    private func readExactly(
        count: Int,
        deadline: () -> UInt64?,
        pollHook: () throws -> Void,
        onFirstByte: () -> Void = {}
    ) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            try pollHook()
            if let deadline = deadline(), LaunchdMonotonicClock.now() >= deadline {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            let bytesRead = try withDescriptor { descriptor in
                data.withUnsafeMutableBytes { buffer in
                    Darwin.read(
                        descriptor,
                        buffer.baseAddress!.advanced(by: offset),
                        count - offset
                    )
                }
            }
            if bytesRead > 0 {
                if offset == 0 { onFirstByte() }
                offset += bytesRead
                continue
            }
            if bytesRead == 0 {
                throw BoundedProcessRunnerError.secureBrokerFailed("broker channel closed")
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK {
                try withDescriptor { descriptor in
                    try Self.wait(descriptor: descriptor, events: Int16(POLLIN))
                }
                continue
            }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read broker channel",
                code: errno
            )
        }
        return data
    }

    private func withDescriptor<T>(_ body: (Int32) throws -> T) throws -> T {
        lock.lock()
        let current = descriptor
        lock.unlock()
        guard current >= 0 else {
            throw BoundedProcessRunnerError.secureBrokerFailed("broker channel is closed")
        }
        return try body(current)
    }

    private static func configure(descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0,
              fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0,
              fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "configure broker channel",
                code: errno
            )
        }
        var enabled: Int32 = 1
        guard setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "configure broker SIGPIPE",
                code: errno
            )
        }
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        deadline: () -> UInt64?,
        pollHook: () throws -> Void
    ) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try checkBoundary(deadline: deadline, pollHook: pollHook)
                let count = Darwin.write(
                    descriptor,
                    bytes.baseAddress!.advanced(by: offset),
                    bytes.count - offset
                )
                if count > 0 {
                    offset += count
                    continue
                }
                if count == -1, errno == EINTR { continue }
                if count == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                    try wait(descriptor: descriptor, events: Int16(POLLOUT))
                    continue
                }
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "write broker channel",
                    code: errno
                )
            }
        }
    }

    private static func checkBoundary(
        deadline: () -> UInt64?,
        pollHook: () throws -> Void
    ) throws {
        try pollHook()
        if let deadline = deadline(), LaunchdMonotonicClock.now() >= deadline {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }

    private static func decodeFileDescriptors(
        control: UnsafeMutableRawPointer,
        controlLength: Int,
        descriptorOffset: Int,
        expectedCount: Int
    ) throws -> [LaunchdOwnedFileDescriptor] {
        guard controlLength >= descriptorOffset else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let alignment = max(
            MemoryLayout<cmsghdr>.alignment,
            MemoryLayout<Int32>.alignment
        )
        var descriptors: [LaunchdOwnedFileDescriptor] = []
        do {
            var offset = 0
            var rightsRecordCount = 0
            var malformed = false
            while offset < controlLength {
                let remaining = controlLength - offset
                guard remaining >= MemoryLayout<cmsghdr>.size else {
                    malformed = true
                    break
                }
                let header = control.load(fromByteOffset: offset, as: cmsghdr.self)
                let declaredLength = Int(header.cmsg_len)
                guard declaredLength >= descriptorOffset,
                      declaredLength <= remaining else {
                    malformed = true
                    break
                }
                if header.cmsg_level == SOL_SOCKET, header.cmsg_type == SCM_RIGHTS {
                    rightsRecordCount += 1
                    let descriptorBytes = declaredLength - descriptorOffset
                    if !descriptorBytes.isMultiple(of: MemoryLayout<Int32>.size) {
                        malformed = true
                    }
                    let receivedCount = descriptorBytes / MemoryLayout<Int32>.size
                    for index in 0..<receivedCount {
                        let rawDescriptor = control.load(
                            fromByteOffset: offset + descriptorOffset
                                + index * MemoryLayout<Int32>.size,
                            as: Int32.self
                        )
                        guard rawDescriptor >= 0 else {
                            throw BoundedProcessRunnerError
                                .secureContainmentVerificationFailed
                        }
                        let descriptor = LaunchdOwnedFileDescriptor(rawDescriptor)
                        try descriptor.relocateAboveStandardDescriptors()
                        guard fcntl(descriptor.rawValue, F_SETFD, FD_CLOEXEC) == 0 else {
                            throw BoundedProcessRunnerError.systemCallFailed(
                                operation: "protect received supervisor descriptor",
                                code: errno
                            )
                        }
                        descriptors.append(descriptor)
                    }
                } else {
                    malformed = true
                }

                let alignedLength = alignedSize(declaredLength, to: alignment)
                if alignedLength > remaining {
                    guard declaredLength == remaining else {
                        malformed = true
                        break
                    }
                    offset = controlLength
                } else {
                    offset += alignedLength
                }
            }
            guard !malformed,
                  offset == controlLength,
                  rightsRecordCount == 1,
                  descriptors.count == expectedCount else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            return descriptors
        } catch {
            descriptors.forEach { $0.close() }
            throw error
        }
    }

    private static func alignedSize(_ size: Int, to alignment: Int) -> Int {
        (size + alignment - 1) & ~(alignment - 1)
    }

    private static func wait(descriptor: Int32, events: Int16) throws {
        var descriptor = pollfd(fd: descriptor, events: events, revents: 0)
        let result = Darwin.poll(&descriptor, 1, Self.pollIntervalMilliseconds)
        if result == -1, errno != EINTR {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "poll broker channel",
                code: errno
            )
        }
    }
}

final class LaunchdBrokerProcess {
    private static let forceCleanupWaitSeconds: TimeInterval = 2

    let pid: pid_t
    let identity: LaunchdProcessIdentity
    let connection: LaunchdBrokerConnection
    private let ownerLiveness: LaunchdOwnedFileDescriptor
    private var reaped = false

    private init(
        pid: pid_t,
        identity: LaunchdProcessIdentity,
        connection: LaunchdBrokerConnection,
        ownerLiveness: LaunchdOwnedFileDescriptor
    ) {
        self.pid = pid
        self.identity = identity
        self.connection = connection
        self.ownerLiveness = ownerLiveness
    }

    deinit {
        if !reaped { _ = forceCleanup() }
    }

    static func spawn() throws -> LaunchdBrokerProcess {
        let executableURL = try brokerExecutableURL()
        var sockets: [Int32] = [-1, -1]
        var ownerLivenessSockets: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "create broker socketpair",
                code: errno
            )
        }
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &ownerLivenessSockets) == 0 else {
            let code = errno
            sockets.forEach { _ = Darwin.close($0) }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "create application liveness socketpair",
                code: code
            )
        }
        do {
            try normalizeSocketDescriptors(&sockets)
            try normalizeSocketDescriptors(&ownerLivenessSockets)
        } catch {
            for descriptor in sockets + ownerLivenessSockets where descriptor >= 0 {
                _ = Darwin.close(descriptor)
            }
            throw error
        }
        let parentDescriptor = LaunchdOwnedFileDescriptor(sockets[0])
        let childDescriptor = LaunchdOwnedFileDescriptor(sockets[1])
        let parentOwnerLiveness = LaunchdOwnedFileDescriptor(ownerLivenessSockets[0])
        let childOwnerLiveness = LaunchdOwnedFileDescriptor(ownerLivenessSockets[1])
        do {
            let connection = try LaunchdBrokerConnection(descriptor: parentDescriptor.rawValue)
            parentDescriptor.releaseOwnership()

            var fileActions: posix_spawn_file_actions_t?
            try BoundedPOSIX.check(
                posix_spawn_file_actions_init(&fileActions),
                operation: "posix_spawn_file_actions_init broker"
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
                operation: "open broker stdin"
            )
            for descriptor in [STDOUT_FILENO, STDERR_FILENO] {
                try BoundedPOSIX.check(
                    posix_spawn_file_actions_addopen(
                        &fileActions,
                        descriptor,
                        "/dev/null",
                        O_WRONLY,
                        0
                    ),
                    operation: "open broker output"
                )
            }
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addclose(&fileActions, sockets[0]),
                operation: "close broker parent channel"
            )
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addclose(
                    &fileActions,
                    ownerLivenessSockets[0]
                ),
                operation: "close broker owner-liveness parent channel"
            )
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addinherit_np(&fileActions, sockets[1]),
                operation: "inherit broker child channel"
            )
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addinherit_np(
                    &fileActions,
                    ownerLivenessSockets[1]
                ),
                operation: "inherit broker owner-liveness child channel"
            )

            var attributes: posix_spawnattr_t?
            try BoundedPOSIX.check(
                posix_spawnattr_init(&attributes),
                operation: "posix_spawnattr_init broker"
            )
            defer { posix_spawnattr_destroy(&attributes) }
            var emptySignalMask = sigset_t()
            sigemptyset(&emptySignalMask)
            try BoundedPOSIX.check(
                posix_spawnattr_setsigmask(&attributes, &emptySignalMask),
                operation: "posix_spawnattr_setsigmask broker"
            )
            var defaultSignals = sigset_t()
            sigfillset(&defaultSignals)
            try BoundedPOSIX.check(
                posix_spawnattr_setsigdefault(&attributes, &defaultSignals),
                operation: "posix_spawnattr_setsigdefault broker"
            )
            let flags = POSIX_SPAWN_CLOEXEC_DEFAULT
                | POSIX_SPAWN_SETSID
                | POSIX_SPAWN_START_SUSPENDED
                | POSIX_SPAWN_SETSIGDEF
                | POSIX_SPAWN_SETSIGMASK
            try BoundedPOSIX.check(
                posix_spawnattr_setflags(&attributes, Int16(flags)),
                operation: "posix_spawnattr_setflags broker"
            )

            var pid: pid_t = 0
            let invocation = [
                executableURL.path,
                LaunchdProcessBrokerEntry.modeArgument,
                String(sockets[1]),
                String(ownerLivenessSockets[1]),
            ]
            var brokerEnvironment = LaunchdProcessEnvironment.sanitized(
                ProcessInfo.processInfo.environment
            )
            for (key, value) in LaunchdProcessNamespace.current.inheritedEnvironment {
                brokerEnvironment[key] = value
            }
            let environment = brokerEnvironment
                .map { "\($0.key)=\($0.value)" }
                .sorted()
            let code = try BoundedCStringArray.withMutablePointers(invocation) { argv in
                try BoundedCStringArray.withMutablePointers(environment) { envp in
                    executableURL.path.withCString { path in
                        posix_spawn(&pid, path, &fileActions, &attributes, argv, envp)
                    }
                }
            }
            try BoundedPOSIX.check(code, operation: "posix_spawn broker")
            childDescriptor.close()
            childOwnerLiveness.close()

            guard let snapshot = LaunchdProcessSnapshot.current(for: pid),
                  snapshot.userID == geteuid(),
                  snapshot.isLive else {
                connection.close()
                parentOwnerLiveness.close()
                guard terminateAndReapSpawnedProcess(pid) else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "unverified broker process could not be reaped"
                    )
                }
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            let process = LaunchdBrokerProcess(
                pid: pid,
                identity: snapshot.identity,
                connection: connection,
                ownerLiveness: parentOwnerLiveness
            )
            guard getpgid(pid) == pid, getsid(pid) == pid else {
                guard process.forceCleanup() else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "broker isolation failed and the broker could not be reaped"
                    )
                }
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            guard !Task.isCancelled else {
                guard process.forceCleanup() else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "cancelled broker could not be reaped"
                    )
                }
                throw CancellationError()
            }
            guard Darwin.kill(pid, SIGCONT) == 0 else {
                let code = errno
                guard process.forceCleanup() else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "broker resume failed and the broker could not be reaped"
                    )
                }
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "resume broker",
                    code: code
                )
            }
            return process
        } catch {
            parentDescriptor.close()
            childDescriptor.close()
            parentOwnerLiveness.close()
            childOwnerLiveness.close()
            throw error
        }
    }

    func closeOwnerLiveness() {
        ownerLiveness.close()
    }

    var isStopped: Bool {
        guard let snapshot = LaunchdProcessSnapshot.current(for: identity.pid),
              snapshot.identity == identity,
              snapshot.isLive else {
            return false
        }
        return snapshot.status == UInt32(SSTOP)
    }

    func verifyResponsive(
        stoppedSince: inout UInt64?,
        graceSeconds: TimeInterval
    ) throws {
        if try connection.hasPendingData() {
            stoppedSince = nil
            return
        }
        guard let snapshot = LaunchdProcessSnapshot.current(for: identity.pid),
              snapshot.identity == identity,
              snapshot.isLive else {
            throw BoundedProcessRunnerError.secureBrokerFailed(
                "broker process identity is no longer live"
            )
        }
        guard snapshot.status == UInt32(SSTOP) else {
            stoppedSince = nil
            return
        }
        let now = LaunchdMonotonicClock.now()
        let observedSince = stoppedSince ?? now
        stoppedSince = observedSince
        if now >= LaunchdMonotonicClock.adding(
            seconds: graceSeconds,
            to: observedSince
        ) {
            throw BoundedProcessRunnerError.secureBrokerFailed(
                "broker process stopped responding"
            )
        }
    }

    func waitForExit(timeoutSeconds: TimeInterval) -> Bool {
        guard !reaped else { return true }
        let deadline = LaunchdMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: LaunchdMonotonicClock.now()
        )
        var status: Int32 = 0
        while LaunchdMonotonicClock.now() < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid {
                reaped = true
                return true
            }
            if result == -1, errno == ECHILD {
                reaped = true
                return true
            }
            if result == -1, errno != EINTR { return false }
            usleep(10_000)
        }
        let finalResult = waitpid(pid, &status, WNOHANG)
        if finalResult == pid || (finalResult == -1 && errno == ECHILD) {
            reaped = true
            return true
        }
        return false
    }

    @discardableResult
    func forceCleanup() -> Bool {
        guard !reaped else { return true }
        closeOwnerLiveness()
        connection.close()
        _ = Darwin.kill(-pid, SIGKILL)
        _ = Darwin.kill(pid, SIGKILL)
        return waitForExit(timeoutSeconds: Self.forceCleanupWaitSeconds)
    }

    private static func terminateAndReapSpawnedProcess(_ pid: pid_t) -> Bool {
        _ = Darwin.kill(-pid, SIGKILL)
        _ = Darwin.kill(pid, SIGKILL)
        let deadline = LaunchdMonotonicClock.adding(
            seconds: forceCleanupWaitSeconds,
            to: LaunchdMonotonicClock.now()
        )
        var status: Int32 = 0
        while LaunchdMonotonicClock.now() < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { return true }
            if result == -1, errno == EINTR { continue }
            if result == -1, errno == ECHILD { return true }
            if result == -1 { return false }
            usleep(10_000)
        }
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid || (result == -1 && errno == ECHILD) {
            return true
        }
        return false
    }

    private static func brokerExecutableURL() throws -> URL {
        if let current = currentExecutableURL(), current.lastPathComponent == "CocxyTerminal",
           FileManager.default.isExecutableFile(atPath: current.path) {
            return current
        }
        for argument in CommandLine.arguments {
            guard let range = argument.range(of: ".xctest") else { continue }
            let bundlePath = String(argument[..<range.upperBound])
            let candidate = URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .appendingPathComponent("CocxyTerminal")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw BoundedProcessRunnerError.secureContainmentUnavailable
    }

    private static func normalizeSocketDescriptors(_ sockets: inout [Int32]) throws {
        for index in sockets.indices {
            if sockets[index] <= STDERR_FILENO {
                let duplicate = fcntl(sockets[index], F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
                guard duplicate >= 0 else {
                    throw BoundedProcessRunnerError.systemCallFailed(
                        operation: "relocate broker channel",
                        code: errno
                    )
                }
                _ = Darwin.close(sockets[index])
                sockets[index] = duplicate
            } else {
                guard fcntl(sockets[index], F_SETFD, FD_CLOEXEC) == 0 else {
                    throw BoundedProcessRunnerError.systemCallFailed(
                        operation: "protect broker channel",
                        code: errno
                    )
                }
            }
        }
    }

    private static func currentExecutableURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
    }
}
