// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRun.swift - Parallel agent task domain models.

import Foundation

enum TaskRunError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyPrompt
    case promptTooLarge(maxBytes: Int)
    case emptyProviders
    case unsupportedProvider(String)
    case invalidCandidateCount(Int)
    case candidateLimitExceeded(maximum: Int)
    case runNotFound(String)
    case candidateNotFound(String)
    case runAlreadyFinished(String)

    var description: String {
        switch self {
        case .emptyPrompt:
            return "Task prompt cannot be empty"
        case .promptTooLarge(let maxBytes):
            return "Task prompt exceeds the \(maxBytes)-byte limit"
        case .emptyProviders:
            return "At least one agent provider is required"
        case .unsupportedProvider(let provider):
            return "Unsupported agent provider: \(provider)"
        case .invalidCandidateCount(let count):
            return "Task candidate count must be at least \(TaskRunRequest.minimumCandidateCount), got \(count)"
        case .candidateLimitExceeded(let maximum):
            return "Task candidate count cannot exceed \(maximum)"
        case .runNotFound(let runID):
            return "Task run not found: \(runID)"
        case .candidateNotFound(let candidateID):
            return "Task candidate not found: \(candidateID)"
        case .runAlreadyFinished(let runID):
            return "Task run is already finished: \(runID)"
        }
    }
}

struct TaskRunRequest: Equatable, Sendable {
    static let minimumCandidateCount = 2
    static let maximumCandidateCount = 8
    static let maximumPromptBytes = 32_768

    let prompt: String
    let providers: [AgentTeamProvider]
    let baseRef: String

    var candidateCount: Int { providers.count }

    static func make(
        prompt rawPrompt: String,
        agents rawAgents: String,
        count: Int? = nil,
        baseRef rawBaseRef: String? = nil
    ) throws -> TaskRunRequest {
        let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { throw TaskRunError.emptyPrompt }
        guard prompt.utf8.count <= maximumPromptBytes else {
            throw TaskRunError.promptTooLarge(maxBytes: maximumPromptBytes)
        }

        let names = rawAgents
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else { throw TaskRunError.emptyProviders }
        let parsedProviders = try names.map(parseProvider)
        let candidateCount = count ?? parsedProviders.count
        guard candidateCount >= minimumCandidateCount else {
            throw TaskRunError.invalidCandidateCount(candidateCount)
        }
        guard candidateCount <= maximumCandidateCount else {
            throw TaskRunError.candidateLimitExceeded(maximum: maximumCandidateCount)
        }

        let providers = (0..<candidateCount).map { index in
            parsedProviders[index % parsedProviders.count]
        }
        let baseRef = rawBaseRef?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "HEAD"
        return TaskRunRequest(prompt: prompt, providers: providers, baseRef: baseRef)
    }

    private static func parseProvider(_ raw: String) throws -> AgentTeamProvider {
        guard let provider = AgentTeamProvider.resolve(named: raw) else {
            throw TaskRunError.unsupportedProvider(raw)
        }
        return provider
    }
}

enum TaskRunStatus: String, Codable, Sendable, Equatable {
    case launching
    case running
    case promoting
    case completed
    case failed
    case cancelled

    var isFinished: Bool {
        self == .completed || self == .failed || self == .cancelled
    }
}

enum TaskRunCandidateStatus: String, Codable, Sendable, Equatable {
    case preparing
    case running
    case finished
    case failed
    case promoted
    case discarded
    case orphaned
}

struct TaskRunCandidate: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let provider: AgentTeamProvider
    let teamID: String
    var worktree: WorktreeManifest.WorktreeEntry?
    var status: TaskRunCandidateStatus
    var estimatedCostMicros: Int64
    var failureMessage: String?
    var touchedFiles: [String]

    init(
        id: String,
        provider: AgentTeamProvider,
        teamID: String,
        worktree: WorktreeManifest.WorktreeEntry? = nil,
        status: TaskRunCandidateStatus = .preparing,
        estimatedCostMicros: Int64 = 0,
        failureMessage: String? = nil,
        touchedFiles: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.teamID = teamID
        self.worktree = worktree
        self.status = status
        self.estimatedCostMicros = max(0, estimatedCostMicros)
        self.failureMessage = failureMessage
        self.touchedFiles = Array(Set(touchedFiles.filter { !$0.isEmpty })).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case teamID
        case worktree
        case status
        case estimatedCostMicros
        case failureMessage
        case touchedFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            provider: try container.decode(AgentTeamProvider.self, forKey: .provider),
            teamID: try container.decode(String.self, forKey: .teamID),
            worktree: try container.decodeIfPresent(
                WorktreeManifest.WorktreeEntry.self,
                forKey: .worktree
            ),
            status: try container.decode(TaskRunCandidateStatus.self, forKey: .status),
            estimatedCostMicros: try container.decodeIfPresent(
                Int64.self,
                forKey: .estimatedCostMicros
            ) ?? 0,
            failureMessage: try container.decodeIfPresent(String.self, forKey: .failureMessage),
            touchedFiles: try container.decodeIfPresent([String].self, forKey: .touchedFiles) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(teamID, forKey: .teamID)
        try container.encodeIfPresent(worktree, forKey: .worktree)
        try container.encode(status, forKey: .status)
        try container.encode(estimatedCostMicros, forKey: .estimatedCostMicros)
        try container.encodeIfPresent(failureMessage, forKey: .failureMessage)
        try container.encode(touchedFiles, forKey: .touchedFiles)
    }
}

struct TaskRun: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let prompt: String
    let originRepoPath: URL
    let worktreeBasePath: String
    let baseRef: String
    let baseCommit: String
    let createdAt: Date
    var updatedAt: Date
    var status: TaskRunStatus
    var candidates: [TaskRunCandidate]
    var promotedCandidateID: String?
    var failureMessage: String?
    var completionWarning: String?

    var projectID: ProjectID {
        ProjectID(rootURL: originRepoPath)
    }

    init(
        id: String,
        request: TaskRunRequest,
        originRepoPath: URL,
        baseCommit: String,
        worktreeBasePath: String = WorktreeConfig.defaults.basePath,
        now: Date = Date()
    ) {
        let normalizedID = AgentTeamConfig.slug(id)
        self.id = normalizedID
        self.prompt = request.prompt
        self.originRepoPath = originRepoPath.standardizedFileURL
        self.worktreeBasePath = worktreeBasePath
        self.baseRef = request.baseRef
        self.baseCommit = baseCommit
        self.createdAt = now
        self.updatedAt = now
        self.status = .launching
        self.candidates = request.providers.enumerated().map { index, provider in
            let candidateID = "\(normalizedID)-candidate-\(index + 1)"
            return TaskRunCandidate(
                id: candidateID,
                provider: provider,
                teamID: "\(candidateID)-team"
            )
        }
        self.promotedCandidateID = nil
        self.failureMessage = nil
        self.completionWarning = nil
    }

    mutating func updateCandidate(
        id candidateID: String,
        now: Date = Date(),
        _ update: (inout TaskRunCandidate) -> Void
    ) throws {
        guard let index = candidates.firstIndex(where: { $0.id == candidateID }) else {
            throw TaskRunError.candidateNotFound(candidateID)
        }
        update(&candidates[index])
        updatedAt = now
    }

    mutating func markRunning(now: Date = Date()) {
        status = .running
        updatedAt = now
        failureMessage = nil
        completionWarning = nil
    }

    mutating func markFailed(_ message: String, now: Date = Date()) {
        status = .failed
        updatedAt = now
        failureMessage = message
        completionWarning = nil
    }

    mutating func markPromoting(candidateID: String, now: Date = Date()) throws {
        guard !status.isFinished else { throw TaskRunError.runAlreadyFinished(id) }
        guard candidates.contains(where: { $0.id == candidateID }) else {
            throw TaskRunError.candidateNotFound(candidateID)
        }
        status = .promoting
        promotedCandidateID = candidateID
        updatedAt = now
        failureMessage = nil
    }

    mutating func markPromotionFailed(
        candidateID: String,
        message: String,
        now: Date = Date()
    ) {
        if let index = candidates.firstIndex(where: { $0.id == candidateID }) {
            candidates[index].status = .failed
            candidates[index].failureMessage = message
            candidates[index].worktree?.tabID = nil
        }
        let hasAlternative = candidates.contains {
            $0.id != candidateID
                && $0.status != .failed
                && $0.status != .discarded
                && $0.status != .orphaned
        }
        status = hasAlternative ? .running : .failed
        promotedCandidateID = nil
        updatedAt = now
        failureMessage = message
        completionWarning = nil
    }

    mutating func markCompleted(
        candidateID: String,
        warning: String? = nil,
        now: Date = Date()
    ) throws {
        guard candidates.contains(where: { $0.id == candidateID }) else {
            throw TaskRunError.candidateNotFound(candidateID)
        }
        promotedCandidateID = candidateID
        for index in candidates.indices {
            candidates[index].status = candidates[index].id == candidateID ? .promoted : .discarded
        }
        status = .completed
        updatedAt = now
        failureMessage = nil
        completionWarning = warning
    }
}

struct TaskRunAgentLaunchPlan: Sendable, Equatable {
    let candidateID: String
    let config: AgentTeamConfig
    let preflightSpec: AgentTeamProviderLaunchSpec

    static func make(
        run: TaskRun,
        preflightWorkingDirectory: URL,
        executableResolver: @escaping AgentTeamExecutableResolver = AgentTeamProviderAdapterRegistry.defaultExecutableResolver,
        launchExecutableResolver: @escaping AgentTeamAsyncExecutableResolver = AgentTeamProviderAdapterRegistry.defaultLaunchExecutableResolver
    ) async throws -> [TaskRunAgentLaunchPlan] {
        let registry = AgentTeamProviderAdapterRegistry(
            executableResolver: executableResolver,
            launchExecutableResolver: launchExecutableResolver
        )
        for provider in Set(run.candidates.map(\.provider)) {
            guard await registry.prepareExecutableForLaunch(for: provider) != nil else {
                throw AgentTeamProviderAdapterError.executableUnavailable(
                    provider: provider,
                    candidates: provider.executableCandidates
                )
            }
        }
        return try run.candidates.enumerated().map { index, candidate in
            let teammate = AgentTeammateConfig(
                id: "\(candidate.teamID)-provider",
                name: "Candidate \(index + 1)",
                prompt: run.prompt
            )
            let config = AgentTeamConfig(
                id: candidate.teamID,
                provider: candidate.provider,
                teammates: [teammate]
            )
            guard let adapter = registry.adapter(for: candidate.provider) else {
                throw AgentTeamProviderAdapterError.executableUnavailable(
                    provider: candidate.provider,
                    candidates: candidate.provider.executableCandidates
                )
            }
            let launchSpec = try adapter.makeLaunchSpec(
                config: config,
                teammate: teammate,
                profile: AgentTeamLaunchProfile(
                    workingDirectory: preflightWorkingDirectory.path
                )
            )
            return TaskRunAgentLaunchPlan(
                candidateID: candidate.id,
                config: config,
                preflightSpec: launchSpec
            )
        }
    }
}

struct TaskRunCandidateComparison: Identifiable, Equatable, Sendable {
    let candidate: TaskRunCandidate
    let diffs: [FileDiff]

    var id: String { candidate.id }
    var additions: Int { diffs.reduce(0) { $0 + $1.additions } }
    var deletions: Int { diffs.reduce(0) { $0 + $1.deletions } }
    var changedFileCount: Int { diffs.count }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
