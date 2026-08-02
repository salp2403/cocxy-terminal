// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamProviderAdapters.swift - Local-first launch planning for agent team providers.

import Foundation
import Darwin

struct AgentTeamLaunchProfile: Codable, Sendable, Equatable {
    let workingDirectory: String?
    let environment: [String: String]
    let arguments: [String]

    init(
        workingDirectory: String? = nil,
        environment: [String: String] = [:],
        arguments: [String] = []
    ) {
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.arguments = arguments
    }
}

struct AgentTeamProviderLaunchSpec: Codable, Sendable, Equatable {
    let provider: AgentTeamProvider
    let teamID: String
    let teammateID: String
    let teammateName: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: String?

    init(
        provider: AgentTeamProvider,
        teamID: String,
        teammateID: String,
        teammateName: String,
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) {
        self.provider = provider
        self.teamID = teamID
        self.teammateID = teammateID
        self.teammateName = teammateName
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AgentTeamProvider.self, forKey: .provider)
        teammateID = try container.decode(String.self, forKey: .teammateID)
        teammateName = try container.decode(String.self, forKey: .teammateName)
        executable = try container.decode(String.self, forKey: .executable)
        arguments = try container.decode([String].self, forKey: .arguments)
        environment = try container.decode([String: String].self, forKey: .environment)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        teamID = try container.decodeIfPresent(String.self, forKey: .teamID)
            ?? environment["COCXY_AGENT_TEAM_ID"]
            ?? teammateID
    }
}

enum AgentTeamLaunchCommand {
    static func makeShellCommand(for launchSpec: AgentTeamProviderLaunchSpec) -> String? {
        let environment = launchSpec.environment.sorted { lhs, rhs in
            lhs.key < rhs.key
        }
        let values = [launchSpec.executable]
            + launchSpec.arguments
            + environment.flatMap { [$0.key, $0.value] }
        guard !launchSpec.executable.isEmpty,
              values.allSatisfy({ !$0.contains("\0") }),
              environment.allSatisfy({ !$0.key.isEmpty && !$0.key.contains("=") }) else {
            return nil
        }

        var components = ["exec", shellQuote("/usr/bin/env")]
        components.append(contentsOf: environment.map { key, value in
            shellQuote("\(key)=\(value)")
        })
        components.append(shellQuote(launchSpec.executable))
        components.append(contentsOf: launchSpec.arguments.map(shellQuote))
        return components.joined(separator: " ")
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum AgentTeamProviderAdapterError: Error, Equatable, Sendable, CustomStringConvertible {
    case executableUnavailable(provider: AgentTeamProvider, candidates: [String])
    case providerMismatch(expected: AgentTeamProvider, actual: AgentTeamProvider)
    case unknownTeammate(String)
    case emptyTeammateName

    var description: String {
        switch self {
        case .executableUnavailable(let provider, let candidates):
            return "No executable found for \(provider.rawValue). Tried: \(candidates.joined(separator: ", "))"
        case .providerMismatch(let expected, let actual):
            return "Provider mismatch. Expected \(expected.rawValue), got \(actual.rawValue)"
        case .unknownTeammate(let teammateID):
            return "Unknown teammate: \(teammateID)"
        case .emptyTeammateName:
            return "Teammate name cannot be empty"
        }
    }
}

protocol AgentTeamProviderAdapter: Sendable {
    var provider: AgentTeamProvider { get }
    var displayName: String { get }
    var executableCandidates: [String] { get }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec
}

typealias AgentTeamExecutableResolver = @Sendable (String) -> String?
typealias AgentTeamAsyncExecutableResolver = @Sendable (String) async -> String?

private struct AgentTeamProviderAdapterCore: Sendable {
    let provider: AgentTeamProvider
    private let executableResolver: AgentTeamExecutableResolver

    init(
        provider: AgentTeamProvider,
        executableResolver: @escaping AgentTeamExecutableResolver
    ) {
        self.provider = provider
        self.executableResolver = executableResolver
    }

    var displayName: String {
        provider.displayName
    }

    var executableCandidates: [String] {
        provider.executableCandidates
    }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile = AgentTeamLaunchProfile()
    ) throws -> AgentTeamProviderLaunchSpec {
        guard config.provider == provider else {
            throw AgentTeamProviderAdapterError.providerMismatch(expected: provider, actual: config.provider)
        }
        guard config.teammates.contains(teammate) else {
            throw AgentTeamProviderAdapterError.unknownTeammate(teammate.id)
        }
        let teammateName = teammate.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teammateName.isEmpty else {
            throw AgentTeamProviderAdapterError.emptyTeammateName
        }
        guard let executable = executableCandidates.lazy.compactMap({ executableResolver($0) }).first else {
            throw AgentTeamProviderAdapterError.executableUnavailable(
                provider: provider,
                candidates: executableCandidates
            )
        }

        var environment = profile.environment
        environment["COCXY_AGENT_TEAM_ID"] = config.id
        environment["COCXY_AGENT_TEAMMATE_ID"] = teammate.id
        environment["COCXY_AGENT_TEAMMATE_NAME"] = teammateName
        environment["COCXY_AGENT_PROVIDER"] = provider.rawValue

        return AgentTeamProviderLaunchSpec(
            provider: provider,
            teamID: config.id,
            teammateID: teammate.id,
            teammateName: teammateName,
            executable: executable,
            arguments: profile.arguments,
            environment: environment,
            workingDirectory: profile.workingDirectory
        )
    }
}

final class AgentTeamExecutableLocator: @unchecked Sendable {
    typealias ExecutableCheck = @Sendable (String) -> Bool
    typealias ShellLookup = @Sendable (String) -> String?

    private let lock = NSLock()
    private let candidateDirectories: [String]
    private let isExecutable: ExecutableCheck
    private let shellLookup: ShellLookup
    private var cache: [String: String] = [:]

    init(
        candidateDirectories: [String],
        isExecutable: @escaping ExecutableCheck,
        shellLookup: @escaping ShellLookup
    ) {
        self.candidateDirectories = Self.deduplicated(candidateDirectories)
        self.isExecutable = isExecutable
        self.shellLookup = shellLookup
    }

    func resolve(_ executable: String) -> String? {
        let normalized = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.contains("\0") else { return nil }

        lock.lock()
        let cached = cache[normalized]
        lock.unlock()
        if let cached {
            if isExecutable(cached) {
                return cached
            } else {
                lock.lock()
                cache.removeValue(forKey: normalized)
                lock.unlock()
            }
        }

        let resolved: String?
        if normalized.contains("/") {
            let path = URL(fileURLWithPath: normalized).standardizedFileURL.path
            resolved = isExecutable(path) ? path : nil
        } else if let candidate = candidateDirectories.lazy
            .map({ URL(fileURLWithPath: $0, isDirectory: true)
                .appendingPathComponent(normalized, isDirectory: false)
                .standardizedFileURL.path })
            .first(where: isExecutable) {
            resolved = candidate
        } else {
            resolved = nil
        }

        if let resolved {
            cacheResolvedPath(resolved, for: normalized)
        }
        return resolved
    }

    func resolveForLaunch(_ executable: String) async -> String? {
        let normalized = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !normalized.contains("\0") else { return nil }
        return await Task.detached(priority: .userInitiated) { [self] in
            if let resolved = resolve(normalized) { return resolved }
            guard let shellPath = Self.lastNonemptyLine(in: shellLookup(normalized)),
                  shellPath.hasPrefix("/") else {
                return nil
            }
            let resolved = URL(fileURLWithPath: shellPath).standardizedFileURL.path
            guard isExecutable(resolved) else { return nil }
            cacheResolvedPath(resolved, for: normalized)
            return resolved
        }.value
    }

    static func lastNonemptyLine(in output: String?) -> String? {
        output?
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
    }

    static func userCandidateDirectories(
        pathValue: String?,
        homeDirectory: URL
    ) -> [String] {
        let pathDirectories = (pathValue ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        let fixedDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            homeDirectory.appendingPathComponent(".local/bin", isDirectory: true).path,
            homeDirectory.appendingPathComponent("bin", isDirectory: true).path,
            "/usr/bin",
            "/bin",
        ]
        return deduplicated(pathDirectories + fixedDirectories)
    }

    static func loginShellLookup(
        executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: TimeInterval = 2
    ) -> String? {
        guard !executable.isEmpty,
              executable.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
                      .contains($0)
              }) else {
            return nil
        }
        let requestedShell = environment["SHELL"] ?? "/bin/zsh"
        let shell = FileManager.default.isExecutableFile(atPath: requestedShell)
            ? requestedShell
            : "/bin/sh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = [
            "-lc",
            "command -v \"$1\"",
            "cocxy-command-resolver",
            executable,
        ]
        process.environment = environment
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        let outputDrained = DispatchSemaphore(value: 0)
        let capturedOutput = LockedBox(Data())
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }
        DispatchQueue.global(qos: .userInitiated).async {
            defer { outputDrained.signal() }
            while let chunk = try? output.fileHandleForReading.read(upToCount: 4_096),
                  !chunk.isEmpty {
                capturedOutput.withValue { capture in
                    Self.appendBoundedTail(chunk, to: &capture, limit: 4_096)
                }
            }
        }
        guard exited.wait(timeout: .now() + max(0.1, timeout)) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + 0.25) != .success {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 0.25)
            }
            _ = outputDrained.wait(timeout: .now() + 0.25)
            return nil
        }
        guard outputDrained.wait(timeout: .now() + 0.25) == .success else { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let capture = capturedOutput.withValue { $0 }
        return String(decoding: capture, as: UTF8.self)
    }

    static func appendBoundedTail(_ chunk: Data, to capture: inout Data, limit: Int) {
        guard limit > 0 else {
            capture.removeAll(keepingCapacity: false)
            return
        }
        if chunk.count >= limit {
            capture = Data(chunk.suffix(limit))
            return
        }
        let overflow = capture.count + chunk.count - limit
        if overflow > 0 {
            capture.removeFirst(overflow)
        }
        capture.append(chunk)
    }

    private func cacheResolvedPath(_ path: String, for executable: String) {
        lock.lock()
        cache[executable] = path
        lock.unlock()
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let path = URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL.path
            return seen.insert(path).inserted ? path : nil
        }
    }
}

struct ClaudeCodeTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .claudeCode, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CodexTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .codex, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct OpenCodeTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .opencode, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct PiTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .pi, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CursorTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .cursor, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct GeminiTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .gemini, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct RovoDevTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .rovoDev, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CopilotTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .copilot, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct CodeBuddyTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .codebuddy, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct FactoryTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .factory, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct QoderTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .qoder, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct KiroTeamProviderAdapter: AgentTeamProviderAdapter {
    private let core: AgentTeamProviderAdapterCore

    init(executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver) {
        self.core = AgentTeamProviderAdapterCore(provider: .kiro, executableResolver: executableResolver)
    }

    var provider: AgentTeamProvider { core.provider }
    var displayName: String { core.displayName }
    var executableCandidates: [String] { core.executableCandidates }

    func makeLaunchSpec(
        config: AgentTeamConfig,
        teammate: AgentTeammateConfig,
        profile: AgentTeamLaunchProfile
    ) throws -> AgentTeamProviderLaunchSpec {
        try core.makeLaunchSpec(config: config, teammate: teammate, profile: profile)
    }
}

struct AgentTeamProviderAdapterRegistry: Sendable {
    private let adaptersByProvider: [AgentTeamProvider: any AgentTeamProviderAdapter]
    private let launchExecutableResolver: AgentTeamAsyncExecutableResolver
    private static let defaultExecutableLocator = AgentTeamExecutableLocator(
        candidateDirectories: AgentTeamExecutableLocator.userCandidateDirectories(
            pathValue: ProcessInfo.processInfo.environment["PATH"],
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ),
        isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
        shellLookup: { AgentTeamExecutableLocator.loginShellLookup(executable: $0) }
    )

    init() {
        self.init(
            executableResolver: Self.defaultExecutableResolver,
            launchExecutableResolver: Self.defaultLaunchExecutableResolver
        )
    }

    init(
        executableResolver: @escaping AgentTeamExecutableResolver,
        launchExecutableResolver: AgentTeamAsyncExecutableResolver? = nil
    ) {
        let launchExecutableResolver = launchExecutableResolver ?? { executable in
            executableResolver(executable)
        }
        let adapters: [any AgentTeamProviderAdapter] = [
            ClaudeCodeTeamProviderAdapter(executableResolver: executableResolver),
            CodexTeamProviderAdapter(executableResolver: executableResolver),
            OpenCodeTeamProviderAdapter(executableResolver: executableResolver),
            PiTeamProviderAdapter(executableResolver: executableResolver),
            CursorTeamProviderAdapter(executableResolver: executableResolver),
            GeminiTeamProviderAdapter(executableResolver: executableResolver),
            RovoDevTeamProviderAdapter(executableResolver: executableResolver),
            CopilotTeamProviderAdapter(executableResolver: executableResolver),
            CodeBuddyTeamProviderAdapter(executableResolver: executableResolver),
            FactoryTeamProviderAdapter(executableResolver: executableResolver),
            QoderTeamProviderAdapter(executableResolver: executableResolver),
            KiroTeamProviderAdapter(executableResolver: executableResolver),
        ]
        self.adaptersByProvider = Dictionary(uniqueKeysWithValues: adapters.map { ($0.provider, $0) })
        self.launchExecutableResolver = launchExecutableResolver
    }

    var providers: [AgentTeamProvider] {
        AgentTeamProvider.allCases.filter { adaptersByProvider[$0] != nil }
    }

    func adapter(for provider: AgentTeamProvider) -> (any AgentTeamProviderAdapter)? {
        adaptersByProvider[provider]
    }

    func prepareExecutableForLaunch(for provider: AgentTeamProvider) async -> String? {
        for candidate in provider.executableCandidates {
            if let executable = await launchExecutableResolver(candidate) {
                return executable
            }
        }
        return nil
    }

    static let defaultExecutableResolver: AgentTeamExecutableResolver = { executable in
        defaultExecutableLocator.resolve(executable)
    }

    static let defaultLaunchExecutableResolver: AgentTeamAsyncExecutableResolver = { executable in
        await defaultExecutableLocator.resolveForLaunch(executable)
    }
}
