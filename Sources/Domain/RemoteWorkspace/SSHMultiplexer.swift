// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHMultiplexer.swift - Manages OpenSSH ControlMaster sessions.

import Darwin
import CryptoKit
import Foundation

// MARK: - SSH Destination

enum SSHDestinationValidationError: Error, Equatable, Sendable {
    case invalidDestination
}

/// A validated OpenSSH destination that remains data at every process boundary.
///
/// Host aliases intentionally allow underscores and plus signs because OpenSSH
/// config names are not limited to DNS hostname grammar. IPv4 and IPv6 literals
/// receive stricter validation to reject ambiguous address-like values.
struct SSHConnectionDestination: Equatable, Sendable {
    private static let maximumByteCount = 1_024
    private static let nameCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "._+-")
    )
    private static let zoneCharacters = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "._-")
    )

    let user: String?
    let host: String

    var value: String {
        user.map { "\($0)@\(host)" } ?? host
    }

    /// SFTP uses colons to separate a destination path, so IPv6 literals
    /// must remain bracketed at that process boundary.
    var sftpValue: String {
        let formattedHost = host.contains(":") ? "[\(host)]" : host
        return user.map { "\($0)@\(formattedHost)" } ?? formattedHost
    }

    init(_ rawValue: String) throws {
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= Self.maximumByteCount,
              rawValue.unicodeScalars.allSatisfy({ scalar in
                  !CharacterSet.whitespacesAndNewlines.contains(scalar)
                      && !CharacterSet.controlCharacters.contains(scalar)
              }) else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let components = rawValue.split(separator: "@", omittingEmptySubsequences: false)
        guard components.count == 1 || components.count == 2 else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let parsedUser = components.count == 2 ? String(components[0]) : nil
        let rawHost = String(components[components.count - 1])
        if let parsedUser {
            try Self.validateUser(parsedUser)
        }

        user = parsedUser
        host = try Self.validateAndNormalizeHost(rawHost)
    }

    init(user: String?, host: String) throws {
        try self.init(user.map { "\($0)@\(host)" } ?? host)
    }

    private static func validateUser(_ user: String) throws {
        guard !user.isEmpty,
              user.first != "-",
              user.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }) else {
            throw SSHDestinationValidationError.invalidDestination
        }
    }

    private static func validateAndNormalizeHost(_ rawHost: String) throws -> String {
        guard !rawHost.isEmpty, rawHost.first != "-" else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let host: String
        if rawHost.first == "[" || rawHost.last == "]" {
            guard rawHost.first == "[", rawHost.last == "]", rawHost.count > 2 else {
                throw SSHDestinationValidationError.invalidDestination
            }
            host = String(rawHost.dropFirst().dropLast())
        } else {
            host = rawHost
        }

        guard !host.isEmpty, host.first != "-" else {
            throw SSHDestinationValidationError.invalidDestination
        }

        if host.contains(":") {
            guard isValidIPv6Literal(host) else {
                throw SSHDestinationValidationError.invalidDestination
            }
            return host
        }

        guard !host.contains("[") && !host.contains("]"),
              host != ".",
              host != "..",
              host.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }) else {
            throw SSHDestinationValidationError.invalidDestination
        }

        let numericAddressCharacters = CharacterSet.decimalDigits.union(
            CharacterSet(charactersIn: ".")
        )
        if host.contains("."),
           host.unicodeScalars.allSatisfy({ numericAddressCharacters.contains($0) }),
           !isCanonicalIPv4Literal(host) {
            throw SSHDestinationValidationError.invalidDestination
        }

        return host
    }

    private static func isCanonicalIPv4Literal(_ value: String) -> Bool {
        var address = in_addr()
        guard value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return false
        }

        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else {
            return false
        }
        return String(cString: buffer) == value
    }

    private static func isValidIPv6Literal(_ value: String) -> Bool {
        let address: String
        if let zoneSeparator = value.lastIndex(of: "%") {
            let zone = value[value.index(after: zoneSeparator)...]
            guard !zone.isEmpty,
                  zone.first != "-",
                  zone.unicodeScalars.allSatisfy({ zoneCharacters.contains($0) }) else {
                return false
            }
            address = String(value[..<zoneSeparator])
        } else {
            address = value
        }

        var parsed = in6_addr()
        return address.withCString { inet_pton(AF_INET6, $0, &parsed) } == 1
    }
}

// MARK: - Process Executor Protocol

/// Abstraction over process execution for testability.
///
/// Production code uses `SystemProcessExecutor`; tests inject a mock
/// that records commands and returns stubbed results.
protocol ProcessExecutor: Sendable {
    func execute(command: String, arguments: [String]) throws -> ProcessResult
    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult
    func executeControl(
        command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult
    func executeControlAsync(
        command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> ProcessResult
    func start(command: String, arguments: [String]) throws -> any ManagedProcess
}

enum ProcessExecutorError: Error, Equatable {
    case managedProcessUnsupported
    case outputLimitExceeded
    case invalidTimeout
}

extension ProcessExecutor {
    func start(command: String, arguments: [String]) throws -> any ManagedProcess {
        _ = command
        _ = arguments
        throw ProcessExecutorError.managedProcessUnsupported
    }
}

protocol ManagedProcess: AnyObject, Sendable {
    var processIdentifier: Int32 { get }
    var isRunning: Bool { get }
    var diagnosticOutput: String { get }
    func closeStandardInput() throws
    func waitForExit(timeout: TimeInterval) -> Bool
    func terminate()
}

// MARK: - Process Result

enum SSHPostExecutionConnectionState: Sendable, Equatable {
    case verified
    case unavailable
}

/// The result of executing a system process.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
    let postExecutionConnectionState: SSHPostExecutionConnectionState

    init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        timedOut: Bool = false,
        postExecutionConnectionState: SSHPostExecutionConnectionState = .verified
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.postExecutionConnectionState = postExecutionConnectionState
    }
}

struct SSHControlMasterIdentity: Equatable, Sendable {
    let processID: Int32
    let controlPath: String
    let supervisorID: UUID?

    init(processID: Int32, controlPath: String, supervisorID: UUID? = nil) {
        self.processID = processID
        self.controlPath = controlPath
        self.supervisorID = supervisorID
    }
}

struct SSHControlSocketAttestation: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let peerProcessID: Int32
}

// MARK: - Multiplexer Errors

/// Errors that can occur during SSH multiplexing operations.
enum SSHMultiplexerError: Error, Equatable, LocalizedError {
    case invalidDestination
    case connectionFailed(String)
    case disconnectFailed(String)
    case forwardFailed(String)
    case forwardTimedOut(String)
    case forwardCleanupUnconfirmed(String)
    case remoteCommandTimedOut(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return "Invalid SSH destination"
        case .connectionFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH connection failed"
        case .disconnectFailed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH disconnect failed"
        case .forwardFailed(let message), .forwardTimedOut(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH port forward failed"
        case .forwardCleanupUnconfirmed(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "SSH port forward cleanup could not be confirmed"
        case .remoteCommandTimedOut(let message):
            return message.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Remote command timed out"
        case .notConnected:
            return "SSH ControlMaster is not connected"
        }
    }
}

// MARK: - SSH Multiplexing Protocol

/// Abstract interface for SSH multiplexing operations.
///
/// Enables dependency injection in orchestrators that depend on SSH
/// connection management.
protocol SSHMultiplexing: Sendable {
    func controlPath(for profile: RemoteConnectionProfile) -> String
    @discardableResult
    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity
    @discardableResult
    func connectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> SSHControlMasterIdentity
    func newSession(profile: RemoteConnectionProfile) throws -> String
    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool
    func isControlMasterProcessAlive(_ identity: SSHControlMasterIdentity) -> Bool
    func terminateControlMaster(_ identity: SSHControlMasterIdentity)
    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws
    func disconnectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws
    func disconnectAsync(
        profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws
    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws
    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws
    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws
    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws
    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws
    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws
    func openDirectTCPTransport(
        to target: ProxyTarget,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity
    ) throws -> any ProxyUpstreamTransport
    func attestControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity
    ) throws -> SSHControlSocketAttestation
    func verifyControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity,
        attestation: SSHControlSocketAttestation
    ) throws

    /// Executes a command on the remote host through the ControlMaster session.
    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult
    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult
}

extension SSHMultiplexing {
    @discardableResult
    func connectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> SSHControlMasterIdentity {
        try connect(profile: profile, executor: executor)
    }

    func disconnectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws {
        try disconnect(profile: profile, executor: executor)
    }

    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws {
        try forwardPort(forward, on: profile, executor: executor)
    }

    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws {
        try cancelForward(forward, on: profile, executor: executor)
    }

    func openDirectTCPTransport(
        to target: ProxyTarget,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity
    ) throws -> any ProxyUpstreamTransport {
        _ = target
        _ = profile
        _ = expectedControlMaster
        throw ProxyUpstreamTransportError.unavailable
    }

    func attestControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity
    ) throws -> SSHControlSocketAttestation {
        _ = expectedControlMaster
        throw SSHMultiplexerError.notConnected
    }

    func verifyControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity,
        attestation: SSHControlSocketAttestation
    ) throws {
        _ = expectedControlMaster
        _ = attestation
        throw SSHMultiplexerError.notConnected
    }
}

private final class AttestedProxyUpstreamTransport: ProxyUpstreamTransport, @unchecked Sendable {
    private let upstream: any ProxyUpstreamTransport
    private let verifyAttestation: @Sendable () throws -> Void

    var processIdentifier: Int32 { upstream.processIdentifier }
    var isRunning: Bool { upstream.isRunning }
    var diagnosticOutput: String { upstream.diagnosticOutput }

    init(
        upstream: any ProxyUpstreamTransport,
        verifyAttestation: @escaping @Sendable () throws -> Void
    ) {
        self.upstream = upstream
        self.verifyAttestation = verifyAttestation
    }

    func waitUntilReady() async throws {
        do {
            try await upstream.waitUntilReady()
            guard upstream.isRunning else { throw ProxyUpstreamTransportError.closed }
            try verifyAttestation()
        } catch {
            upstream.cancel()
            throw error
        }
    }

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        upstream.send(data, completion: completion)
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        upstream.receive(maximumLength: maximumLength, completion: completion)
    }

    func closeWrite() {
        upstream.closeWrite()
    }

    func cancel() {
        upstream.cancel()
    }
}

// MARK: - SSH Multiplexer

/// Manages OpenSSH ControlMaster sessions for connection reuse.
///
/// ControlMaster allows multiple SSH sessions to share a single TCP
/// connection, reducing latency for new sessions and enabling approved
/// local and remote forwarding through `ssh -O forward`.
///
/// ## Socket Layout
///
/// ```
/// ~/.config/cocxy/sockets/
/// └── <process-session>/
///     └── <profile-uuid>.sock
/// ```
final class SSHMultiplexer: SSHMultiplexing, @unchecked Sendable {

    static let defaultControlCommandTimeoutSeconds: TimeInterval = 5

    typealias DirectTCPTransportFactory = @Sendable (
        _ controlPath: String,
        _ target: ProxyTarget,
        _ expectedAttestation: SSHControlSocketAttestation
    ) throws -> any ProxyUpstreamTransport

    typealias ControlSocketAttestationProvider = @Sendable (
        _ controlPath: String
    ) throws -> SSHControlSocketAttestation

    private final class LifecycleLockRegistry: @unchecked Sendable {
        private let registryLock = NSLock()
        private var locks: [String: NSLock] = [:]

        func lock(for controlPath: String) -> NSLock {
            registryLock.lock()
            defer { registryLock.unlock() }
            if let existing = locks[controlPath] { return existing }
            let created = NSLock()
            locks[controlPath] = created
            return created
        }
    }

    private struct ControlSocketFileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private struct SupervisedProcessEntry {
        let operationID: UUID
        let process: any ManagedProcess
        var childProcessID: Int32?
        var controlSocketAttestation: SSHControlSocketAttestation?
        var terminationRequested = false
    }

    private enum ControlSocketProbe {
        case active(processID: Int32)
        case stale
        case indeterminate
    }

    private enum StaleSocketPolicy: Equatable {
        case retain
        case removeOnlyWhenSupervised
    }

    static let supervisorScript = """
    ssh_path="$1"
    shift
    exec 3<&0
    ssh_pid=""
    watcher_pid=""
    cleanup() {
        trap - EXIT HUP INT TERM PIPE
        /usr/bin/pkill -TERM -P "$$" -x ssh 2>/dev/null || true
        /usr/bin/pkill -TERM -P "$$" -x sh 2>/dev/null || true
        [ -n "$ssh_pid" ] && wait "$ssh_pid" 2>/dev/null || true
        [ -n "$watcher_pid" ] && wait "$watcher_pid" 2>/dev/null || true
        exec 3<&-
    }
    trap cleanup EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 141' PIPE
    "$ssh_path" "$@" </dev/null &
    ssh_pid=$!
    printf 'COCXY_SSH_CHILD_PID=%s\n' "$ssh_pid" >&2
    /bin/sh -c '
        parent_pid="$1"
        while IFS= read -r _; do :; done
        set -- $(/bin/ps -o ppid= -p "$$")
        [ "${1:-}" = "$parent_pid" ] && kill -TERM "$parent_pid" 2>/dev/null || true
    ' cocxy-ssh-stdin-watch "$$" <&3 &
    watcher_pid=$!
    wait "$ssh_pid"
    """

    private static let lifecycleLocks = LifecycleLockRegistry()
    private let processLock = NSLock()
    private var supervisedProcesses: [String: SupervisedProcessEntry] = [:]
    private let directTCPTransportFactory: DirectTCPTransportFactory
    private let controlSocketAttestationProvider: ControlSocketAttestationProvider?
    private let controlCommandTimeoutSeconds: TimeInterval

    init(
        directTCPTransportFactory: @escaping DirectTCPTransportFactory = {
            controlPath, target, expectedAttestation in
            try SSHDirectTCPTransport(
                controlPath: controlPath,
                target: target,
                expectedAttestation: expectedAttestation
            )
        },
        controlSocketAttestationProvider: ControlSocketAttestationProvider? = nil,
        controlCommandTimeoutSeconds: TimeInterval = SSHMultiplexer.defaultControlCommandTimeoutSeconds
    ) {
        self.directTCPTransportFactory = directTCPTransportFactory
        self.controlSocketAttestationProvider = controlSocketAttestationProvider
        self.controlCommandTimeoutSeconds = controlCommandTimeoutSeconds
    }

    deinit {
        processLock.lock()
        let processes = supervisedProcesses.values.map(\.process)
        processLock.unlock()
        for process in processes {
            try? process.closeStandardInput()
        }
        for process in processes where !process.waitForExit(timeout: 0.5) {
            process.terminate()
            _ = process.waitForExit(timeout: 0.5)
        }
    }

    // MARK: - Control Path

    /// Returns the ControlMaster socket path for the given profile.
    func controlPath(for profile: RemoteConnectionProfile) -> String {
        profile.controlPath
    }

    // MARK: - Connect

    /// Starts a ControlMaster session for the given profile.
    ///
    /// Runs a foreground `ssh -N` master under a pipe-bound local supervisor.
    /// Closing Cocxy's side of that pipe terminates the master, including after
    /// abrupt app termination, so reverse forwards cannot outlive their brokers.
    ///
    /// - Parameters:
    ///   - profile: The connection profile to use.
    ///   - executor: The process executor for running SSH.
    /// - Throws: `SSHMultiplexerError.invalidDestination` for malformed destinations,
    ///   or `SSHMultiplexerError.connectionFailed` if SSH exits with a non-zero code.
    @discardableResult
    func connect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity {
        try Task.checkCancellation()
        let destination = try destination(for: profile)
        try ensureControlPathDirectory(for: profile)

        let currentPath = controlPath(for: profile)
        let legacyPath = profile.legacyControlPath
        if legacyPath != currentPath {
            try withLifecycleLock(controlPath: legacyPath, executor: executor) {
                try retireExistingControlMaster(
                    profile: profile,
                    controlPath: legacyPath,
                    staleSocketPolicy: .retain,
                    requiresSupervisorOwnership: false,
                    executor: executor
                )
            }
        }
        return try withLifecycleLock(controlPath: currentPath, executor: executor) {
            try startControlMaster(
                profile: profile,
                destination: destination,
                currentPath: currentPath,
                executor: executor
            )
        }
    }

    @discardableResult
    func connectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> SSHControlMasterIdentity {
        let operation = Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            return try connect(profile: profile, executor: executor)
        }
        return try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private func startControlMaster(
        profile: RemoteConnectionProfile,
        destination: SSHConnectionDestination,
        currentPath: String,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity {
        if try controlSocketFileIdentity(at: currentPath) == nil {
            try retireRegisteredSupervisorWithoutSocket(controlPath: currentPath)
        }
        try retireExistingControlMaster(
            profile: profile,
            controlPath: currentPath,
            staleSocketPolicy: .removeOnlyWhenSupervised,
            requiresSupervisorOwnership: true,
            executor: executor
        )

        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: ["-o", "ControlMaster=yes"])
        arguments.append(contentsOf: ["-o", "ControlPersist=no"])
        arguments.append(contentsOf: ["-o", "ControlPath=\(currentPath)"])
        arguments.append("-N")
        arguments.append(contentsOf: ["--", destination.value])

        let process = try executor.start(
            command: "/bin/sh",
            arguments: [
                "-c",
                Self.supervisorScript,
                "cocxy-ssh-supervisor",
                "/usr/bin/ssh",
            ] + arguments
        )
        let operationID = UUID()
        do {
            try registerSupervisedProcess(
                process,
                operationID: operationID,
                controlPath: currentPath
            )
        } catch {
            try? process.closeStandardInput()
            if !process.waitForExit(timeout: 0.5) {
                process.terminate()
                _ = process.waitForExit(timeout: 0.5)
            }
            throw error
        }
        var verified = false
        defer {
            if !verified {
                finishFailedSupervisedProcess(
                    controlPath: currentPath,
                    operationID: operationID
                )
            }
        }

        for _ in 0..<50 {
            try Task.checkCancellation()
            let childProcessID = Self.supervisedChildProcessID(
                from: process.diagnosticOutput
            )
            if let childProcessID,
               let identity = try controlMasterIdentity(
                profile: profile,
                controlPath: currentPath,
                executor: executor
               ), identity.processID == childProcessID {
                guard bindSupervisedProcess(
                    operationID: operationID,
                    childProcessID: childProcessID,
                    controlPath: currentPath
                ) else {
                    throw SSHMultiplexerError.connectionFailed(
                        "SSH ControlMaster supervisor ownership changed during startup"
                    )
                }
                verified = true
                return SSHControlMasterIdentity(
                    processID: identity.processID,
                    controlPath: identity.controlPath,
                    supervisorID: operationID
                )
            }
            if !process.isRunning { break }
            usleep(100_000)
        }

        let diagnostic = process.diagnosticOutput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw SSHMultiplexerError.connectionFailed(
            diagnostic.isEmpty ? "SSH ControlMaster identity could not be verified" : diagnostic
        )
    }

    // MARK: - New Session

    /// Returns an SSH command string that reuses the existing ControlMaster.
    ///
    /// The returned command uses `ControlMaster=no` to attach to (not replace)
    /// the existing master session.
    ///
    /// - Throws: `SSHMultiplexerError.invalidDestination` for malformed destinations.
    func newSession(profile: RemoteConnectionProfile) throws -> String {
        let destination = try destination(for: profile)
        var parts: [String] = ["ssh"]
        parts.append("-o ControlMaster=no")
        parts.append("-o ControlPath=\(controlPath(for: profile))")

        if let port = profile.port {
            parts.append("-p \(port)")
        }

        parts.append("--")
        parts.append(destination.value)
        return parts.joined(separator: " ")
    }

    // MARK: - Health Check

    /// Checks whether the ControlMaster session is still alive.
    ///
    /// Runs `ssh -O check` against the control socket.
    ///
    /// - Returns: `true` if the master process is running.
    func isAlive(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> Bool {
        let destination = try destination(for: profile)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", "check",
            "-o", "ControlPath=\(controlPath(for: profile))",
            "--", destination.value,
        ])

        let result = try await executor.executeControlAsync(
            command: "/usr/bin/ssh",
            arguments: arguments,
            timeoutSeconds: controlCommandTimeoutSeconds
        )
        guard !result.timedOut else {
            throw SSHMultiplexerError.connectionFailed(
                "SSH ControlMaster health check timed out"
            )
        }
        return result.exitCode == 0
    }

    func isControlMasterProcessAlive(_ identity: SSHControlMasterIdentity) -> Bool {
        guard identity.processID > 0 else { return false }
        if let supervisorID = identity.supervisorID {
            processLock.lock()
            guard let entry = supervisedProcesses[identity.controlPath],
                  entry.operationID == supervisorID,
                  entry.childProcessID == identity.processID else {
                processLock.unlock()
                return false
            }
            let supervisorIsRunning = entry.process.isRunning
            if !supervisorIsRunning {
                supervisedProcesses.removeValue(forKey: identity.controlPath)
            }
            processLock.unlock()
            return supervisorIsRunning
        }
        if Darwin.kill(identity.processID, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Closes only the supervisor pipe owned by the exact verified master.
    /// The supervisor's EOF trap terminates the foreground SSH child without
    /// running another potentially blocking OpenSSH control command.
    func terminateControlMaster(_ identity: SSHControlMasterIdentity) {
        guard let supervisorID = identity.supervisorID else { return }
        requestSupervisedProcessTermination(
            controlPath: identity.controlPath,
            operationID: supervisorID,
            childProcessID: identity.processID
        )
    }

    // MARK: - Disconnect

    /// Terminates only the exact ControlMaster supervisor owned by this instance.
    func disconnect(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let currentPath = controlPath(for: profile)
        try withLifecycleLock(controlPath: currentPath, executor: executor) {
            guard let supervisedIdentity = supervisedControlMasterIdentity(
                controlPath: currentPath
            ) else {
                throw SSHMultiplexerError.notConnected
            }
            guard isControlMasterProcessAlive(supervisedIdentity) else {
                throw SSHMultiplexerError.notConnected
            }
            try terminateAndWaitForControlMaster(
                supervisedIdentity,
                failureMessage: "SSH ControlMaster did not terminate"
            )
        }
    }

    func disconnectAsync(
        profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws {
        let operation = Task.detached(priority: .userInitiated) { [self] in
            try disconnect(profile: profile, executor: executor)
        }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    func disconnectAsync(
        profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        guard expectedControlMaster.controlPath == controlPath(for: profile) else {
            throw SSHMultiplexerError.notConnected
        }
        let operation = Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            try disconnect(
                expectedControlMaster: expectedControlMaster,
                executor: executor
            )
        }
        try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: {
            operation.cancel()
        }
    }

    private func disconnect(
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) throws {
        try withLifecycleLock(
            controlPath: expectedControlMaster.controlPath,
            executor: executor
        ) {
            guard supervisedControlMasterIdentity(
                controlPath: expectedControlMaster.controlPath
            ) == expectedControlMaster,
            isControlMasterProcessAlive(expectedControlMaster) else {
                throw SSHMultiplexerError.notConnected
            }
            try terminateAndWaitForControlMaster(
                expectedControlMaster,
                failureMessage: "SSH ControlMaster did not terminate"
            )
        }
    }

    // MARK: - Port Forwarding

    /// Dynamically adds a port forward to an active ControlMaster session.
    ///
    /// Runs `ssh -O forward` for an approved local or remote forward.
    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let arguments = try forwardControlArguments(
            operation: "forward",
            forward: forward,
            profile: profile
        )
        let result = try executor.executeControl(
            command: "/usr/bin/ssh",
            arguments: arguments,
            timeoutSeconds: controlCommandTimeoutSeconds
        )
        try validateForwardControlResult(result, operation: "request")
    }

    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws {
        let arguments = try forwardControlArguments(
            operation: "forward",
            forward: forward,
            profile: profile
        )
        let result = try await executor.executeControlAsync(
            command: "/usr/bin/ssh",
            arguments: arguments,
            timeoutSeconds: controlCommandTimeoutSeconds
        )
        try validateForwardControlResult(result, operation: "request")
    }

    func forwardPortAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        try await performExactForwardControlAsync(
            operation: "forward",
            resultOperation: "request",
            forward: forward,
            profile: profile,
            expectedControlMaster: expectedControlMaster,
            executor: executor
        )
    }

    /// Cancels a port forward on an active ControlMaster session.
    ///
    /// Runs `ssh -O cancel` with the same forwarding spec that was used to add it.
    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {
        let arguments = try forwardControlArguments(
            operation: "cancel",
            forward: forward,
            profile: profile
        )
        let result = try executor.executeControl(
            command: "/usr/bin/ssh",
            arguments: arguments,
            timeoutSeconds: controlCommandTimeoutSeconds
        )
        try validateForwardControlResult(result, operation: "cancellation")
    }

    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws {
        let arguments = try forwardControlArguments(
            operation: "cancel",
            forward: forward,
            profile: profile
        )
        let result = try await executor.executeControlAsync(
            command: "/usr/bin/ssh",
            arguments: arguments,
            timeoutSeconds: controlCommandTimeoutSeconds
        )
        try validateForwardControlResult(result, operation: "cancellation")
    }

    func cancelForwardAsync(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        try await performExactForwardControlAsync(
            operation: "cancel",
            resultOperation: "cancellation",
            forward: forward,
            profile: profile,
            expectedControlMaster: expectedControlMaster,
            executor: executor
        )
    }

    private func performExactForwardControlAsync(
        operation: String,
        resultOperation: String,
        forward: RemoteConnectionProfile.PortForward,
        profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws {
        guard expectedControlMaster.controlPath == controlPath(for: profile) else {
            throw SSHMultiplexerError.notConnected
        }
        let task = Task.detached(priority: .userInitiated) { [self] in
            try Task.checkCancellation()
            try withLifecycleLock(
                controlPath: expectedControlMaster.controlPath,
                executor: executor
            ) {
                try Task.checkCancellation()
                let attestation = try attestControlMaster(expectedControlMaster)
                let arguments = try forwardControlArguments(
                    operation: operation,
                    forward: forward,
                    profile: profile
                )
                let result = try executor.executeControl(
                    command: "/usr/bin/ssh",
                    arguments: arguments,
                    timeoutSeconds: controlCommandTimeoutSeconds
                )
                try validateForwardControlResult(result, operation: resultOperation)
                try Task.checkCancellation()
                try verifyControlMaster(
                    expectedControlMaster,
                    attestation: attestation
                )
            }
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - Direct TCP Transport

    /// Opens one direct-tcpip channel through the exact supervised ControlMaster.
    ///
    /// The transport verifies `LOCAL_PEERPID` on the same MUX descriptor that
    /// receives the destination and stream descriptors, so path replacement
    /// cannot redirect the channel to another local process.
    func openDirectTCPTransport(
        to target: ProxyTarget,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity
    ) throws -> any ProxyUpstreamTransport {
        let currentPath = controlPath(for: profile)
        guard expectedControlMaster.controlPath == currentPath,
              expectedControlMaster.supervisorID != nil,
              supervisedControlMasterIdentity(controlPath: currentPath) == expectedControlMaster,
              isControlMasterProcessAlive(expectedControlMaster) else {
            throw SSHMultiplexerError.notConnected
        }

        let attestation = try directTCPControlSocketAttestation(at: currentPath)
        guard attestation.peerProcessID == expectedControlMaster.processID,
              bindOrVerifyControlSocketAttestation(
                attestation,
                expectedControlMaster: expectedControlMaster
              ) else {
            throw SSHMultiplexerError.notConnected
        }

        let transport = try directTCPTransportFactory(
            currentPath,
            target,
            attestation
        )
        do {
            try verifyDirectTCPControlSocket(
                expectedControlMaster: expectedControlMaster,
                expectedAttestation: attestation
            )
        } catch {
            transport.cancel()
            throw error
        }

        return AttestedProxyUpstreamTransport(
            upstream: transport,
            verifyAttestation: { [weak self] in
                guard let self else { throw SSHMultiplexerError.notConnected }
                try self.verifyDirectTCPControlSocket(
                    expectedControlMaster: expectedControlMaster,
                    expectedAttestation: attestation
                )
            }
        )
    }

    func attestControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity
    ) throws -> SSHControlSocketAttestation {
        guard supervisedControlMasterIdentity(
            controlPath: expectedControlMaster.controlPath
        ) == expectedControlMaster,
        isControlMasterProcessAlive(expectedControlMaster) else {
            throw SSHMultiplexerError.notConnected
        }
        let attestation = try directTCPControlSocketAttestation(
            at: expectedControlMaster.controlPath
        )
        guard attestation.peerProcessID == expectedControlMaster.processID,
              bindOrVerifyControlSocketAttestation(
                  attestation,
                  expectedControlMaster: expectedControlMaster
              ) else {
            throw SSHMultiplexerError.notConnected
        }
        return attestation
    }

    func verifyControlMaster(
        _ expectedControlMaster: SSHControlMasterIdentity,
        attestation: SSHControlSocketAttestation
    ) throws {
        try verifyDirectTCPControlSocket(
            expectedControlMaster: expectedControlMaster,
            expectedAttestation: attestation
        )
    }

    // MARK: - Remote Command Execution

    /// Executes a command on the remote host through the ControlMaster session.
    ///
    /// Reuses the existing multiplexed connection through Cocxy's helper. The
    /// helper validates `LOCAL_PEERPID` on the connected Unix descriptor before
    /// it sends the command or standard-stream descriptors to the master.
    ///
    /// - Parameters:
    ///   - command: The shell command to run on the remote host.
    ///   - profile: The connection profile whose ControlMaster to use.
    ///   - executor: The bounded process executor for running the MUX helper.
    /// - Returns: The result of the remote command execution.
    /// - Throws: `SSHMultiplexerError.invalidDestination` for malformed destinations,
    ///   or `SSHMultiplexerError.connectionFailed` if the command fails to execute.
    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        _ = try destination(for: profile)
        let path = controlPath(for: profile)
        guard let identity = supervisedControlMasterIdentity(controlPath: path) else {
            throw SSHMultiplexerError.notConnected
        }
        return try await executeRemoteCommand(
            command,
            on: profile,
            expectedControlMaster: identity,
            executor: executor
        )
    }

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        expectedControlMaster: SSHControlMasterIdentity,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        _ = try destination(for: profile)
        let path = controlPath(for: profile)
        guard expectedControlMaster.controlPath == path else {
            throw SSHMultiplexerError.notConnected
        }
        let attestation = try attestControlMaster(expectedControlMaster)
        let helperURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        guard helperURL.path.first == "/" else {
            throw SSHMultiplexerError.connectionFailed(
                "The verified SSH command helper is unavailable"
            )
        }
        let arguments: [String]
        do {
            arguments = try SFTPMuxSessionArgumentContract.arguments(
                controlPath: path,
                attestation: attestation,
                command: command
            )
        } catch {
            throw SSHMultiplexerError.connectionFailed(
                "The remote command exceeds the safe execution boundary"
            )
        }
        let result = try await executor.executeAsync(
            command: helperURL.path,
            arguments: arguments
        )
        let connectionState: SSHPostExecutionConnectionState
        do {
            try verifyControlMaster(expectedControlMaster, attestation: attestation)
            connectionState = result.postExecutionConnectionState
        } catch {
            connectionState = .unavailable
        }
        return ProcessResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            timedOut: result.timedOut,
            postExecutionConnectionState: connectionState
        )
    }

    // MARK: - Helpers

    private func controlMasterIdentity(
        profile: RemoteConnectionProfile,
        controlPath: String,
        executor: any ProcessExecutor
    ) throws -> SSHControlMasterIdentity? {
        let destination = try destination(for: profile)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", "check",
            "-o", "ControlPath=\(controlPath)",
            "--", destination.value,
        ])
        let result = try executor.executeControl(
            command: "/usr/bin/ssh",
            arguments: arguments,
            timeoutSeconds: controlCommandTimeoutSeconds
        )
        guard !result.timedOut else {
            throw SSHMultiplexerError.connectionFailed(
                "SSH ControlMaster check timed out"
            )
        }
        guard result.exitCode == 0 else { return nil }
        let output = result.stdout + "\n" + result.stderr
        guard let processID = Self.controlMasterProcessID(from: output) else {
            return nil
        }
        return SSHControlMasterIdentity(processID: processID, controlPath: controlPath)
    }

    private func forwardControlArguments(
        operation: String,
        forward: RemoteConnectionProfile.PortForward,
        profile: RemoteConnectionProfile
    ) throws -> [String] {
        let destination = try destination(for: profile)
        let forwardArgs = try forwardArguments(for: forward)
        var arguments = buildBaseArguments(for: profile)
        arguments.append(contentsOf: [
            "-O", operation,
            "-o", "ControlPath=\(controlPath(for: profile))",
        ] + forwardArgs + ["--", destination.value])
        return arguments
    }

    private func validateForwardControlResult(
        _ result: ProcessResult,
        operation: String
    ) throws {
        guard !result.timedOut else {
            throw SSHMultiplexerError.forwardTimedOut(
                "SSH port forward \(operation) timed out"
            )
        }
        guard result.exitCode == 0 else {
            throw SSHMultiplexerError.forwardFailed(result.stderr)
        }
    }

    private func retireExistingControlMaster(
        profile: RemoteConnectionProfile,
        controlPath: String,
        staleSocketPolicy: StaleSocketPolicy,
        requiresSupervisorOwnership: Bool,
        executor: any ProcessExecutor
    ) throws {
        guard let originalFileIdentity = try controlSocketFileIdentity(at: controlPath) else {
            return
        }

        let checkedIdentity = try controlMasterIdentity(
            profile: profile,
            controlPath: controlPath,
            executor: executor
        )
        let identity: SSHControlMasterIdentity
        if let checkedIdentity {
            identity = checkedIdentity
        } else {
            switch probeControlSocket(at: controlPath) {
            case .active(let processID):
                identity = SSHControlMasterIdentity(
                    processID: processID,
                    controlPath: controlPath
                )
            case .stale:
                guard staleSocketPolicy == .removeOnlyWhenSupervised else {
                    return
                }
                guard let supervisedProcessID = supervisedChildProcessID(
                    controlPath: controlPath
                ), !isControlMasterProcessAlive(
                    SSHControlMasterIdentity(
                        processID: supervisedProcessID,
                        controlPath: controlPath
                    )
                ) else {
                    throw SSHMultiplexerError.connectionFailed(
                        "Stale SSH control socket is not owned by this Cocxy process"
                    )
                }
                guard try controlSocketFileIdentity(at: controlPath) == originalFileIdentity else {
                    throw SSHMultiplexerError.connectionFailed(
                        "Existing SSH control socket changed during stale-file verification"
                    )
                }
                guard Darwin.unlink(controlPath) == 0 else {
                    throw SSHMultiplexerError.connectionFailed(
                        "Existing stale SSH control socket could not be removed"
                    )
                }
                return
            case .indeterminate:
                throw SSHMultiplexerError.connectionFailed(
                    "Existing SSH control socket ownership could not be verified"
                )
            }
        }

        guard requiresSupervisorOwnership else {
            throw SSHMultiplexerError.connectionFailed(
                "An existing legacy SSH ControlMaster is active and was left untouched"
            )
        }

        guard identity.processID > 0 else {
            throw SSHMultiplexerError.connectionFailed(
                "Existing SSH control socket identity is invalid"
            )
        }
        if requiresSupervisorOwnership {
            guard supervisedChildProcessID(controlPath: controlPath) == identity.processID else {
                throw SSHMultiplexerError.connectionFailed(
                    "Existing SSH control socket is not owned by this Cocxy process"
                )
            }
        }
        guard try controlSocketFileIdentity(at: controlPath) == originalFileIdentity else {
            throw SSHMultiplexerError.connectionFailed(
                "Existing SSH control socket changed during ownership verification"
            )
        }

        guard let supervisedIdentity = supervisedControlMasterIdentity(
            controlPath: controlPath,
            childProcessID: identity.processID
        ) else {
            throw SSHMultiplexerError.connectionFailed(
                "Existing SSH control socket is not owned by its registered supervisor"
            )
        }
        try terminateAndWaitForControlMaster(
            supervisedIdentity,
            failureMessage: "Existing SSH ControlMaster did not terminate"
        )
    }

    private func terminateAndWaitForControlMaster(
        _ identity: SSHControlMasterIdentity,
        failureMessage: String
    ) throws {
        terminateControlMaster(identity)
        for _ in 0..<20 {
            if !isControlMasterProcessAlive(identity) { return }
            usleep(50_000)
        }
        throw SSHMultiplexerError.disconnectFailed(failureMessage)
    }

    private func registerSupervisedProcess(
        _ process: any ManagedProcess,
        operationID: UUID,
        controlPath: String
    ) throws {
        processLock.lock()
        if let previous = supervisedProcesses[controlPath], previous.process.isRunning {
            processLock.unlock()
            throw SSHMultiplexerError.connectionFailed(
                "Previous SSH ControlMaster supervisor termination is not confirmed"
            )
        }
        supervisedProcesses.removeValue(forKey: controlPath)
        let entry = SupervisedProcessEntry(
            operationID: operationID,
            process: process,
            childProcessID: nil,
            controlSocketAttestation: nil
        )
        supervisedProcesses[controlPath] = entry
        processLock.unlock()
    }

    private func retireRegisteredSupervisorWithoutSocket(
        controlPath: String
    ) throws {
        guard let identity = supervisedControlMasterIdentity(controlPath: controlPath) else {
            return
        }
        terminateControlMaster(identity)
        for _ in 0..<20 {
            if !isControlMasterProcessAlive(identity) { return }
            usleep(50_000)
        }
        throw SSHMultiplexerError.disconnectFailed(
            "Previous SSH ControlMaster supervisor did not terminate"
        )
    }

    private func bindSupervisedProcess(
        operationID: UUID,
        childProcessID: Int32,
        controlPath: String
    ) -> Bool {
        processLock.lock()
        defer { processLock.unlock() }
        guard var entry = supervisedProcesses[controlPath],
              entry.operationID == operationID else { return false }
        entry.childProcessID = childProcessID
        supervisedProcesses[controlPath] = entry
        return true
    }

    private func bindOrVerifyControlSocketAttestation(
        _ attestation: SSHControlSocketAttestation,
        expectedControlMaster: SSHControlMasterIdentity
    ) -> Bool {
        guard let supervisorID = expectedControlMaster.supervisorID else { return false }
        processLock.lock()
        defer { processLock.unlock() }
        guard var entry = supervisedProcesses[expectedControlMaster.controlPath],
              entry.operationID == supervisorID,
              entry.childProcessID == expectedControlMaster.processID else {
            return false
        }
        if let existing = entry.controlSocketAttestation {
            return existing == attestation
        }
        entry.controlSocketAttestation = attestation
        supervisedProcesses[expectedControlMaster.controlPath] = entry
        return true
    }

    private func supervisedChildProcessID(controlPath: String) -> Int32? {
        processLock.lock()
        defer { processLock.unlock() }
        return supervisedProcesses[controlPath]?.childProcessID
    }

    private func supervisedControlMasterIdentity(
        controlPath: String,
        childProcessID: Int32? = nil
    ) -> SSHControlMasterIdentity? {
        processLock.lock()
        defer { processLock.unlock() }
        guard let entry = supervisedProcesses[controlPath],
              let registeredChildProcessID = entry.childProcessID,
              childProcessID.map({ registeredChildProcessID == $0 }) ?? true else {
            return nil
        }
        return SSHControlMasterIdentity(
            processID: registeredChildProcessID,
            controlPath: controlPath,
            supervisorID: entry.operationID
        )
    }

    @discardableResult
    private func requestSupervisedProcessTermination(
        controlPath: String,
        operationID: UUID,
        childProcessID: Int32? = nil
    ) -> Bool {
        processLock.lock()
        guard var entry = supervisedProcesses[controlPath],
              entry.operationID == operationID,
              childProcessID.map({ entry.childProcessID == $0 }) ?? true else {
            processLock.unlock()
            return false
        }
        entry.terminationRequested = true
        supervisedProcesses[controlPath] = entry
        processLock.unlock()

        do {
            try entry.process.closeStandardInput()
            return true
        } catch {
            entry.process.terminate()
            return false
        }
    }

    private func finishFailedSupervisedProcess(
        controlPath: String,
        operationID: UUID
    ) {
        processLock.lock()
        let entry = supervisedProcesses[controlPath].flatMap { current in
            current.operationID == operationID ? current : nil
        }
        processLock.unlock()
        guard let entry else { return }

        _ = requestSupervisedProcessTermination(
            controlPath: controlPath,
            operationID: operationID
        )
        if !entry.process.waitForExit(timeout: 0.5) {
            entry.process.terminate()
            _ = entry.process.waitForExit(timeout: 0.5)
        }

        guard !entry.process.isRunning else { return }
        processLock.lock()
        if supervisedProcesses[controlPath]?.operationID == operationID {
            supervisedProcesses.removeValue(forKey: controlPath)
        }
        processLock.unlock()
    }

    private func withLifecycleLock<T>(
        controlPath: String,
        executor: any ProcessExecutor,
        operation: () throws -> T
    ) throws -> T {
        let lifecycleLock = Self.lifecycleLocks.lock(for: controlPath)
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        var lockDescriptor: Int32 = -1
        if executor is SystemProcessExecutor {
            let lockPath = lifecycleLockPath(for: controlPath)
            lockDescriptor = lockPath.withCString { path in
                Darwin.open(
                    path,
                    O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
                    mode_t(0o600)
                )
            }
            guard lockDescriptor >= 0 else {
                throw SSHMultiplexerError.connectionFailed(
                    "SSH ControlMaster lifecycle lock could not be opened"
                )
            }

            var metadata = stat()
            guard Darwin.fstat(lockDescriptor, &metadata) == 0,
                  (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                  metadata.st_uid == geteuid(),
                  metadata.st_nlink == 1,
                  (metadata.st_mode & 0o077) == 0,
                  Darwin.lockf(lockDescriptor, F_TLOCK, 0) == 0 else {
                Darwin.close(lockDescriptor)
                throw SSHMultiplexerError.connectionFailed(
                    "Another Cocxy SSH lifecycle operation owns the control directory"
                )
            }
        }
        defer {
            if lockDescriptor >= 0 {
                _ = Darwin.lockf(lockDescriptor, F_ULOCK, 0)
                Darwin.close(lockDescriptor)
            }
        }

        return try operation()
    }

    private func lifecycleLockPath(for controlPath: String) -> String {
        let directory = URL(fileURLWithPath: controlPath).deletingLastPathComponent()
        let digest = SHA256.hash(data: Data(controlPath.utf8))
            .prefix(16)
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent(".lifecycle-\(digest).lock").path
    }

    private func controlSocketFileIdentity(
        at path: String
    ) throws -> ControlSocketFileIdentity? {
        var metadata = stat()
        let result = path.withCString { Darwin.lstat($0, &metadata) }
        guard result == 0 else {
            if errno == ENOENT { return nil }
            throw SSHMultiplexerError.connectionFailed(
                "Existing SSH control path could not be inspected"
            )
        }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              (metadata.st_mode & 0o077) == 0 else {
            throw SSHMultiplexerError.connectionFailed(
                "Existing SSH control path is not a protected owner socket"
            )
        }
        return ControlSocketFileIdentity(
            device: metadata.st_dev,
            inode: metadata.st_ino
        )
    }

    private func directTCPControlSocketAttestation(
        at path: String
    ) throws -> SSHControlSocketAttestation {
        if let controlSocketAttestationProvider {
            return try controlSocketAttestationProvider(path)
        }

        guard let originalFileIdentity = try controlSocketFileIdentity(at: path) else {
            throw SSHMultiplexerError.notConnected
        }
        let peerProcessID: Int32
        switch probeControlSocket(at: path) {
        case .active(let processID):
            peerProcessID = processID
        case .stale, .indeterminate:
            throw SSHMultiplexerError.notConnected
        }
        guard try controlSocketFileIdentity(at: path) == originalFileIdentity else {
            throw SSHMultiplexerError.notConnected
        }
        return SSHControlSocketAttestation(
            device: UInt64(truncatingIfNeeded: originalFileIdentity.device),
            inode: UInt64(truncatingIfNeeded: originalFileIdentity.inode),
            peerProcessID: peerProcessID
        )
    }

    private func verifyDirectTCPControlSocket(
        expectedControlMaster: SSHControlMasterIdentity,
        expectedAttestation: SSHControlSocketAttestation
    ) throws {
        guard supervisedControlMasterIdentity(
            controlPath: expectedControlMaster.controlPath
        ) == expectedControlMaster,
        isControlMasterProcessAlive(expectedControlMaster) else {
            throw SSHMultiplexerError.notConnected
        }
        let currentAttestation = try directTCPControlSocketAttestation(
            at: expectedControlMaster.controlPath
        )
        guard currentAttestation == expectedAttestation,
              currentAttestation.peerProcessID == expectedControlMaster.processID,
              bindOrVerifyControlSocketAttestation(
                currentAttestation,
                expectedControlMaster: expectedControlMaster
              ) else {
            throw SSHMultiplexerError.notConnected
        }
    }

    private static func controlMasterProcessID(from output: String) -> Int32? {
        guard let marker = output.range(of: "pid=") else { return nil }
        let digits = output[marker.upperBound...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int32(digits)
    }

    private static func supervisedChildProcessID(from output: String) -> Int32? {
        guard let marker = output.range(of: "COCXY_SSH_CHILD_PID=") else { return nil }
        let digits = output[marker.upperBound...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int32(digits)
    }

    private func probeControlSocket(at path: String) -> ControlSocketProbe {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .indeterminate }
        defer { Darwin.close(descriptor) }
        guard Darwin.fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
            return .indeterminate
        }
        let currentFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard currentFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK) == 0 else {
            return .indeterminate
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else { return .indeterminate }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                    _ = memset(destination, 0, pathCapacity)
                    _ = memcpy(destination, source, pathBytes.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        if connectResult != 0 {
            let connectError = errno
            if connectError == ECONNREFUSED || connectError == ENOENT {
                return .stale
            }
            // This probe runs from synchronous lifecycle and MainActor-owned
            // forwarding paths. Never wait for a queued local connect here:
            // an incomplete result is conservatively rejected and the caller
            // can retry without blocking UI or teardown cancellation.
            return .indeterminate
        }

        var processID: pid_t = 0
        var processIDLength = socklen_t(MemoryLayout<pid_t>.size)
        let peerResult = Darwin.getsockopt(
            descriptor,
            SOL_LOCAL,
            LOCAL_PEERPID,
            &processID,
            &processIDLength
        )
        guard peerResult == 0, processID > 0 else { return .indeterminate }
        return .active(processID: processID)
    }

    /// Builds the base SSH arguments from a profile (port, identity, etc.).
    private func buildBaseArguments(for profile: RemoteConnectionProfile) -> [String] {
        var arguments: [String] = []

        if let port = profile.port {
            arguments.append(contentsOf: ["-p", "\(port)"])
        }

        if let identityFile = profile.identityFile {
            arguments.append(contentsOf: ["-i", identityFile])
        }

        if let strictHostKeyChecking = profile.strictHostKeyChecking {
            arguments.append(contentsOf: ["-o", "StrictHostKeyChecking=\(strictHostKeyChecking)"])
        }

        if let knownHostsFile = profile.knownHostsFile {
            arguments.append(contentsOf: ["-o", "UserKnownHostsFile=\(knownHostsFile)"])
        }

        if let batchMode = profile.batchMode {
            arguments.append(contentsOf: ["-o", "BatchMode=\(batchMode ? "yes" : "no")"])
        }

        if !profile.jumpHosts.isEmpty {
            arguments.append(contentsOf: ["-J", profile.jumpHosts.joined(separator: ",")])
        }

        arguments.append(contentsOf: [
            "-o", "ServerAliveInterval=\(profile.keepAliveInterval)",
        ])

        return arguments
    }

    private func ensureControlPathDirectory(for profile: RemoteConnectionProfile) throws {
        let controlPathURL = URL(fileURLWithPath: controlPath(for: profile))
        let directoryURL = controlPathURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    /// Returns a validated SSH destination: "user@host" or just "host".
    private func destination(for profile: RemoteConnectionProfile) throws -> SSHConnectionDestination {
        do {
            return try SSHConnectionDestination(user: profile.user, host: profile.host)
        } catch {
            throw SSHMultiplexerError.invalidDestination
        }
    }

    /// Converts a port forward spec into SSH command-line arguments.
    private func forwardArguments(
        for forward: RemoteConnectionProfile.PortForward
    ) throws -> [String] {
        switch forward {
        case let .local(localPort, remotePort, remoteHost):
            return ["-L", "\(localPort):\(remoteHost):\(remotePort)"]
        case let .remote(remotePort, localPort, localHost):
            return ["-R", "\(remotePort):\(localHost):\(localPort)"]
        case .dynamic:
            throw SSHMultiplexerError.forwardFailed(
                "Dynamic forwarding requires the authenticated proxy"
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - System Process Executor

private final class SystemManagedProcess: ManagedProcess, @unchecked Sendable {
    private static let maximumDiagnosticBytes = 65_536

    private let process: Process
    private let standardInputPipe: Pipe
    private let outputPipe: Pipe
    private let lock = NSLock()
    private var standardInputClosed = false
    private var diagnosticData = Data()

    var processIdentifier: Int32 {
        process.processIdentifier
    }

    var isRunning: Bool {
        process.isRunning
    }

    var diagnosticOutput: String {
        lock.lock()
        let data = diagnosticData
        lock.unlock()
        return String(decoding: data, as: UTF8.self)
    }

    init(command: String, arguments: [String]) throws {
        process = Process()
        standardInputPipe = Pipe()
        outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardInput = standardInputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.appendDiagnosticData(data)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func closeStandardInput() throws {
        lock.lock()
        guard !standardInputClosed else {
            lock.unlock()
            return
        }
        do {
            try standardInputPipe.fileHandleForWriting.close()
            standardInputClosed = true
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
    }

    func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while process.isRunning, Date() < deadline {
            usleep(10_000)
        }
        return !process.isRunning
    }

    func terminate() {
        try? closeStandardInput()
        if process.isRunning {
            process.terminate()
        }
    }

    deinit {
        try? closeStandardInput()
        outputPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func appendDiagnosticData(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = Self.maximumDiagnosticBytes - diagnosticData.count
        guard remaining > 0 else { return }
        diagnosticData.append(data.prefix(remaining))
    }
}

private final class ProcessExecutionCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }
}

/// Production implementation that runs real system processes.
struct SystemProcessExecutor: ProcessExecutor {
    static let defaultAsyncTimeoutSeconds: TimeInterval = 30 * 60
    static let maximumRetainedBytesPerStream = 4 * 1_024 * 1_024

    /// Background queue for async process execution.
    private static let processQueue = DispatchQueue(
        label: "com.cocxy.process-executor",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private let asyncTimeoutSeconds: TimeInterval
    private let maximumRetainedBytesPerStream: Int

    init(
        asyncTimeoutSeconds: TimeInterval = Self.defaultAsyncTimeoutSeconds,
        maximumRetainedBytesPerStream: Int = Self.maximumRetainedBytesPerStream
    ) {
        self.asyncTimeoutSeconds = asyncTimeoutSeconds
        self.maximumRetainedBytesPerStream = maximumRetainedBytesPerStream
    }

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        try executeBounded(
            command: command,
            arguments: arguments,
            timeoutSeconds: nil,
            cancellationRequested: { false }
        )
    }

    func executeControl(
        command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) throws -> ProcessResult {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw ProcessExecutorError.invalidTimeout
        }
        return try executeBounded(
            command: command,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds,
            cancellationRequested: { false }
        )
    }

    func start(command: String, arguments: [String]) throws -> any ManagedProcess {
        try SystemManagedProcess(command: command, arguments: arguments)
    }

    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult {
        try await executeAsyncBounded(
            command: command,
            arguments: arguments,
            timeoutSeconds: asyncTimeoutSeconds
        )
    }

    func executeControlAsync(
        command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> ProcessResult {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
            throw ProcessExecutorError.invalidTimeout
        }
        return try await executeAsyncBounded(
            command: command,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )
    }

    private func executeAsyncBounded(
        command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let cancellation = ProcessExecutionCancellationState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.processQueue.async {
                    do {
                        continuation.resume(returning: try executeBounded(
                            command: command,
                            arguments: arguments,
                            timeoutSeconds: timeoutSeconds,
                            cancellationRequested: { cancellation.isCancellationRequested }
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func executeBounded(
        command: String,
        arguments: [String],
        timeoutSeconds: TimeInterval?,
        cancellationRequested: @escaping @Sendable () -> Bool
    ) throws -> ProcessResult {
        let result = try BoundedProcessRunner(
            maximumRetainedBytesPerStream: maximumRetainedBytesPerStream,
            observesTaskCancellation: false,
            externalCancellationRequested: cancellationRequested
        ).run(
            executableURL: URL(fileURLWithPath: command),
            arguments: arguments,
            workingDirectory: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            ),
            timeoutSeconds: timeoutSeconds,
            timeoutDiagnostic: timeoutSeconds == nil ? nil : "SSH command timed out."
        )
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else {
            throw ProcessExecutorError.outputLimitExceeded
        }
        return ProcessResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            timedOut: result.timedOut
        )
    }
}
