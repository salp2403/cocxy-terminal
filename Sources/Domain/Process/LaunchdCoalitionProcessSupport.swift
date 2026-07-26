// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LaunchdCoalitionProcessSupport.swift - Secure launchd setup and coalition inspection.

import Darwin
import Foundation

struct LaunchdProcessNamespace: Equatable, Sendable {
    static let testRootEnvironmentKey = "COCXY_TEST_BOUNDED_PROCESS_ROOT"
    static let testLabelEnvironmentKey = "COCXY_TEST_BOUNDED_PROCESS_LABEL_PREFIX"

    static let production = LaunchdProcessNamespace(
        rootURL: URL(
            fileURLWithPath: "/private/tmp/dev.cocxy.bp.\(getuid())",
            isDirectory: true
        ),
        labelPrefix: "dev.cocxy.bounded-process",
        isValid: true,
        isTest: false
    )

    let rootURL: URL
    let labelPrefix: String
    let isValid: Bool
    let isTest: Bool

    var inheritedEnvironment: [String: String] {
        guard isTest, isValid else { return [:] }
        return [
            Self.testRootEnvironmentKey: rootURL.path,
            Self.testLabelEnvironmentKey: labelPrefix,
        ]
    }

    static var current: LaunchdProcessNamespace {
        resolve(
            arguments: CommandLine.arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func resolve(
        arguments: [String],
        environment: [String: String]
    ) -> LaunchdProcessNamespace {
        let executablePath = arguments.first ?? ""
        let isXCTestHost = URL(fileURLWithPath: executablePath).lastPathComponent == "xctest"
            || executablePath.contains(".xctest/")
        let isSwiftPMTestingHost = executablePath.hasSuffix(
            "/usr/libexec/swift/pm/swiftpm-testing-helper"
        )
        let isBrokerProcess = arguments.count == 4
            && arguments[1] == LaunchdProcessBrokerEntry.modeArgument
            && Int32(arguments[2]).map { $0 >= 0 } == true
            && Int32(arguments[3]).map { $0 >= 0 } == true
        let isSupervisorProcess = arguments.count == 6
            && arguments[1] == LaunchdProcessSupervisorEntry.modeArgument
            && pid_t(arguments[3]).map { $0 > 1 } == true
            && UInt64(arguments[4]) != nil
            && UInt64(arguments[5]) != nil
        let isAuthorizedTestProcess = isXCTestHost
            || isSwiftPMTestingHost
            || isBrokerProcess
            || isSupervisorProcess
        guard isAuthorizedTestProcess else { return .production }

        let rootPath = environment[testRootEnvironmentKey]
        let labelPrefix = environment[testLabelEnvironmentKey]
        guard rootPath != nil || labelPrefix != nil else { return .production }
        guard let rootPath, let labelPrefix,
              let rootNonce = validatedTestRootNonce(path: rootPath),
              let labelNonce = validatedTestLabelNonce(labelPrefix),
              rootNonce == labelNonce else {
            return LaunchdProcessNamespace(
                rootURL: URL(
                    fileURLWithPath: "/private/tmp/cxbpt.invalid.\(getuid())",
                    isDirectory: true
                ),
                labelPrefix: "dev.cocxy.bounded-process.invalid",
                isValid: false,
                isTest: true
            )
        }
        return LaunchdProcessNamespace(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
            labelPrefix: labelPrefix,
            isValid: true,
            isTest: true
        )
    }

    private static func validatedTestRootNonce(path: String) -> Substring? {
        let expectedPrefix = "/private/tmp/cxbpt.\(getuid())."
        guard path.hasPrefix(expectedPrefix),
              path.utf8.count < Int(PATH_MAX) else {
            return nil
        }
        let nonce = path.dropFirst(expectedPrefix.count)
        return validatedTestNonce(nonce) ? nonce : nil
    }

    private static func validatedTestLabelNonce(_ value: String) -> Substring? {
        let expectedPrefix = "dev.cocxy.bounded-process.test.\(getuid())."
        guard value.hasPrefix(expectedPrefix), value.utf8.count <= 180 else {
            return nil
        }
        let nonce = value.dropFirst(expectedPrefix.count)
        return validatedTestNonce(nonce) ? nonce : nil
    }

    private static func validatedTestNonce(_ value: Substring) -> Bool {
        value.utf8.count == 8 && value.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }
}

struct LaunchdBootIdentity: Codable, Equatable, Sendable {
    private static let currentEncodingVersion = 2
    private static let maximumSessionUUIDBytes = 128

    let sessionUUID: String?
    let legacySeconds: Int64?
    let legacyMicroseconds: Int64?

    var isStable: Bool { sessionUUID != nil }

    init(sessionUUID: UUID) {
        self.sessionUUID = sessionUUID.uuidString.lowercased()
        legacySeconds = nil
        legacyMicroseconds = nil
    }

    init(seconds: Int64, microseconds: Int64) {
        sessionUUID = nil
        legacySeconds = seconds
        legacyMicroseconds = microseconds
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sessionUUID
        case seconds
        case microseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawSessionUUID = try container.decodeIfPresent(
            String.self,
            forKey: .sessionUUID
        ) {
            let version = try container.decodeIfPresent(Int.self, forKey: .version)
            guard version == Self.currentEncodingVersion,
                  let uuid = UUID(uuidString: rawSessionUUID) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sessionUUID,
                    in: container,
                    debugDescription: "Invalid boot session identity"
                )
            }
            sessionUUID = uuid.uuidString.lowercased()
            legacySeconds = nil
            legacyMicroseconds = nil
            return
        }

        let seconds = try container.decode(Int64.self, forKey: .seconds)
        let microseconds = try container.decode(Int64.self, forKey: .microseconds)
        guard seconds > 0, microseconds >= 0, microseconds < 1_000_000 else {
            throw DecodingError.dataCorruptedError(
                forKey: .seconds,
                in: container,
                debugDescription: "Invalid legacy boot time"
            )
        }
        sessionUUID = nil
        legacySeconds = seconds
        legacyMicroseconds = microseconds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let sessionUUID {
            try container.encode(Self.currentEncodingVersion, forKey: .version)
            try container.encode(sessionUUID, forKey: .sessionUUID)
            return
        }
        guard let legacySeconds, let legacyMicroseconds else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Missing boot identity"
                )
            )
        }
        try container.encode(legacySeconds, forKey: .seconds)
        try container.encode(legacyMicroseconds, forKey: .microseconds)
    }

    static func current() throws -> LaunchdBootIdentity {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0,
              size > 1,
              size <= Self.maximumSessionUUIDBytes else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read system boot session identity",
                code: errno == 0 ? EIO : errno
            )
        }
        let queriedSize = size
        var buffer = [CChar](repeating: 0, count: queriedSize + 1)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctlbyname(
                "kern.bootsessionuuid",
                bytes.baseAddress,
                &size,
                nil,
                0
            )
        }
        guard result == 0,
              size > 1,
              size <= queriedSize else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read system boot session identity",
                code: errno == 0 ? EIO : errno
            )
        }
        buffer[size] = 0
        let rawSessionUUID = buffer.withUnsafeBufferPointer { storage -> String in
            String(cString: storage.baseAddress!)
        }
        guard let uuid = UUID(uuidString: rawSessionUUID) else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read system boot session identity",
                code: errno == 0 ? EIO : errno
            )
        }
        return LaunchdBootIdentity(sessionUUID: uuid)
    }

    static func currentLegacyBootTime() throws -> LaunchdBootIdentity {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var managementInformationBase = [Int32(CTL_KERN), Int32(KERN_BOOTTIME)]
        guard sysctl(
            &managementInformationBase,
            u_int(managementInformationBase.count),
            &bootTime,
            &size,
            nil,
            0
        ) == 0,
        size == MemoryLayout<timeval>.size,
        bootTime.tv_sec > 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read system boot identity",
                code: errno
            )
        }
        return LaunchdBootIdentity(
            seconds: Int64(bootTime.tv_sec),
            microseconds: Int64(bootTime.tv_usec)
        )
    }
}

enum LaunchdExecutionBoundaryError: Error {
    case deadlineExceeded
}

struct LaunchdExecutionBoundary: Sendable {
    let deadline: UInt64?
    let cancellationRequested: @Sendable () -> Bool

    func check() throws {
        if cancellationRequested() { throw CancellationError() }
        if let deadline, LaunchdMonotonicClock.now() >= deadline {
            throw LaunchdExecutionBoundaryError.deadlineExceeded
        }
    }

    func remainingSeconds(maximum: TimeInterval) throws -> TimeInterval {
        try check()
        guard let deadline else { return maximum }
        let now = LaunchdMonotonicClock.now()
        guard now < deadline else {
            throw LaunchdExecutionBoundaryError.deadlineExceeded
        }
        let remaining = Double(deadline - now) / 1_000_000_000
        return min(maximum, max(remaining, 0.001))
    }

    func boundedDeadline(maximum: TimeInterval) throws -> UInt64 {
        let local = LaunchdMonotonicClock.adding(
            seconds: maximum,
            to: LaunchdMonotonicClock.now()
        )
        guard let deadline else { return local }
        try check()
        return min(deadline, local)
    }

    func contextualError(
        _ operation: String,
        preservingBoundaryFrom error: Error
    ) throws -> BoundedProcessRunnerError {
        if error is CancellationError {
            throw CancellationError()
        }
        if let boundaryError = error as? LaunchdExecutionBoundaryError {
            throw boundaryError
        }
        try check()
        return BoundedProcessRunnerError.contextual(operation, error: error)
    }
}

enum LaunchdProcessEnvironment {
    private static let allowedExactKeys: Set<String> = [
        "PATH",
        "HOME",
        "TMPDIR",
        "DEVELOPER_DIR",
        "SDKROOT",
        "TOOLCHAINS",
        "SHELL",
        "USER",
        "LOGNAME",
        "LANG",
        "TERM",
        "COLORTERM",
        "XDG_CONFIG_HOME",
        "XDG_CACHE_HOME",
        "XDG_DATA_HOME",
        "JAVA_HOME",
        "GOPATH",
        "GOROOT",
        "CARGO_HOME",
        "RUSTUP_HOME",
        "NODE_PATH",
        "NPM_CONFIG_PREFIX",
        "PYENV_ROOT",
        "RBENV_ROOT",
        "GEM_HOME",
        "GEM_PATH",
        "COMPOSER_HOME",
        "COCXY_TEMPLATE_HOOK",
    ]
    private static let blockedFragments = [
        "secret",
        "token",
        "password",
        "credential",
        "private_key",
        "apikey",
        "api_key",
    ]

    static func sanitized(_ environment: [String: String]) -> [String: String] {
        environment.reduce(into: [:]) { result, pair in
            let lowercaseKey = pair.key.lowercased()
            guard allowedExactKeys.contains(pair.key) || pair.key.hasPrefix("LC_") else {
                return
            }
            guard !blockedFragments.contains(where: lowercaseKey.contains) else { return }
            result[pair.key] = pair.value
        }
    }
}

struct LaunchdContainedInvocation {
    private static let sandboxExecutableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
    private static let environmentExecutableURL = URL(fileURLWithPath: "/usr/bin/env")

    let executableURL: URL
    let arguments: [String]

    static func make(
        executableURL: URL,
        arguments: [String],
        deniedArtifactRoot: URL
    ) throws -> LaunchdContainedInvocation {
        guard FileManager.default.isExecutableFile(atPath: sandboxExecutableURL.path) else {
            throw BoundedProcessRunnerError.secureContainmentUnavailable
        }
        let rules = containmentRules(deniedArtifactRoot: deniedArtifactRoot)
        if executableURL.standardizedFileURL == sandboxExecutableURL {
            guard arguments.count >= 3, arguments[0] == "-p" else {
                throw BoundedProcessRunnerError.invalidInvocation
            }
            var mergedArguments = arguments
            mergedArguments[1] = arguments[1] + "\n" + rules
            return LaunchdContainedInvocation(
                executableURL: sandboxExecutableURL,
                arguments: mergedArguments
            )
        }
        if executableURL.standardizedFileURL == environmentExecutableURL,
           let nested = nestedSandboxInvocation(in: arguments) {
            return LaunchdContainedInvocation(
                executableURL: sandboxExecutableURL,
                arguments: [
                    "-p",
                    nested.profile + "\n" + rules,
                    environmentExecutableURL.path,
                ] + nested.environmentAssignments + nested.command
            )
        }
        let profile = """
        (version 1)
        (allow default)
        \(rules)
        """
        return LaunchdContainedInvocation(
            executableURL: sandboxExecutableURL,
            arguments: ["-p", profile, executableURL.path] + arguments
        )
    }

    private static func nestedSandboxInvocation(
        in arguments: [String]
    ) -> (environmentAssignments: [String], profile: String, command: [String])? {
        var commandIndex = 0
        while commandIndex < arguments.count,
              isEnvironmentAssignment(arguments[commandIndex]) {
            commandIndex += 1
        }
        guard commandIndex + 3 < arguments.count,
              arguments[commandIndex] == sandboxExecutableURL.path,
              arguments[commandIndex + 1] == "-p" else {
            return nil
        }
        let command = Array(arguments[(commandIndex + 3)...])
        guard !command.isEmpty else { return nil }
        return (
            Array(arguments[..<commandIndex]),
            arguments[commandIndex + 2],
            command
        )
    }

    private static func isEnvironmentAssignment(_ argument: String) -> Bool {
        guard let separator = argument.firstIndex(of: "="), separator != argument.startIndex else {
            return false
        }
        let key = argument[..<separator]
        guard key.first?.isNumber != true else { return false }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private static func containmentRules(deniedArtifactRoot: URL) -> String {
        let path = escapeSandboxString(deniedArtifactRoot.path)
        return """
        (deny job-creation)
        (deny lsopen)
        (deny appleevent-send)
        (deny authorization-right-obtain)
        (deny system-privilege)
        (deny process-exec (literal "/usr/bin/osascript"))
        (deny process-exec (literal "/usr/bin/open"))
        (deny process-exec (literal "/usr/bin/automator"))
        (deny process-exec (literal "/usr/bin/shortcuts"))
        (deny signal)
        (allow signal (target same-sandbox))
        (deny file-read* (subpath "\(path)"))
        (deny file-write* (subpath "\(path)"))
        """
    }

    private static func escapeSandboxString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

struct LaunchdProcessLease: Codable, Equatable, Sendable {
    let label: String
    let domain: String?
    let coalitionID: UInt64?
    let directoryPath: String
    let directoryDevice: UInt64
    let directoryInode: UInt64

    func secured(domain: String, coalitionID: UInt64) -> LaunchdProcessLease {
        LaunchdProcessLease(
            label: label,
            domain: domain,
            coalitionID: coalitionID,
            directoryPath: directoryPath,
            directoryDevice: directoryDevice,
            directoryInode: directoryInode
        )
    }

    func emergencyCleanup() throws {
        try LaunchdProcessArtifacts.emergencyCleanup(lease: self)
    }

    func isConsistent(with state: LaunchdPersistedExecutionState) -> Bool {
        label == state.label
            && directoryDevice == state.directoryDevice
            && directoryInode == state.directoryInode
            && (domain == nil || domain == state.domain)
            && (coalitionID == nil || coalitionID == state.coalitionID)
            && (domain == nil) == (coalitionID == nil)
    }
}

struct LaunchdArtifactIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
}

struct LaunchdPersistedExecutionState: Codable, Equatable {
    let label: String
    let domain: String
    let coalitionID: UInt64
    let bootIdentity: LaunchdBootIdentity?
    let supervisorIdentity: LaunchdProcessIdentity
    let directoryDevice: UInt64
    let directoryInode: UInt64
    let payloadMayHaveRun: Bool

    func bootScope(
        currentBootIdentity: LaunchdBootIdentity,
        currentLegacyBootIdentity: LaunchdBootIdentity?
    ) -> LaunchdPersistedBootScope {
        guard let bootIdentity else { return .unverifiable }
        if bootIdentity.isStable {
            return bootIdentity == currentBootIdentity ? .current : .differentBoot
        }
        guard let currentLegacyBootIdentity,
              bootIdentity == currentLegacyBootIdentity else {
            return .unverifiable
        }
        return .current
    }
}

enum LaunchdPersistedBootScope: Equatable {
    case current
    case differentBoot
    case unverifiable
}

enum LaunchdOwnedJobEvidence {
    case absent
    case matching(LaunchdJobSnapshot)
    case unknown(String)
    case conflicting(String)

    var permitsBootoutAttempt: Bool {
        switch self {
        case .matching:
            return true
        case .absent, .unknown, .conflicting:
            return false
        }
    }
}

struct LaunchdSupervisorHandshakeState {
    private var pendingCompletion: LaunchdSupervisorCompletion?

    /// Accepts the supervisor's first frame, requiring it to agree with the
    /// coalition the broker proved against the kernel.
    ///
    /// Both sides read `proc_pidinfo` independently, so this comparison is the
    /// release-independent cross-check of the handoff: it holds on every
    /// supported macOS version, including the ones whose `launchctl print`
    /// publishes no coalition block at all.
    mutating func acceptInitial(
        _ message: LaunchdSupervisorMessage,
        expectedCoalitionID: UInt64
    ) throws {
        try message.validate()
        switch message.kind {
        case .acknowledged:
            guard message.coalitionID == expectedCoalitionID else {
                throw BoundedProcessRunnerError.secureBrokerFailed(
                    "supervisor coalition mismatch (expected \(expectedCoalitionID), "
                        + "observed \(message.coalitionID.map(String.init) ?? "none"))"
                )
            }
            return
        case .completed:
            guard let completion = message.completion else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            pendingCompletion = completion
        }
    }

    mutating func takePendingCompletion() -> LaunchdSupervisorCompletion? {
        defer { pendingCompletion = nil }
        return pendingCompletion
    }
}

final class LaunchdProcessArtifacts {
    static var rootURL: URL { LaunchdProcessNamespace.current.rootURL }
    private static let directoryPrefix = "execution"
    private static let stagingDirectoryPrefix = "staging"
    private static let cleanupDirectoryPrefix = "cleanup"
    private static var labelPrefix: String { LaunchdProcessNamespace.current.labelPrefix }
    private static let controlSocketName = "control.sock"
    private static let stateFileName = "state.plist"
    private static let pendingStateFileName = "state.plist.pending"
    private static let handshakeWaitSeconds: TimeInterval = 5

    let directoryURL: URL
    let label: String
    let propertyListURL: URL
    let controlSocketURL: URL
    let controlListener: LaunchdOwnedFileDescriptor
    let stdoutReader: BoundedOwnedFileDescriptor
    let stderrReader: BoundedOwnedFileDescriptor
    let stdoutWriter: BoundedOwnedFileDescriptor
    let stderrWriter: BoundedOwnedFileDescriptor
    private let directoryLock: LaunchdOwnedFileDescriptor
    private let directoryIdentity: LaunchdArtifactIdentity
    private let controlSocketIdentity: LaunchdArtifactIdentity
    private var supervisorConnection: LaunchdBrokerConnection?
    private var supervisorHandshake = LaunchdSupervisorHandshakeState()

    private var streamsClosed = false
    private var removed = false

    private init(
        directoryURL: URL,
        label: String,
        propertyListURL: URL,
        controlSocketURL: URL,
        controlListener: LaunchdOwnedFileDescriptor,
        stdoutReader: BoundedOwnedFileDescriptor,
        stderrReader: BoundedOwnedFileDescriptor,
        stdoutWriter: BoundedOwnedFileDescriptor,
        stderrWriter: BoundedOwnedFileDescriptor,
        directoryLock: LaunchdOwnedFileDescriptor,
        directoryIdentity: LaunchdArtifactIdentity,
        controlSocketIdentity: LaunchdArtifactIdentity
    ) {
        self.directoryURL = directoryURL
        self.label = label
        self.propertyListURL = propertyListURL
        self.controlSocketURL = controlSocketURL
        self.controlListener = controlListener
        self.stdoutReader = stdoutReader
        self.stderrReader = stderrReader
        self.stdoutWriter = stdoutWriter
        self.stderrWriter = stderrWriter
        self.directoryLock = directoryLock
        self.directoryIdentity = directoryIdentity
        self.controlSocketIdentity = controlSocketIdentity
    }

    deinit {
        closeStreams()
    }

    var lease: LaunchdProcessLease {
        LaunchdProcessLease(
            label: label,
            domain: nil,
            coalitionID: nil,
            directoryPath: directoryURL.path,
            directoryDevice: directoryIdentity.device,
            directoryInode: directoryIdentity.inode
        )
    }

    static func create(
        brokerIdentity: LaunchdProcessIdentity,
        directoryLockAcquirer: ((URL) throws -> LaunchdOwnedFileDescriptor?)? = nil
    ) throws -> LaunchdProcessArtifacts {
        try ensurePrivateRoot()

        let identifier = UUID().uuidString.lowercased()
        let label = "\(labelPrefix).\(identifier)"
        let directoryURL = rootURL.appendingPathComponent(
            "\(directoryPrefix).\(identifier)",
            isDirectory: true
        )
        let stagingDirectoryURL = rootURL.appendingPathComponent(
            "\(stagingDirectoryPrefix).\(identifier)",
            isDirectory: true
        )
        guard mkdir(stagingDirectoryURL.path, S_IRWXU) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "mkdir launchd staging directory",
                code: errno
            )
        }
        let directoryIdentity: LaunchdArtifactIdentity
        do {
            directoryIdentity = try executionDirectoryIdentity(at: stagingDirectoryURL)
        } catch {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "new launchd staging directory could not be identified after creation"
            )
        }
        var directoryWasPublished = false
        do {
            let acquireLock = directoryLockAcquirer ?? acquireExecutionDirectoryLock
            guard let directoryLock = try acquireLock(stagingDirectoryURL) else {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "new launchd staging directory lock was unexpectedly held"
                )
            }
            let controlSocketURL = directoryURL.appendingPathComponent(controlSocketName)
            let supervisorURL = try currentExecutableURL()
            var propertyList: [String: Any] = [
                "Label": label,
                "ProgramArguments": [
                    supervisorURL.path,
                    LaunchdProcessSupervisorEntry.modeArgument,
                    controlSocketURL.path,
                    String(brokerIdentity.pid),
                    String(brokerIdentity.startSeconds),
                    String(brokerIdentity.startMicroseconds),
                ],
                "WorkingDirectory": "/",
                "StandardInPath": "/dev/null",
                "StandardOutPath": "/dev/null",
                "StandardErrorPath": "/dev/null",
                "RunAtLoad": true,
                "KeepAlive": ["SuccessfulExit": false],
                "ThrottleInterval": 1,
                "ProcessType": "Interactive",
                "ExitTimeOut": 1,
            ]
            let inheritedEnvironment = LaunchdProcessNamespace.current.inheritedEnvironment
            if !inheritedEnvironment.isEmpty {
                propertyList["EnvironmentVariables"] = inheritedEnvironment
            }
            let propertyListData = try PropertyListSerialization.data(
                fromPropertyList: propertyList,
                format: .binary,
                options: 0
            )
            try writeExclusiveFile(
                propertyListData,
                named: "job.plist",
                directoryDescriptor: directoryLock.rawValue,
                permissions: S_IRUSR
            )
            try synchronizeDirectory(descriptor: directoryLock.rawValue)
            try publishStagingDirectory(
                stagingDirectoryURL,
                as: directoryURL,
                expectedIdentity: directoryIdentity
            )
            directoryWasPublished = true
            guard try executionDirectoryIdentity(at: directoryURL) == directoryIdentity else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }

            let propertyListURL = directoryURL.appendingPathComponent("job.plist")
            let stdoutPipe = try BoundedPipe.make()
            let stderrPipe = try BoundedPipe.make()
            try stdoutPipe.read.setNonBlocking()
            try stderrPipe.read.setNonBlocking()
            let (controlListener, controlSocketIdentity) = try createControlListener(
                at: controlSocketURL
            )

            return LaunchdProcessArtifacts(
                directoryURL: directoryURL,
                label: label,
                propertyListURL: propertyListURL,
                controlSocketURL: controlSocketURL,
                controlListener: controlListener,
                stdoutReader: stdoutPipe.read,
                stderrReader: stderrPipe.read,
                stdoutWriter: stdoutPipe.write,
                stderrWriter: stderrPipe.write,
                directoryLock: directoryLock,
                directoryIdentity: directoryIdentity,
                controlSocketIdentity: controlSocketIdentity
            )
        } catch let originalError {
            do {
                if directoryWasPublished {
                    try removeVerified(
                        directoryURL: directoryURL,
                        expectedIdentity: directoryIdentity
                    )
                } else {
                    try removeStagingVerified(
                        directoryURL: stagingDirectoryURL,
                        expectedIdentity: directoryIdentity
                    )
                }
            } catch {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "launchd artifact preparation cleanup failed after "
                        + "\(Self.errorDetail(originalError)): \(Self.errorDetail(error))"
                )
            }
            throw originalError
        }
    }

    func acceptSupervisor(
        expectedIdentity: LaunchdProcessIdentity,
        boundary: LaunchdExecutionBoundary
    ) throws {
        let deadline = try boundary.boundedDeadline(maximum: Self.handshakeWaitSeconds)
        while true {
            try boundary.check()
            guard try Self.controlSocketIdentity(at: controlSocketURL)
                    == controlSocketIdentity else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            let rawDescriptor = Darwin.accept(controlListener.rawValue, nil, nil)
            if rawDescriptor == -1 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
                    if LaunchdMonotonicClock.now() >= deadline {
                        throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                    }
                    usleep(5_000)
                    continue
                }
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "accept launchd supervisor",
                    code: errno
                )
            }

            let descriptor = LaunchdOwnedFileDescriptor(rawDescriptor)
            do {
                try descriptor.relocateAboveStandardDescriptors()
                try LaunchdPeerAuthenticator.verify(
                    descriptor: descriptor.rawValue,
                    expectedIdentity: expectedIdentity
                )
                let connection = try LaunchdBrokerConnection(descriptor: descriptor.rawValue)
                descriptor.releaseOwnership()
                try unlinkVerifiedControlSocket()
                controlListener.close()
                supervisorConnection = connection
                return
            } catch {
                descriptor.close()
                throw error
            }
        }
    }

    func releaseInvocation(
        _ request: LaunchdSupervisorRequest,
        ownerLivenessDescriptor: Int32,
        expectedCoalitionID: UInt64,
        boundary: LaunchdExecutionBoundary
    ) throws {
        guard let supervisorConnection, ownerLivenessDescriptor >= 0 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let deadline = try boundary.boundedDeadline(maximum: Self.handshakeWaitSeconds)
        try supervisorConnection.sendFileDescriptors(
            [stdoutWriter.rawValue, stderrWriter.rawValue, ownerLivenessDescriptor],
            deadline: { deadline },
            pollHook: { try boundary.check() }
        )
        stdoutWriter.close()
        stderrWriter.close()
        try supervisorConnection.writeFrame(
            request,
            deadline: { deadline },
            pollHook: { try boundary.check() }
        )
        let message: LaunchdSupervisorMessage = try supervisorConnection.readFrame(
            deadline: { deadline },
            pollHook: { try boundary.check() }
        )
        try supervisorHandshake.acceptInitial(
            message,
            expectedCoalitionID: expectedCoalitionID
        )
    }

    func readSupervisorCompletion(deadline: UInt64) throws -> LaunchdSupervisorCompletion {
        if let pendingCompletion = supervisorHandshake.takePendingCompletion() {
            return pendingCompletion
        }
        guard let supervisorConnection else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let message: LaunchdSupervisorMessage = try supervisorConnection.readFrame(
            deadline: { deadline },
            pollHook: {}
        )
        try message.validate()
        guard message.kind == .completed, let completion = message.completion else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        try completion.validate()
        return completion
    }

    func persistSecuredState(
        domain: String,
        coalitionID: UInt64,
        supervisorIdentity: LaunchdProcessIdentity
    ) throws {
        try Self.persistSecuredState(
            label: label,
            domain: domain,
            coalitionID: coalitionID,
            supervisorIdentity: supervisorIdentity,
            directoryIdentity: directoryIdentity,
            directoryDescriptor: directoryLock.rawValue
        )
    }

    private static func persistSecuredState(
        label: String,
        domain: String,
        coalitionID: UInt64,
        supervisorIdentity: LaunchdProcessIdentity,
        directoryIdentity: LaunchdArtifactIdentity,
        directoryDescriptor: Int32
    ) throws {
        guard LaunchdControlClient.domains.contains(domain), coalitionID != 0 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let bootIdentity = try LaunchdBootIdentity.current()
        let state = LaunchdPersistedExecutionState(
            label: label,
            domain: domain,
            coalitionID: coalitionID,
            bootIdentity: bootIdentity,
            supervisorIdentity: supervisorIdentity,
            directoryDevice: directoryIdentity.device,
            directoryInode: directoryIdentity.inode,
            payloadMayHaveRun: true
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try Self.writeAtomicFile(
            encoder.encode(state),
            finalName: Self.stateFileName,
            pendingName: Self.pendingStateFileName,
            directoryDescriptor: directoryDescriptor,
            permissions: S_IRUSR
        )
    }

    func closeStreams() {
        guard !streamsClosed else { return }
        streamsClosed = true
        supervisorConnection?.close()
        supervisorConnection = nil
        controlListener.close()
        stdoutReader.close()
        stderrReader.close()
        stdoutWriter.close()
        stderrWriter.close()
    }

    func removeVerified() throws {
        guard !removed else { return }
        closeStreams()
        try Self.removeVerified(
            directoryURL: directoryURL,
            expectedIdentity: directoryIdentity
        )
        directoryLock.close()
        removed = true
    }

    static func contains(directoryURL: URL) -> Bool {
        contains(directoryURL: directoryURL, prefix: directoryPrefix)
    }

    private static func containsStaging(directoryURL: URL) -> Bool {
        contains(directoryURL: directoryURL, prefix: stagingDirectoryPrefix)
    }

    private static func containsCleanup(directoryURL: URL) -> Bool {
        contains(directoryURL: directoryURL, prefix: cleanupDirectoryPrefix)
    }

    private static func contains(directoryURL: URL, prefix: String) -> Bool {
        guard LaunchdProcessNamespace.current.isValid else { return false }
        let rootPath = rootURL.standardizedFileURL.path
        let parentPath = directoryURL.deletingLastPathComponent().standardizedFileURL.path
        guard parentPath == rootPath else { return false }
        let component = directoryURL.lastPathComponent
        let componentPrefix = "\(prefix)."
        guard component.hasPrefix(componentPrefix) else { return false }
        let identifier = String(component.dropFirst(componentPrefix.count))
        guard let uuid = UUID(uuidString: identifier) else { return false }
        return identifier == uuid.uuidString.lowercased()
    }

    static func contains(controlSocketURL: URL) -> Bool {
        controlSocketURL.lastPathComponent == controlSocketName
            && contains(directoryURL: controlSocketURL.deletingLastPathComponent())
    }

    static func recoverSupervisorCoalitionAfterConnectionFailure(
        controlSocketURL: URL,
        expectedBrokerIdentity: LaunchdProcessIdentity
    ) throws -> Bool {
        guard contains(controlSocketURL: controlSocketURL) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let directoryURL = controlSocketURL.deletingLastPathComponent()
        let inspectionDescriptor = try openExecutionDirectory(at: directoryURL)
        defer { inspectionDescriptor.close() }
        let inspectedMetadata = try persistedMetadata(
            directoryURL: directoryURL,
            directoryDescriptor: inspectionDescriptor.rawValue
        )
        guard inspectedMetadata.owner == expectedBrokerIdentity else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        if inspectedMetadata.state == nil {
            return try recoverPrePayloadSupervisor(
                label: inspectedMetadata.label,
                directoryURL: directoryURL,
                directoryDescriptor: inspectionDescriptor.rawValue,
                expectedBrokerIdentity: expectedBrokerIdentity
            )
        }

        guard let directoryLock = try acquireExecutionDirectoryLock(at: directoryURL) else {
            return false
        }
        defer { directoryLock.close() }

        let metadata = try persistedMetadata(
            directoryURL: directoryURL,
            directoryDescriptor: directoryLock.rawValue
        )
        let currentBootIdentity = try LaunchdBootIdentity.current()
        let currentLegacyBootIdentity = try? LaunchdBootIdentity.currentLegacyBootTime()
        guard metadata.owner == expectedBrokerIdentity,
              let state = metadata.state,
              state.bootScope(
                  currentBootIdentity: currentBootIdentity,
                  currentLegacyBootIdentity: currentLegacyBootIdentity
              ) == .current else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        if let owner = LaunchdProcessSnapshot.current(for: expectedBrokerIdentity.pid),
           owner.identity == expectedBrokerIdentity,
           owner.isLive {
            return false
        }

        guard let supervisor = LaunchdProcessSnapshot.current(for: getpid()),
              supervisor.userID == geteuid(),
              supervisor.isLive,
              LaunchdProcessCoalition.resourceID(for: getpid()) == state.coalitionID else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let presence = try LaunchdControlClient().presence(
            domain: state.domain,
            label: state.label
        )
        // The kernel already proved this process belongs to the persisted
        // coalition above; launchd only corroborates when it publishes a
        // coalition block, which not every supported macOS release does.
        guard case .present(let job) = presence,
              job.pid == getpid(),
              Self.launchdCoalitionCorroborates(job, expected: state.coalitionID) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        try LaunchdProcessCoalition.terminateMembers(
            id: state.coalitionID,
            excluding: getpid(),
            gracePeriodSeconds: 0.2,
            killWaitSeconds: 1
        )
        try LaunchdProcessCoalition.verifyEmpty(
            id: state.coalitionID,
            excluding: getpid(),
            waitSeconds: 1
        )
        return true
    }

    private static func recoverPrePayloadSupervisor(
        label: String,
        directoryURL: URL,
        directoryDescriptor: Int32,
        expectedBrokerIdentity: LaunchdProcessIdentity
    ) throws -> Bool {
        guard let supervisor = LaunchdProcessSnapshot.current(for: getpid()),
              supervisor.userID == geteuid(),
              supervisor.isLive,
              let coalitionID = LaunchdProcessCoalition.resourceID(for: getpid()) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let domain = try prePayloadDomain(label: label, coalitionID: coalitionID)

        // A state published during inspection has already transferred cleanup authority.
        guard try readPrivateArtifact(
            name: stateFileName,
            directoryDescriptor: directoryDescriptor,
            maximumBytes: 1 * 1_024 * 1_024
        ) == nil else {
            return false
        }

        if let owner = LaunchdProcessSnapshot.current(for: expectedBrokerIdentity.pid),
           owner.identity == expectedBrokerIdentity,
           owner.isLive {
            try LaunchdProcessCoalition.terminateMembers(
                id: coalitionID,
                excluding: getpid(),
                gracePeriodSeconds: 0,
                killWaitSeconds: 1
            )
            try LaunchdProcessCoalition.verifyEmpty(
                id: coalitionID,
                excluding: getpid(),
                waitSeconds: 1
            )
            return true
        }

        guard let directoryLock = try acquireExecutionDirectoryLock(at: directoryURL) else {
            return false
        }
        defer { directoryLock.close() }

        let metadata = try persistedMetadata(
            directoryURL: directoryURL,
            directoryDescriptor: directoryLock.rawValue
        )
        guard metadata.label == label,
              metadata.owner == expectedBrokerIdentity,
              let currentSupervisor = LaunchdProcessSnapshot.current(for: getpid()),
              currentSupervisor.identity == supervisor.identity,
              currentSupervisor.userID == geteuid(),
              currentSupervisor.isLive,
              LaunchdProcessCoalition.resourceID(for: getpid()) == coalitionID,
              try prePayloadDomain(label: label, coalitionID: coalitionID) == domain else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        if let state = metadata.state {
            let currentBootIdentity = try LaunchdBootIdentity.current()
            let currentLegacyBootIdentity = try? LaunchdBootIdentity.currentLegacyBootTime()
            guard state.domain == domain,
                  state.coalitionID == coalitionID,
                  state.supervisorIdentity == supervisor.identity,
                  state.bootScope(
                      currentBootIdentity: currentBootIdentity,
                      currentLegacyBootIdentity: currentLegacyBootIdentity
                  ) == .current else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        } else {
            try persistSecuredState(
                label: label,
                domain: domain,
                coalitionID: coalitionID,
                supervisorIdentity: supervisor.identity,
                directoryIdentity: metadata.directoryIdentity,
                directoryDescriptor: directoryLock.rawValue
            )
        }

        try LaunchdProcessCoalition.terminateMembers(
            id: coalitionID,
            excluding: getpid(),
            gracePeriodSeconds: 0,
            killWaitSeconds: 1
        )
        try LaunchdProcessCoalition.verifyEmpty(
            id: coalitionID,
            excluding: getpid(),
            waitSeconds: 1
        )
        return true
    }

    private static func prePayloadDomain(
        label: String,
        coalitionID: UInt64
    ) throws -> String {
        var matchingDomain: String?
        let control = LaunchdControlClient()
        for domain in LaunchdControlClient.domains {
            switch try control.presence(domain: domain, label: label) {
            case .absent:
                break
            case .present(let job):
                // The coalition is proven against the kernel for this very
                // process; launchd's coalition block, when the running macOS
                // release publishes one, must agree with it.
                guard matchingDomain == nil,
                      job.state != "not running",
                      job.pid == getpid(),
                      LaunchdProcessCoalition.resourceID(for: getpid()) == coalitionID,
                      Self.launchdCoalitionCorroborates(job, expected: coalitionID) else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                matchingDomain = domain
            case .unknown:
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        }
        guard let matchingDomain else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        return matchingDomain
    }

    /// Reports whether launchd's own coalition record contradicts `expected`.
    ///
    /// `launchctl print` publishes a coalition block only on macOS releases that
    /// expose one. A published coalition must agree with the coalition the
    /// kernel reported for the same process; an omitted block states nothing and
    /// therefore contradicts nothing. Callers must have proven the coalition
    /// against `LaunchdProcessCoalition.resourceID(for:)` before relying on this.
    private static func launchdCoalitionCorroborates(
        _ job: LaunchdJobSnapshot,
        expected: UInt64
    ) -> Bool {
        guard let reportedCoalitionID = job.resourceCoalitionID else { return true }
        return reportedCoalitionID == expected
    }

    static func matches(lease: LaunchdProcessLease) -> Bool {
        guard validatesStructure(of: lease) else { return false }
        let directoryURL = URL(fileURLWithPath: lease.directoryPath, isDirectory: true)
        guard let identity = try? executionDirectoryIdentity(at: directoryURL),
              identity.device == lease.directoryDevice,
              identity.inode == lease.directoryInode else {
            return false
        }
        return true
    }

    static func emergencyCleanup(lease: LaunchdProcessLease) throws {
        guard validatesStructure(of: lease) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let directoryURL = URL(fileURLWithPath: lease.directoryPath, isDirectory: true)
        let expectedIdentity = LaunchdArtifactIdentity(
            device: lease.directoryDevice,
            inode: lease.directoryInode
        )
        let directoryLock: LaunchdOwnedFileDescriptor?
        let rawDirectory = Darwin.open(
            directoryURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        if rawDirectory >= 0 {
            _ = Darwin.close(rawDirectory)
            guard let acquiredLock = try acquireExecutionDirectoryLock(at: directoryURL)
            else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            var status = stat()
            guard fstat(acquiredLock.rawValue, &status) == 0,
                  LaunchdArtifactIdentity(
                      device: UInt64(truncatingIfNeeded: status.st_dev),
                      inode: UInt64(truncatingIfNeeded: status.st_ino)
                  ) == expectedIdentity else {
                acquiredLock.close()
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            directoryLock = acquiredLock
        } else if errno == ENOENT {
            directoryLock = nil
        } else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open emergency-cleanup directory",
                code: errno
            )
        }
        defer { directoryLock?.close() }

        guard let directoryLock else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                "execution metadata disappeared before client fallback cleanup"
            )
        }
        let metadata = try persistedMetadata(
            directoryURL: directoryURL,
            directoryDescriptor: directoryLock.rawValue
        )
        guard metadata.label == lease.label,
              metadata.directoryIdentity == expectedIdentity else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        guard let state = metadata.state else {
            guard lease.domain == nil, lease.coalitionID == nil else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            let uncertainties = LaunchdControlClient().nonOwnerDomainUncertainties(
                ownerDomain: nil,
                label: lease.label
            )
            guard uncertainties.isEmpty else {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    uncertainties.joined(separator: "; ")
                )
            }
            try removeVerified(
                directoryURL: directoryURL,
                expectedIdentity: expectedIdentity
            )
            return
        }
        guard lease.isConsistent(with: state) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        let currentBootIdentity = try LaunchdBootIdentity.current()
        let currentLegacyBootIdentity = try? LaunchdBootIdentity.currentLegacyBootTime()
        let bootScope = state.bootScope(
            currentBootIdentity: currentBootIdentity,
            currentLegacyBootIdentity: currentLegacyBootIdentity
        )
        guard bootScope != .differentBoot else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        let control = LaunchdControlClient()
        let ownerEvidence = control.ownerCleanupEvidence(
            domain: state.domain,
            label: state.label,
            expectedCoalitionID: state.coalitionID
        )
        if bootScope == .unverifiable {
            guard case .matching(let snapshot) = ownerEvidence,
                  jobCorroborates(
                      state: state,
                      snapshot: snapshot,
                      bootScope: bootScope
                  ) else {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    "legacy execution state could not be corroborated by its launchd job"
                )
            }
        }

        var uncertainties: [String] = []
        var permitsBootout = ownerEvidence.permitsBootoutAttempt
        switch ownerEvidence {
        case .matching(let snapshot):
            guard jobCorroborates(
                state: state,
                snapshot: snapshot,
                bootScope: bootScope
            ) else {
                permitsBootout = false
                uncertainties.append("owner launchd job identity contradicted persisted state")
                break
            }
        case .conflicting(let detail):
            uncertainties.append(detail)
        case .unknown(let detail):
            uncertainties.append(detail)
        case .absent:
            break
        }
        try terminateAuthoritativeExecution(
            state: state,
            permitsBootout: permitsBootout,
            uncertainties: uncertainties,
            control: control
        )
        let foreignUncertainties = control.nonOwnerDomainUncertainties(
            ownerDomain: state.domain,
            label: state.label
        )
        guard foreignUncertainties.isEmpty else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                foreignUncertainties.joined(separator: "; ")
            )
        }
        try removeVerified(
            directoryURL: directoryURL,
            expectedIdentity: expectedIdentity
        )
    }

    /// Decides whether an owner-domain launchd record corroborates persisted state.
    ///
    /// The coalition evidence is ranked by how strong it is, never skipped:
    /// a coalition published by launchd must equal the persisted one; when the
    /// running macOS release publishes no coalition block, the kernel answers
    /// for the pid launchd reported; and when launchd reports no process at all
    /// there is nothing left to interrogate, so the persisted state must prove
    /// it belongs to this boot. That last requirement is what stops a record
    /// left by a previous boot from authorising the termination of a coalition
    /// ID that the current boot may have handed to an unrelated coalition.
    private static func jobCorroborates(
        state: LaunchdPersistedExecutionState,
        snapshot: LaunchdJobSnapshot,
        bootScope: LaunchdPersistedBootScope
    ) -> Bool {
        if let reportedCoalitionID = snapshot.resourceCoalitionID {
            guard reportedCoalitionID == state.coalitionID else { return false }
        }
        if snapshot.state == "not running" {
            if snapshot.resourceCoalitionID != nil { return true }
            guard let reportedPID = snapshot.pid,
                  let observedCoalitionID = LaunchdProcessCoalition.resourceID(
                      for: reportedPID
                  ) else {
                // A stopped job leaves no process to interrogate: either launchd
                // published no pid, or it published a stale one the kernel can no
                // longer resolve. Neither is a contradiction, so corroboration
                // falls to the persisted state proving it belongs to this boot —
                // treating it as a mismatch would strand a cleanly finished
                // execution as permanently unverifiable.
                return bootScope == .current
            }
            return observedCoalitionID == state.coalitionID
        }
        guard snapshot.pid == state.supervisorIdentity.pid,
              let supervisor = LaunchdProcessSnapshot.current(
                  for: state.supervisorIdentity.pid
              ) else {
            return false
        }
        return supervisor.identity == state.supervisorIdentity
            && supervisor.isLive
            && LaunchdProcessCoalition.resourceID(for: supervisor.identity.pid)
                == state.coalitionID
    }

    private static func terminateAuthoritativeExecution(
        state: LaunchdPersistedExecutionState,
        permitsBootout: Bool,
        uncertainties: [String],
        control: LaunchdControlClient
    ) throws {
        var failures = uncertainties
        if permitsBootout {
            do {
                try control.removeJob(domain: state.domain, label: state.label)
            } catch {
                let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                    ?? error.localizedDescription
                failures.append("owner domain \(state.domain): \(detail)")
            }
        }
        do {
            try LaunchdProcessCoalition.terminateMembers(
                id: state.coalitionID,
                excluding: getpid(),
                gracePeriodSeconds: 0,
                killWaitSeconds: 1
            )
            try LaunchdProcessCoalition.verifyEmpty(
                id: state.coalitionID,
                waitSeconds: 1
            )
        } catch {
            let detail = (error as? BoundedProcessRunnerError)?.diagnosticDescription
                ?? error.localizedDescription
            failures.append("coalition \(state.coalitionID): \(detail)")
        }
        guard failures.isEmpty else {
            throw BoundedProcessRunnerError.secureCleanupUnverified(
                failures.joined(separator: "; ")
            )
        }
    }

    private static func validatesStructure(of lease: LaunchdProcessLease) -> Bool {
        let directoryURL = URL(fileURLWithPath: lease.directoryPath, isDirectory: true)
        guard contains(directoryURL: directoryURL) else { return false }
        let component = directoryURL.lastPathComponent
        let identifier = String(component.dropFirst("\(directoryPrefix).".count))
        return lease.label == "\(labelPrefix).\(identifier)"
              && (lease.coalitionID.map { $0 != 0 } ?? true)
              && (lease.domain.map { LaunchdControlClient.domains.contains($0) } ?? true)
              && (lease.domain == nil) == (lease.coalitionID == nil)
              && lease.directoryDevice != 0
              && lease.directoryInode != 0
    }

    static func reconcileAbandonedExecutions() throws {
        try ensurePrivateRoot()
        let executionGate = LaunchdLocalExecutionGate.shared
        let gateGeneration = try executionGate.reconciliationGeneration()
        var encounteredActiveExecutions = false
        let currentBootIdentity = try LaunchdBootIdentity.current()
        let currentLegacyBootIdentity = try? LaunchdBootIdentity.currentLegacyBootTime()
        let entries = try FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for directoryURL in entries {
            if directoryURL.lastPathComponent == LaunchdLocalExecutionGate.stateFileName {
                try executionGate.validatePersistedState()
                continue
            }
            guard isPrivateExecutionDirectory(at: directoryURL),
                  contains(directoryURL: directoryURL)
                    || containsStaging(directoryURL: directoryURL)
                    || containsCleanup(directoryURL: directoryURL) else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            guard let directoryLock = try acquireExecutionDirectoryLock(
                at: directoryURL
            ) else {
                encounteredActiveExecutions = true
                continue
            }
            defer { directoryLock.close() }
            let directoryIdentity = try executionDirectoryIdentity(at: directoryURL)
            if containsCleanup(directoryURL: directoryURL) {
                try removeCleanupVerified(
                    directoryURL: directoryURL,
                    expectedIdentity: directoryIdentity
                )
                continue
            }
            if containsStaging(directoryURL: directoryURL) {
                try removeStagingVerified(
                    directoryURL: directoryURL,
                    expectedIdentity: directoryIdentity
                )
                continue
            }

            let metadata = try persistedMetadata(
                directoryURL: directoryURL,
                directoryDescriptor: directoryLock.rawValue
            )
            if let owner = LaunchdProcessSnapshot.current(for: metadata.owner.pid),
               owner.identity == metadata.owner,
               owner.isLive {
                encounteredActiveExecutions = true
                continue
            }

            let control = LaunchdControlClient()
            guard let state = metadata.state else {
                let uncertainties = control.nonOwnerDomainUncertainties(
                    ownerDomain: nil,
                    label: metadata.label
                )
                guard uncertainties.isEmpty else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        uncertainties.joined(separator: "; ")
                    )
                }
                try removeVerified(
                    directoryURL: directoryURL,
                    expectedIdentity: metadata.directoryIdentity
                )
                continue
            }

            let bootScope = state.bootScope(
                currentBootIdentity: currentBootIdentity,
                currentLegacyBootIdentity: currentLegacyBootIdentity
            )
            let ownerEvidence = control.ownerCleanupEvidence(
                domain: state.domain,
                label: state.label,
                expectedCoalitionID: state.coalitionID
            )
            if bootScope == .differentBoot {
                let foreignUncertainties = control.nonOwnerDomainUncertainties(
                    ownerDomain: state.domain,
                    label: state.label
                )
                guard case .absent = ownerEvidence,
                      foreignUncertainties.isEmpty else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                try removeVerified(
                    directoryURL: directoryURL,
                    expectedIdentity: metadata.directoryIdentity
                )
                continue
            }

            if bootScope == .unverifiable {
                if case .matching(let snapshot) = ownerEvidence,
                   jobCorroborates(
                       state: state,
                       snapshot: snapshot,
                       bootScope: bootScope
                   ) {
                    // A matching live launchd record safely migrates legacy state.
                } else if case .absent = ownerEvidence {
                    let foreignUncertainties = control.nonOwnerDomainUncertainties(
                        ownerDomain: state.domain,
                        label: state.label
                    )
                    guard foreignUncertainties.isEmpty else {
                        throw BoundedProcessRunnerError.secureCleanupUnverified(
                            foreignUncertainties.joined(separator: "; ")
                        )
                    }
                    do {
                        try LaunchdProcessCoalition.verifyEmpty(
                            id: state.coalitionID,
                            waitSeconds: 0.1
                        )
                    } catch {
                        let detail = (error as? BoundedProcessRunnerError)?
                            .diagnosticDescription ?? error.localizedDescription
                        throw BoundedProcessRunnerError.secureCleanupUnverified(
                            "legacy execution state remained unverifiable: \(detail)"
                        )
                    }
                    try removeVerified(
                        directoryURL: directoryURL,
                        expectedIdentity: metadata.directoryIdentity
                    )
                    continue
                } else {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "legacy execution state could not be corroborated safely"
                    )
                }
            }

            var uncertainties: [String] = []
            var permitsBootout = ownerEvidence.permitsBootoutAttempt
            switch ownerEvidence {
            case .matching(let snapshot):
                guard jobCorroborates(
                    state: state,
                    snapshot: snapshot,
                    bootScope: bootScope
                ) else {
                    permitsBootout = false
                    uncertainties.append(
                        "owner launchd job identity contradicted persisted state"
                    )
                    break
                }
            case .conflicting(let detail):
                uncertainties.append(detail)
            case .unknown(let detail):
                uncertainties.append(detail)
            case .absent:
                break
            }
            try terminateAuthoritativeExecution(
                state: state,
                permitsBootout: permitsBootout,
                uncertainties: uncertainties,
                control: control
            )
            let foreignUncertainties = control.nonOwnerDomainUncertainties(
                ownerDomain: state.domain,
                label: state.label
            )
            guard foreignUncertainties.isEmpty else {
                throw BoundedProcessRunnerError.secureCleanupUnverified(
                    foreignUncertainties.joined(separator: "; ")
                )
            }
            try removeVerified(
                directoryURL: directoryURL,
                expectedIdentity: metadata.directoryIdentity
            )
        }
        try executionGate.clearAfterVerifiedReconciliation(
            expectedGeneration: gateGeneration,
            encounteredActiveExecutions: encounteredActiveExecutions
        )
    }

    static func removeVerified(
        directoryURL: URL,
        expectedIdentity: LaunchdArtifactIdentity
    ) throws {
        guard contains(directoryURL: directoryURL) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        try removeArtifactDirectoryVerified(
            directoryURL: directoryURL,
            expectedIdentity: expectedIdentity,
            includesRuntimeArtifacts: true
        )
    }

    private static func removeStagingVerified(
        directoryURL: URL,
        expectedIdentity: LaunchdArtifactIdentity
    ) throws {
        guard containsStaging(directoryURL: directoryURL) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        try removeArtifactDirectoryVerified(
            directoryURL: directoryURL,
            expectedIdentity: expectedIdentity,
            includesRuntimeArtifacts: false
        )
    }

    private static func removeCleanupVerified(
        directoryURL: URL,
        expectedIdentity: LaunchdArtifactIdentity
    ) throws {
        guard containsCleanup(directoryURL: directoryURL) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        try removeArtifactDirectoryVerified(
            directoryURL: directoryURL,
            expectedIdentity: expectedIdentity,
            includesRuntimeArtifacts: true
        )
    }

    private static func removeArtifactDirectoryVerified(
        directoryURL: URL,
        expectedIdentity: LaunchdArtifactIdentity,
        includesRuntimeArtifacts: Bool
    ) throws {
        let rootRawDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootRawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open launchd execution root",
                code: errno
            )
        }
        let rootDescriptor = LaunchdOwnedFileDescriptor(rootRawDescriptor)
        defer { rootDescriptor.close() }
        var rootStatus = stat()
        guard fstat(rootDescriptor.rawValue, &rootStatus) == 0,
              rootStatus.st_uid == geteuid(),
              rootStatus.st_mode & S_IFMT == S_IFDIR,
              rootStatus.st_mode & 0o777 == S_IRWXU else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let requestedComponent = directoryURL.lastPathComponent
        let cleanupComponent: String
        if containsCleanup(directoryURL: directoryURL) {
            cleanupComponent = requestedComponent
        } else {
            guard let separator = requestedComponent.firstIndex(of: ".") else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            let identifier = requestedComponent[requestedComponent.index(after: separator)...]
            cleanupComponent = "\(cleanupDirectoryPrefix).\(identifier)"
        }

        var openedComponent = requestedComponent
        var directoryRawDescriptor = Darwin.openat(
            rootDescriptor.rawValue,
            openedComponent,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        if directoryRawDescriptor < 0,
           errno == ENOENT,
           requestedComponent != cleanupComponent {
            openedComponent = cleanupComponent
            directoryRawDescriptor = Darwin.openat(
                rootDescriptor.rawValue,
                openedComponent,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard directoryRawDescriptor >= 0 else {
            if errno == ENOENT { return }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open launchd execution directory",
                code: errno
            )
        }
        let directoryDescriptor = LaunchdOwnedFileDescriptor(directoryRawDescriptor)
        defer { directoryDescriptor.close() }
        var directoryStatus = stat()
        guard fstat(directoryDescriptor.rawValue, &directoryStatus) == 0,
              isPrivateExecutionDirectory(status: directoryStatus),
              LaunchdArtifactIdentity(
                  device: UInt64(truncatingIfNeeded: directoryStatus.st_dev),
                  inode: UInt64(truncatingIfNeeded: directoryStatus.st_ino)
              ) == expectedIdentity else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        var allowedArtifactNames: Set<String> = ["job.plist"]
        if includesRuntimeArtifacts {
            allowedArtifactNames.insert(controlSocketName)
            allowedArtifactNames.insert(stateFileName)
            allowedArtifactNames.insert(pendingStateFileName)
        }
        try verifyOnlyKnownArtifacts(
            directoryDescriptor: directoryDescriptor.rawValue,
            allowedNames: allowedArtifactNames
        )

        if openedComponent != cleanupComponent {
            guard renameatx_np(
                rootDescriptor.rawValue,
                openedComponent,
                rootDescriptor.rawValue,
                cleanupComponent,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "quarantine launchd artifact directory",
                    code: errno
                )
            }
            var quarantinedStatus = stat()
            guard fstatat(
                rootDescriptor.rawValue,
                cleanupComponent,
                &quarantinedStatus,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
            LaunchdArtifactIdentity(
                device: UInt64(truncatingIfNeeded: quarantinedStatus.st_dev),
                inode: UInt64(truncatingIfNeeded: quarantinedStatus.st_ino)
            ) == expectedIdentity else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            try synchronizeDirectory(descriptor: rootDescriptor.rawValue)
        }

        try verifyOnlyKnownArtifacts(
            directoryDescriptor: directoryDescriptor.rawValue,
            allowedNames: allowedArtifactNames
        )

        if includesRuntimeArtifacts {
            try unlinkKnownArtifact(
                name: controlSocketName,
                directoryDescriptor: directoryDescriptor.rawValue,
                expectedType: S_IFSOCK,
                expectedPermissions: S_IRUSR | S_IWUSR
            )
            try unlinkKnownArtifact(
                name: pendingStateFileName,
                directoryDescriptor: directoryDescriptor.rawValue,
                expectedType: S_IFREG,
                expectedPermissions: S_IRUSR
            )
            try unlinkKnownArtifact(
                name: stateFileName,
                directoryDescriptor: directoryDescriptor.rawValue,
                expectedType: S_IFREG,
                expectedPermissions: S_IRUSR
            )
        }
        try unlinkKnownArtifact(
            name: "job.plist",
            directoryDescriptor: directoryDescriptor.rawValue,
            expectedType: S_IFREG,
            expectedPermissions: S_IRUSR
        )
        try synchronizeDirectory(descriptor: directoryDescriptor.rawValue)
        try verifyOnlyKnownArtifacts(
            directoryDescriptor: directoryDescriptor.rawValue,
            allowedNames: []
        )
        var linkedStatus = stat()
        guard fstatat(
            rootDescriptor.rawValue,
            cleanupComponent,
            &linkedStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: linkedStatus.st_dev),
            inode: UInt64(truncatingIfNeeded: linkedStatus.st_ino)
        ) == expectedIdentity,
        unlinkat(rootDescriptor.rawValue, cleanupComponent, AT_REMOVEDIR) == 0 else {
            let code = errno
            if code == ENOTEMPTY {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "remove launchd execution directory",
                code: code
            )
        }
        try synchronizeDirectory(descriptor: rootDescriptor.rawValue)
        guard fstatat(
            rootDescriptor.rawValue,
            cleanupComponent,
            &linkedStatus,
            AT_SYMLINK_NOFOLLOW
        ) == -1,
        errno == ENOENT else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }

    private static func unlinkKnownArtifact(
        name: String,
        directoryDescriptor: Int32,
        expectedType: mode_t,
        expectedPermissions: mode_t
    ) throws {
        var status = stat()
        guard fstatat(
            directoryDescriptor,
            name,
            &status,
            AT_SYMLINK_NOFOLLOW
        ) == 0 else {
            if errno == ENOENT { return }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "inspect launchd artifact",
                code: errno
            )
        }
        guard status.st_uid == geteuid(),
              status.st_mode & S_IFMT == expectedType,
              status.st_mode & 0o777 == expectedPermissions,
              status.st_nlink == 1,
              unlinkat(directoryDescriptor, name, 0) == 0 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }

    static func verifyOnlyKnownArtifacts(
        directoryDescriptor: Int32,
        allowedNames: Set<String>
    ) throws {
        let duplicate = Darwin.openat(
            directoryDescriptor,
            ".",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard duplicate >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "duplicate launchd artifact directory",
                code: errno
            )
        }
        guard let stream = fdopendir(duplicate) else {
            let code = errno
            _ = Darwin.close(duplicate)
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "enumerate launchd artifact directory",
                code: code
            )
        }
        defer { closedir(stream) }

        errno = 0
        while let entry = readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(entry.pointee.d_namlen) + 1
                ) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard allowedNames.contains(name) else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
        }
        guard errno == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read launchd artifact directory",
                code: errno
            )
        }
    }

    static func ensurePrivateRoot() throws {
        guard LaunchdProcessNamespace.current.isValid else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        if mkdir(rootURL.path, S_IRWXU) == -1, errno != EEXIST {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "mkdir launchd execution root",
                code: errno
            )
        }
        var status = stat()
        guard lstat(rootURL.path, &status) == 0,
              status.st_uid == getuid(),
              status.st_mode & S_IFMT == S_IFDIR,
              status.st_mode & 0o777 == S_IRWXU else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }

    private static func persistedMetadata(
        directoryURL: URL,
        directoryDescriptor: Int32
    ) throws -> (
        label: String,
        owner: LaunchdProcessIdentity,
        directoryIdentity: LaunchdArtifactIdentity,
        state: LaunchdPersistedExecutionState?
    ) {
        var directoryStatus = stat()
        guard fstat(directoryDescriptor, &directoryStatus) == 0,
              isPrivateExecutionDirectory(status: directoryStatus) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let directoryIdentity = LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: directoryStatus.st_dev),
            inode: UInt64(truncatingIfNeeded: directoryStatus.st_ino)
        )
        guard try executionDirectoryIdentity(at: directoryURL) == directoryIdentity else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        guard let data = try readPrivateArtifact(
            name: "job.plist",
            directoryDescriptor: directoryDescriptor,
            maximumBytes: 1 * 1_024 * 1_024
        ) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        guard let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
        let label = propertyList["Label"] as? String,
        let arguments = propertyList["ProgramArguments"] as? [String],
        arguments.count == 6,
        arguments[1] == LaunchdProcessSupervisorEntry.modeArgument,
        arguments[2] == directoryURL.appendingPathComponent(controlSocketName).path,
        let pid = pid_t(arguments[3]),
        pid > 1,
        let startSeconds = UInt64(arguments[4]),
        let startMicroseconds = UInt64(arguments[5]) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let expectedLease = LaunchdProcessLease(
            label: label,
            domain: nil,
            coalitionID: nil,
            directoryPath: directoryURL.path,
            directoryDevice: directoryIdentity.device,
            directoryInode: directoryIdentity.inode
        )
        guard matches(lease: expectedLease) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let persistedState: LaunchdPersistedExecutionState?
        if let stateData = try readPrivateArtifact(
            name: stateFileName,
            directoryDescriptor: directoryDescriptor,
            maximumBytes: 1 * 1_024 * 1_024
        ) {
            let state = try PropertyListDecoder().decode(
                LaunchdPersistedExecutionState.self,
                from: stateData
            )
            guard state.label == label,
                  LaunchdControlClient.domains.contains(state.domain),
                  state.coalitionID != 0,
                  state.supervisorIdentity.pid > 1,
                  state.directoryDevice == directoryIdentity.device,
                  state.directoryInode == directoryIdentity.inode,
                  state.payloadMayHaveRun else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            persistedState = state
        } else {
            persistedState = nil
        }
        return (
            label,
            LaunchdProcessIdentity(
                pid: pid,
                startSeconds: startSeconds,
                startMicroseconds: startMicroseconds
            ),
            directoryIdentity,
            persistedState
        )
    }

    private static func readPrivateArtifact(
        name: String,
        directoryDescriptor: Int32,
        maximumBytes: Int
    ) throws -> Data? {
        let rawDescriptor = Darwin.openat(
            directoryDescriptor,
            name,
            O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW
        )
        guard rawDescriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open launchd metadata",
                code: errno
            )
        }
        let descriptor = LaunchdOwnedFileDescriptor(rawDescriptor)
        defer { descriptor.close() }
        var status = stat()
        guard fstat(descriptor.rawValue, &status) == 0,
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & 0o777 == S_IRUSR,
              status.st_nlink == 1,
              status.st_size > 0,
              status.st_size <= maximumBytes else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        var data = Data()
        data.reserveCapacity(Int(status.st_size))
        var buffer = [UInt8](repeating: 0, count: 32 * 1_024)
        while true {
            let count = Darwin.read(descriptor.rawValue, &buffer, buffer.count)
            if count > 0 {
                guard data.count <= maximumBytes - count else {
                    throw BoundedProcessRunnerError.secureContainmentVerificationFailed
                }
                data.append(buffer, count: count)
                continue
            }
            if count == 0 { break }
            if errno == EINTR { continue }
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "read launchd metadata",
                code: errno
            )
        }
        guard data.count == Int(status.st_size) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        return data
    }

    private static func isPrivateExecutionDirectory(at url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0 && isPrivateExecutionDirectory(status: status)
    }

    private static func executionDirectoryIdentity(
        at url: URL
    ) throws -> LaunchdArtifactIdentity {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              isPrivateExecutionDirectory(status: status) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        return LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: status.st_dev),
            inode: UInt64(truncatingIfNeeded: status.st_ino)
        )
    }

    private static func isPrivateExecutionDirectory(status: stat) -> Bool {
        status.st_uid == getuid()
            && status.st_mode & S_IFMT == S_IFDIR
            && status.st_mode & 0o777 == S_IRWXU
    }

    private static func acquireExecutionDirectoryLock(
        at url: URL
    ) throws -> LaunchdOwnedFileDescriptor? {
        let descriptor = try openExecutionDirectory(at: url)
        if flock(descriptor.rawValue, LOCK_EX | LOCK_NB) == 0 {
            return descriptor
        }
        let code = errno
        descriptor.close()
        if code == EWOULDBLOCK { return nil }
        throw BoundedProcessRunnerError.systemCallFailed(
            operation: "lock launchd execution directory",
            code: code
        )
    }

    private static func openExecutionDirectory(
        at url: URL
    ) throws -> LaunchdOwnedFileDescriptor {
        let rawDescriptor = Darwin.open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open launchd execution directory lock",
                code: errno
            )
        }
        let descriptor = LaunchdOwnedFileDescriptor(rawDescriptor)
        var status = stat()
        guard fstat(descriptor.rawValue, &status) == 0,
              isPrivateExecutionDirectory(status: status) else {
            descriptor.close()
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        return descriptor
    }

    private static func synchronizeDirectory(descriptor: Int32) throws {
        var status = stat()
        guard descriptor >= 0,
              fstat(descriptor, &status) == 0,
              isPrivateExecutionDirectory(status: status) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        guard fsync(descriptor) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "synchronize launchd directory",
                code: errno
            )
        }
    }

    private static func publishStagingDirectory(
        _ stagingURL: URL,
        as directoryURL: URL,
        expectedIdentity: LaunchdArtifactIdentity
    ) throws {
        guard containsStaging(directoryURL: stagingURL),
              contains(directoryURL: directoryURL) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let rootRawDescriptor = Darwin.open(
            rootURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard rootRawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "open launchd root for publication",
                code: errno
            )
        }
        let rootDescriptor = LaunchdOwnedFileDescriptor(rootRawDescriptor)
        defer { rootDescriptor.close() }
        var rootStatus = stat()
        guard fstat(rootDescriptor.rawValue, &rootStatus) == 0,
              isPrivateExecutionDirectory(status: rootStatus) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        let stagingComponent = stagingURL.lastPathComponent
        let directoryComponent = directoryURL.lastPathComponent
        var linkedStatus = stat()
        guard fstatat(
            rootDescriptor.rawValue,
            stagingComponent,
            &linkedStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0,
        LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: linkedStatus.st_dev),
            inode: UInt64(truncatingIfNeeded: linkedStatus.st_ino)
        ) == expectedIdentity else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }

        var wasRenamed = false
        do {
            guard renameatx_np(
                rootDescriptor.rawValue,
                stagingComponent,
                rootDescriptor.rawValue,
                directoryComponent,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "publish launchd execution directory",
                    code: errno
                )
            }
            wasRenamed = true
            guard fstatat(
                rootDescriptor.rawValue,
                directoryComponent,
                &linkedStatus,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
            LaunchdArtifactIdentity(
                device: UInt64(truncatingIfNeeded: linkedStatus.st_dev),
                inode: UInt64(truncatingIfNeeded: linkedStatus.st_ino)
            ) == expectedIdentity else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            try synchronizeDirectory(descriptor: rootDescriptor.rawValue)
        } catch {
            if wasRenamed {
                do {
                    try removeArtifactDirectoryVerified(
                        directoryURL: directoryURL,
                        expectedIdentity: expectedIdentity,
                        includesRuntimeArtifacts: true
                    )
                } catch let cleanupError {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "launchd artifact publication cleanup failed after "
                            + "\(errorDetail(error)): \(errorDetail(cleanupError))"
                    )
                }
            }
            throw error
        }
    }

    private static func createControlListener(
        at url: URL
    ) throws -> (LaunchdOwnedFileDescriptor, LaunchdArtifactIdentity) {
        guard contains(controlSocketURL: url) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let rawDescriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard rawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "create launchd control socket",
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
                    operation: "configure launchd control socket",
                    code: errno
                )
            }
            var address = try socketAddress(path: url.path)
            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(
                        descriptor.rawValue,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                }
            }
            guard bindResult == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "bind launchd control socket",
                    code: errno
                )
            }
            guard chmod(url.path, S_IRUSR | S_IWUSR) == 0,
                  Darwin.listen(descriptor.rawValue, 4) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "listen on launchd control socket",
                    code: errno
                )
            }
            return (descriptor, try controlSocketIdentity(at: url))
        } catch {
            descriptor.close()
            _ = Darwin.unlink(url.path)
            throw error
        }
    }

    private static func controlSocketIdentity(at url: URL) throws -> LaunchdArtifactIdentity {
        guard contains(controlSocketURL: url) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        var status = stat()
        guard lstat(url.path, &status) == 0,
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFSOCK,
              status.st_mode & 0o777 == (S_IRUSR | S_IWUSR),
              status.st_nlink == 1 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        return LaunchdArtifactIdentity(
            device: UInt64(truncatingIfNeeded: status.st_dev),
            inode: UInt64(truncatingIfNeeded: status.st_ino)
        )
    }

    private func unlinkVerifiedControlSocket() throws {
        guard try Self.controlSocketIdentity(at: controlSocketURL) == controlSocketIdentity,
              Darwin.unlink(controlSocketURL.path) == 0 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
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

    private static func currentExecutableURL() throws -> URL {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else {
            throw BoundedProcessRunnerError.secureContainmentUnavailable
        }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            throw BoundedProcessRunnerError.secureContainmentUnavailable
        }
        let url = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
        if url.lastPathComponent == "CocxyTerminal",
           FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        for argument in CommandLine.arguments {
            guard let range = argument.range(of: ".xctest") else { continue }
            let bundlePath = String(argument[..<range.upperBound])
            let candidate = URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .appendingPathComponent("CocxyTerminal")
                .resolvingSymlinksInPath()
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw BoundedProcessRunnerError.secureContainmentUnavailable
    }

    private static func writeExclusiveFile(
        _ data: Data,
        named name: String,
        directoryDescriptor: Int32,
        permissions: mode_t
    ) throws {
        guard !name.isEmpty, !name.contains("/"), directoryDescriptor >= 0 else {
            throw BoundedProcessRunnerError.invalidInvocation
        }
        let rawDescriptor = Darwin.openat(
            directoryDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            permissions
        )
        guard rawDescriptor >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "create launchd artifact",
                code: errno
            )
        }
        let descriptor = LaunchdOwnedFileDescriptor(rawDescriptor)
        defer { descriptor.close() }
        var status = stat()
        guard fstat(descriptor.rawValue, &status) == 0,
              status.st_uid == geteuid(),
              status.st_mode & S_IFMT == S_IFREG,
              status.st_mode & 0o777 == permissions,
              status.st_nlink == 1 else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        try writeAll(data, to: descriptor.rawValue, operation: "write launchd artifact")
        guard fsync(descriptor.rawValue) == 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "fsync launchd artifact",
                code: errno
            )
        }
    }

    private static func writeAtomicFile(
        _ data: Data,
        finalName: String,
        pendingName: String,
        directoryDescriptor: Int32,
        permissions: mode_t
    ) throws {
        var published = false
        do {
            try writeExclusiveFile(
                data,
                named: pendingName,
                directoryDescriptor: directoryDescriptor,
                permissions: permissions
            )
            guard renameatx_np(
                directoryDescriptor,
                pendingName,
                directoryDescriptor,
                finalName,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "publish launchd state",
                    code: errno
                )
            }
            published = true
            var status = stat()
            guard fstatat(
                directoryDescriptor,
                finalName,
                &status,
                AT_SYMLINK_NOFOLLOW
            ) == 0,
            status.st_uid == geteuid(),
            status.st_mode & S_IFMT == S_IFREG,
            status.st_mode & 0o777 == permissions,
            status.st_nlink == 1 else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            try synchronizeDirectory(descriptor: directoryDescriptor)
        } catch let originalError {
            if !published {
                do {
                    try unlinkKnownArtifact(
                        name: pendingName,
                        directoryDescriptor: directoryDescriptor,
                        expectedType: S_IFREG,
                        expectedPermissions: permissions
                    )
                    try synchronizeDirectory(descriptor: directoryDescriptor)
                } catch {
                    throw BoundedProcessRunnerError.secureCleanupUnverified(
                        "launchd pending-state cleanup failed after "
                            + "\(errorDetail(originalError)): \(errorDetail(error))"
                    )
                }
            }
            throw originalError
        }
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        operation: String
    ) throws {
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
                    continue
                }
                if count == -1, errno == EINTR { continue }
                throw BoundedProcessRunnerError.systemCallFailed(operation: operation, code: errno)
            }
        }
    }

    private static func errorDetail(_ error: Error) -> String {
        (error as? BoundedProcessRunnerError)?.diagnosticDescription
            ?? error.localizedDescription
    }
}

enum LaunchdJobPresence: Equatable {
    case absent
    case present(LaunchdJobSnapshot)
    case unknown(exitCode: Int32)
}

struct LaunchdControlClient {
    private static let launchctlURL = URL(fileURLWithPath: "/bin/launchctl")
    private static let maximumControlOutputBytes = 4 * 1_024 * 1_024
    private static let commandTimeoutSeconds: TimeInterval = 3
    private static let absentExitCode: Int32 = 113
    static let domains = ["gui/\(getuid())", "user/\(getuid())"]

    func bootstrap(
        label: String,
        propertyListURL: URL,
        boundary: LaunchdExecutionBoundary
    ) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: Self.launchctlURL.path) else {
            throw BoundedProcessRunnerError.secureContainmentUnavailable
        }
        var lastExitCode: Int32 = 1
        for domain in Self.domains {
            let result = try execute(
                ["bootstrap", domain, propertyListURL.path],
                timeoutSeconds: boundary.remainingSeconds(maximum: Self.commandTimeoutSeconds),
                observesTaskCancellation: false,
                externalCancellationRequested: boundary.cancellationRequested
            )
            if result.exitCode == 0 { return domain }
            lastExitCode = result.exitCode
            do {
                try removeJob(domain: domain, label: label)
            } catch {
                throw BoundedProcessRunnerError.contextual(
                    "launchd bootstrap rollback",
                    error: error
                )
            }
            if result.timedOut { try boundary.check() }
        }
        throw BoundedProcessRunnerError.launchdCommandFailed(
            operation: "launchd bootstrap",
            exitCode: lastExitCode
        )
    }

    func snapshot(
        domain: String,
        label: String,
        boundary: LaunchdExecutionBoundary? = nil
    ) throws -> LaunchdJobSnapshot {
        if let boundary { try boundary.check() }
        let timeout = try boundary?.remainingSeconds(maximum: Self.commandTimeoutSeconds)
            ?? Self.commandTimeoutSeconds
        let cancellationRequested: @Sendable () -> Bool = if let boundary {
            { boundary.cancellationRequested() }
        } else {
            { false }
        }
        let result = try execute(
            ["print", "\(domain)/\(label)"],
            timeoutSeconds: timeout,
            observesTaskCancellation: false,
            externalCancellationRequested: cancellationRequested
        )
        if result.timedOut, let boundary { try boundary.check() }
        guard result.exitCode == 0, let snapshot = LaunchdJobSnapshot(output: result.stdout) else {
            throw BoundedProcessRunnerError.launchdCommandFailed(
                operation: "launchd status (stdout \(result.stdout.utf8.count), stderr \(result.stderr.utf8.count))",
                exitCode: result.exitCode
            )
        }
        return snapshot
    }

    func presence(domain: String, label: String, timeoutSeconds: TimeInterval = 1) throws
        -> LaunchdJobPresence {
        let result = try execute(
            ["print", "\(domain)/\(label)"],
            timeoutSeconds: timeoutSeconds,
            observesTaskCancellation: false,
            externalCancellationRequested: { false }
        )
        return Self.classifyPresence(result)
    }

    static func classifyPresence(_ result: BoundedProcessResult) -> LaunchdJobPresence {
        if result.timedOut { return .unknown(exitCode: result.exitCode) }
        if result.exitCode == Self.absentExitCode { return .absent }
        if result.exitCode == 0, let snapshot = LaunchdJobSnapshot(output: result.stdout) {
            return .present(snapshot)
        }
        return .unknown(exitCode: result.exitCode)
    }

    func ownerCleanupEvidence(
        domain: String,
        label: String,
        expectedCoalitionID: UInt64
    ) -> LaunchdOwnedJobEvidence {
        guard Self.domains.contains(domain) else {
            return .unknown("owner domain is outside cleanup authority")
        }

        do {
            switch try presence(domain: domain, label: label) {
            case .absent:
                return .absent
            case .present(let snapshot):
                return Self.coalitionEvidence(
                    for: snapshot,
                    expectedCoalitionID: expectedCoalitionID
                )
            case .unknown(let exitCode):
                return .unknown(
                    "owner domain presence was indeterminate (exit \(exitCode))"
                )
            }
        } catch {
            return .unknown(
                "owner domain inspection failed: \(Self.errorDetail(error))"
            )
        }
    }

    /// Weighs a present owner job against the coalition the caller expects.
    ///
    /// `launchctl print` publishes a coalition block only on macOS releases that
    /// expose one, so a missing block is an absence of testimony, never a
    /// contradiction. The kernel is asked about the very pid launchd reported,
    /// which is at least as strong as the field it replaces. When launchd
    /// reports no process either, the record carries no coalition testimony at
    /// all: it is still the owner job for this unique label, and corroborating
    /// it is left to the caller, which weighs the persisted state's boot scope
    /// before permitting any bootout.
    private static func coalitionEvidence(
        for snapshot: LaunchdJobSnapshot,
        expectedCoalitionID: UInt64
    ) -> LaunchdOwnedJobEvidence {
        if let reportedCoalitionID = snapshot.resourceCoalitionID {
            guard reportedCoalitionID == expectedCoalitionID else {
                return .conflicting(
                    "owner domain coalition mismatch (expected "
                        + "\(expectedCoalitionID), observed \(reportedCoalitionID))"
                )
            }
            return .matching(snapshot)
        }
        // No live process to interrogate: launchd either published no pid, or
        // published one the kernel can no longer resolve because the supervisor
        // already exited. Both are the same absence of testimony, never a
        // contradiction — a finished execution must stay reconcilable. The
        // caller corroborates these records through `jobCorroborates`, which
        // requires the persisted state to belong to this boot.
        guard let reportedPID = snapshot.pid,
              let kernelCoalitionID = LaunchdProcessCoalition.resourceID(
                  for: reportedPID
              ) else {
            return .matching(snapshot)
        }
        guard kernelCoalitionID == expectedCoalitionID else {
            return .conflicting(
                "owner domain coalition mismatch (expected "
                    + "\(expectedCoalitionID), observed \(kernelCoalitionID))"
            )
        }
        return .matching(snapshot)
    }

    func nonOwnerDomainUncertainties(
        ownerDomain: String?,
        label: String
    ) -> [String] {
        var uncertainties: [String] = []
        for domain in Self.domains where domain != ownerDomain {
            do {
                switch try presence(domain: domain, label: label) {
                case .absent:
                    break
                case .present(let snapshot):
                    let coalition = snapshot.resourceCoalitionID.map { String($0) }
                        ?? "unknown"
                    uncertainties.append(
                        "\(domain): unexpected job remained in coalition \(coalition)"
                    )
                case .unknown(let exitCode):
                    uncertainties.append(
                        "\(domain): job presence remained indeterminate (exit \(exitCode))"
                    )
                }
            } catch {
                uncertainties.append("\(domain): \(Self.errorDetail(error))")
            }
        }
        return uncertainties
    }

    func removeJob(domain: String, label: String) throws {
        guard Self.domains.contains(domain) else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
        let deadline = LaunchdMonotonicClock.adding(
            seconds: Self.commandTimeoutSeconds,
            to: LaunchdMonotonicClock.now()
        )
        var lastUnknownExitCode: Int32?
        while LaunchdMonotonicClock.now() < deadline {
            switch try presence(domain: domain, label: label, timeoutSeconds: 0.5) {
            case .absent:
                return
            case .present:
                break
            case .unknown(let exitCode):
                lastUnknownExitCode = exitCode
            }
            if let result = try? execute(
                ["bootout", "\(domain)/\(label)"],
                timeoutSeconds: 1,
                observesTaskCancellation: false,
                externalCancellationRequested: { false }
            ), result.exitCode != 0 {
                lastUnknownExitCode = result.exitCode
            }
            usleep(10_000)
        }
        throw BoundedProcessRunnerError.launchdCommandFailed(
            operation: "launchd verified bootout",
            exitCode: lastUnknownExitCode ?? 1
        )
    }

    private static func errorDetail(_ error: Error) -> String {
        (error as? BoundedProcessRunnerError)?.diagnosticDescription
            ?? error.localizedDescription
    }

    private func execute(
        _ arguments: [String],
        timeoutSeconds: TimeInterval,
        observesTaskCancellation: Bool,
        externalCancellationRequested: @escaping @Sendable () -> Bool
    ) throws -> BoundedProcessResult {
        try BoundedProcessRunner(
            maximumRetainedBytesPerStream: Self.maximumControlOutputBytes,
            observesTaskCancellation: observesTaskCancellation,
            externalCancellationRequested: externalCancellationRequested
        ).run(
            executableURL: Self.launchctlURL,
            arguments: arguments,
            workingDirectory: URL(fileURLWithPath: "/", isDirectory: true),
            timeoutSeconds: timeoutSeconds
        )
    }
}

struct LaunchdJobSnapshot: Equatable {
    let state: String?
    let pid: pid_t?
    let runCount: Int?
    let resourceCoalitionID: UInt64?
    let exitCode: Int32?
    let terminatingSignal: Int32?

    init?(output: String) {
        var state: String?
        var pid: pid_t?
        var runCount: Int?
        var resourceCoalitionID: UInt64?
        var exitCode: Int32?
        var terminatingSignal: Int32?
        var inResourceCoalition = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "resource coalition = {" {
                inResourceCoalition = true
                continue
            }
            if line.hasSuffix("coalition = {") {
                inResourceCoalition = false
                continue
            }
            if line == "}" {
                inResourceCoalition = false
                continue
            }
            if inResourceCoalition,
               line.hasPrefix("ID = "),
               let value = UInt64(line.dropFirst(5)) {
                resourceCoalitionID = value
                continue
            }
            if line.hasPrefix("resource coalition ID = "),
               let value = UInt64(line.dropFirst(24)) {
                resourceCoalitionID = value
            } else if state == nil, line.hasPrefix("state = ") {
                state = String(line.dropFirst(8))
            } else if pid == nil, line.hasPrefix("pid = ") {
                pid = pid_t(line.dropFirst(6))
            } else if runCount == nil, line.hasPrefix("runs = ") {
                runCount = Int(line.dropFirst(7))
            } else if line.hasPrefix("last exit code = ") {
                exitCode = Int32(line.dropFirst(17))
            } else if line.hasPrefix("last terminating signal = ") {
                terminatingSignal = line
                    .split(whereSeparator: { $0.isWhitespace })
                    .last
                    .flatMap { Int32($0) }
            }
        }

        guard state != nil
            || pid != nil
            || runCount != nil
            || resourceCoalitionID != nil
            || exitCode != nil
            || terminatingSignal != nil else {
            return nil
        }
        self.state = state
        self.pid = pid
        self.runCount = runCount
        self.resourceCoalitionID = resourceCoalitionID
        self.exitCode = exitCode
        self.terminatingSignal = terminatingSignal
    }
}

struct LaunchdProcessIdentity: Codable, Equatable, Hashable, Sendable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct LaunchdProcessSnapshot {
    let identity: LaunchdProcessIdentity
    let userID: uid_t
    let status: UInt32

    var isLive: Bool { status != UInt32(SZOMB) }

    static func current(for pid: pid_t) -> LaunchdProcessSnapshot? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout.size(ofValue: info))
        var result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
        if result != expectedSize {
            result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 1, &info, expectedSize)
        }
        guard result == expectedSize else { return nil }
        return LaunchdProcessSnapshot(
            identity: LaunchdProcessIdentity(
                pid: pid,
                startSeconds: UInt64(info.pbi_start_tvsec),
                startMicroseconds: UInt64(info.pbi_start_tvusec)
            ),
            userID: info.pbi_uid,
            status: info.pbi_status
        )
    }

    static func allProcessIDs() throws -> [pid_t] {
        var capacity = max(
            Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0))
                / MemoryLayout<pid_t>.stride + 64,
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
                return Array(pids.prefix(count).filter { $0 > 0 })
            }
            capacity *= 2
        }
        throw BoundedProcessRunnerError.systemCallFailed(
            operation: "proc_listpids",
            code: EOVERFLOW
        )
    }
}

enum LaunchdPeerAuthenticator {
    static func verify(
        descriptor: Int32,
        expectedIdentity: LaunchdProcessIdentity
    ) throws {
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        var peerPID: pid_t = 0
        var peerPIDLength = socklen_t(MemoryLayout<pid_t>.size)
        guard descriptor >= 0,
              getpeereid(descriptor, &peerUID, &peerGID) == 0,
              peerUID == geteuid(),
              getsockopt(
                  descriptor,
                  SOL_LOCAL,
                  LOCAL_PEERPID,
                  &peerPID,
                  &peerPIDLength
              ) == 0,
              peerPID == expectedIdentity.pid,
              let snapshot = LaunchdProcessSnapshot.current(for: peerPID),
              snapshot.identity == expectedIdentity,
              snapshot.isLive else {
            throw BoundedProcessRunnerError.secureContainmentVerificationFailed
        }
    }
}

enum LaunchdProcessSignalAuthority: Equatable {
    case available
    case absent
    case denied
    case failed(Int32)
}

struct LaunchdCoalitionInspection {
    let processIDs: () throws -> [pid_t]
    let snapshot: (pid_t) -> LaunchdProcessSnapshot?
    let resourceID: (pid_t) -> UInt64?
    let signalAuthority: (pid_t) -> LaunchdProcessSignalAuthority
    let retryCount: Int
    let retryDelayMicroseconds: useconds_t

    static var system: LaunchdCoalitionInspection {
        LaunchdCoalitionInspection(
            processIDs: { try LaunchdProcessSnapshot.allProcessIDs() },
            snapshot: { LaunchdProcessSnapshot.current(for: $0) },
            resourceID: { LaunchdProcessCoalition.resourceID(for: $0) },
            signalAuthority: { pid in
                if Darwin.kill(pid, 0) == 0 { return .available }
                let code = errno
                switch code {
                case ESRCH:
                    return .absent
                case EPERM:
                    return .denied
                default:
                    return .failed(code)
                }
            },
            retryCount: 50,
            retryDelayMicroseconds: 1_000
        )
    }
}

enum LaunchdProcessCoalition {
    private static let coalitionInfoFlavor: Int32 = 20
    private static let stableEmptyPasses = 3
    private static let scanIntervalMicroseconds: useconds_t = 10_000

    static func resourceID(for pid: pid_t) -> UInt64? {
        var info = LaunchdRawCoalitionInfo()
        let expectedSize = Int32(MemoryLayout.size(ofValue: info))
        let result = proc_pidinfo(pid, coalitionInfoFlavor, 0, &info, expectedSize)
        guard result == expectedSize, info.resourceID != 0 else { return nil }
        return info.resourceID
    }

    static func liveMembers(
        id: UInt64,
        inspection: LaunchdCoalitionInspection = .system,
        deadline: UInt64? = nil
    ) throws -> [LaunchdProcessSnapshot] {
        try requireTimeRemaining(until: deadline)
        let processIDs = try inspection.processIDs()
        try requireTimeRemaining(until: deadline)
        var members: [LaunchdProcessSnapshot] = []
        for pid in processIDs {
            try requireTimeRemaining(until: deadline)
            guard let candidateResourceID = try candidateResourceID(
                for: pid,
                inspection: inspection,
                deadline: deadline
            ),
                  candidateResourceID == id else {
                continue
            }
            guard let observation = try stableMembership(
                for: pid,
                coalitionID: id,
                inspection: inspection,
                deadline: deadline
            ) else { continue }
            try requireTimeRemaining(until: deadline)
            if try validateLiveMember(
                observation.snapshot,
                observedResourceID: observation.resourceID,
                expectedResourceID: id,
                signalAuthority: inspection.signalAuthority(pid)
            ) {
                members.append(observation.snapshot)
            }
        }
        return members
    }

    private static func candidateResourceID(
        for pid: pid_t,
        inspection: LaunchdCoalitionInspection,
        deadline: UInt64?
    ) throws -> UInt64? {
        for _ in 0..<max(inspection.retryCount, 1) {
            try requireTimeRemaining(until: deadline)
            if let resourceID = inspection.resourceID(pid) { return resourceID }
            switch inspection.signalAuthority(pid) {
            case .absent:
                return nil
            case .denied:
                throw unverifiedMemberError(
                    pid: pid,
                    reason: "signal authority was denied"
                )
            case .failed(let code):
                throw BoundedProcessRunnerError.systemCallFailed(
                    operation: "inspect launchd coalition member",
                    code: code
                )
            case .available:
                break
            }
            if let snapshot = inspection.snapshot(pid), !snapshot.isLive {
                return nil
            }
            try pause(
                microseconds: inspection.retryDelayMicroseconds,
                until: deadline
            )
        }

        try requireTimeRemaining(until: deadline)
        if inspection.signalAuthority(pid) == .absent { return nil }
        if let snapshot = inspection.snapshot(pid), !snapshot.isLive { return nil }
        throw BoundedProcessRunnerError.secureCleanupUnverified(
            "coalition membership remained unverifiable for live pid \(pid)"
        )
    }

    private static func stableMembership(
        for pid: pid_t,
        coalitionID: UInt64,
        inspection: LaunchdCoalitionInspection,
        deadline: UInt64?
    ) throws -> (snapshot: LaunchdProcessSnapshot, resourceID: UInt64)? {
        for _ in 0..<max(inspection.retryCount, 1) {
            try requireTimeRemaining(until: deadline)
            guard let before = inspection.snapshot(pid) else {
                if try memberIsAbsent(
                    pid,
                    coalitionID: coalitionID,
                    inspection: inspection,
                    deadline: deadline
                ) { return nil }
                try pause(
                    microseconds: inspection.retryDelayMicroseconds,
                    until: deadline
                )
                continue
            }
            guard before.isLive else { return nil }
            guard let observedResourceID = inspection.resourceID(pid) else {
                if try memberIsAbsent(
                    pid,
                    coalitionID: coalitionID,
                    inspection: inspection,
                    deadline: deadline
                ) { return nil }
                try pause(
                    microseconds: inspection.retryDelayMicroseconds,
                    until: deadline
                )
                continue
            }
            guard let after = inspection.snapshot(pid) else {
                if try memberIsAbsent(
                    pid,
                    coalitionID: coalitionID,
                    inspection: inspection,
                    deadline: deadline
                ) { return nil }
                try pause(
                    microseconds: inspection.retryDelayMicroseconds,
                    until: deadline
                )
                continue
            }
            guard after.isLive else { return nil }
            guard after.identity == before.identity else {
                try pause(
                    microseconds: inspection.retryDelayMicroseconds,
                    until: deadline
                )
                continue
            }
            guard after.userID == before.userID else {
                throw BoundedProcessRunnerError.secureContainmentVerificationFailed
            }
            guard try validateLiveMember(
                after,
                observedResourceID: observedResourceID,
                expectedResourceID: coalitionID,
                signalAuthority: inspection.signalAuthority(pid)
            ) else {
                return nil
            }
            return (after, observedResourceID)
        }

        if try memberIsAbsent(
            pid,
            coalitionID: coalitionID,
            inspection: inspection,
            deadline: deadline
        ) { return nil }
        if let snapshot = inspection.snapshot(pid), !snapshot.isLive {
            return nil
        }
        throw BoundedProcessRunnerError.secureCleanupUnverified(
            "stable coalition membership remained unverifiable for live pid \(pid)"
        )
    }

    private static func memberIsAbsent(
        _ pid: pid_t,
        coalitionID: UInt64,
        inspection: LaunchdCoalitionInspection,
        deadline: UInt64?
    ) throws -> Bool {
        try requireTimeRemaining(until: deadline)
        switch inspection.signalAuthority(pid) {
        case .available:
            return false
        case .absent:
            return true
        case .denied:
            throw unverifiedMemberError(
                pid: pid,
                reason: "signal authority was denied for coalition \(coalitionID)"
            )
        case .failed(let code):
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "inspect launchd coalition member",
                code: code
            )
        }
    }

    static func validateLiveMember(
        _ snapshot: LaunchdProcessSnapshot,
        observedResourceID: UInt64,
        expectedResourceID: UInt64,
        signalAuthority: LaunchdProcessSignalAuthority
    ) throws -> Bool {
        guard snapshot.isLive, observedResourceID == expectedResourceID else { return false }
        guard snapshot.userID == geteuid() else {
            throw unverifiedMemberError(
                pid: snapshot.identity.pid,
                reason: "member UID is outside cleanup authority"
            )
        }
        switch signalAuthority {
        case .available:
            return true
        case .absent:
            return false
        case .denied:
            throw unverifiedMemberError(
                pid: snapshot.identity.pid,
                reason: "signal authority was denied"
            )
        case .failed(let code):
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "inspect launchd coalition member",
                code: code
            )
        }
    }

    static func terminateMembers(
        id: UInt64,
        excluding excludedPID: pid_t,
        gracePeriodSeconds: TimeInterval,
        killWaitSeconds: TimeInterval
    ) throws {
        let termDeadline = LaunchdMonotonicClock.adding(
            seconds: gracePeriodSeconds,
            to: LaunchdMonotonicClock.now()
        )
        while LaunchdMonotonicClock.now() < termDeadline {
            do {
                let members = try liveMembers(id: id, deadline: termDeadline).filter {
                    $0.identity.pid != excludedPID
                }
                if members.isEmpty { break }
                try signal(members: members, signal: SIGTERM, coalitionID: id)
                try pause(microseconds: scanIntervalMicroseconds, until: termDeadline)
            } catch BoundedProcessRunnerError.processTreeDidNotTerminate {
                break
            }
        }

        let killDeadline = LaunchdMonotonicClock.adding(
            seconds: killWaitSeconds,
            to: LaunchdMonotonicClock.now()
        )
        var emptyPasses = 0
        while LaunchdMonotonicClock.now() < killDeadline {
            let members = try liveMembers(id: id, deadline: killDeadline).filter {
                $0.identity.pid != excludedPID
            }
            if members.isEmpty {
                emptyPasses += 1
                if emptyPasses >= stableEmptyPasses { return }
            } else {
                emptyPasses = 0
                try signal(members: members, signal: SIGKILL, coalitionID: id)
            }
            try pause(microseconds: scanIntervalMicroseconds, until: killDeadline)
        }
        throw BoundedProcessRunnerError.processTreeDidNotTerminate
    }

    static func verifyEmpty(
        id: UInt64,
        excluding excludedPID: pid_t? = nil,
        waitSeconds: TimeInterval,
        inspection: LaunchdCoalitionInspection = .system
    ) throws {
        let deadline = LaunchdMonotonicClock.adding(
            seconds: waitSeconds,
            to: LaunchdMonotonicClock.now()
        )
        var emptyPasses = 0
        while LaunchdMonotonicClock.now() < deadline {
            let members = try liveMembers(
                id: id,
                inspection: inspection,
                deadline: deadline
            ).filter {
                guard let excludedPID else { return true }
                return $0.identity.pid != excludedPID
            }
            if members.isEmpty {
                emptyPasses += 1
                if emptyPasses >= stableEmptyPasses { return }
            } else {
                emptyPasses = 0
            }
            try pause(microseconds: scanIntervalMicroseconds, until: deadline)
        }
        throw BoundedProcessRunnerError.processTreeDidNotTerminate
    }

    private static func requireTimeRemaining(until deadline: UInt64?) throws {
        guard let deadline else { return }
        guard LaunchdMonotonicClock.now() < deadline else {
            throw BoundedProcessRunnerError.processTreeDidNotTerminate
        }
    }

    private static func pause(
        microseconds: useconds_t,
        until deadline: UInt64?
    ) throws {
        try requireTimeRemaining(until: deadline)
        guard microseconds > 0 else { return }
        guard let deadline else {
            usleep(microseconds)
            return
        }
        let now = LaunchdMonotonicClock.now()
        guard now < deadline else {
            throw BoundedProcessRunnerError.processTreeDidNotTerminate
        }
        let remainingMicroseconds = (deadline - now) / 1_000
        guard remainingMicroseconds > 0 else { return }
        usleep(useconds_t(min(UInt64(microseconds), remainingMicroseconds)))
    }

    private static func signal(
        members: [LaunchdProcessSnapshot],
        signal: Int32,
        coalitionID: UInt64
    ) throws {
        var firstFailure: BoundedProcessRunnerError?
        for member in members {
            guard let current = LaunchdProcessSnapshot.current(for: member.identity.pid),
                  current.identity == member.identity,
                  let currentResourceID = resourceID(for: member.identity.pid),
                  try validateLiveMember(
                      current,
                      observedResourceID: currentResourceID,
                      expectedResourceID: coalitionID,
                      signalAuthority: LaunchdCoalitionInspection.system.signalAuthority(
                          member.identity.pid
                      )
                  ) else {
                continue
            }
            if Darwin.kill(member.identity.pid, signal) == -1 {
                let code = errno
                if code == ESRCH { continue }
                if code == EPERM {
                    throw unverifiedMemberError(
                        pid: member.identity.pid,
                        reason: "signal delivery was denied"
                    )
                }
                guard firstFailure == nil else { continue }
                firstFailure = .systemCallFailed(
                    operation: "signal launchd coalition",
                    code: code
                )
            }
        }
        if let firstFailure { throw firstFailure }
    }

    private static func unverifiedMemberError(
        pid: pid_t,
        reason: String
    ) -> BoundedProcessRunnerError {
        .secureCleanupUnverified("live coalition member \(pid): \(reason)")
    }
}

private struct LaunchdRawCoalitionInfo {
    var resourceID: UInt64 = 0
    var jetsamID: UInt64 = 0
    var reserved1: UInt64 = 0
    var reserved2: UInt64 = 0
    var reserved3: UInt64 = 0
}

final class LaunchdOwnedFileDescriptor {
    private(set) var rawValue: Int32

    init(_ rawValue: Int32) {
        self.rawValue = rawValue
    }

    deinit { close() }

    func relocateAboveStandardDescriptors() throws {
        guard rawValue <= STDERR_FILENO else { return }
        let duplicate = fcntl(rawValue, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
        guard duplicate >= 0 else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "relocate launchd descriptor",
                code: errno
            )
        }
        _ = Darwin.close(rawValue)
        rawValue = duplicate
    }

    func close() {
        guard rawValue >= 0 else { return }
        _ = Darwin.close(rawValue)
        rawValue = -1
    }

    func releaseOwnership() {
        rawValue = -1
    }
}

enum LaunchdMonotonicClock {
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    static func adding(seconds: TimeInterval, to base: UInt64) -> UInt64 {
        let maximumSeconds = Double(UInt64.max) / 1_000_000_000
        guard seconds.isFinite else { return seconds.sign == .minus ? base : UInt64.max }
        guard seconds > 0 else { return base }
        guard seconds < maximumSeconds else { return UInt64.max }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        return base > UInt64.max - nanoseconds ? UInt64.max : base + nanoseconds
    }
}
