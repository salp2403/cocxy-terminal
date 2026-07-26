// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LaunchdProcessSupervisor.swift - Authenticated handoff into a launchd coalition.

import Darwin
import Foundation

struct LaunchdSupervisorRequest: Codable {
    private static let maximumArgumentCount = 4_096
    private static let maximumEnvironmentCount = 512
    private static let maximumTextBytes: Int = {
        let value = sysconf(_SC_ARG_MAX)
        return value > 0 ? Int(value) : 1 * 1_024 * 1_024
    }()

    let executablePath: String
    let arguments: [String]
    let workingDirectoryPath: String
    let environment: [String: String]
    let deadline: UInt64?
    let timeoutDiagnostic: String?

    func validate() throws {
        var isDirectory = ObjCBool(false)
        guard executablePath.hasPrefix("/"),
              workingDirectoryPath.hasPrefix("/"),
              !executablePath.utf8.contains(0),
              !workingDirectoryPath.utf8.contains(0),
              executablePath.utf8.count < Int(PATH_MAX),
              workingDirectoryPath.utf8.count < Int(PATH_MAX),
              FileManager.default.isExecutableFile(atPath: executablePath),
              FileManager.default.fileExists(
                  atPath: workingDirectoryPath,
                  isDirectory: &isDirectory
              ),
              isDirectory.boolValue,
              arguments.count <= Self.maximumArgumentCount,
              arguments.allSatisfy({ !$0.utf8.contains(0) }),
              environment.count <= Self.maximumEnvironmentCount,
              environment.allSatisfy({ key, value in
                  !key.isEmpty
                      && !key.contains("=")
                      && !key.utf8.contains(0)
                      && !value.utf8.contains(0)
              }),
              (timeoutDiagnostic?.utf8.count ?? 0) <= 16 * 1_024,
              timeoutDiagnostic?.utf8.contains(0) != true,
              textByteCount <= Self.maximumTextBytes else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
    }

    /// Kept as separately annotated sub-expressions: as a single chained sum the
    /// two `reduce` closures push the type checker past its budget on Swift 6.1
    /// toolchains, which fails the build instead of degrading.
    private var textByteCount: Int {
        let pathBytes: Int = executablePath.utf8.count + workingDirectoryPath.utf8.count
        let argumentBytes: Int = arguments.reduce(into: 0) { total, argument in
            total += argument.utf8.count + 1
        }
        let environmentBytes: Int = environment.reduce(into: 0) { total, entry in
            total += entry.key.utf8.count + entry.value.utf8.count + 2
        }
        let diagnosticBytes: Int = timeoutDiagnostic?.utf8.count ?? 0
        return pathBytes + argumentBytes + environmentBytes + diagnosticBytes
    }
}

struct LaunchdSupervisorCompletion: Codable, Equatable {
    let terminationStatus: Int32
    let cleanupVerified: Bool
    let timedOut: Bool

    func validate() throws {
        guard (0...255).contains(terminationStatus),
              cleanupVerified,
              !timedOut || terminationStatus == 124 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }
}

enum LaunchdSupervisorMessageKind: String, Codable, Equatable {
    case acknowledged
    case completed
}

struct LaunchdSupervisorMessage: Codable, Equatable {
    let kind: LaunchdSupervisorMessageKind
    let accepted: Bool?
    let completion: LaunchdSupervisorCompletion?
    /// The coalition the supervisor read for itself from the kernel.
    ///
    /// The broker derives the same value independently from `proc_pidinfo`, so
    /// echoing it here gives the handoff a second, release-independent witness:
    /// `launchctl print` publishes a coalition block only on some macOS
    /// releases, and this frame does not depend on it at all.
    let coalitionID: UInt64?

    static func acknowledged(coalitionID: UInt64) -> Self {
        LaunchdSupervisorMessage(
            kind: .acknowledged,
            accepted: true,
            completion: nil,
            coalitionID: coalitionID
        )
    }

    static func completed(_ completion: LaunchdSupervisorCompletion) -> Self {
        LaunchdSupervisorMessage(
            kind: .completed,
            accepted: nil,
            completion: completion,
            coalitionID: nil
        )
    }

    func validate() throws {
        switch kind {
        case .acknowledged:
            guard accepted == true, completion == nil, coalitionID != nil else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        case .completed:
            guard accepted == nil, coalitionID == nil, let completion else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            try completion.validate()
        }
    }
}

enum LaunchdProcessSupervisorEntry {
    static let modeArgument = "--cocxy-bounded-process-supervisor"
    private static let handshakeWaitSeconds: TimeInterval = 8
    private static let childReapWaitSeconds: TimeInterval = 1

    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.count >= 2, arguments[1] == modeArgument else { return nil }
        guard arguments.count == 6,
              let expectedBrokerPID = pid_t(arguments[3]),
              expectedBrokerPID > 1,
              let startSeconds = UInt64(arguments[4]),
              let startMicroseconds = UInt64(arguments[5]) else {
            return 64
        }

        var outputDescriptors: [LaunchdOwnedFileDescriptor] = []
        var diagnosticDescriptor = STDERR_FILENO
        let socketURL = URL(fileURLWithPath: arguments[2])
        let expectedBrokerIdentity = LaunchdProcessIdentity(
            pid: expectedBrokerPID,
            startSeconds: startSeconds,
            startMicroseconds: startMicroseconds
        )
        defer { outputDescriptors.forEach { $0.close() } }
        do {
            let connection = try connect(
                socketURL: socketURL,
                expectedBrokerIdentity: expectedBrokerIdentity
            )
            defer { connection.close() }
            let deadline = LaunchdMonotonicClock.adding(
                seconds: handshakeWaitSeconds,
                to: LaunchdMonotonicClock.now()
            )
            outputDescriptors = try connection.receiveFileDescriptors(
                count: 3,
                deadline: { deadline },
                pollHook: {}
            )
            diagnosticDescriptor = outputDescriptors[1].rawValue
            let request: LaunchdSupervisorRequest = try connection.readFrame(
                deadline: { deadline },
                pollHook: {}
            )
            try request.validate()
            let completion = try runSupervised(
                request,
                connection: connection,
                acknowledgementDeadline: deadline,
                stdoutDescriptor: outputDescriptors[0].rawValue,
                stderrDescriptor: outputDescriptors[1].rawValue,
                ownerLivenessDescriptor: outputDescriptors[2].rawValue
            )
            try completion.validate()
            let completionDeadline = LaunchdMonotonicClock.adding(
                seconds: 1,
                to: LaunchdMonotonicClock.now()
            )
            try? connection.writeFrame(
                LaunchdSupervisorMessage.completed(completion),
                deadline: { completionDeadline },
                pollHook: {}
            )
            return EXIT_SUCCESS
        } catch {
            var detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                ?? error.localizedDescription
            do {
                if try LaunchdProcessArtifacts
                    .recoverSupervisorCoalitionAfterConnectionFailure(
                        controlSocketURL: socketURL,
                        expectedBrokerIdentity: expectedBrokerIdentity
                    ) {
                    return EXIT_SUCCESS
                }
            } catch {
                let recoveryDetail = (error as? BoundedProcessRunnerError)?
                    .diagnosticDescription ?? error.localizedDescription
                detail += "; orphan recovery failed: \(recoveryDetail)"
            }
            writeDiagnostic(
                "Secure supervisor startup failed: \(detail)",
                descriptor: diagnosticDescriptor
            )
            return EXIT_FAILURE
        }
    }

    private static func connect(
        socketURL: URL,
        expectedBrokerIdentity: LaunchdProcessIdentity
    ) throws -> LaunchdBrokerConnection {
        guard LaunchdProcessArtifacts.contains(controlSocketURL: socketURL) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let rawDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard rawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "create supervisor channel",
                code: errno
            )
        }
        let descriptor = LaunchdOwnedFileDescriptor(rawDescriptor)
        do {
            try descriptor.relocateAboveStandardDescriptors()
            let flags = fcntl(descriptor.rawValue, F_GETFL)
            guard flags >= 0,
                  fcntl(descriptor.rawValue, F_SETFL, flags | O_NONBLOCK) == 0,
                  fcntl(descriptor.rawValue, F_SETFD, FD_CLOEXEC) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "configure supervisor channel",
                    code: errno
                )
            }
            let deadline = LaunchdMonotonicClock.adding(
                seconds: handshakeWaitSeconds,
                to: LaunchdMonotonicClock.now()
            )
            try connect(
                descriptor: descriptor.rawValue,
                path: socketURL.path,
                deadline: deadline
            )
            try LaunchdPeerAuthenticator.verify(
                descriptor: descriptor.rawValue,
                expectedIdentity: expectedBrokerIdentity
            )
            let connection = try LaunchdBrokerConnection(descriptor: descriptor.rawValue)
            descriptor.releaseOwnership()
            return connection
        } catch {
            descriptor.close()
            throw error
        }
    }

    private static func connect(
        descriptor: Int32,
        path: String,
        deadline: UInt64
    ) throws {
        var address = try socketAddress(path: path)
        while true {
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(
                        descriptor,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            if result == 0 { return }
            let code = errno
            if code == EINTR {
                try checkDeadline(deadline)
                continue
            }
            guard code == EINPROGRESS || code == EALREADY || code == EAGAIN else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "connect supervisor channel",
                    code: code
                )
            }
            try waitForConnection(descriptor: descriptor, deadline: deadline)
            return
        }
    }

    private static func waitForConnection(descriptor: Int32, deadline: UInt64) throws {
        while true {
            try checkDeadline(deadline)
            var state = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
            let result = Darwin.poll(&state, 1, 20)
            if result > 0 {
                guard state.revents & Int16(POLLNVAL) == 0 else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                var socketError: Int32 = 0
                var length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_ERROR,
                    &socketError,
                    &length
                ) == 0,
                socketError == 0 else {
                    throw BoundedProcessRunnerError.systemCallFailed(
                        operation: "complete supervisor connection",
                        code: socketError == 0 ? errno : socketError
                    )
                }
                return
            }
            if result == -1, errno != EINTR {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "poll supervisor channel",
                    code: errno
                )
            }
        }
    }

    private static func runSupervised(
        _ request: LaunchdSupervisorRequest,
        connection: LaunchdBrokerConnection,
        acknowledgementDeadline: UInt64,
        stdoutDescriptor: Int32,
        stderrDescriptor: Int32,
        ownerLivenessDescriptor: Int32
    ) throws -> LaunchdSupervisorCompletion {
        guard let coalitionID = LaunchdProcessCoalition.resourceID(for: getpid()) else {
            throw BoundedProcessRunnerError.secureContainmentUnavailable
        }
        if let deadline = request.deadline,
           LaunchdMonotonicClock.now() >= deadline {
            try terminateRemainingCoalition(coalitionID: coalitionID)
            return completion(terminationStatus: 124, timedOut: true)
        }
        if try connection.peerHasClosed()
            || (try peerHasClosed(descriptor: ownerLivenessDescriptor)) {
            try terminateRemainingCoalition(coalitionID: coalitionID)
            return completion(terminationStatus: 70, timedOut: false)
        }
        let child = try spawn(
            request,
            expectedCoalitionID: coalitionID,
            stdoutDescriptor: stdoutDescriptor,
            stderrDescriptor: stderrDescriptor
        )
        var childWasReaped = false
        defer {
            if !childWasReaped {
                _ = Darwin.kill(child.identity.pid, SIGKILL)
                try? reap(
                    child.identity.pid,
                    timeoutSeconds: childReapWaitSeconds
                )
            }
        }
        func cleanupAndReap() throws {
            try terminateRemainingCoalition(coalitionID: coalitionID)
            if !childWasReaped {
                try reap(
                    child.identity.pid,
                    timeoutSeconds: childReapWaitSeconds
                )
                childWasReaped = true
            }
        }

        do {
            try connection.writeFrame(
                LaunchdSupervisorMessage.acknowledged(coalitionID: coalitionID),
                deadline: { acknowledgementDeadline },
                pollHook: {}
            )
            guard LaunchdProcessSnapshot.current(for: child.identity.pid)?.identity
                    == child.identity,
                  LaunchdProcessCoalition.resourceID(for: child.identity.pid)
                    == coalitionID else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            if let deadline = request.deadline,
               LaunchdMonotonicClock.now() >= deadline {
                try cleanupAndReap()
                return completion(terminationStatus: 124, timedOut: true)
            }
            if try connection.peerHasClosed()
                || (try peerHasClosed(descriptor: ownerLivenessDescriptor)) {
                try cleanupAndReap()
                return completion(terminationStatus: 70, timedOut: false)
            }
            guard Darwin.kill(child.identity.pid, SIGCONT) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "resume contained command",
                    code: errno
                )
            }

            while true {
                var status: Int32 = 0
                let waitResult = waitpid(child.identity.pid, &status, WNOHANG)
                if waitResult == child.identity.pid {
                    childWasReaped = true
                    try cleanupAndReap()
                    return completion(
                        terminationStatus: terminationStatus(from: status),
                        timedOut: false
                    )
                }
                if waitResult == -1, errno != EINTR {
                    throw BoundedProcessRunnerError.systemCallFailed(
                        operation: "wait for contained command",
                        code: errno
                    )
                }
                if try connection.peerHasClosed()
                    || (try peerHasClosed(descriptor: ownerLivenessDescriptor)) {
                    try cleanupAndReap()
                    return completion(terminationStatus: 70, timedOut: false)
                }
                if let deadline = request.deadline,
                   LaunchdMonotonicClock.now() >= deadline {
                    try cleanupAndReap()
                    return completion(terminationStatus: 124, timedOut: true)
                }
                usleep(20_000)
            }
        } catch let originalError {
            do {
                try cleanupAndReap()
            } catch {
                let originalDetail = (originalError as? BoundedProcessRunnerError)?
                    .diagnosticDescription ?? originalError.localizedDescription
                let cleanupDetail = (error as? BoundedProcessRunnerError)?
                    .diagnosticDescription ?? error.localizedDescription
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "supervisor cleanup failed after \(originalDetail): \(cleanupDetail)"
                )
            }
            throw originalError
        }
    }

    private static func completion(
        terminationStatus: Int32,
        timedOut: Bool
    ) -> LaunchdSupervisorCompletion {
        LaunchdSupervisorCompletion(
            terminationStatus: terminationStatus,
            cleanupVerified: true,
            timedOut: timedOut
        )
    }

    private static func spawn(
        _ request: LaunchdSupervisorRequest,
        expectedCoalitionID: UInt64,
        stdoutDescriptor: Int32,
        stderrDescriptor: Int32
    ) throws -> LaunchdProcessSnapshot {
        var fileActions: posix_spawn_file_actions_t?
        try BoundedPOSIX.check(
            posix_spawn_file_actions_init(&fileActions),
            operation: "posix_spawn_file_actions_init supervisor"
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
            operation: "open contained stdin"
        )
        for (source, destination) in [
            (stdoutDescriptor, STDOUT_FILENO),
            (stderrDescriptor, STDERR_FILENO),
        ] {
            try BoundedPOSIX.check(
                posix_spawn_file_actions_adddup2(&fileActions, source, destination),
                operation: "redirect contained output"
            )
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addclose(&fileActions, source),
                operation: "close contained output source"
            )
        }
        try request.workingDirectoryPath.withCString { path in
            try BoundedPOSIX.check(
                posix_spawn_file_actions_addchdir_np(&fileActions, path),
                operation: "change contained working directory"
            )
        }

        var attributes: posix_spawnattr_t?
        try BoundedPOSIX.check(
            posix_spawnattr_init(&attributes),
            operation: "posix_spawnattr_init supervisor"
        )
        defer { posix_spawnattr_destroy(&attributes) }
        var emptySignalMask = sigset_t()
        sigemptyset(&emptySignalMask)
        try BoundedPOSIX.check(
            posix_spawnattr_setsigmask(&attributes, &emptySignalMask),
            operation: "set contained signal mask"
        )
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        try BoundedPOSIX.check(
            posix_spawnattr_setsigdefault(&attributes, &defaultSignals),
            operation: "set contained signal defaults"
        )
        let flags = POSIX_SPAWN_CLOEXEC_DEFAULT
            | POSIX_SPAWN_SETSID
            | POSIX_SPAWN_START_SUSPENDED
            | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK
        try BoundedPOSIX.check(
            posix_spawnattr_setflags(&attributes, Int16(flags)),
            operation: "set contained spawn flags"
        )

        var pid: pid_t = 0
        let invocation = [request.executablePath] + request.arguments
        let environment = LaunchdProcessEnvironment.sanitized(request.environment)
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        let code = try BoundedCStringArray.withMutablePointers(invocation) { argv in
            try BoundedCStringArray.withMutablePointers(environment) { envp in
                request.executablePath.withCString { path in
                    posix_spawn(&pid, path, &fileActions, &attributes, argv, envp)
                }
            }
        }
        try BoundedPOSIX.check(code, operation: "spawn contained command")
        guard let snapshot = LaunchdProcessSnapshot.current(for: pid),
              snapshot.userID == geteuid(),
              snapshot.isLive,
              LaunchdProcessCoalition.resourceID(for: pid) == expectedCoalitionID,
              getpgid(pid) == pid,
              getsid(pid) == pid else {
            _ = Darwin.kill(pid, SIGKILL)
            try reap(pid, timeoutSeconds: childReapWaitSeconds)
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        return snapshot
    }

    private static func terminateRemainingCoalition(coalitionID: UInt64) throws {
        try LaunchdProcessCoalition.terminateMembers(
            id: coalitionID,
            excluding: getpid(),
            gracePeriodSeconds: 0.2,
            killWaitSeconds: 1
        )
        try LaunchdProcessCoalition.verifyEmpty(
            id: coalitionID,
            excluding: getpid(),
            waitSeconds: 1
        )
    }

    private static func reap(_ pid: pid_t, timeoutSeconds: TimeInterval) throws {
        let deadline = LaunchdMonotonicClock.adding(
            seconds: timeoutSeconds,
            to: LaunchdMonotonicClock.now()
        )
        var status: Int32 = 0
        while LaunchdMonotonicClock.now() < deadline {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) { return }
            if result == -1, errno == EINTR { continue }
            if result == -1 {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "reap contained command",
                    code: errno
                )
            }
            usleep(10_000)
        }
        let finalResult = waitpid(pid, &status, WNOHANG)
        if finalResult == pid || (finalResult == -1 && errno == ECHILD) { return }
        if finalResult == -1, errno != EINTR {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "reap contained command",
                code: errno
            )
        }
        throw BoundedProcessRunnerError.secureCleanupUnverified(
            "contained command \(pid) could not be reaped before the cleanup deadline"
        )
    }

    private static func terminationStatus(from waitStatus: Int32) -> Int32 {
        let signal = waitStatus & 0x7f
        if signal == 0 { return (waitStatus >> 8) & 0xff }
        if signal != 0x7f { return signal }
        return 1
    }

    private static func peerHasClosed(descriptor: Int32) throws -> Bool {
        guard descriptor >= 0 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        var byte: UInt8 = 0
        let count = Darwin.recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if count == 0 { return true }
        if count > 0 { return false }
        if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { return false }
        throw BoundedProcessRunnerError.systemCallFailed(
            operation: "inspect application liveness channel",
            code: errno
        )
    }

    private static func writeDiagnostic(_ diagnostic: String?, descriptor: Int32) {
        guard let diagnostic, descriptor >= 0 else { return }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0,
              fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            return
        }
        let data = Data("\(diagnostic)\n".utf8)
        data.withUnsafeBytes { bytes in
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
                } else if count == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                    return
                } else {
                    return
                }
            }
        }
    }

    private static func socketAddress(path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
                    _ = memset(destination, 0, capacity)
                    _ = memcpy(destination, source, bytes.count)
                }
            }
        }
        return address
    }

    private static func checkDeadline(_ deadline: UInt64) throws {
        if LaunchdMonotonicClock.now() >= deadline {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }
}
