// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LaunchdCoalitionProcessRunner.swift - Bounded execution in a verified launchd coalition.

import Darwin
import Foundation

/// Runs a contained local command in a dedicated launchd resource coalition.
struct LaunchdCoalitionProcessRunner: Sendable {
    private static let pollIntervalMicroseconds: useconds_t = 20_000
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
        environment: [String: String],
        ownerLivenessDescriptor: Int32,
        deadline: UInt64?,
        timeoutDiagnostic: String? = nil,
        onPrepared: (@Sendable (LaunchdProcessLease) throws -> Void)? = nil,
        onReady: (@Sendable (LaunchdProcessLease) throws -> Void)? = nil
    ) throws -> BoundedProcessResult {
        guard maximumRetainedBytesPerStream > 0 else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        let boundary = LaunchdExecutionBoundary(
            deadline: deadline,
            cancellationRequested: { [self] in isCancellationRequested() }
        )
        do {
            try boundary.check()
        } catch LaunchdExecutionBoundaryError.deadlineExceeded {
            return .timeoutResult(
                diagnostic: timeoutDiagnostic,
                maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
            )
        }

        let execution: LaunchdCoalitionExecution
        do {
            execution = try LaunchdCoalitionExecution.start(
                executableURL: executableURL,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                ownerLivenessDescriptor: ownerLivenessDescriptor,
                retainedBytesPerStream: maximumRetainedBytesPerStream,
                boundary: boundary,
                timeoutDiagnostic: timeoutDiagnostic,
                onPrepared: onPrepared,
                onReady: onReady
            )
        } catch LaunchdExecutionBoundaryError.deadlineExceeded {
            return .timeoutResult(
                diagnostic: timeoutDiagnostic,
                maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw BoundedProcessRunnerError.contextual("launchd startup", error: error)
        }

        do {
            var stopReason: LaunchdProcessStopReason?
            var termination: LaunchdProcessTermination?
            while termination == nil, stopReason == nil {
                try execution.drainAvailableOutput()
                if try !execution.leaderIsRunning(boundary: boundary) {
                    termination = try execution.waitForTermination(
                        timeoutSeconds: Self.killWaitSeconds
                    )
                    if termination?.timedOut == true {
                        stopReason = .timedOut
                    }
                    break
                }
                if isCancellationRequested() {
                    stopReason = .cancelled
                } else if let deadline, LaunchdMonotonicClock.now() >= deadline {
                    stopReason = .timedOut
                } else {
                    usleep(Self.pollIntervalMicroseconds)
                }
            }
            try execution.terminateCoalition(
                gracePeriodSeconds: Self.terminationGracePeriodSeconds,
                killWaitSeconds: Self.killWaitSeconds
            )
            try execution.drainOutputToEnd(timeoutSeconds: Self.outputDrainWaitSeconds)
            let stdout = execution.stdoutString()
            let resultDiagnostic = stopReason == .timedOut ? timeoutDiagnostic : nil
            let stderr = execution.stderrString(diagnostic: resultDiagnostic)
            let stdoutWasTruncated = execution.stdoutWasTruncated
            let stderrWasTruncated = execution.stderrWasTruncated(
                diagnostic: resultDiagnostic
            )
            try execution.finishCleanup()

            switch stopReason {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                return BoundedProcessResult(
                    exitCode: 124,
                    stdout: stdout,
                    stderr: stderr,
                    stdoutWasTruncated: stdoutWasTruncated,
                    stderrWasTruncated: stderrWasTruncated,
                    timedOut: true
                )
            case nil:
                return BoundedProcessResult(
                    exitCode: termination?.status ?? 1,
                    stdout: stdout,
                    stderr: stderr,
                    stdoutWasTruncated: stdoutWasTruncated,
                    stderrWasTruncated: stderrWasTruncated,
                    timedOut: false
                )
            }
        } catch let originalError {
            do {
                try execution.verifiedCleanup()
            } catch {
                throw BoundedProcessRunnerError.contextual(
                    "launchd fallback cleanup",
                    error: error
                )
            }
            if originalError is LaunchdExecutionBoundaryError {
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
            }
            throw LaunchdCleanupAttestation.errorAfterVerifiedFallback(originalError)
        }
    }

    private func isCancellationRequested() -> Bool {
        (observesTaskCancellation && Task.isCancelled) || externalCancellationRequested()
    }

}

private enum LaunchdProcessStopReason {
    case cancelled
    case timedOut
}

enum LaunchdCleanupAttestation {
    static func errorAfterVerifiedFallback(_ originalError: Error) -> Error {
        guard let bounded = originalError as? BoundedProcessRunnerError,
              case .secureCleanupUnverified(let detail) = bounded else {
            return originalError
        }
        return BoundedProcessRunnerError.secureBrokerFailed(
            "\(detail); fallback cleanup was verified"
        )
    }
}

private struct LaunchdProcessTermination {
    let status: Int32
    let timedOut: Bool
}

private final class LaunchdCoalitionExecution {
    private static let maximumIOBytesPerCycle = 256 * 1_024
    private static let fallbackCleanupWaitSeconds: TimeInterval = 1
    private static let scanIntervalMicroseconds: useconds_t = 10_000

    private let artifacts: LaunchdProcessArtifacts
    private let control = LaunchdControlClient()
    private var domain: String?
    private var leaderIdentity: LaunchdProcessIdentity?
    private var coalitionID: UInt64?
    private var stdoutCapture: BoundedCapturedStream
    private var stderrCapture: BoundedCapturedStream
    private var stdoutReachedEOF = false
    private var stderrReachedEOF = false
    private var cleanupFinished = false

    private init(artifacts: LaunchdProcessArtifacts, retainedBytesPerStream: Int) {
        self.artifacts = artifacts
        stdoutCapture = BoundedCapturedStream(limit: retainedBytesPerStream)
        stderrCapture = BoundedCapturedStream(limit: retainedBytesPerStream)
    }

    static func start(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        ownerLivenessDescriptor: Int32,
        retainedBytesPerStream: Int,
        boundary: LaunchdExecutionBoundary,
        timeoutDiagnostic: String?,
        onPrepared: (@Sendable (LaunchdProcessLease) throws -> Void)?,
        onReady: (@Sendable (LaunchdProcessLease) throws -> Void)?
    ) throws -> LaunchdCoalitionExecution {
        try boundary.check()
        guard let brokerSnapshot = LaunchdProcessSnapshot.current(for: getpid()),
              brokerSnapshot.userID == getuid(),
              brokerSnapshot.isLive,
              let supervisorCoalitionID = LaunchdProcessCoalition.resourceID(for: getpid()) else {
            throw BoundedProcessRunnerError.secureContainmentUnavailable
        }
        let contained = try LaunchdContainedInvocation.make(
            executableURL: executableURL,
            arguments: arguments,
            deniedArtifactRoot: LaunchdProcessArtifacts.rootURL
        )
        let supervisorRequest = LaunchdSupervisorRequest(
            executablePath: contained.executableURL.path,
            arguments: contained.arguments,
            workingDirectoryPath: workingDirectory.path,
            environment: LaunchdProcessEnvironment.sanitized(environment),
            deadline: boundary.deadline,
            timeoutDiagnostic: timeoutDiagnostic
        )
        try supervisorRequest.validate()
        let artifacts: LaunchdProcessArtifacts
        do {
            artifacts = try LaunchdProcessArtifacts.create(
                brokerIdentity: brokerSnapshot.identity
            )
        } catch {
            throw BoundedProcessRunnerError.contextual(
                "launchd artifact preparation",
                error: error
            )
        }
        let execution = LaunchdCoalitionExecution(
            artifacts: artifacts,
            retainedBytesPerStream: retainedBytesPerStream
        )

        do {
            try onPrepared?(artifacts.lease)
            try boundary.check()
            let domain = try execution.control.bootstrap(
                label: artifacts.label,
                propertyListURL: artifacts.propertyListURL,
                boundary: boundary
            )
            execution.domain = domain

            let jobSnapshot: LaunchdJobSnapshot
            while true {
                let candidate = try execution.control.snapshot(
                    domain: domain,
                    label: artifacts.label,
                    boundary: boundary
                )
                if candidate.state == "not running" {
                    try execution.drainAvailableOutput()
                    throw BoundedProcessRunnerError.secureBrokerFailed(
                        "launchd supervisor exited before handoff: \(execution.stderrString())"
                    )
                }
                // `launchctl print` only publishes a coalition block on macOS
                // versions that expose one, so waiting for that field would
                // never finish on the releases that omit it. The pid is
                // published everywhere, and the coalition is proven against the
                // kernel below, which answers on every supported release.
                if candidate.pid != nil {
                    jobSnapshot = candidate
                    break
                }
                try boundary.check()
                usleep(Self.scanIntervalMicroseconds)
            }
            guard let leaderPID = jobSnapshot.pid else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            let identityDeadline = try boundary.boundedDeadline(maximum: 2)
            var leaderSnapshot: LaunchdProcessSnapshot?
            while LaunchdMonotonicClock.now() < identityDeadline {
                if let candidate = LaunchdProcessSnapshot.current(for: leaderPID),
                   candidate.userID == getuid(),
                   candidate.isLive {
                    leaderSnapshot = candidate
                    break
                }
                let refreshed = try execution.control.snapshot(
                    domain: domain,
                    label: artifacts.label,
                    boundary: boundary
                )
                if refreshed.state == "not running" || refreshed.pid != leaderPID { break }
                usleep(Self.scanIntervalMicroseconds)
            }
            guard let leaderSnapshot else {
                try boundary.check()
                let finalSnapshot = try? execution.control.snapshot(
                    domain: domain,
                    label: artifacts.label,
                    boundary: boundary
                )
                try boundary.check()
                try execution.drainAvailableOutput()
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "launchd supervisor identity is unavailable for pid \(leaderPID) "
                        + "(state \(finalSnapshot?.state ?? "unknown"), "
                        + "exit \(finalSnapshot?.exitCode ?? -1), "
                        + "signal \(finalSnapshot?.terminatingSignal ?? -1)): "
                        + execution.stderrString()
                )
            }
            // The kernel is the authority on coalition membership. Waiting for
            // launchd to publish the coalition used to settle the job before it
            // was read; poll the kernel within the same boundary instead, so a
            // supervisor observed before launchd finishes moving it out of this
            // process's coalition is retried rather than rejected outright.
            let coalitionDeadline = try boundary.boundedDeadline(maximum: 2)
            var isolatedCoalitionID: UInt64?
            while true {
                if let candidate = LaunchdProcessCoalition.resourceID(for: leaderPID),
                   candidate != supervisorCoalitionID {
                    isolatedCoalitionID = candidate
                    break
                }
                guard LaunchdMonotonicClock.now() < coalitionDeadline else { break }
                try boundary.check()
                usleep(Self.scanIntervalMicroseconds)
            }
            guard let coalitionID = isolatedCoalitionID else {
                // An exhausted execution budget stays a timeout, exactly as it
                // does when the supervisor identity never settles.
                try boundary.check()
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "launchd supervisor coalition is unavailable or not isolated"
                )
            }
            execution.leaderIdentity = leaderSnapshot.identity
            execution.coalitionID = coalitionID

            guard jobSnapshot.pid == leaderPID else {
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "launchd PID mismatch (expected \(leaderPID), observed \(jobSnapshot.pid ?? -1))"
                )
            }
            // launchd corroborates the kernel whenever it publishes a coalition;
            // a disagreement stays a hard failure. Releases that publish no
            // coalition block report nothing to contradict, and the kernel
            // reading above already proved isolation for this very pid.
            if let reportedCoalitionID = jobSnapshot.resourceCoalitionID,
               reportedCoalitionID != coalitionID {
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "launchd coalition mismatch (expected \(coalitionID), observed \(reportedCoalitionID))"
                )
            }
            // The scan above accepts the first snapshot carrying a pid, which on
            // releases that do publish a coalition block can still predate it,
            // leaving the corroboration nothing to compare. Read once more now
            // that the kernel has settled, so those releases keep cross-checking
            // launchd against the kernel deterministically instead of by timing.
            // A failed re-read weakens nothing: isolation is already proven for
            // this pid, and the boundary is re-checked by the handoff below.
            if jobSnapshot.resourceCoalitionID == nil,
               let settled = try? execution.control.snapshot(
                   domain: domain,
                   label: artifacts.label,
                   boundary: boundary
               ),
               settled.pid == leaderPID,
               let settledCoalitionID = settled.resourceCoalitionID,
               settledCoalitionID != coalitionID {
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "launchd coalition mismatch (expected \(coalitionID), observed \(settledCoalitionID))"
                )
            }
            guard LaunchdProcessSnapshot.current(for: leaderPID)?.identity
                    == leaderSnapshot.identity else {
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "launchd leader identity changed before release"
                )
            }
            do {
                try artifacts.acceptSupervisor(
                    expectedIdentity: leaderSnapshot.identity,
                    boundary: boundary
                )
            } catch {
                let contextualError = try boundary.contextualError(
                    "launchd supervisor authentication",
                    preservingBoundaryFrom: error
                )
                throw contextualError
            }
            do {
                try artifacts.persistSecuredState(
                    domain: domain,
                    coalitionID: coalitionID,
                    supervisorIdentity: leaderSnapshot.identity
                )
            } catch {
                throw BoundedProcessRunnerError.contextual(
                    "launchd recovery-state persistence",
                    error: error
                )
            }

            let securedLease = artifacts.lease.secured(
                domain: domain,
                coalitionID: coalitionID
            )
            try onReady?(securedLease)
            try boundary.check()
            do {
                try artifacts.releaseInvocation(
                    supervisorRequest,
                    ownerLivenessDescriptor: ownerLivenessDescriptor,
                    boundary: boundary
                )
            } catch {
                let contextualError = try boundary.contextualError(
                    "launchd supervisor handoff",
                    preservingBoundaryFrom: error
                )
                throw contextualError
            }
            return execution
        } catch {
            do {
                try execution.verifiedCleanup()
            } catch {
                throw BoundedProcessRunnerError.contextual(
                    "launchd startup cleanup",
                    error: error
                )
            }
            throw LaunchdCleanupAttestation.errorAfterVerifiedFallback(error)
        }
    }

    func leaderIsRunning(boundary: LaunchdExecutionBoundary) throws -> Bool {
        try boundary.check()
        guard let leaderIdentity else { return false }
        if let snapshot = LaunchdProcessSnapshot.current(for: leaderIdentity.pid) {
            return snapshot.identity == leaderIdentity && snapshot.isLive
        }
        if Darwin.kill(leaderIdentity.pid, 0) == -1, errno == ESRCH { return false }
        if let domain {
            let snapshot = try control.snapshot(
                domain: domain,
                label: artifacts.label,
                boundary: boundary
            )
            try boundary.check()
            if snapshot.pid != leaderIdentity.pid || snapshot.state == "not running" {
                return false
            }
        }
        throw BoundedProcessRunnerError.secureContainmentVerificationFailed
    }

    func waitForTermination(timeoutSeconds: TimeInterval) throws -> LaunchdProcessTermination {
        guard let domain else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let deadline = LaunchdMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: LaunchdMonotonicClock.now()
        )
        let completionDeadline = min(
            deadline,
            LaunchdMonotonicClock.adding(
                seconds: 0.5,
                to: LaunchdMonotonicClock.now()
            )
        )
        let completionFailure: String
        do {
            let completion = try artifacts.readSupervisorCompletion(
                deadline: completionDeadline
            )
            return LaunchdProcessTermination(
                status: completion.terminationStatus,
                timedOut: completion.timedOut
            )
        } catch {
            completionFailure = Self.errorDetail(error)
        }

        var launchdFailure = "launchd did not publish a termination status"
        while LaunchdMonotonicClock.now() < deadline {
            let boundary = LaunchdExecutionBoundary(
                deadline: deadline,
                cancellationRequested: { false }
            )
            do {
                let snapshot = try control.snapshot(
                    domain: domain,
                    label: artifacts.label,
                    boundary: boundary
                )
                if let terminatingSignal = snapshot.terminatingSignal {
                    return LaunchdProcessTermination(
                        status: terminatingSignal,
                        timedOut: false
                    )
                }
                if let exitCode = snapshot.exitCode {
                    if exitCode != EXIT_SUCCESS {
                        return LaunchdProcessTermination(
                            status: exitCode,
                            timedOut: false
                        )
                    }
                    launchdFailure = "supervisor exited successfully without authenticated completion"
                    break
                }
            } catch {
                launchdFailure = Self.errorDetail(error)
                break
            }
            usleep(Self.scanIntervalMicroseconds)
        }
        throw BoundedProcessRunnerError.secureBrokerFailed(
            "authenticated supervisor completion unavailable (\(completionFailure)); "
                + "termination fallback failed (\(launchdFailure))"
        )
    }

    func terminateCoalition(
        gracePeriodSeconds: TimeInterval,
        killWaitSeconds: TimeInterval
    ) throws {
        try terminateOwnedExecution(
            gracePeriodSeconds: gracePeriodSeconds,
            killWaitSeconds: killWaitSeconds
        )
    }

    func drainAvailableOutput() throws {
        if !stdoutReachedEOF {
            _ = try drain(
                descriptor: artifacts.stdoutReader,
                capture: &stdoutCapture,
                final: false
            )
        }
        if !stderrReachedEOF {
            _ = try drain(
                descriptor: artifacts.stderrReader,
                capture: &stderrCapture,
                final: false
            )
        }
    }

    func drainOutputToEnd(timeoutSeconds: TimeInterval) throws {
        let deadline = LaunchdMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: LaunchdMonotonicClock.now()
        )
        while !stdoutReachedEOF || !stderrReachedEOF {
            if !stdoutReachedEOF {
                stdoutReachedEOF = try drain(
                    descriptor: artifacts.stdoutReader,
                    capture: &stdoutCapture,
                    final: true
                )
            }
            if !stderrReachedEOF {
                stderrReachedEOF = try drain(
                    descriptor: artifacts.stderrReader,
                    capture: &stderrCapture,
                    final: true
                )
            }
            if stdoutReachedEOF, stderrReachedEOF { return }
            if LaunchdMonotonicClock.now() >= deadline {
                throw BoundedProcessRunnerError.outputDrainDidNotFinish
            }
            usleep(Self.scanIntervalMicroseconds)
        }
    }

    func stdoutString() -> String { stdoutCapture.rendered() }
    var stdoutWasTruncated: Bool { stdoutCapture.renderedWasTruncated() }
    func stderrString(diagnostic: String? = nil) -> String {
        stderrCapture.rendered(diagnostic: diagnostic)
    }
    func stderrWasTruncated(diagnostic: String? = nil) -> Bool {
        stderrCapture.renderedWasTruncated(diagnostic: diagnostic)
    }

    func finishCleanup() throws {
        guard !cleanupFinished else { return }
        try artifacts.removeVerified()
        cleanupFinished = true
    }

    func verifiedCleanup() throws {
        guard !cleanupFinished else { return }
        do {
            try terminateOwnedExecution(
                gracePeriodSeconds: 0,
                killWaitSeconds: Self.fallbackCleanupWaitSeconds
            )
            try artifacts.removeVerified()
            cleanupFinished = true
        } catch {
            if let leaderIdentity,
               LaunchdProcessSnapshot.current(for: leaderIdentity.pid)?.identity == leaderIdentity {
                _ = Darwin.kill(leaderIdentity.pid, SIGKILL)
            }
            artifacts.closeStreams()
            let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                ?? error.localizedDescription
            throw BoundedProcessRunnerError.secureCleanupUnverified(detail)
        }
    }

    private func terminateOwnedExecution(
        gracePeriodSeconds: TimeInterval,
        killWaitSeconds: TimeInterval
    ) throws {
        var failures: [String] = []
        if let domain {
            do {
                try control.removeJob(domain: domain, label: artifacts.label)
            } catch {
                failures.append("owner domain \(domain): \(Self.errorDetail(error))")
            }
        } else {
            failures.append(contentsOf: control.nonOwnerDomainUncertainties(
                ownerDomain: nil,
                label: artifacts.label
            ))
        }

        if let coalitionID {
            do {
                try LaunchdProcessCoalition.terminateMembers(
                    id: coalitionID,
                    excluding: getpid(),
                    gracePeriodSeconds: gracePeriodSeconds,
                    killWaitSeconds: killWaitSeconds
                )
                try LaunchdProcessCoalition.verifyEmpty(
                    id: coalitionID,
                    waitSeconds: killWaitSeconds
                )
            } catch {
                failures.append(
                    "coalition \(coalitionID): \(Self.errorDetail(error))"
                )
            }
        }

        if let domain {
            failures.append(contentsOf: control.nonOwnerDomainUncertainties(
                ownerDomain: domain,
                label: artifacts.label
            ))
        }
        guard failures.isEmpty else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                failures.joined(separator: "; ")
            )
        }
    }

    private static func errorDetail(_ error: Error) -> String {
        (error as? BoundedProcessRunnerError)?.diagnosticDescription
            ?? error.localizedDescription
    }

    private func drain(
        descriptor: BoundedOwnedFileDescriptor,
        capture: inout BoundedCapturedStream,
        final: Bool
    ) throws -> Bool {
        guard descriptor.rawValue >= 0 else { return true }
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
                if final { descriptor.close() }
                return final
            }
            if errno == EINTR { continue }
            if errno == EAGAIN || errno == EWOULDBLOCK { return false }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read launchd output",
                code: errno
            )
        }
        return false
    }
}
