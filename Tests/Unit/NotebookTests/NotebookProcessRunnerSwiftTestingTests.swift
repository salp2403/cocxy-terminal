// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookProcessRunnerSwiftTestingTests.swift - Notebook process-tree lifecycle coverage.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Notebook process runner", .serialized, .timeLimit(.minutes(1)))
struct NotebookProcessRunnerSwiftTestingTests {
    @Test("starts the kernel in a dedicated launchd process group and preserves normal output")
    func startsDedicatedProcessGroup() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                "-c",
                "import os, sys; print(os.getpid(), os.getpgrp(), os.getsid(0)); sys.stderr.write('warn\\n')",
            ],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        let identifiers = result.stdout
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Int32($0) }
        #expect(result.exitCode == 0)
        #expect(identifiers.count == 3)
        if identifiers.count == 3 {
            #expect(identifiers[0] == identifiers[1])
            #expect(identifiers[2] > 0)
        }
        #expect(result.stderr == "warn\n")
    }

    @Test("preserves a nonzero exit code and both output streams")
    func preservesNonzeroExitResult() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "printf 'out\\n'; printf 'err\\n' >&2; exit 7"],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 7)
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
    }

    @Test("does not classify a payload exit status of 124 as a timeout")
    func payloadExit124IsNotTimeout() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try LaunchdProcessBrokerClient(
            maximumRetainedBytesPerStream: 64 * 1_024
        ).run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "exit 124"],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 124)
        #expect(!result.timedOut)
    }

    @Test("preserves a terminating signal as the process exit status")
    func preservesTerminatingSignal() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "kill -TERM $$"],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == SIGTERM)
        #expect(result.stdout.isEmpty)
        #expect(result.stderr.isEmpty)
    }

    @Test("parses launchd's named terminating-signal status")
    func parsesNamedLaunchdTerminatingSignal() throws {
        let snapshot = try #require(LaunchdJobSnapshot(output: """
        gui/504/dev.cocxy.example = {
            state = not running
            runs = 1
            last terminating signal = Terminated: 15
            resource coalition = {
                ID = 42
                type = resource
            }
        }
        """))

        #expect(snapshot.state == "not running")
        #expect(snapshot.terminatingSignal == SIGTERM)
        #expect(snapshot.resourceCoalitionID == 42)
    }

    @Test("persisted coalition recovery is scoped to the current system boot")
    func persistedCoalitionRecoveryIsBootScoped() throws {
        let currentBootIdentity = try LaunchdBootIdentity.current()
        #expect(currentBootIdentity.isStable)
        let state = LaunchdPersistedExecutionState(
            label: "dev.cocxy.bounded-process.test",
            domain: "gui/\(getuid())",
            coalitionID: 42,
            bootIdentity: currentBootIdentity,
            supervisorIdentity: LaunchdProcessIdentity(
                pid: 42,
                startSeconds: 1,
                startMicroseconds: 2
            ),
            directoryDevice: 3,
            directoryInode: 4,
            payloadMayHaveRun: true
        )

        #expect(
            state.bootScope(
                currentBootIdentity: currentBootIdentity,
                currentLegacyBootIdentity: nil
            ) == .current
        )
        var differentBootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        while differentBootIdentity == currentBootIdentity {
            differentBootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        }
        #expect(
            state.bootScope(
                currentBootIdentity: differentBootIdentity,
                currentLegacyBootIdentity: nil
            ) == .differentBoot
        )

        let currentLegacyBootIdentity = try LaunchdBootIdentity.currentLegacyBootTime()
        let legacyState = LaunchdPersistedExecutionState(
            label: state.label,
            domain: state.domain,
            coalitionID: state.coalitionID,
            bootIdentity: currentLegacyBootIdentity,
            supervisorIdentity: state.supervisorIdentity,
            directoryDevice: state.directoryDevice,
            directoryInode: state.directoryInode,
            payloadMayHaveRun: state.payloadMayHaveRun
        )
        #expect(
            legacyState.bootScope(
                currentBootIdentity: currentBootIdentity,
                currentLegacyBootIdentity: currentLegacyBootIdentity
            ) == .current
        )
        let legacySeconds = try #require(currentLegacyBootIdentity.legacySeconds)
        let legacyMicroseconds = try #require(
            currentLegacyBootIdentity.legacyMicroseconds
        )
        let staleLegacyBootIdentity = LaunchdBootIdentity(
            seconds: legacySeconds + 1,
            microseconds: legacyMicroseconds
        )
        #expect(
            legacyState.bootScope(
                currentBootIdentity: currentBootIdentity,
                currentLegacyBootIdentity: staleLegacyBootIdentity
            ) == .unverifiable
        )

        let encoded = try PropertyListEncoder().encode(state)
        var propertyList = try #require(
            PropertyListSerialization.propertyList(
                from: encoded,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        propertyList.removeValue(forKey: "bootIdentity")
        let legacyData = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )
        let stateWithoutBootIdentity = try PropertyListDecoder().decode(
            LaunchdPersistedExecutionState.self,
            from: legacyData
        )
        #expect(stateWithoutBootIdentity.bootIdentity == nil)
        #expect(
            stateWithoutBootIdentity.bootScope(
                currentBootIdentity: currentBootIdentity,
                currentLegacyBootIdentity: currentLegacyBootIdentity
            ) == .unverifiable
        )
    }

    @Test("emergency cleanup leases must agree with persisted execution identity")
    func cleanupLeaseRequiresPersistedStateCoherence() throws {
        let state = LaunchdPersistedExecutionState(
            label: "dev.cocxy.bounded-process.test",
            domain: "gui/\(getuid())",
            coalitionID: 42,
            bootIdentity: LaunchdBootIdentity(sessionUUID: UUID()),
            supervisorIdentity: LaunchdProcessIdentity(
                pid: 43,
                startSeconds: 1,
                startMicroseconds: 2
            ),
            directoryDevice: 3,
            directoryInode: 4,
            payloadMayHaveRun: true
        )
        let prepared = LaunchdProcessLease(
            label: state.label,
            domain: nil,
            coalitionID: nil,
            directoryPath: "/private/tmp/unused",
            directoryDevice: state.directoryDevice,
            directoryInode: state.directoryInode
        )
        let secured = prepared.secured(
            domain: state.domain,
            coalitionID: state.coalitionID
        )
        let mismatchedCoalition = prepared.secured(
            domain: state.domain,
            coalitionID: state.coalitionID + 1
        )
        let contradictory = LaunchdProcessLease(
            label: state.label,
            domain: state.domain,
            coalitionID: nil,
            directoryPath: prepared.directoryPath,
            directoryDevice: state.directoryDevice,
            directoryInode: state.directoryInode
        )
        let matchingJob = try #require(LaunchdJobSnapshot(output: """
        gui/504/dev.cocxy.example = {
            state = not running
            resource coalition ID = 42
        }
        """))

        #expect(prepared.isConsistent(with: state))
        #expect(secured.isConsistent(with: state))
        #expect(!mismatchedCoalition.isConsistent(with: state))
        #expect(!contradictory.isConsistent(with: state))
        #expect(!LaunchdOwnedJobEvidence.absent.permitsBootoutAttempt)
        #expect(!LaunchdOwnedJobEvidence.unknown("indeterminate").permitsBootoutAttempt)
        #expect(!LaunchdOwnedJobEvidence.conflicting("mismatch").permitsBootoutAttempt)
        #expect(LaunchdOwnedJobEvidence.matching(matchingJob).permitsBootoutAttempt)
    }

    @Test("parses launchd flat coalition and inactive exit status formats")
    func parsesAdditionalLaunchdStatusFormats() throws {
        let running = try #require(LaunchdJobSnapshot(output: """
        user/504/dev.cocxy.example = {
            state = running
            pid = 1234
            resource coalition ID = 9876
        }
        """))
        let inactive = try #require(LaunchdJobSnapshot(output: """
        gui/504/dev.cocxy.example = {
            state = not running
            runs = 1
            last exit code = 7
        }
        """))

        #expect(running.state == "running")
        #expect(running.pid == 1234)
        #expect(running.resourceCoalitionID == 9876)
        #expect(inactive.state == "not running")
        #expect(inactive.exitCode == 7)
    }

    @Test("classifies launchd absence, presence, and indeterminate control results")
    func classifiesLaunchdPresenceWithoutCollapsingUnknown() throws {
        let absent = BoundedProcessResult(
            exitCode: 113,
            stdout: "",
            stderr: "missing",
            stdoutWasTruncated: false,
            stderrWasTruncated: false,
            timedOut: false
        )
        let present = BoundedProcessResult(
            exitCode: 0,
            stdout: """
            gui/504/dev.cocxy.example = {
                state = running
                pid = 42
            }
            """,
            stderr: "",
            stdoutWasTruncated: false,
            stderrWasTruncated: false,
            timedOut: false
        )
        let timedOut = BoundedProcessResult(
            exitCode: 124,
            stdout: "",
            stderr: "",
            stdoutWasTruncated: false,
            stderrWasTruncated: false,
            timedOut: true
        )
        let failed = BoundedProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "denied",
            stdoutWasTruncated: false,
            stderrWasTruncated: false,
            timedOut: false
        )

        #expect(LaunchdControlClient.classifyPresence(absent) == .absent)
        let presentSnapshot = try #require(LaunchdJobSnapshot(output: present.stdout))
        #expect(LaunchdControlClient.classifyPresence(present) == .present(presentSnapshot))
        #expect(LaunchdControlClient.classifyPresence(timedOut) == .unknown(exitCode: 124))
        #expect(LaunchdControlClient.classifyPresence(failed) == .unknown(exitCode: 1))
    }

    @Test("bounded control execution captures launchctl output")
    func capturesLaunchctlOutput() throws {
        let result = try BoundedProcessRunner(maximumRetainedBytesPerStream: 64 * 1_024).run(
            executableURL: URL(fileURLWithPath: "/bin/launchctl"),
            arguments: ["print", "gui/\(getuid())"],
            workingDirectory: URL(fileURLWithPath: "/", isDirectory: true),
            timeoutSeconds: 3
        )

        #expect(result.exitCode == 0)
        #expect(!result.stdout.isEmpty)
    }

    @Test("zero timeout prevents generic process side effects")
    func genericZeroTimeoutPreventsSideEffects() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let marker = workspace.appendingPathComponent("must-not-exist")

        let result = try BoundedProcessRunner(
            maximumRetainedBytesPerStream: 64 * 1_024
        ).run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", ": > \(notebookShellQuoted(marker.path))"],
            workingDirectory: workspace,
            timeoutSeconds: 0,
            timeoutDiagnostic: "expired before launch"
        )

        #expect(result.exitCode == 124)
        #expect(result.timedOut)
        #expect(result.stderr == "expired before launch\n")
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("local execution gate persists authenticated state across instances")
    func localExecutionGatePersistsAcrossInstances() throws {
        let root = try notebookProcessTemporaryDirectory()
        try #require(chmod(root.path, S_IRWXU) == 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        let firstGate = LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { bootIdentity }
        )
        let secondGate = LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { bootIdentity }
        )
        try firstGate.check()

        try firstGate.block(reason: "first cleanup failure")
        let staleGeneration = try secondGate.reconciliationGeneration()
        try firstGate.block(reason: "later cleanup failure")

        do {
            try secondGate.clearAfterVerifiedReconciliation(
                expectedGeneration: staleGeneration,
                encounteredActiveExecutions: false
            )
            Issue.record("A stale reconciliation cleared a newer persisted block")
        } catch let error as BoundedProcessRunnerError {
            #expect(error.diagnosticDescription.contains("changed during reconciliation"))
        }

        do {
            try secondGate.check()
            Issue.record("A second gate instance ignored the persisted block")
        } catch let error as BoundedProcessRunnerError {
            #expect(error.diagnosticDescription.contains("first cleanup failure"))
            #expect(!error.diagnosticDescription.contains("later cleanup failure"))
        }

        let generation = try secondGate.reconciliationGeneration()
        do {
            try secondGate.clearAfterVerifiedReconciliation(
                expectedGeneration: generation,
                encounteredActiveExecutions: true
            )
            Issue.record("An active execution incorrectly cleared the persisted gate")
        } catch let error as BoundedProcessRunnerError {
            #expect(error.diagnosticDescription.contains("active local executions"))
        }
        try secondGate.clearAfterVerifiedReconciliation(
            expectedGeneration: generation,
            encounteredActiveExecutions: false
        )
        try LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { bootIdentity }
        ).check()
    }

    @Test("local execution gate initializes safely under concurrent first use")
    func localExecutionGateSerializesConcurrentInitialization() throws {
        let root = try notebookProcessTemporaryDirectory()
        try #require(chmod(root.path, S_IRWXU) == 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        let start = DispatchSemaphore(value: 0)
        let completion = DispatchGroup()
        let errors = NotebookProcessTestErrorCollector()
        let contenderCount = 32

        for _ in 0..<contenderCount {
            let gate = LaunchdLocalExecutionGate(
                stateDirectoryURL: root,
                bootIdentityProvider: { bootIdentity }
            )
            completion.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { completion.leave() }
                start.wait()
                do {
                    try gate.check()
                } catch {
                    errors.record(error)
                }
            }
        }
        for _ in 0..<contenderCount {
            start.signal()
        }

        #expect(completion.wait(timeout: .now() + 10) == .success)
        #expect(errors.messages.isEmpty)
        try LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { bootIdentity }
        ).check()
    }

    @Test("local execution gate fails closed for malformed state")
    func localExecutionGateRejectsMalformedState() throws {
        let root = try notebookProcessTemporaryDirectory()
        try #require(chmod(root.path, S_IRWXU) == 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent(LaunchdLocalExecutionGate.stateFileName)
        try Data("not a property list".utf8).write(to: stateURL)
        try #require(chmod(stateURL.path, S_IRUSR | S_IWUSR) == 0)
        let gate = LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { LaunchdBootIdentity(sessionUUID: UUID()) }
        )

        do {
            try gate.check()
            Issue.record("Malformed gate state was accepted")
        } catch let error as BoundedProcessRunnerError {
            #expect(error.diagnosticDescription.contains("malformed"))
        }
    }

    @Test("local execution gate bounds contention on its persisted lock")
    func localExecutionGateBoundsPersistedLockContention() throws {
        let root = try notebookProcessTemporaryDirectory()
        try #require(chmod(root.path, S_IRWXU) == 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let bootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        let initializer = LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { bootIdentity }
        )
        try initializer.check()
        let stateURL = root.appendingPathComponent(LaunchdLocalExecutionGate.stateFileName)
        let descriptor = Darwin.open(stateURL.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        try #require(descriptor >= 0)
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        let contender = LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { bootIdentity },
            lockWaitSeconds: 0.05
        )
        let start = DispatchTime.now().uptimeNanoseconds

        do {
            try contender.check()
            Issue.record("A held execution gate lock was accepted")
        } catch let error as BoundedProcessRunnerError {
            #expect(error.diagnosticDescription.contains("timed out waiting"))
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        #expect(elapsed < 0.5)
    }

    @Test("local execution gate fails closed for truncated state")
    func localExecutionGateRejectsTruncatedState() throws {
        let root = try notebookProcessTemporaryDirectory()
        try #require(chmod(root.path, S_IRWXU) == 0)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = LaunchdLocalExecutionGate(
            stateDirectoryURL: root,
            bootIdentityProvider: { LaunchdBootIdentity(sessionUUID: UUID()) }
        )
        try gate.check()
        let stateURL = root.appendingPathComponent(LaunchdLocalExecutionGate.stateFileName)
        try Data().write(to: stateURL)
        try #require(chmod(stateURL.path, S_IRUSR | S_IWUSR) == 0)

        do {
            try gate.check()
            Issue.record("Truncated gate state was accepted as unblocked")
        } catch let error as BoundedProcessRunnerError {
            #expect(error.diagnosticDescription.contains("truncated"))
        }
    }

    @Test("successful fallback cleanup carries verified attestation")
    func successfulFallbackCleanupIsAttested() {
        let resolved = LaunchdCleanupAttestation.errorAfterVerifiedFallback(
            BoundedProcessRunnerError.secureCleanupUnverified("transient cleanup failure")
        )
        guard let bounded = resolved as? BoundedProcessRunnerError else {
            Issue.record("Fallback cleanup did not return a bounded process error")
            return
        }
        if case .secureBrokerFailed(let detail) = bounded {
            #expect(detail.contains("transient cleanup failure"))
            #expect(detail.contains("fallback cleanup was verified"))
        } else {
            Issue.record("Verified fallback remained classified as unverified")
        }
    }

    @Test("expired launchd status probes preserve the command deadline")
    func expiredLaunchdProbePreservesDeadline() throws {
        let boundary = LaunchdExecutionBoundary(
            deadline: LaunchdMonotonicClock.now(),
            cancellationRequested: { false }
        )
        let start = LaunchdMonotonicClock.now()
        do {
            _ = try LaunchdControlClient().snapshot(
                domain: "gui/\(getuid())",
                label: "dev.cocxy.test.expired-probe",
                boundary: boundary
            )
            Issue.record("An expired status probe invoked launchctl")
        } catch is LaunchdExecutionBoundaryError {
            let elapsed = Double(LaunchdMonotonicClock.now() - start) / 1_000_000_000
            #expect(elapsed < 0.2)
        }
    }

    @Test("broker requests are validated before a broker is created")
    func brokerClientValidatesBeforeSpawn() throws {
        do {
            _ = try LaunchdProcessBrokerClient(
                maximumRetainedBytesPerStream: 16 * 1_024 * 1_024 + 1
            ).run(
                executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                arguments: [],
                workingDirectory: URL(fileURLWithPath: "/", isDirectory: true),
                timeoutSeconds: 1
            )
            Issue.record("An oversized broker request was accepted")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .invalidInvocation)
        }
    }

    @Test("broker writes stop at their absolute deadline when the peer does not read")
    func brokerWriteHonorsDeadline() throws {
        var sockets: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let receiver = LaunchdOwnedFileDescriptor(sockets[1])
        let connection = try LaunchdBrokerConnection(descriptor: sockets[0])
        defer {
            connection.close()
            receiver.close()
        }
        var sendBufferBytes: Int32 = 1_024
        try #require(setsockopt(
            sockets[0],
            SOL_SOCKET,
            SO_SNDBUF,
            &sendBufferBytes,
            socklen_t(MemoryLayout.size(ofValue: sendBufferBytes))
        ) == 0)
        let deadline = LaunchdMonotonicClock.adding(
            seconds: 0.05,
            to: LaunchdMonotonicClock.now()
        )

        do {
            try connection.writeFrame(
                LaunchdBrokerEvent(
                    kind: .failed,
                    errorMessage: String(repeating: "x", count: 4 * 1_024 * 1_024)
                ),
                deadline: { deadline },
                pollHook: {}
            )
            Issue.record("Broker write unexpectedly completed without a reader")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .secureContainmentVerificationFailed)
        }
    }

    @Test("an interrupted request frame records no complete broker delivery")
    func interruptedBrokerRequestIsNotDelivered() throws {
        var sockets: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let writer = try LaunchdBrokerConnection(descriptor: sockets[0])
        let receiver = LaunchdOwnedFileDescriptor(sockets[1])
        defer {
            writer.close()
            receiver.close()
        }
        var delivery = LaunchdBrokerRequestDeliveryState()
        var boundaryChecks = 0

        do {
            try delivery.record {
                try writer.writeFrame(
                    LaunchdBrokerEvent(kind: .completed),
                    deadline: { nil },
                    pollHook: {
                        boundaryChecks += 1
                        if boundaryChecks == 2 { throw CancellationError() }
                    }
                )
            }
            Issue.record("A request interrupted before its payload was marked delivered")
        } catch is CancellationError {
            // Expected between the frame header and payload.
        }

        #expect(!delivery.completed)
        #expect(delivery.verifiesLeaseWasImpossible(brokerWasReaped: true))
        #expect(!delivery.verifiesLeaseWasImpossible(brokerWasReaped: false))
    }

    @Test("handoff context preserves cancellation and command deadline errors")
    func handoffPreservesExecutionBoundary() {
        let activeBoundary = LaunchdExecutionBoundary(
            deadline: nil,
            cancellationRequested: { false }
        )
        do {
            _ = try activeBoundary.contextualError(
                "test handoff",
                preservingBoundaryFrom: CancellationError()
            )
            Issue.record("Handoff cancellation was converted into a startup failure")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }

        let expiredBoundary = LaunchdExecutionBoundary(
            deadline: LaunchdMonotonicClock.now(),
            cancellationRequested: { false }
        )
        do {
            _ = try expiredBoundary.contextualError(
                "test handoff",
                preservingBoundaryFrom: BoundedProcessRunnerError
                    .secureContainmentVerificationFailed
            )
            Issue.record("Handoff deadline was converted into a startup failure")
        } catch LaunchdExecutionBoundaryError.deadlineExceeded {
            // Expected.
        } catch {
            Issue.record("Unexpected deadline error: \(error)")
        }
    }

    @Test("partial broker frames stop at their absolute read deadline")
    func partialBrokerFrameHonorsReadDeadline() throws {
        var sockets: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let writer = LaunchdOwnedFileDescriptor(sockets[0])
        let reader = try LaunchdBrokerConnection(descriptor: sockets[1])
        defer {
            writer.close()
            reader.close()
        }
        var partialHeader: UInt16 = 1
        try #require(Darwin.write(
            writer.rawValue,
            &partialHeader,
            MemoryLayout<UInt16>.size
        ) == MemoryLayout<UInt16>.size)
        let deadline = LaunchdMonotonicClock.adding(
            seconds: 0.05,
            to: LaunchdMonotonicClock.now()
        )

        do {
            let _: LaunchdBrokerEvent = try reader.readFrame(
                deadline: { deadline },
                pollHook: {}
            )
            Issue.record("A partial broker frame ignored its read deadline")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .secureContainmentVerificationFailed)
        }
    }

    @Test("supervisor completion can precede acknowledgement and preserves timeout cause")
    func supervisorCompletionBeforeAcknowledgementRoundTrips() throws {
        var sockets: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let writer = try LaunchdBrokerConnection(descriptor: sockets[0])
        let reader = try LaunchdBrokerConnection(descriptor: sockets[1])
        defer {
            writer.close()
            reader.close()
        }
        let expected = LaunchdSupervisorCompletion(
            terminationStatus: 124,
            cleanupVerified: true,
            timedOut: true
        )
        let expectedMessage = LaunchdSupervisorMessage.completed(expected)

        try writer.writeFrame(expectedMessage)
        let deadline = LaunchdMonotonicClock.adding(
            seconds: 0.5,
            to: LaunchdMonotonicClock.now()
        )
        let received: LaunchdSupervisorMessage = try reader.readFrame(
            deadline: { deadline },
            pollHook: {}
        )
        var handshake = LaunchdSupervisorHandshakeState()
        try handshake.acceptInitial(received)

        #expect(received == expectedMessage)
        #expect(handshake.takePendingCompletion() == expected)
        #expect(handshake.takePendingCompletion() == nil)
    }

    @Test("timeout diagnostics remain inside the stderr byte budget")
    func timeoutDiagnosticRespectsCapturedStreamBudget() {
        let limit = 64
        let result = BoundedProcessResult.timeoutResult(
            diagnostic: String(repeating: "timeout-diagnostic-", count: 16),
            maximumRetainedBytesPerStream: limit
        )

        #expect(result.stderr.utf8.count <= limit)
        #expect(result.stderrWasTruncated)
        #expect(result.timedOut)
    }

    @Test("drains an authenticated broker response after the broker exits")
    func completedBrokerResponseSurvivesBrokerExit() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let broker = try LaunchdBrokerProcess.spawn()
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 1) { broker.forceCleanup() }
        }
        let request = LaunchdBrokerRequest(
            executablePath: "/bin/echo",
            arguments: ["buffered-completion"],
            workingDirectoryPath: workspace.path,
            environment: ["PATH": "/usr/bin:/bin"],
            maximumRetainedBytesPerStream: 4_096,
            deadline: LaunchdMonotonicClock.adding(
                seconds: 10,
                to: LaunchdMonotonicClock.now()
            ),
            timeoutDiagnostic: nil
        )

        try broker.connection.writeFrame(request)
        try #require(broker.waitForExit(timeoutSeconds: 10))

        let responseDeadline = LaunchdMonotonicClock.adding(
            seconds: 1,
            to: LaunchdMonotonicClock.now()
        )
        var stoppedSince: UInt64?
        var completedResult: BoundedProcessResult?
        while completedResult == nil {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { responseDeadline },
                pollHook: {
                    try broker.verifyResponsive(
                        stoppedSince: &stoppedSince,
                        graceSeconds: 0.05
                    )
                }
            )
            switch event.kind {
            case .prepared, .ready:
                continue
            case .completed:
                try #require(event.cleanupVerified == true)
                guard let result = event.result else {
                    Issue.record("Broker completion omitted its process result")
                    return
                }
                completedResult = result
            case .cancelled, .failed:
                Issue.record("Broker did not return its buffered completion event")
                return
            }
        }

        #expect(completedResult?.exitCode == 0)
        #expect(completedResult?.stdout == "buffered-completion\n")
    }

    @Test("environment indirection merges a nested workspace sandbox")
    func environmentWrappedSandboxIsMerged() throws {
        let invocation = try LaunchdContainedInvocation.make(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "TMPDIR=/private/tmp/untrusted",
                "/usr/bin/sandbox-exec",
                "-p",
                "(version 1) (allow default) (deny network*)",
                "/usr/bin/env",
                "TMPDIR=/private/tmp/owned",
                "/bin/echo",
                "ok",
            ],
            deniedArtifactRoot: LaunchdProcessArtifacts.rootURL
        )

        #expect(invocation.executableURL.path == "/usr/bin/sandbox-exec")
        #expect(invocation.arguments[0] == "-p")
        #expect(invocation.arguments[1].contains("(deny network*)"))
        #expect(invocation.arguments[1].contains("(deny job-creation)"))
        #expect(invocation.arguments.dropFirst(2).filter {
            $0 == "/usr/bin/sandbox-exec"
        }.isEmpty)
        #expect(Array(invocation.arguments.dropFirst(2)) == [
            "/usr/bin/env",
            "TMPDIR=/private/tmp/untrusted",
            "/usr/bin/env",
            "TMPDIR=/private/tmp/owned",
            "/bin/echo",
            "ok",
        ])
    }

    @Test("a stopped broker is rejected without a command deadline")
    func stoppedBrokerWatchdogHasIndependentDeadline() throws {
        let broker = try LaunchdBrokerProcess.spawn()
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 1) { broker.forceCleanup() }
        }
        try #require(kill(broker.pid, SIGSTOP) == 0)
        var stoppedSince: UInt64?
        let start = LaunchdMonotonicClock.now()

        do {
            let _: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { nil },
                pollHook: {
                    try broker.verifyResponsive(
                        stoppedSince: &stoppedSince,
                        graceSeconds: 0.05
                    )
                }
            )
            Issue.record("A stopped broker kept an unbounded response wait open")
        } catch let error as BoundedProcessRunnerError {
            guard case .secureBrokerFailed = error else {
                Issue.record("Unexpected stopped-broker error: \(error)")
                return
            }
        }
        let elapsed = Double(LaunchdMonotonicClock.now() - start) / 1_000_000_000
        #expect(elapsed < 1)
    }

    @Test("peer authentication rejects a mismatched process start identity")
    func peerAuthenticationRejectsStartIdentityMismatch() throws {
        var sockets: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let first = LaunchdOwnedFileDescriptor(sockets[0])
        let second = LaunchdOwnedFileDescriptor(sockets[1])
        defer {
            first.close()
            second.close()
        }
        let current = try #require(LaunchdProcessSnapshot.current(for: getpid()))
        try LaunchdPeerAuthenticator.verify(
            descriptor: first.rawValue,
            expectedIdentity: current.identity
        )
        let mismatched = LaunchdProcessIdentity(
            pid: current.identity.pid,
            startSeconds: current.identity.startSeconds,
            startMicroseconds: current.identity.startMicroseconds &+ 1
        )

        do {
            try LaunchdPeerAuthenticator.verify(
                descriptor: first.rawValue,
                expectedIdentity: mismatched
            )
            Issue.record("Peer authentication accepted a mismatched start identity")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .secureContainmentVerificationFailed)
        }
    }

    @Test("peer authentication rejects an exited zombie process")
    func peerAuthenticationRejectsZombieProcess() throws {
        let xcrunURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        let testBundleURL = try #require(notebookCurrentTestBundleURL())
        try #require(FileManager.default.isExecutableFile(atPath: xcrunURL.path))
        var sockets: [Int32] = [-1, -1]
        var releasePipe: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        try #require(pipe(&releasePipe) == 0)

        var fileActions: posix_spawn_file_actions_t?
        try BoundedPOSIX.check(
            posix_spawn_file_actions_init(&fileActions),
            operation: "initialize zombie-peer file actions"
        )
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        try BoundedPOSIX.check(
            posix_spawn_file_actions_adddup2(&fileActions, releasePipe[0], STDIN_FILENO),
            operation: "redirect zombie-peer input"
        )
        try BoundedPOSIX.check(
            posix_spawn_file_actions_adddup2(&fileActions, sockets[1], STDOUT_FILENO),
            operation: "redirect zombie-peer output"
        )

        var attributes: posix_spawnattr_t?
        try BoundedPOSIX.check(
            posix_spawnattr_init(&attributes),
            operation: "initialize zombie-peer attributes"
        )
        defer { posix_spawnattr_destroy(&attributes) }
        try BoundedPOSIX.check(
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)),
            operation: "protect zombie-peer descriptors"
        )

        var child: pid_t = 0
        let invocation = [xcrunURL.path, "xctest", testBundleURL.path]
        var spawnedEnvironment = ProcessInfo.processInfo.environment
        spawnedEnvironment["COCXY_TEST_ZOMBIE_PEER"] = "1"
        let environment = spawnedEnvironment.map { "\($0.key)=\($0.value)" }.sorted()
        let spawnCode = try BoundedCStringArray.withMutablePointers(invocation) { argv in
            try BoundedCStringArray.withMutablePointers(environment) { envp in
                xcrunURL.path.withCString { path in
                    posix_spawn(&child, path, &fileActions, &attributes, argv, envp)
                }
            }
        }
        try #require(spawnCode == 0)

        _ = Darwin.close(sockets[1])
        _ = Darwin.close(releasePipe[0])
        let peer = LaunchdOwnedFileDescriptor(sockets[0])
        var childWasReaped = false
        defer {
            peer.close()
            _ = Darwin.close(releasePipe[1])
            if !childWasReaped {
                _ = Darwin.kill(child, SIGKILL)
                _ = notebookReapChild(child)
            }
        }

        var readiness = pollfd(
            fd: peer.rawValue,
            events: Int16(POLLIN),
            revents: 0
        )
        var readinessResult: Int32?
        while true {
            let result = Darwin.poll(&readiness, 1, 1_000)
            if result >= 0 {
                readinessResult = result
                break
            }
            if errno != EINTR {
                readinessResult = result
                break
            }
        }
        try #require(readinessResult == 1)
        try #require(readiness.revents & Int16(POLLIN) != 0)
        var ready: UInt8 = 0
        try #require(Darwin.read(peer.rawValue, &ready, 1) == 1)
        try #require(ready == 1)
        let identity = try #require(LaunchdProcessSnapshot.current(for: child)?.identity)
        _ = Darwin.close(releasePipe[1])
        releasePipe[1] = -1

        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while LaunchdProcessSnapshot.current(for: child)?.isLive != false,
              DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(1_000)
        }
        try #require(LaunchdProcessSnapshot.current(for: child)?.isLive == false)

        do {
            try LaunchdPeerAuthenticator.verify(
                descriptor: peer.rawValue,
                expectedIdentity: identity
            )
            Issue.record("Peer authentication accepted an exited zombie process")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .secureContainmentVerificationFailed)
        }

        try #require(notebookReapChild(child))
        childWasReaped = true
    }

    @Test("rejected descriptor transfers close every received descriptor")
    func rejectedDescriptorTransferClosesReceivedDescriptors() throws {
        var sockets: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
        let sender = try LaunchdBrokerConnection(descriptor: sockets[0])
        let receiver = try LaunchdBrokerConnection(descriptor: sockets[1])
        let pipes = try (0..<3).map { _ in try BoundedPipe.make() }
        defer {
            sender.close()
            receiver.close()
            for pipe in pipes {
                pipe.read.close()
                pipe.write.close()
            }
        }

        try sender.sendFileDescriptors(
            pipes.map { $0.read.rawValue },
            deadline: { nil },
            pollHook: {}
        )
        do {
            _ = try receiver.receiveFileDescriptors(
                count: 2,
                deadline: { nil },
                pollHook: {}
            )
            Issue.record("A truncated descriptor transfer was unexpectedly accepted")
        } catch {
            // Rejection is expected; the received copies must still be closed.
        }

        for pipe in pipes {
            pipe.read.close()
            var byte: UInt8 = 1
            errno = 0
            #expect(Darwin.write(pipe.write.rawValue, &byte, 1) == -1)
            #expect(errno == EPIPE)
        }
    }

    @Test("monotonic deadline math saturates without overflowing")
    func monotonicDeadlineMathSaturates() {
        let base: UInt64 = 123
        #expect(LaunchdMonotonicClock.adding(seconds: -1, to: base) == base)
        #expect(BoundedMonotonicClock.adding(seconds: -1, to: base) == base)
        #expect(
            LaunchdMonotonicClock.adding(
                seconds: 20_000_000_000,
                to: base
            ) == UInt64.max
        )
        #expect(
            BoundedMonotonicClock.adding(
                seconds: 20_000_000_000,
                to: base
            ) == UInt64.max
        )
        #expect(
            LaunchdMonotonicClock.adding(
                seconds: .greatestFiniteMagnitude,
                to: base
            ) == UInt64.max
        )
        #expect(
            BoundedMonotonicClock.adding(
                seconds: .greatestFiniteMagnitude,
                to: base
            ) == UInt64.max
        )
    }

    @Test("zero process-list bytes fail closed")
    func zeroProcessListBytesFailClosed() {
        do {
            try BoundedPOSIX.requireProcessListBytes(0, errorCode: 0)
            Issue.record("An empty process enumeration was accepted")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .systemCallFailed(operation: "proc_listpids", code: EIO))
        } catch {
            Issue.record("Unexpected process-list error: \(error)")
        }
    }

    @Test("coalition emptiness rejects live members outside UID authority")
    func coalitionDifferentUIDIsCleanupUnverified() {
        let coalitionID: UInt64 = 9_001
        let pid: pid_t = 90_001
        let otherUID: uid_t = geteuid() == 0 ? 1 : 0
        let snapshot = LaunchdProcessSnapshot(
            identity: LaunchdProcessIdentity(
                pid: pid,
                startSeconds: 1,
                startMicroseconds: 1
            ),
            userID: otherUID,
            status: 1
        )
        let inspection = notebookCoalitionInspection(
            pid: pid,
            coalitionID: coalitionID,
            snapshot: snapshot,
            signalAuthority: .available
        )

        do {
            try LaunchdProcessCoalition.verifyEmpty(
                id: coalitionID,
                waitSeconds: 0.05,
                inspection: inspection
            )
            Issue.record("A live cross-UID coalition member was counted as absent")
        } catch let error as BoundedProcessRunnerError {
            guard case .secureCleanupUnverified = error else {
                Issue.record("Unexpected cross-UID cleanup error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected cross-UID cleanup error: \(error)")
        }
    }

    @Test("coalition emptiness rejects EPERM for a live member")
    func coalitionEPERMIsCleanupUnverified() {
        let coalitionID: UInt64 = 9_002
        let pid: pid_t = 90_002
        let snapshot = LaunchdProcessSnapshot(
            identity: LaunchdProcessIdentity(
                pid: pid,
                startSeconds: 1,
                startMicroseconds: 1
            ),
            userID: geteuid(),
            status: 1
        )
        let inspection = notebookCoalitionInspection(
            pid: pid,
            coalitionID: coalitionID,
            snapshot: snapshot,
            signalAuthority: .denied
        )

        do {
            try LaunchdProcessCoalition.verifyEmpty(
                id: coalitionID,
                waitSeconds: 0.05,
                inspection: inspection
            )
            Issue.record("An EPERM coalition member was counted as absent")
        } catch let error as BoundedProcessRunnerError {
            guard case .secureCleanupUnverified = error else {
                Issue.record("Unexpected EPERM cleanup error: \(error)")
                return
            }
        } catch {
            Issue.record("Unexpected EPERM cleanup error: \(error)")
        }
    }

    @Test("coalition scans ignore confirmed zombie processes")
    func coalitionScanIgnoresConfirmedZombie() throws {
        guard let coalitionID = LaunchdProcessCoalition.resourceID(for: getpid()) else {
            return
        }
        var child: pid_t = 0
        let invocation = ["/usr/bin/true"]
        let environment = ["PATH=/usr/bin:/bin"]
        let spawnCode = try BoundedCStringArray.withMutablePointers(invocation) { argv in
            try BoundedCStringArray.withMutablePointers(environment) { envp in
                "/usr/bin/true".withCString { path in
                    posix_spawn(&child, path, nil, nil, argv, envp)
                }
            }
        }
        try #require(spawnCode == 0)
        defer {
            _ = notebookReapChild(child)
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while LaunchdProcessSnapshot.current(for: child)?.isLive != false,
              DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(1_000)
        }
        #expect(LaunchdProcessSnapshot.current(for: child)?.isLive == false)
        _ = try LaunchdProcessCoalition.liveMembers(id: coalitionID)
    }

    @Test("coalition verification bounds identity retries by its absolute deadline")
    func coalitionIdentityRetriesHonorDeadline() throws {
        let snapshot = try #require(LaunchdProcessSnapshot.current(for: getpid()))
        let inspection = LaunchdCoalitionInspection(
            processIDs: { [snapshot.identity.pid] },
            snapshot: { $0 == snapshot.identity.pid ? snapshot : nil },
            resourceID: { _ in nil },
            signalAuthority: { _ in .available },
            retryCount: 100,
            retryDelayMicroseconds: 10_000
        )
        let started = LaunchdMonotonicClock.now()

        do {
            try LaunchdProcessCoalition.verifyEmpty(
                id: UInt64.max - 1,
                waitSeconds: 0.05,
                inspection: inspection
            )
            Issue.record("Coalition identity retries ignored the verification deadline")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .processTreeDidNotTerminate)
        }

        let elapsed = Double(LaunchdMonotonicClock.now() - started) / 1_000_000_000
        #expect(elapsed < 0.25)
    }

    @Test("artifact cleanup never recursively removes unexpected content")
    func artifactCleanupIsNonRecursive() throws {
        try FileManager.default.createDirectory(
            at: LaunchdProcessArtifacts.rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let directoryURL = LaunchdProcessArtifacts.rootURL.appendingPathComponent(
            "execution.\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        let unexpectedDirectory = directoryURL.appendingPathComponent(
            "unexpected",
            isDirectory: true
        )
        let sentinelURL = unexpectedDirectory.appendingPathComponent("sentinel")
        let propertyListURL = directoryURL.appendingPathComponent("job.plist")
        try FileManager.default.createDirectory(
            at: unexpectedDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data("keep".utf8).write(to: sentinelURL)
        try Data("metadata".utf8).write(to: propertyListURL)
        try #require(chmod(propertyListURL.path, S_IRUSR) == 0)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        var status = stat()
        try #require(lstat(directoryURL.path, &status) == 0)
        let identity = LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: status.st_dev),
            inode: UInt64(truncatingIfNeeded: status.st_ino)
        )

        do {
            try LaunchdProcessArtifacts.removeVerified(
                directoryURL: directoryURL,
                expectedIdentity: identity
            )
            Issue.record("Cleanup unexpectedly removed an unknown artifact tree")
        } catch {
            #expect(FileManager.default.fileExists(atPath: sentinelURL.path))
            #expect(FileManager.default.fileExists(atPath: propertyListURL.path))
        }
    }

    @Test("artifact verification reopens the directory for every pass")
    func artifactVerificationDoesNotReuseDirectoryCursor() throws {
        let directoryURL = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let knownURL = directoryURL.appendingPathComponent("job.plist")
        try Data("metadata".utf8).write(to: knownURL)
        let rawDescriptor = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        try #require(rawDescriptor >= 0)
        defer { _ = Darwin.close(rawDescriptor) }

        try LaunchdProcessArtifacts.verifyOnlyKnownArtifacts(
            directoryDescriptor: rawDescriptor,
            allowedNames: ["job.plist"]
        )
        try Data("unexpected".utf8).write(
            to: directoryURL.appendingPathComponent("unexpected")
        )
        do {
            try LaunchdProcessArtifacts.verifyOnlyKnownArtifacts(
                directoryDescriptor: rawDescriptor,
                allowedNames: ["job.plist"]
            )
            Issue.record("A second verification reused the directory's EOF cursor")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .secureContainmentVerificationFailed)
        }
    }

    @Test("staging cleanup runs even when initial lock acquisition fails")
    func stagingCleanupSurvivesInitialLockFailure() throws {
        try LaunchdProcessArtifacts.ensurePrivateRoot()
        let before = Set(try notebookBoundedArtifactDirectories())
        let broker = try #require(LaunchdProcessSnapshot.current(for: getpid()))

        do {
            _ = try LaunchdProcessArtifacts.create(
                brokerIdentity: broker.identity,
                directoryLockAcquirer: { _ in
                    throw BoundedProcessRunnerError.systemCallFailed(
                        operation: "injected staging lock failure",
                        code: EMFILE
                    )
                }
            )
            Issue.record("Injected staging lock failure unexpectedly succeeded")
        } catch let error as BoundedProcessRunnerError {
            #expect(error == .systemCallFailed(
                operation: "injected staging lock failure",
                code: EMFILE
            ))
        }

        #expect(Set(try notebookBoundedArtifactDirectories()) == before)
    }

    @Test("artifact cleanup resumes after quarantine rename")
    func artifactCleanupResumesAfterQuarantineRename() throws {
        try FileManager.default.createDirectory(
            at: LaunchdProcessArtifacts.rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let identifier = UUID().uuidString.lowercased()
        let requestedURL = LaunchdProcessArtifacts.rootURL.appendingPathComponent(
            "execution.\(identifier)",
            isDirectory: true
        )
        let cleanupURL = LaunchdProcessArtifacts.rootURL.appendingPathComponent(
            "cleanup.\(identifier)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: cleanupURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let propertyListURL = cleanupURL.appendingPathComponent("job.plist")
        try Data("metadata".utf8).write(to: propertyListURL)
        try #require(chmod(propertyListURL.path, S_IRUSR) == 0)
        defer { try? FileManager.default.removeItem(at: cleanupURL) }
        var status = stat()
        try #require(lstat(cleanupURL.path, &status) == 0)
        let identity = LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: status.st_dev),
            inode: UInt64(truncatingIfNeeded: status.st_ino)
        )

        try LaunchdProcessArtifacts.removeVerified(
            directoryURL: requestedURL,
            expectedIdentity: identity
        )

        #expect(!FileManager.default.fileExists(atPath: cleanupURL.path))
    }

    @Test("startup reconciliation removes abandoned staging directories")
    func startupReconciliationRemovesAbandonedStaging() throws {
        try FileManager.default.createDirectory(
            at: LaunchdProcessArtifacts.rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let stagingURL = LaunchdProcessArtifacts.rootURL.appendingPathComponent(
            "staging.\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stagingURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: stagingURL) }

        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()

        #expect(!FileManager.default.fileExists(atPath: stagingURL.path))
    }

    @Test("startup reconciliation finishes quarantined pending-state cleanup")
    func startupReconciliationRemovesQuarantinedPendingState() throws {
        try FileManager.default.createDirectory(
            at: LaunchdProcessArtifacts.rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let cleanupURL = LaunchdProcessArtifacts.rootURL.appendingPathComponent(
            "cleanup.\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: cleanupURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let pendingState = cleanupURL.appendingPathComponent("state.plist.pending")
        try Data("partial".utf8).write(to: pendingState)
        try #require(chmod(pendingState.path, S_IRUSR) == 0)
        defer { try? FileManager.default.removeItem(at: cleanupURL) }

        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()

        #expect(!FileManager.default.fileExists(atPath: cleanupURL.path))
    }

    @Test("startup reconciliation never reuses a coalition from a prior boot")
    func startupReconciliationRejectsPriorBootCoalition() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let control = LaunchdControlClient()
        let sentinelLabel = "dev.cocxy.test.prior-boot-sentinel."
            + UUID().uuidString.lowercased()
        defer { notebookBestEffortRemoveLaunchdJob(label: sentinelLabel) }
        let sentinelPropertyListURL = workspace.appendingPathComponent("sentinel.plist")
        let sentinelPropertyList: [String: Any] = [
            "Label": sentinelLabel,
            "ProgramArguments": ["/bin/sleep", "30"],
            "StandardInPath": "/dev/null",
            "StandardOutPath": "/dev/null",
            "StandardErrorPath": "/dev/null",
            "RunAtLoad": true,
            "ProcessType": "Background",
        ]
        try PropertyListSerialization.data(
            fromPropertyList: sentinelPropertyList,
            format: .binary,
            options: 0
        ).write(to: sentinelPropertyListURL, options: .atomic)
        try #require(chmod(sentinelPropertyListURL.path, S_IRUSR) == 0)
        let sentinelBoundary = LaunchdExecutionBoundary(
            deadline: LaunchdMonotonicClock.adding(
                seconds: 5,
                to: LaunchdMonotonicClock.now()
            ),
            cancellationRequested: { false }
        )
        let sentinelDomain = try control.bootstrap(
            label: sentinelLabel,
            propertyListURL: sentinelPropertyListURL,
            boundary: sentinelBoundary
        )
        let sentinelDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        var sentinelSnapshot: LaunchdJobSnapshot?
        var sentinelProcessIdentity: LaunchdProcessIdentity?
        while LaunchdMonotonicClock.now() < sentinelDeadline {
            let snapshot = try control.snapshot(
                domain: sentinelDomain,
                label: sentinelLabel
            )
            if let pid = snapshot.pid,
               let coalitionID = snapshot.resourceCoalitionID,
               let processSnapshot = LaunchdProcessSnapshot.current(for: pid),
               processSnapshot.isLive,
               LaunchdProcessCoalition.resourceID(for: pid) == coalitionID {
                sentinelSnapshot = snapshot
                sentinelProcessIdentity = processSnapshot.identity
                break
            }
            usleep(10_000)
        }
        let runningSentinel = try #require(sentinelSnapshot)
        let sentinelPID = try #require(runningSentinel.pid)
        let sentinelCoalitionID = try #require(runningSentinel.resourceCoalitionID)
        let sentinelIdentity = try #require(sentinelProcessIdentity)
        if let testCoalitionID = LaunchdProcessCoalition.resourceID(for: getpid()) {
            try #require(sentinelCoalitionID != testCoalitionID)
        }

        try FileManager.default.createDirectory(
            at: LaunchdProcessArtifacts.rootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let identifier = UUID().uuidString.lowercased()
        let label = "\(LaunchdProcessNamespace.current.labelPrefix).\(identifier)"
        let directoryURL = LaunchdProcessArtifacts.rootURL.appendingPathComponent(
            "execution.\(identifier)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        var directoryStatus = stat()
        try #require(lstat(directoryURL.path, &directoryStatus) == 0)
        let directoryIdentity = LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: directoryStatus.st_dev),
            inode: UInt64(truncatingIfNeeded: directoryStatus.st_ino)
        )
        let supervisorIdentity = LaunchdProcessIdentity(
            pid: Int32.max,
            startSeconds: 1,
            startMicroseconds: 1
        )
        let controlSocketPath = directoryURL.appendingPathComponent("control.sock").path
        let propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/true",
                LaunchdProcessSupervisorEntry.modeArgument,
                controlSocketPath,
                String(supervisorIdentity.pid),
                String(supervisorIdentity.startSeconds),
                String(supervisorIdentity.startMicroseconds),
            ],
        ]
        let propertyListData = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )
        let propertyListURL = directoryURL.appendingPathComponent("job.plist")
        try propertyListData.write(to: propertyListURL)
        try #require(chmod(propertyListURL.path, S_IRUSR) == 0)

        let currentBootIdentity = try LaunchdBootIdentity.current()
        var staleBootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        while staleBootIdentity == currentBootIdentity {
            staleBootIdentity = LaunchdBootIdentity(sessionUUID: UUID())
        }
        let staleState = LaunchdPersistedExecutionState(
            label: label,
            domain: "gui/\(getuid())",
            coalitionID: sentinelCoalitionID,
            bootIdentity: staleBootIdentity,
            supervisorIdentity: supervisorIdentity,
            directoryDevice: directoryIdentity.device,
            directoryInode: directoryIdentity.inode,
            payloadMayHaveRun: true
        )
        let stateURL = directoryURL.appendingPathComponent("state.plist")
        try PropertyListEncoder().encode(staleState).write(to: stateURL)
        try #require(chmod(stateURL.path, S_IRUSR) == 0)

        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()

        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
        let survivingSentinel = try control.snapshot(
            domain: sentinelDomain,
            label: sentinelLabel
        )
        #expect(survivingSentinel.pid == sentinelPID)
        #expect(survivingSentinel.resourceCoalitionID == sentinelCoalitionID)
        #expect(
            LaunchdProcessSnapshot.current(for: sentinelPID)?.identity
                == sentinelIdentity
        )
    }

    @Test("cleanup failures remain unverified until persisted-state recovery succeeds")
    func cleanupFailureRequiresVerifiedFallback() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let broker = try LaunchdBrokerProcess.spawn()
        var preparedLease: LaunchdProcessLease?
        var securedLease: LaunchdProcessLease?
        var sentinelURL: URL?
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 8) { broker.forceCleanup() }
            if let sentinelURL { try? FileManager.default.removeItem(at: sentinelURL) }
            try? preparedLease?.emergencyCleanup()
            try? securedLease?.emergencyCleanup()
        }

        let request = LaunchdBrokerRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 0.5"],
            workingDirectoryPath: workspace.path,
            environment: ["PATH": "/usr/bin:/bin", "HOME": workspace.path],
            maximumRetainedBytesPerStream: 64 * 1_024,
            deadline: LaunchdMonotonicClock.adding(
                seconds: 10,
                to: LaunchdMonotonicClock.now()
            ),
            timeoutDiagnostic: nil
        )
        try broker.connection.writeFrame(request)
        let eventDeadline = LaunchdMonotonicClock.adding(
            seconds: 8,
            to: LaunchdMonotonicClock.now()
        )
        var receivedExpectedFailure = false
        while !receivedExpectedFailure {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { eventDeadline },
                pollHook: {}
            )
            switch event.kind {
            case .prepared:
                preparedLease = event.lease
            case .ready:
                let lease = try #require(event.lease)
                securedLease = lease
                let unexpected = URL(fileURLWithPath: lease.directoryPath)
                    .appendingPathComponent("unexpected")
                try Data("keep".utf8).write(to: unexpected)
                sentinelURL = unexpected
            case .failed:
                #expect(event.failureKind == .cleanupUnverified)
                #expect(event.cleanupVerified == false)
                receivedExpectedFailure = true
            case .completed, .cancelled:
                Issue.record("Cleanup failure was incorrectly reported as verified")
                receivedExpectedFailure = true
            }
        }

        #expect(broker.waitForExit(timeoutSeconds: 8))
        let sentinel = try #require(sentinelURL)
        try FileManager.default.removeItem(at: sentinel)
        sentinelURL = nil
        let preliminaryLease = try #require(preparedLease)
        #expect(preliminaryLease.coalitionID == nil)
        try preliminaryLease.emergencyCleanup()
        #expect(!FileManager.default.fileExists(atPath: preliminaryLease.directoryPath))
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
        preparedLease = nil
        securedLease = nil
    }

    @Test("per-user artifact paths fit Darwin Unix sockets")
    func perUserArtifactPathFitsUnixSocket() {
        let namespace = LaunchdProcessNamespace.current
        let environment = ProcessInfo.processInfo.environment
        let testRoot = environment[LaunchdProcessNamespace.testRootEnvironmentKey]
            ?? "missing"
        let testLabel = environment[LaunchdProcessNamespace.testLabelEnvironmentKey]
            ?? "missing"
        let namespaceDiagnostic = "root=\(testRoot), label=\(testLabel)"
        let socketURL = LaunchdProcessArtifacts.rootURL
            .appendingPathComponent(
                "execution.00000000-0000-0000-0000-000000000000",
                isDirectory: true
            )
            .appendingPathComponent("control.sock")
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

        #expect(namespace.isValid, Comment(rawValue: namespaceDiagnostic))
        #expect(namespace.isTest)
        #expect(namespace.rootURL != LaunchdProcessNamespace.production.rootURL)
        #expect(namespace.rootURL.path.hasPrefix("/private/tmp/cxbpt.\(getuid())."))
        #expect(socketURL.path.utf8CString.count <= capacity)

        var createdRoot = false
        if mkdir(namespace.rootURL.path, S_IRWXU) == 0 {
            createdRoot = true
        } else {
            #expect(errno == EEXIST)
        }
        defer {
            if createdRoot {
                _ = rmdir(namespace.rootURL.path)
            }
        }
        #expect(
            LaunchdProcessNamespace.current == namespace,
            "Materializing the private root must not change namespace validation"
        )
    }

    @Test("ordinary app arguments cannot activate the bounded process test namespace")
    func ordinaryAppArgumentsCannotActivateTestNamespace() {
        let nonce = "deadbeef"
        let environment = [
            LaunchdProcessNamespace.testRootEnvironmentKey:
                "/private/tmp/cxbpt.\(getuid()).\(nonce)",
            LaunchdProcessNamespace.testLabelEnvironmentKey:
                "dev.cocxy.bounded-process.test.\(getuid()).\(nonce)",
        ]
        let disguised = LaunchdProcessNamespace.resolve(
            arguments: [
                "/Applications/Cocxy Terminal.app/Contents/MacOS/CocxyTerminal",
                "--ordinary-app-option",
                LaunchdProcessBrokerEntry.modeArgument,
            ],
            environment: environment
        )
        let broker = LaunchdProcessNamespace.resolve(
            arguments: [
                "/Applications/Cocxy Terminal.app/Contents/MacOS/CocxyTerminal",
                LaunchdProcessBrokerEntry.modeArgument,
                "3",
                "4",
            ],
            environment: environment
        )

        #expect(disguised == .production)
        #expect(broker.isTest)
        #expect(broker.isValid)
    }

    @Test("a pre-payload supervisor failure does not enter a KeepAlive restart cycle")
    func prePayloadSupervisorFailureDoesNotRestart() throws {
        let broker = try #require(LaunchdProcessSnapshot.current(for: getpid()))
        let artifacts = try LaunchdProcessArtifacts.create(
            brokerIdentity: broker.identity
        )
        let lease = artifacts.lease
        let control = LaunchdControlClient()
        defer {
            notebookBestEffortRemoveLaunchdJob(label: artifacts.label)
            try? artifacts.removeVerified()
            try? lease.emergencyCleanup()
        }

        artifacts.closeStreams()
        let boundary = LaunchdExecutionBoundary(
            deadline: LaunchdMonotonicClock.adding(
                seconds: 5,
                to: LaunchdMonotonicClock.now()
            ),
            cancellationRequested: { false }
        )
        let domain = try control.bootstrap(
            label: artifacts.label,
            propertyListURL: artifacts.propertyListURL,
            boundary: boundary
        )
        let settleDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        var stoppedSnapshot: LaunchdJobSnapshot?
        while LaunchdMonotonicClock.now() < settleDeadline {
            let snapshot = try control.snapshot(
                domain: domain,
                label: artifacts.label
            )
            if snapshot.state == "not running" {
                stoppedSnapshot = snapshot
                break
            }
            usleep(10_000)
        }
        let firstStop = try #require(stoppedSnapshot)
        #expect(firstStop.exitCode == EXIT_SUCCESS)
        #expect(firstStop.runCount == 1)
        #expect(!FileManager.default.fileExists(
            atPath: URL(fileURLWithPath: lease.directoryPath)
                .appendingPathComponent("state.plist").path
        ))

        usleep(1_250_000)
        let afterThrottle = try control.snapshot(
            domain: domain,
            label: artifacts.label
        )
        #expect(afterThrottle.state == "not running")
        #expect(afterThrottle.exitCode == EXIT_SUCCESS)
        #expect(afterThrottle.runCount == firstStop.runCount)

        try control.removeJob(domain: domain, label: artifacts.label)
        try artifacts.removeVerified()
    }

    @Test("a pre-payload supervisor persists recovery state after its owner dies")
    func prePayloadSupervisorPersistsStateAfterOwnerDeath() throws {
        var ownerPID = try notebookSpawnSleepingProcess()
        var ownerWasReaped = false
        var artifacts: LaunchdProcessArtifacts?
        var lease: LaunchdProcessLease?
        var label: String?
        defer {
            if let label { notebookBestEffortRemoveLaunchdJob(label: label) }
            try? lease?.emergencyCleanup()
            try? artifacts?.removeVerified()
            if !ownerWasReaped {
                _ = Darwin.kill(ownerPID, SIGKILL)
                _ = notebookReapChild(ownerPID)
            }
        }

        let owner = try #require(LaunchdProcessSnapshot.current(for: ownerPID))
        artifacts = try LaunchdProcessArtifacts.create(
            brokerIdentity: owner.identity
        )
        let propertyListURL: URL
        let directoryURL: URL
        do {
            let activeArtifacts = try #require(artifacts)
            lease = activeArtifacts.lease
            label = activeArtifacts.label
            propertyListURL = activeArtifacts.propertyListURL
            directoryURL = activeArtifacts.directoryURL
            activeArtifacts.closeStreams()
        }

        try #require(Darwin.kill(ownerPID, SIGKILL) == 0)
        try #require(notebookReapChild(ownerPID))
        ownerWasReaped = true
        ownerPID = -1
        artifacts = nil

        let boundary = LaunchdExecutionBoundary(
            deadline: LaunchdMonotonicClock.adding(
                seconds: 5,
                to: LaunchdMonotonicClock.now()
            ),
            cancellationRequested: { false }
        )
        let control = LaunchdControlClient()
        let domain = try control.bootstrap(
            label: try #require(label),
            propertyListURL: propertyListURL,
            boundary: boundary
        )
        let settleDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        var stoppedSnapshot: LaunchdJobSnapshot?
        while LaunchdMonotonicClock.now() < settleDeadline {
            let snapshot = try control.snapshot(
                domain: domain,
                label: try #require(label)
            )
            if snapshot.state == "not running" {
                stoppedSnapshot = snapshot
                break
            }
            usleep(10_000)
        }

        let stopped = try #require(stoppedSnapshot)
        #expect(stopped.exitCode == EXIT_SUCCESS)
        #expect(stopped.runCount == 1)
        let stateData = try Data(
            contentsOf: directoryURL.appendingPathComponent("state.plist")
        )
        let state = try PropertyListDecoder().decode(
            LaunchdPersistedExecutionState.self,
            from: stateData
        )
        #expect(state.domain == domain)
        #expect(state.coalitionID == stopped.resourceCoalitionID)
        #expect(state.payloadMayHaveRun)

        try #require(lease).emergencyCleanup()
        for candidateDomain in LaunchdControlClient.domains {
            #expect(
                try control.presence(
                    domain: candidateDomain,
                    label: try #require(label)
                ) == .absent
            )
        }
        #expect(!FileManager.default.fileExists(atPath: directoryURL.path))
        lease = nil
        label = nil
    }

    @Test("absolute timeout includes broker startup and prevents command side effects")
    func absoluteTimeoutCoversStartup() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sideEffect = workspace.appendingPathComponent("should-not-exist")
        let start = DispatchTime.now().uptimeNanoseconds

        let result = try LaunchdProcessBrokerClient(
            maximumRetainedBytesPerStream: 64 * 1_024
        ).run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", ": > \(notebookShellQuoted(sideEffect.path))"],
            workingDirectory: workspace,
            timeoutSeconds: 0.01,
            timeoutDiagnostic: "timed out"
        )
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000

        #expect(result.exitCode == 124)
        #expect(result.timedOut)
        #expect(!FileManager.default.fileExists(atPath: sideEffect.path))
        #expect(elapsed < 3)
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
    }

    @Test("owner loss before handoff never starts the payload")
    func ownerLossBeforeHandoffPreventsSideEffects() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sideEffect = workspace.appendingPathComponent("handoff-side-effect")
        let broker = try LaunchdBrokerProcess.spawn()
        var latestLease: LaunchdProcessLease?
        var preparedReceived = false
        var terminalEventReceived = false
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 8) { broker.forceCleanup() }
            try? latestLease?.emergencyCleanup()
        }

        let request = LaunchdBrokerRequest(
            executablePath: "/bin/sh",
            arguments: ["-c", ": > \(notebookShellQuoted(sideEffect.path))"],
            workingDirectoryPath: workspace.path,
            environment: ["PATH": "/usr/bin:/bin", "HOME": workspace.path],
            maximumRetainedBytesPerStream: 64 * 1_024,
            deadline: LaunchdMonotonicClock.adding(
                seconds: 10,
                to: LaunchdMonotonicClock.now()
            ),
            timeoutDiagnostic: nil
        )
        try broker.connection.writeFrame(request)
        let eventDeadline = LaunchdMonotonicClock.adding(
            seconds: 8,
            to: LaunchdMonotonicClock.now()
        )
        while !terminalEventReceived {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { eventDeadline },
                pollHook: {}
            )
            switch event.kind {
            case .prepared:
                guard let lease = event.lease else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                preparedReceived = true
                latestLease = lease
                broker.closeOwnerLiveness()
            case .ready:
                #expect(preparedReceived)
                guard let lease = event.lease else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                latestLease = lease
            case .completed:
                #expect(preparedReceived)
                #expect(event.cleanupVerified == true)
                #expect(event.result?.exitCode == 70)
                terminalEventReceived = true
            case .failed, .cancelled:
                #expect(preparedReceived)
                #expect(event.cleanupVerified == true)
                terminalEventReceived = true
            }
        }

        #expect(preparedReceived)
        #expect(!FileManager.default.fileExists(atPath: sideEffect.path))
        #expect(broker.waitForExit(timeoutSeconds: 8))
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
        latestLease = nil
    }

    @Test("contained commands receive only the explicitly sanitized environment")
    func stripsInheritedAndSensitiveEnvironment() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let marker = "cocxy-secret-\(UUID().uuidString)"
        let source = """
        import os
        print("PATH=" + os.environ.get("PATH", "<missing>"))
        print("HOME=" + os.environ.get("HOME", "<missing>"))
        print("SSH_AUTH_SOCK=" + os.environ.get("SSH_AUTH_SOCK", "<missing>"))
        print("COCXY_SECRET_TOKEN=" + os.environ.get("COCXY_SECRET_TOKEN", "<missing>"))
        """

        let result = try LaunchdProcessBrokerClient(
            maximumRetainedBytesPerStream: 64 * 1_024
        ).run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-c", source],
            workingDirectory: workspace,
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": workspace.path,
                "LANG": "C",
                "SSH_AUTH_SOCK": marker,
                "COCXY_SECRET_TOKEN": marker,
            ],
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("PATH=/usr/bin:/bin\n"))
        #expect(result.stdout.contains("HOME=\(workspace.path)\n"))
        #expect(result.stdout.contains("SSH_AUTH_SOCK=<missing>\n"))
        #expect(result.stdout.contains("COCXY_SECRET_TOKEN=<missing>\n"))
        #expect(!result.stdout.contains(marker))
    }

    @Test("preserves workspace sandbox execution and temporary cleanup")
    func preservesWorkspaceSandbox() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { return }
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let document = NotebookDocument(cells: [
            .code(language: "bash", source: "printf 'sandbox-ok\\n'"),
        ])

        let summary = try NotebookExecutor().execute(
            document,
            workingDirectory: workspace,
            timeoutSeconds: 10,
            sandbox: .workspace
        )

        #expect(summary.results.map(\.exitCode) == [0])
        #expect(summary.results.map(\.stdout) == ["sandbox-ok\n"])
        #expect(!FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent(".cocxy-notebook-tmp").path
        ))
    }

    @Test("executes normal Bash, Python, and Swift notebook kernels")
    func executesNormalKernelMatrix() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/swift") else { return }
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let document = NotebookDocument(cells: [
            .code(language: "bash", source: "printf 'bash-ok\\n'"),
            .code(language: "python", source: "print('python-ok')"),
            .code(language: "swift", source: #"print("swift-ok")"#),
        ])

        let summary = try NotebookExecutor().execute(
            document,
            workingDirectory: workspace,
            timeoutSeconds: 30,
            sandbox: .none,
            stopOnFailure: true
        )

        #expect(summary.failedCellIndex == nil)
        #expect(summary.results.map(\.exitCode) == [0, 0, 0])
        #expect(summary.results.map(\.stdout) == [
            "bash-ok\n",
            "python-ok\n",
            "swift-ok\n",
        ])
    }

    @Test("mandatory containment blocks launchd job creation escapes")
    func blocksLaunchdJobCreationEscape() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let label = "dev.cocxy.test.escape.\(UUID().uuidString.lowercased())"
        defer { notebookBestEffortRemoveLaunchdJob(label: label) }
        let source = """
        /bin/launchctl submit -l "$1" -- /bin/sleep 30 >/dev/null 2>&1
        status=$?
        printf '%d\n' "$status"
        exit 0
        """

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", source, "cocxy-launchctl-test", label],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        let status = try #require(
            Int32(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        #expect(result.exitCode == 0)
        #expect(status != 0)
        for domain in LaunchdControlClient.domains {
            let presence = try LaunchdControlClient().presence(domain: domain, label: label)
            #expect(presence == .absent)
        }
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
    }

    @Test("mandatory containment blocks LaunchServices and Apple Event escapes")
    func blocksLaunchServicesAndAppleEventEscapes() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let markerURL = workspace.appendingPathComponent("launch-services-escape.pid")
        let helperURL = try notebookCreateLaunchServicesHelper(
            in: workspace,
            markerURL: markerURL
        )
        var escapedIdentity: NotebookTestProcessIdentity?
        defer {
            if let escapedIdentity { notebookBestEffortTerminate(escapedIdentity) }
        }
        let source = """
        /usr/bin/open -n "$1"
        printf 'open=%d\n' "$?"
        /usr/bin/osascript -e 'tell application "Finder" to get name'
        printf 'appleevent=%d\n' "$?"
        """

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", source, "cocxy-launch-services", helperURL.path],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )
        if FileManager.default.fileExists(atPath: markerURL.path) {
            escapedIdentity = try? notebookReadProcessIdentity(markerURL)
        }

        #expect(result.exitCode == 0)
        #expect(result.stdout == "open=126\nappleevent=126\n")
        #expect(result.stderr.contains("/usr/bin/open"))
        #expect(result.stderr.contains("/usr/bin/osascript"))
        #expect(result.stderr.contains("Operation not permitted"))
        #expect(escapedIdentity == nil)
    }

    @Test("mandatory launchd denial survives workspace sandbox composition")
    func workspaceSandboxBlocksLaunchdJobCreationEscape() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let label = "dev.cocxy.test.workspace-escape.\(UUID().uuidString.lowercased())"
        defer { notebookBestEffortRemoveLaunchdJob(label: label) }
        let source = """
        /bin/launchctl submit -l \(notebookShellQuoted(label)) -- /bin/sleep 30 >/dev/null 2>&1
        status=$?
        printf '%d\n' "$status"
        exit 0
        """
        let document = NotebookDocument(cells: [.code(language: "bash", source: source)])

        let summary = try NotebookExecutor().execute(
            document,
            workingDirectory: workspace,
            timeoutSeconds: 10,
            sandbox: .workspace
        )

        let result = try #require(summary.results.first)
        let status = try #require(
            Int32(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        #expect(result.exitCode == 0)
        #expect(status != 0)
        for domain in LaunchdControlClient.domains {
            let presence = try LaunchdControlClient().presence(domain: domain, label: label)
            #expect(presence == .absent)
        }
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
    }

    @Test("contained descendants can signal a parent in the same sandbox")
    func allowsSignalsWithinContainedExecution() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = """
        received=0
        trap 'received=1' USR1
        /bin/sh -c '/bin/kill -USR1 "$PPID"'
        wait
        printf 'received=%d\n' "$received"
        """

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", source],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "received=1\n")
    }

    @Test("mandatory containment prevents signals to unrelated processes")
    func blocksSignalsToUnrelatedProcesses() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let sentinel = Process()
        sentinel.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sentinel.arguments = ["30"]
        try sentinel.run()
        let sentinelIdentity = try #require(
            notebookCurrentProcessIdentity(sentinel.processIdentifier)
        )
        defer {
            if sentinel.isRunning { sentinel.terminate() }
            sentinel.waitUntilExit()
        }
        let source = """
        /bin/kill -KILL "$1" >/dev/null 2>&1
        status=$?
        printf '%d\n' "$status"
        exit 0
        """

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                source,
                "cocxy-signal-test",
                String(sentinelIdentity.pid),
            ],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        let status = try #require(
            Int32(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
        )
        #expect(result.exitCode == 0)
        #expect(status != 0)
        #expect(notebookCurrentProcessIdentity(sentinelIdentity.pid) == sentinelIdentity)
    }

    @Test("broker owner-channel loss cancels the workload and removes launchd state")
    func ownerChannelLossCleansExecution() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let pidFile = workspace.appendingPathComponent("owner-loss.pid")
        let secretMarker = "owner-secret-\(UUID().uuidString)"
        let source = notebookSignalResistantPythonChild(pidFile: pidFile)
        let broker = try LaunchdBrokerProcess.spawn()
        var latestLease: LaunchdProcessLease?
        var identity: NotebookTestProcessIdentity?
        defer {
            broker.connection.close()
            if !broker.waitForExit(timeoutSeconds: 8) { broker.forceCleanup() }
            try? latestLease?.emergencyCleanup()
            if let identity { notebookBestEffortTerminate(identity) }
        }

        let request = LaunchdBrokerRequest(
            executablePath: "/usr/bin/env",
            arguments: ["python3", "-c", source],
            workingDirectoryPath: workspace.path,
            environment: [
                "PATH": "/usr/bin:/bin",
                "HOME": workspace.path,
                "COCXY_SECRET_TOKEN": secretMarker,
            ],
            maximumRetainedBytesPerStream: 64 * 1_024,
            deadline: LaunchdMonotonicClock.adding(
                seconds: 30,
                to: LaunchdMonotonicClock.now()
            ),
            timeoutDiagnostic: "owner-loss timeout"
        )
        try broker.connection.writeFrame(request)
        let eventDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        while latestLease?.coalitionID == nil {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { eventDeadline },
                pollHook: {}
            )
            switch event.kind {
            case .prepared, .ready:
                guard let lease = event.lease else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                latestLease = lease
            case .failed:
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    event.errorMessage ?? "owner-loss setup failed"
                )
            case .completed, .cancelled:
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        }

        let securedLease = try #require(latestLease)
        let propertyListURL = URL(fileURLWithPath: securedLease.directoryPath)
            .appendingPathComponent("job.plist")
        let propertyListData = try Data(contentsOf: propertyListURL)
        let propertyList = try #require(
            PropertyListSerialization.propertyList(
                from: propertyListData,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let persistedArguments = try #require(propertyList["ProgramArguments"] as? [String])
        let inheritedEnvironment = try #require(
            propertyList["EnvironmentVariables"] as? [String: String]
        )
        #expect(inheritedEnvironment == LaunchdProcessNamespace.current.inheritedEnvironment)
        #expect(propertyList["StandardOutPath"] as? String == "/dev/null")
        #expect(propertyList["StandardErrorPath"] as? String == "/dev/null")
        let keepAlive = try #require(propertyList["KeepAlive"] as? [String: Any])
        #expect(keepAlive["SuccessfulExit"] as? Bool == false)
        #expect(propertyList["ThrottleInterval"] as? Int == 1)
        #expect(persistedArguments.count == 6)
        #expect(!persistedArguments.contains(source))
        #expect(!persistedArguments.contains("python3"))
        #expect(propertyListData.range(of: Data(secretMarker.utf8)) == nil)
        #expect(propertyListData.range(of: Data(source.utf8)) == nil)
        let stateData = try Data(
            contentsOf: URL(fileURLWithPath: securedLease.directoryPath)
                .appendingPathComponent("state.plist")
        )
        let persistedState = try PropertyListDecoder().decode(
            LaunchdPersistedExecutionState.self,
            from: stateData
        )
        #expect(persistedState.label == securedLease.label)
        #expect(persistedState.domain == securedLease.domain)
        #expect(persistedState.coalitionID == securedLease.coalitionID)
        #expect(persistedState.bootIdentity == (try LaunchdBootIdentity.current()))
        #expect(persistedState.payloadMayHaveRun)
        #expect(stateData.range(of: Data(secretMarker.utf8)) == nil)
        #expect(stateData.range(of: Data(source.utf8)) == nil)
        let persistedArtifactNames = try Set(
            FileManager.default.contentsOfDirectory(atPath: securedLease.directoryPath)
        )
        #expect(persistedArtifactNames == ["job.plist", "state.plist"])

        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()
        #expect(FileManager.default.fileExists(atPath: securedLease.directoryPath))
        if let domain = securedLease.domain {
            let presence = try LaunchdControlClient().presence(
                domain: domain,
                label: securedLease.label
            )
            if case .present = presence {
                // Expected: reconciliation must not touch a live broker's execution.
            } else {
                Issue.record("Active launchd execution was removed during reconciliation")
            }
        }

        try await notebookWaitForFile(pidFile, timeoutSeconds: 2)
        identity = try notebookReadProcessIdentity(pidFile)
        broker.connection.close()
        #expect(broker.waitForExit(timeoutSeconds: 8))

        if let identity { await notebookExpectProcessGone(identity) }
        for domain in LaunchdControlClient.domains {
            let presence = try LaunchdControlClient().presence(
                domain: domain,
                label: securedLease.label
            )
            #expect(presence == .absent)
        }
        #expect(!FileManager.default.fileExists(atPath: securedLease.directoryPath))
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
        identity = nil
    }

    @Test("launchd recovery contains the workload when owner, broker, and supervisor die")
    func simultaneousOwnerAndBrokerDeathRemainsContained() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let pidFile = workspace.appendingPathComponent("simultaneous-owner-loss.pid")
        let source = notebookSignalResistantPythonChild(pidFile: pidFile)
        let broker = try LaunchdBrokerProcess.spawn()
        var latestLease: LaunchdProcessLease?
        var identity: NotebookTestProcessIdentity?
        var supervisorIdentity: NotebookTestProcessIdentity?
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 1) { broker.forceCleanup() }
            try? latestLease?.emergencyCleanup()
            if let identity { notebookBestEffortTerminate(identity) }
            if let supervisorIdentity { notebookBestEffortTerminate(supervisorIdentity) }
        }

        let request = LaunchdBrokerRequest(
            executablePath: "/usr/bin/env",
            arguments: ["python3", "-c", source],
            workingDirectoryPath: workspace.path,
            environment: ["PATH": "/usr/bin:/bin", "HOME": workspace.path],
            maximumRetainedBytesPerStream: 64 * 1_024,
            deadline: LaunchdMonotonicClock.adding(
                seconds: 30,
                to: LaunchdMonotonicClock.now()
            ),
            timeoutDiagnostic: "simultaneous owner loss"
        )
        try broker.connection.writeFrame(request)
        let eventDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        while latestLease?.coalitionID == nil {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { eventDeadline },
                pollHook: {}
            )
            switch event.kind {
            case .prepared, .ready:
                guard let lease = event.lease else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                latestLease = lease
            case .failed:
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    event.errorMessage ?? "simultaneous owner-loss setup failed"
                )
            case .completed, .cancelled:
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        }

        let securedLease = try #require(latestLease)
        try await notebookWaitForFile(pidFile, timeoutSeconds: 2)
        identity = try notebookReadProcessIdentity(pidFile)
        let domain = try #require(securedLease.domain)
        let jobPresence = try LaunchdControlClient().presence(
            domain: domain,
            label: securedLease.label
        )
        guard case .present(let job) = jobPresence,
              let supervisorPID = job.pid else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let observedSupervisorIdentity = try #require(
            notebookCurrentProcessIdentity(supervisorPID)
        )
        supervisorIdentity = observedSupervisorIdentity
        #expect(notebookResourceCoalitionID(supervisorPID) == securedLease.coalitionID)

        try #require(kill(broker.pid, SIGSTOP) == 0)
        try #require(kill(supervisorPID, SIGSTOP) == 0)
        broker.connection.close()
        broker.closeOwnerLiveness()
        try #require(kill(broker.pid, SIGKILL) == 0)
        try #require(kill(supervisorPID, SIGKILL) == 0)
        #expect(broker.waitForExit(timeoutSeconds: 2))

        if let identity {
            await notebookExpectProcessGone(identity, timeoutSeconds: 5)
        }
        let recoveryDeadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        var recoverySettled = false
        while DispatchTime.now().uptimeNanoseconds < recoveryDeadline {
            let presence = try LaunchdControlClient().presence(
                domain: domain,
                label: securedLease.label
            )
            switch presence {
            case .absent:
                break
            case .present(let snapshot) where snapshot.state == "not running":
                break
            default:
                try await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            recoverySettled = true
            break
        }
        #expect(recoverySettled)
        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()
        for domain in LaunchdControlClient.domains {
            #expect(
                try LaunchdControlClient().presence(
                    domain: domain,
                    label: securedLease.label
                ) == .absent
            )
        }
        #expect(!FileManager.default.fileExists(atPath: securedLease.directoryPath))
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
        latestLease = nil
        identity = nil
        supervisorIdentity = nil
    }

    @Test("supervisor observes app death while the broker is stopped")
    func appLivenessBypassesStoppedBroker() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let pidFile = workspace.appendingPathComponent("stopped-broker-owner-loss.pid")
        let source = notebookSignalResistantPythonChild(pidFile: pidFile)
        let broker = try LaunchdBrokerProcess.spawn()
        var latestLease: LaunchdProcessLease?
        var identity: NotebookTestProcessIdentity?
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 1) { broker.forceCleanup() }
            try? latestLease?.emergencyCleanup()
            if let identity { notebookBestEffortTerminate(identity) }
        }

        let request = LaunchdBrokerRequest(
            executablePath: "/usr/bin/env",
            arguments: ["python3", "-c", source],
            workingDirectoryPath: workspace.path,
            environment: ["PATH": "/usr/bin:/bin", "HOME": workspace.path],
            maximumRetainedBytesPerStream: 64 * 1_024,
            deadline: nil,
            timeoutDiagnostic: nil
        )
        try broker.connection.writeFrame(request)
        let eventDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        while latestLease?.coalitionID == nil {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { eventDeadline },
                pollHook: {}
            )
            switch event.kind {
            case .prepared, .ready:
                guard let lease = event.lease else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                latestLease = lease
            case .failed:
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    event.errorMessage ?? "stopped-broker setup failed"
                )
            case .completed, .cancelled:
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        }

        let securedLease = try #require(latestLease)
        try await notebookWaitForFile(pidFile, timeoutSeconds: 2)
        identity = try notebookReadProcessIdentity(pidFile)
        try #require(kill(broker.pid, SIGSTOP) == 0)
        broker.closeOwnerLiveness()

        if let identity { await notebookExpectProcessGone(identity) }
        try #require(kill(broker.pid, SIGKILL) == 0)
        #expect(broker.waitForExit(timeoutSeconds: 2))
        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()
        for domain in LaunchdControlClient.domains {
            #expect(
                try LaunchdControlClient().presence(
                    domain: domain,
                    label: securedLease.label
                ) == .absent
            )
        }
        #expect(!FileManager.default.fileExists(atPath: securedLease.directoryPath))
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
        latestLease = nil
        identity = nil
    }

    @Test("watchdog diagnostics cannot block a stopped broker's supervisor")
    func watchdogDiagnosticIsNonBlocking() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let pidFile = workspace.appendingPathComponent("blocked-diagnostic.pid")
        let source = """
        import os, signal
        signal.alarm(30)
        with open(\(notebookPythonLiteral(pidFile.path)), "w") as handle:
            handle.write(str(os.getpid()))
            handle.flush()
        chunk = b"x" * 65536
        while True:
            os.write(2, chunk)
        """
        let broker = try LaunchdBrokerProcess.spawn()
        var latestLease: LaunchdProcessLease?
        var identity: NotebookTestProcessIdentity?
        defer {
            broker.connection.close()
            broker.closeOwnerLiveness()
            if !broker.waitForExit(timeoutSeconds: 1) { broker.forceCleanup() }
            try? latestLease?.emergencyCleanup()
            if let identity { notebookBestEffortTerminate(identity) }
        }

        let request = LaunchdBrokerRequest(
            executablePath: "/usr/bin/env",
            arguments: ["python3", "-c", source],
            workingDirectoryPath: workspace.path,
            environment: ["PATH": "/usr/bin:/bin", "HOME": workspace.path],
            maximumRetainedBytesPerStream: 64 * 1_024,
            deadline: LaunchdMonotonicClock.adding(
                seconds: 2,
                to: LaunchdMonotonicClock.now()
            ),
            timeoutDiagnostic: "watchdog timeout"
        )
        try broker.connection.writeFrame(request)
        let eventDeadline = LaunchdMonotonicClock.adding(
            seconds: 5,
            to: LaunchdMonotonicClock.now()
        )
        while latestLease?.coalitionID == nil {
            let event: LaunchdBrokerEvent = try broker.connection.readFrame(
                deadline: { eventDeadline },
                pollHook: {}
            )
            switch event.kind {
            case .prepared, .ready:
                guard let lease = event.lease else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                latestLease = lease
            case .failed:
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    event.errorMessage ?? "watchdog setup failed"
                )
            case .completed, .cancelled:
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        }

        let securedLease = try #require(latestLease)
        try await notebookWaitForFile(pidFile, timeoutSeconds: 2)
        identity = try notebookReadProcessIdentity(pidFile)
        try #require(kill(broker.pid, SIGSTOP) == 0)
        if let identity { await notebookExpectProcessGone(identity) }

        let stopDeadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        var supervisorStopped = false
        while DispatchTime.now().uptimeNanoseconds < stopDeadline {
            let states = try LaunchdControlClient.domains.map {
                try LaunchdControlClient().presence(
                    domain: $0,
                    label: securedLease.label,
                    timeoutSeconds: 0.5
                )
            }
            supervisorStopped = states.allSatisfy { presence in
                switch presence {
                case .absent:
                    return true
                case .present(let snapshot):
                    return snapshot.state == "not running"
                case .unknown:
                    return false
                }
            }
            if supervisorStopped { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(supervisorStopped)

        try #require(kill(broker.pid, SIGKILL) == 0)
        #expect(broker.waitForExit(timeoutSeconds: 2))
        try LaunchdProcessArtifacts.reconcileAbandonedExecutions()
        #expect(!FileManager.default.fileExists(atPath: securedLease.directoryPath))
        #expect(try notebookBoundedArtifactDirectories().isEmpty)
        latestLease = nil
        identity = nil
    }

    @Test("cleans background children after normal parent exit for every kernel")
    func cleansBackgroundChildrenAfterNormalParentExit() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/swift") else { return }
        for language in ["bash", "python", "swift"] {
            try await verifyNormalParentExitCleanup(language: language)
        }
    }

    @Test("timeout kills a signal-resistant child and grandchild in a detached session")
    func timeoutKillsCompleteProcessTree() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let files = NotebookTreeFixtureFiles(workspace: workspace)
        let source = notebookPythonTreeSource(files: files)
        let executor = NotebookExecutor()
        let document = NotebookDocument(cells: [.code(language: "python", source: source)])
        let task = Task.detached {
            try executor.execute(
                document,
                workingDirectory: workspace,
                timeoutSeconds: 2,
                sandbox: .workspace
            )
        }
        var identities: [NotebookTestProcessIdentity] = []
        defer {
            task.cancel()
            identities.forEach(notebookBestEffortTerminate)
        }

        do {
            try await notebookWaitForFile(files.ready, timeoutSeconds: 1)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        do {
            identities = try [files.parentPID, files.childPID, files.grandchildPID]
                .map(notebookReadProcessIdentity)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        #expect(getsid(identities[0].pid) > 0)
        #expect(getsid(identities[1].pid) == identities[1].pid)
        #expect(getsid(identities[2].pid) == identities[1].pid)

        let summary = try await task.value

        #expect(summary.results.count == 1)
        #expect(summary.results[0].exitCode == 124)
        #expect(summary.results[0].stderr.contains("Command timed out after 2 seconds."))
        for identity in identities {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("timeout finds a double-forked descendant after both intermediaries exit")
    func timeoutKillsRapidDoubleForkEscape() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let escapedPID = workspace.appendingPathComponent("escaped.pid")
        let rootReady = workspace.appendingPathComponent("root.ready")
        let source = notebookRapidDoubleForkSource(pidFile: escapedPID, rootReady: rootReady)
        let task = Task.detached {
            try NotebookProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-c", source],
                workingDirectory: workspace,
                timeoutSeconds: 5
            )
        }
        var identity: NotebookTestProcessIdentity?
        defer {
            task.cancel()
            if let identity { notebookBestEffortTerminate(identity) }
        }

        do {
            async let rootBecameReady: Void = notebookWaitForFile(
                rootReady,
                timeoutSeconds: 3
            )
            async let escapedPIDWasPublished: Void = notebookWaitForFile(
                escapedPID,
                timeoutSeconds: 3
            )
            _ = try await (rootBecameReady, escapedPIDWasPublished)
            identity = try notebookReadProcessIdentity(escapedPID)
            if let identity {
                #expect(getsid(identity.pid) == identity.pid)
            }
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }

        let result = try await task.value

        #expect(result.exitCode == 124)
        #expect(result.stderr.contains("Command timed out after 5 seconds."))
        if let identity {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("normal exit cleans a child that disclaims responsibility and creates a new session")
    func normalExitKillsDisclaimedSessionEscape() async throws {
        let xctestURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        guard FileManager.default.isExecutableFile(atPath: xctestURL.path),
              let testBundleURL = notebookCurrentTestBundleURL() else {
            Issue.record("The xctest runtime is unavailable: \(CommandLine.arguments)")
            return
        }
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let evidenceURL = workspace.appendingPathComponent("responsibility-escape.pid")
        let task = Task.detached {
            try NotebookProcessRunner().run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: [
                    "COCXY_TEST_RESPONSIBILITY_ESCAPE_EVIDENCE=\(evidenceURL.path)",
                    xctestURL.path,
                    "xctest",
                    testBundleURL.path,
                ],
                workingDirectory: workspace,
                timeoutSeconds: 10
            )
        }
        var identity: NotebookTestProcessIdentity?
        defer {
            task.cancel()
            if let identity { notebookBestEffortTerminate(identity) }
        }
        let escapedPID: pid_t
        let responsiblePID: pid_t
        let sessionPID: pid_t
        do {
            try await notebookWaitForFile(evidenceURL, timeoutSeconds: 3)
            let fields = try String(contentsOf: evidenceURL, encoding: .utf8)
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { UInt64($0) }
            guard fields.count == 5,
                  let parsedEscapedPID = pid_t(exactly: fields[0]),
                  let parsedResponsiblePID = pid_t(exactly: fields[1]),
                  let parsedSessionPID = pid_t(exactly: fields[2]) else {
                throw NotebookProcessTestError.invalidProcessID(
                    String(describing: fields)
                )
            }
            escapedPID = parsedEscapedPID
            responsiblePID = parsedResponsiblePID
            sessionPID = parsedSessionPID
            identity = NotebookTestProcessIdentity(
                pid: escapedPID,
                startSeconds: fields[3],
                startMicroseconds: fields[4]
            )
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }

        let result = try await task.value

        #expect(result.exitCode == 0)
        #expect(responsiblePID == escapedPID)
        #expect(sessionPID == escapedPID)
        if let liveIdentity = identity {
            await notebookExpectProcessGone(liveIdentity)
            identity = notebookCurrentProcessIdentity(escapedPID)
        }
        #expect(identity == nil)
    }

    @Test("task cancellation tears down the complete process tree before throwing")
    func cancellationKillsCompleteProcessTree() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let files = NotebookTreeFixtureFiles(workspace: workspace)
        let source = notebookPythonTreeSource(files: files)
        let executor = NotebookExecutor()
        let document = NotebookDocument(cells: [.code(language: "python", source: source)])
        let task = Task.detached {
            try executor.execute(
                document,
                workingDirectory: workspace,
                timeoutSeconds: nil,
                sandbox: .none
            )
        }
        var identities: [NotebookTestProcessIdentity] = []
        defer {
            task.cancel()
            identities.forEach(notebookBestEffortTerminate)
        }

        do {
            try await notebookWaitForFile(files.ready, timeoutSeconds: 2)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        do {
            identities = try [files.parentPID, files.childPID, files.grandchildPID]
                .map(notebookReadProcessIdentity)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected notebook execution cancellation")
        } catch is CancellationError {
            // Expected after process-tree teardown.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        for identity in identities {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("a timed-out execution cannot signal a concurrent notebook session")
    func concurrentExecutionsRemainIsolated() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstPID = workspace.appendingPathComponent("first.pid")
        let secondPID = workspace.appendingPathComponent("second.pid")
        let secondRelease = workspace.appendingPathComponent("second.release")
        let firstSource = notebookSignalResistantPythonChild(pidFile: firstPID)
        let secondSource = """
        import os, signal, time
        signal.alarm(30)
        with open(\(notebookPythonLiteral(secondPID.path)), "w") as handle:
            handle.write(str(os.getpid()))
            handle.flush()
        while not os.path.exists(\(notebookPythonLiteral(secondRelease.path))):
            time.sleep(0.005)
        print("second-ok")
        """
        let runner = NotebookProcessRunner()
        let firstTask = Task.detached {
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-c", firstSource],
                workingDirectory: workspace,
                timeoutSeconds: 2
            )
        }
        let secondTask = Task.detached {
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-c", secondSource],
                workingDirectory: workspace,
                timeoutSeconds: 10
            )
        }
        var identities: [NotebookTestProcessIdentity] = []
        defer {
            firstTask.cancel()
            secondTask.cancel()
            _ = FileManager.default.createFile(atPath: secondRelease.path, contents: Data())
            identities.forEach(notebookBestEffortTerminate)
        }

        do {
            async let firstPIDWasPublished: Void = notebookWaitForFile(
                firstPID,
                timeoutSeconds: 3
            )
            async let secondPIDWasPublished: Void = notebookWaitForFile(
                secondPID,
                timeoutSeconds: 3
            )
            _ = try await (firstPIDWasPublished, secondPIDWasPublished)
            identities = try [firstPID, secondPID].map(notebookReadProcessIdentity)
        } catch {
            firstTask.cancel()
            secondTask.cancel()
            _ = FileManager.default.createFile(atPath: secondRelease.path, contents: Data())
            _ = try? await firstTask.value
            _ = try? await secondTask.value
            throw error
        }
        #expect(identities[0].pid != identities[1].pid)
        #expect(getpgid(identities[0].pid) == identities[0].pid)
        #expect(getpgid(identities[1].pid) == identities[1].pid)
        let firstCoalitionID = try #require(notebookResourceCoalitionID(identities[0].pid))
        let secondCoalitionID = try #require(notebookResourceCoalitionID(identities[1].pid))
        #expect(firstCoalitionID != secondCoalitionID)

        let firstResult = try await firstTask.value

        #expect(firstResult.exitCode == 124)
        #expect(notebookCurrentProcessIdentity(identities[1].pid) == identities[1])
        _ = FileManager.default.createFile(atPath: secondRelease.path, contents: Data())
        let secondResult = try await secondTask.value
        #expect(secondResult.exitCode == 0)
        #expect(secondResult.stdout == "second-ok\n")
        for identity in identities {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("retains bounded stdout and stderr while continuing to drain both pipes")
    func boundsCapturedOutput() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let emittedBytes = NotebookProcessRunner.maximumRetainedBytesPerStream + 128 * 1_024
        let source = """
        import sys
        sys.stdout.buffer.write(b"\\xff" * \(emittedBytes))
        sys.stderr.write("e" * \(emittedBytes))
        """

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-c", source],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count <= NotebookProcessRunner.maximumRetainedBytesPerStream)
        #expect(result.stderr.utf8.count <= NotebookProcessRunner.maximumRetainedBytesPerStream)
        #expect(result.stdout.contains("Output truncated at"))
        #expect(result.stderr.contains("Output truncated at"))
    }

    private func verifyNormalParentExitCleanup(language: String) async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let childPID = workspace.appendingPathComponent("child.pid")
        let ready = workspace.appendingPathComponent("parent.ready")
        let release = workspace.appendingPathComponent("parent.release")
        let childSource = notebookSignalResistantPythonChild(pidFile: childPID)
        let source = notebookParentSource(
            language: language,
            childSource: childSource,
            childPID: childPID,
            ready: ready,
            release: release
        )
        let executor = NotebookExecutor()
        let document = NotebookDocument(cells: [.code(language: language, source: source)])
        let task = Task.detached {
            try executor.execute(
                document,
                workingDirectory: workspace,
                timeoutSeconds: 30,
                sandbox: .none
            )
        }
        var identity: NotebookTestProcessIdentity?
        defer {
            task.cancel()
            _ = FileManager.default.createFile(atPath: release.path, contents: Data())
            if let identity { notebookBestEffortTerminate(identity) }
        }

        do {
            try await notebookWaitForFile(ready, timeoutSeconds: 15)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        do {
            identity = try notebookReadProcessIdentity(childPID)
        } catch {
            task.cancel()
            _ = FileManager.default.createFile(atPath: release.path, contents: Data())
            _ = try? await task.value
            throw error
        }
        _ = FileManager.default.createFile(atPath: release.path, contents: Data())

        let summary = try await task.value

        #expect(summary.failedCellIndex == nil)
        #expect(summary.results.count == 1)
        #expect(summary.results[0].exitCode == 0)
        #expect(summary.results[0].stdout == "\(language)-parent-exited\n")
        if let identity {
            await notebookExpectProcessGone(identity)
        }
    }
}

private struct NotebookTreeFixtureFiles {
    let parentPID: URL
    let childPID: URL
    let grandchildPID: URL
    let ready: URL

    init(workspace: URL) {
        parentPID = workspace.appendingPathComponent("parent.pid")
        childPID = workspace.appendingPathComponent("child.pid")
        grandchildPID = workspace.appendingPathComponent("grandchild.pid")
        ready = workspace.appendingPathComponent("tree.ready")
    }
}

private struct NotebookTestProcessIdentity: Equatable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

private final class NotebookProcessTestErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.withLock { storage }
    }

    func record(_ error: any Error) {
        lock.withLock {
            storage.append(String(reflecting: error))
        }
    }
}

private struct NotebookTestCoalitionInfo {
    var resourceID: UInt64 = 0
    var jetsamID: UInt64 = 0
    var reserved1: UInt64 = 0
    var reserved2: UInt64 = 0
    var reserved3: UInt64 = 0
}

private enum NotebookProcessTestError: Error {
    case timedOut(String)
    case invalidProcessID(String)
    case processNotRunning(pid_t)
}

private func notebookCoalitionInspection(
    pid: pid_t,
    coalitionID: UInt64,
    snapshot: LaunchdProcessSnapshot,
    signalAuthority: LaunchdProcessSignalAuthority
) -> LaunchdCoalitionInspection {
    LaunchdCoalitionInspection(
        processIDs: { [pid] },
        snapshot: { $0 == pid ? snapshot : nil },
        resourceID: { $0 == pid ? coalitionID : nil },
        signalAuthority: { $0 == pid ? signalAuthority : .absent },
        retryCount: 1,
        retryDelayMicroseconds: 0
    )
}

private func notebookSignalResistantPythonChild(pidFile: URL) -> String {
    """
    import os, signal, time
    signal.alarm(60)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(pidFile.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    while True:
        time.sleep(60)
    """
}

private func notebookRapidDoubleForkSource(pidFile: URL, rootReady: URL) -> String {
    """
    import os, signal, time
    signal.alarm(30)
    open(\(notebookPythonLiteral(rootReady.path)), "w").close()
    time.sleep(0.125)
    intermediate = os.fork()
    if intermediate == 0:
        os.setsid()
        escaped = os.fork()
        if escaped > 0:
            os._exit(0)
        os.setsid()
        signal.alarm(30)
        null_fd = os.open("/dev/null", os.O_RDWR)
        for descriptor in (0, 1, 2):
            os.dup2(null_fd, descriptor)
        if null_fd > 2:
            os.close(null_fd)
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        pid_path = \(notebookPythonLiteral(pidFile.path))
        temporary_pid_path = pid_path + ".tmp"
        with open(temporary_pid_path, "w") as handle:
            handle.write(str(os.getpid()))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_pid_path, pid_path)
        while True:
            time.sleep(60)
    reap_deadline = time.monotonic() + 2
    while time.monotonic() < reap_deadline:
        reaped, _ = os.waitpid(intermediate, os.WNOHANG)
        if reaped == intermediate:
            break
        time.sleep(0.005)
    while True:
        time.sleep(60)
    """
}

private func notebookParentSource(
    language: String,
    childSource: String,
    childPID: URL,
    ready: URL,
    release: URL
) -> String {
    switch language {
    case "bash":
        return """
        /usr/bin/python3 -c \(notebookShellQuoted(childSource)) &
        while [ ! -s \(notebookShellQuoted(childPID.path)) ]; do :; done
        : > \(notebookShellQuoted(ready.path))
        while [ ! -e \(notebookShellQuoted(release.path)) ]; do :; done
        printf 'bash-parent-exited\\n'
        """
    case "python":
        return """
        import os, subprocess, sys, time
        subprocess.Popen(
            [sys.executable, "-c", \(notebookPythonLiteral(childSource))],
            stdin=subprocess.DEVNULL
        )
        while not (
            os.path.exists(\(notebookPythonLiteral(childPID.path)))
            and os.path.getsize(\(notebookPythonLiteral(childPID.path))) > 0
        ):
            time.sleep(0.005)
        open(\(notebookPythonLiteral(ready.path)), "w").close()
        while not os.path.exists(\(notebookPythonLiteral(release.path))):
            time.sleep(0.005)
        print("python-parent-exited")
        """
    case "swift":
        return """
        import Foundation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", \(String(reflecting: childSource))]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.standardOutput
        child.standardError = FileHandle.standardError
        try child.run()
        while !FileManager.default.fileExists(atPath: \(String(reflecting: childPID.path))) {
            usleep(5_000)
        }
        FileManager.default.createFile(atPath: \(String(reflecting: ready.path)), contents: Data())
        while !FileManager.default.fileExists(atPath: \(String(reflecting: release.path))) {
            usleep(5_000)
        }
        print("swift-parent-exited")
        """
    default:
        return ""
    }
}

private func notebookPythonTreeSource(files: NotebookTreeFixtureFiles) -> String {
    let grandchildSource = """
    import os, signal, time
    signal.alarm(60)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(files.grandchildPID.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    while True:
        time.sleep(60)
    """
    let childSource = """
    import os, signal, subprocess, sys, time
    os.setsid()
    signal.alarm(60)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(files.childPID.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    subprocess.Popen([sys.executable, "-c", \(notebookPythonLiteral(grandchildSource))])
    while not (
        os.path.exists(\(notebookPythonLiteral(files.grandchildPID.path)))
        and os.path.getsize(\(notebookPythonLiteral(files.grandchildPID.path))) > 0
    ):
        time.sleep(0.005)
    open(\(notebookPythonLiteral(files.ready.path)), "w").close()
    while True:
        time.sleep(60)
    """
    return """
    import os, signal, subprocess, sys, time
    signal.alarm(60)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(files.parentPID.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    subprocess.Popen([sys.executable, "-c", \(notebookPythonLiteral(childSource))])
    while True:
        time.sleep(60)
    """
}

private func notebookPythonLiteral(_ value: String) -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .withoutEscapingSlashes]
    )
    return String(decoding: data, as: UTF8.self)
}

private func notebookShellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func notebookCreateLaunchServicesHelper(
    in workspace: URL,
    markerURL: URL
) throws -> URL {
    let appURL = workspace.appendingPathComponent("EscapeHelper.app", isDirectory: true)
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    let executableDirectory = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
    try FileManager.default.createDirectory(
        at: executableDirectory,
        withIntermediateDirectories: true
    )
    let executableURL = executableDirectory.appendingPathComponent("EscapeHelper")
    let script = """
    #!/bin/sh
    printf '%s\n' "$$" > \(notebookShellQuoted(markerURL.path))
    trap '' HUP TERM
    /bin/sleep 30
    """
    try Data(script.utf8).write(to: executableURL, options: .atomic)
    try #require(chmod(executableURL.path, S_IRWXU) == 0)
    let propertyList: [String: Any] = [
        "CFBundleExecutable": "EscapeHelper",
        "CFBundleIdentifier": "dev.cocxy.tests.escape-helper.\(UUID().uuidString.lowercased())",
        "CFBundleName": "EscapeHelper",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
    ]
    let propertyListData = try PropertyListSerialization.data(
        fromPropertyList: propertyList,
        format: .xml,
        options: 0
    )
    try propertyListData.write(
        to: contentsURL.appendingPathComponent("Info.plist"),
        options: .atomic
    )
    return appURL
}

private func notebookProcessTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-notebook-process-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func notebookBoundedArtifactDirectories() throws -> [String] {
    guard FileManager.default.fileExists(atPath: LaunchdProcessArtifacts.rootURL.path) else {
        return []
    }
    return try FileManager.default.contentsOfDirectory(
        atPath: LaunchdProcessArtifacts.rootURL.path
    ).filter {
        $0.hasPrefix("execution.")
            || $0.hasPrefix("staging.")
            || $0.hasPrefix("cleanup.")
    }
}

private func notebookSpawnSleepingProcess() throws -> pid_t {
    var attributes: posix_spawnattr_t?
    try BoundedPOSIX.check(
        posix_spawnattr_init(&attributes),
        operation: "initialize sleeping process attributes"
    )
    defer { posix_spawnattr_destroy(&attributes) }
    try BoundedPOSIX.check(
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)),
        operation: "protect sleeping process descriptors"
    )

    let executable = "/bin/sleep"
    let invocation = [executable, "30"]
    let environment = ["PATH=/usr/bin:/bin"]
    var child: pid_t = 0
    let code = try BoundedCStringArray.withMutablePointers(invocation) { argv in
        try BoundedCStringArray.withMutablePointers(environment) { envp in
            executable.withCString { path in
                posix_spawn(&child, path, nil, &attributes, argv, envp)
            }
        }
    }
    try BoundedPOSIX.check(code, operation: "spawn sleeping process")
    return child
}

private func notebookCurrentTestBundleURL() -> URL? {
    for argument in CommandLine.arguments {
        var candidate = URL(fileURLWithPath: argument).standardizedFileURL
        while candidate.path != "/" {
            if candidate.pathExtension == "xctest",
               FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
    }
    return nil
}

private func notebookWaitForFile(_ url: URL, timeoutSeconds: TimeInterval) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds
        + UInt64(timeoutSeconds * 1_000_000_000)
    while !FileManager.default.fileExists(atPath: url.path) {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw NotebookProcessTestError.timedOut(url.path)
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func notebookReadProcessIdentity(_ url: URL) throws -> NotebookTestProcessIdentity {
    let contents = try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let pid = pid_t(contents), pid > 0 else {
        throw NotebookProcessTestError.invalidProcessID(contents)
    }
    guard let identity = notebookCurrentProcessIdentity(pid) else {
        throw NotebookProcessTestError.processNotRunning(pid)
    }
    return identity
}

private func notebookCurrentProcessIdentity(_ pid: pid_t) -> NotebookTestProcessIdentity? {
    var info = proc_bsdinfo()
    let expectedSize = Int32(MemoryLayout.size(ofValue: info))
    let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
    guard result == expectedSize else { return nil }
    return NotebookTestProcessIdentity(
        pid: pid,
        startSeconds: UInt64(info.pbi_start_tvsec),
        startMicroseconds: UInt64(info.pbi_start_tvusec)
    )
}

private func notebookResourceCoalitionID(_ pid: pid_t) -> UInt64? {
    var info = NotebookTestCoalitionInfo()
    let expectedSize = Int32(MemoryLayout.size(ofValue: info))
    let result = proc_pidinfo(pid, 20, 0, &info, expectedSize)
    guard result == expectedSize, info.resourceID != 0 else { return nil }
    return info.resourceID
}

private func notebookExpectProcessGone(
    _ identity: NotebookTestProcessIdentity,
    timeoutSeconds: TimeInterval = 2
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds
        + UInt64(timeoutSeconds * 1_000_000_000)
    while notebookCurrentProcessIdentity(identity.pid) == identity {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Notebook descendant \(identity.pid) remained alive after teardown")
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func notebookBestEffortTerminate(_ identity: NotebookTestProcessIdentity) {
    guard notebookCurrentProcessIdentity(identity.pid) == identity else { return }
    _ = kill(identity.pid, SIGKILL)
}

private func notebookBestEffortRemoveLaunchdJob(label: String) {
    let control = LaunchdControlClient()
    for domain in LaunchdControlClient.domains {
        try? control.removeJob(domain: domain, label: label)
    }
}

@discardableResult
private func notebookReapChild(
    _ child: pid_t,
    timeoutSeconds: TimeInterval = 2
) -> Bool {
    let deadline = LaunchdMonotonicClock.adding(
        seconds: timeoutSeconds,
        to: LaunchdMonotonicClock.now()
    )
    var status: Int32 = 0
    while true {
        let result = waitpid(child, &status, WNOHANG)
        if result == child || (result == -1 && errno == ECHILD) { return true }
        if result == -1, errno != EINTR { return false }
        if LaunchdMonotonicClock.now() >= deadline { return false }
        usleep(10_000)
    }
}
