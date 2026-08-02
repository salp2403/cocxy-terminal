// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPipeline.swift - Dependency-aware agent pipeline domain execution.

import Foundation

enum AgentPipelineError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyID
    case idTooLong(maximumBytes: Int)
    case emptyStepID
    case stepIDTooLong(stepID: String, maximumBytes: Int)
    case emptySteps
    case tooManySteps(maximum: Int)
    case duplicateStepID(String)
    case emptyPrompt(stepID: String)
    case promptTooLarge(stepID: String, maximumBytes: Int)
    case nameTooLong(maximumBytes: Int)
    case worktreePathTooLong(stepID: String, maximumBytes: Int)
    case invalidProjectPath(stepID: String)
    case projectPathTooLong(stepID: String, maximumBytes: Int)
    case unknownDependency(stepID: String, dependencyID: String)
    case selfDependency(stepID: String)
    case dependencyCycle([String])
    case invalidConcurrency(Int)

    var description: String {
        switch self {
        case .emptyID:
            return "Agent pipeline id cannot be empty"
        case .idTooLong(let maximumBytes):
            return "Agent pipeline id cannot exceed \(maximumBytes) UTF-8 bytes"
        case .emptyStepID:
            return "Agent pipeline step id cannot be empty"
        case .stepIDTooLong(let stepID, let maximumBytes):
            return "Agent pipeline step id \(stepID) cannot exceed \(maximumBytes) UTF-8 bytes"
        case .emptySteps:
            return "Agent pipeline must contain at least one step"
        case .tooManySteps(let maximum):
            return "Agent pipeline cannot contain more than \(maximum) steps"
        case .duplicateStepID(let stepID):
            return "Agent pipeline contains duplicate step id: \(stepID)"
        case .emptyPrompt(let stepID):
            return "Agent pipeline step \(stepID) has an empty prompt"
        case .promptTooLarge(let stepID, let maximumBytes):
            return "Agent pipeline step \(stepID) exceeds the \(maximumBytes)-byte prompt limit"
        case .nameTooLong(let maximumBytes):
            return "Agent pipeline name cannot exceed \(maximumBytes) UTF-8 bytes"
        case .worktreePathTooLong(let stepID, let maximumBytes):
            return "Agent pipeline step \(stepID) worktree cannot exceed \(maximumBytes) UTF-8 bytes"
        case .invalidProjectPath(let stepID):
            return "Agent pipeline step \(stepID) project must be an absolute local path"
        case .projectPathTooLong(let stepID, let maximumBytes):
            return "Agent pipeline step \(stepID) project cannot exceed \(maximumBytes) UTF-8 bytes"
        case .unknownDependency(let stepID, let dependencyID):
            return "Agent pipeline step \(stepID) depends on unknown step \(dependencyID)"
        case .selfDependency(let stepID):
            return "Agent pipeline step \(stepID) cannot depend on itself"
        case .dependencyCycle(let stepIDs):
            return "Agent pipeline contains a dependency cycle: \(stepIDs.joined(separator: ", "))"
        case .invalidConcurrency(let value):
            return "Agent pipeline concurrency must be between 1 and 8, got \(value)"
        }
    }
}

struct AgentPipelineStep: Identifiable, Codable, Sendable, Equatable {
    static let maximumPromptBytes = 32 * 1_024
    static let maximumIDBytes = 128
    static let maximumWorktreePathBytes = 4_096

    let id: String
    let provider: AgentTeamProvider
    let prompt: String
    let worktree: String?
    let project: String?
    let dependsOn: [String]

    init(
        id: String,
        provider: AgentTeamProvider,
        prompt: String,
        worktree: String? = nil,
        project: String? = nil,
        dependsOn: [String] = []
    ) {
        self.id = Self.normalizedID(id)
        self.provider = provider
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedWorktree = worktree?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.worktree = normalizedWorktree?.isEmpty == false ? normalizedWorktree : nil
        let normalizedProject = project?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.project = normalizedProject?.isEmpty == false ? normalizedProject : nil
        self.dependsOn = Self.uniqueNormalizedIDs(dependsOn)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case prompt
        case worktree
        case project
        case dependsOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            provider: try container.decode(AgentTeamProvider.self, forKey: .provider),
            prompt: try container.decode(String.self, forKey: .prompt),
            worktree: try container.decodeIfPresent(String.self, forKey: .worktree),
            project: try container.decodeIfPresent(String.self, forKey: .project),
            dependsOn: try container.decodeIfPresent([String].self, forKey: .dependsOn) ?? []
        )
    }

    static func normalizedID(_ rawID: String) -> String {
        let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else {
            return ""
        }
        return AgentTeamConfig.slug(trimmed)
    }

    private static func uniqueNormalizedIDs(_ rawIDs: [String]) -> [String] {
        var seen: Set<String> = []
        return rawIDs.compactMap { rawID in
            let normalized = normalizedID(rawID)
            return seen.insert(normalized).inserted ? normalized : nil
        }
    }
}

struct AgentPipeline: Identifiable, Codable, Sendable, Equatable {
    static let maximumStepCount = 64
    static let maximumIDBytes = 128
    static let maximumNameBytes = 256

    let id: String
    let name: String?
    let steps: [AgentPipelineStep]

    init(
        id: String,
        name: String? = nil,
        steps: [AgentPipelineStep]
    ) throws {
        let normalizedID = AgentPipelineStep.normalizedID(id)
        guard !normalizedID.isEmpty else { throw AgentPipelineError.emptyID }
        guard normalizedID.utf8.count <= Self.maximumIDBytes else {
            throw AgentPipelineError.idTooLong(maximumBytes: Self.maximumIDBytes)
        }
        guard !steps.isEmpty else { throw AgentPipelineError.emptySteps }
        guard steps.count <= Self.maximumStepCount else {
            throw AgentPipelineError.tooManySteps(maximum: Self.maximumStepCount)
        }

        self.id = normalizedID
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, trimmedName.utf8.count > Self.maximumNameBytes {
            throw AgentPipelineError.nameTooLong(maximumBytes: Self.maximumNameBytes)
        }
        self.name = trimmedName?.isEmpty == false ? trimmedName : nil
        self.steps = steps
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case steps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: try container.decode(String.self, forKey: .id),
            name: try container.decodeIfPresent(String.self, forKey: .name),
            steps: try container.decode([AgentPipelineStep].self, forKey: .steps)
        )
    }

    func topologicalBatches() throws -> [[AgentPipelineStep]] {
        try validate()
        let order = Dictionary(uniqueKeysWithValues: steps.enumerated().map { ($0.element.id, $0.offset) })
        var remaining = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, Set($0.dependsOn)) })
        var batches: [[AgentPipelineStep]] = []

        while !remaining.isEmpty {
            let readyIDs = remaining
                .filter { $0.value.isEmpty }
                .map(\.key)
                .sorted { order[$0, default: 0] < order[$1, default: 0] }
            guard !readyIDs.isEmpty else {
                throw AgentPipelineError.dependencyCycle(remaining.keys.sorted())
            }

            let readySet = Set(readyIDs)
            batches.append(readyIDs.compactMap { id in steps.first(where: { $0.id == id }) })
            for id in readyIDs {
                remaining.removeValue(forKey: id)
            }
            for id in Array(remaining.keys) {
                remaining[id]?.subtract(readySet)
            }
        }

        return batches
    }

    private func validate() throws {
        var knownIDs: Set<String> = []
        for step in steps {
            guard !step.id.isEmpty else {
                throw AgentPipelineError.emptyStepID
            }
            guard step.id.utf8.count <= AgentPipelineStep.maximumIDBytes else {
                throw AgentPipelineError.stepIDTooLong(
                    stepID: step.id,
                    maximumBytes: AgentPipelineStep.maximumIDBytes
                )
            }
            guard knownIDs.insert(step.id).inserted else {
                throw AgentPipelineError.duplicateStepID(step.id)
            }
            guard !step.prompt.isEmpty else {
                throw AgentPipelineError.emptyPrompt(stepID: step.id)
            }
            guard step.prompt.utf8.count <= AgentPipelineStep.maximumPromptBytes else {
                throw AgentPipelineError.promptTooLarge(
                    stepID: step.id,
                    maximumBytes: AgentPipelineStep.maximumPromptBytes
                )
            }
            if let worktree = step.worktree,
               worktree.utf8.count > AgentPipelineStep.maximumWorktreePathBytes {
                throw AgentPipelineError.worktreePathTooLong(
                    stepID: step.id,
                    maximumBytes: AgentPipelineStep.maximumWorktreePathBytes
                )
            }
            if let project = step.project {
                guard NSString(string: project).isAbsolutePath,
                      !project.contains("\0") else {
                    throw AgentPipelineError.invalidProjectPath(stepID: step.id)
                }
                guard project.utf8.count <= AgentPipelineStep.maximumWorktreePathBytes else {
                    throw AgentPipelineError.projectPathTooLong(
                        stepID: step.id,
                        maximumBytes: AgentPipelineStep.maximumWorktreePathBytes
                    )
                }
            }
        }

        for step in steps {
            for dependencyID in step.dependsOn {
                guard dependencyID != step.id else {
                    throw AgentPipelineError.selfDependency(stepID: step.id)
                }
                guard knownIDs.contains(dependencyID) else {
                    throw AgentPipelineError.unknownDependency(
                        stepID: step.id,
                        dependencyID: dependencyID
                    )
                }
            }
        }

        var remaining = Dictionary(uniqueKeysWithValues: steps.map { ($0.id, Set($0.dependsOn)) })
        while !remaining.isEmpty {
            let ready = Set(remaining.filter { $0.value.isEmpty }.map(\.key))
            guard !ready.isEmpty else {
                throw AgentPipelineError.dependencyCycle(remaining.keys.sorted())
            }
            for id in ready {
                remaining.removeValue(forKey: id)
            }
            for id in Array(remaining.keys) {
                remaining[id]?.subtract(ready)
            }
        }
    }
}

enum AgentPipelineStepStatus: String, Codable, Sendable, Equatable {
    case succeeded
    case failed
    case skipped
    case cancelled

    var satisfiesDependency: Bool { self == .succeeded }
}

struct AgentPipelineStepResult: Identifiable, Codable, Sendable, Equatable {
    let stepID: String
    let status: AgentPipelineStepStatus
    let output: String?
    let error: String?
    let startedAt: Date?
    let finishedAt: Date

    var id: String { stepID }
}

enum AgentPipelineRunStatus: String, Codable, Sendable, Equatable {
    case succeeded
    case failed
    case cancelled
}

struct AgentPipelineRunSummary: Codable, Sendable, Equatable {
    let pipelineID: String
    let status: AgentPipelineRunStatus
    let stepResults: [AgentPipelineStepResult]
    let startedAt: Date
    let finishedAt: Date

    var succeededStepCount: Int {
        stepResults.filter { $0.status == .succeeded }.count
    }
}

struct AgentPipelineStepExecutionOutput: Sendable, Equatable {
    let summary: String?

    init(summary: String? = nil) {
        let trimmed = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = trimmed?.isEmpty == false ? trimmed : nil
    }
}

typealias AgentPipelineStepRunner = @Sendable (
    _ step: AgentPipelineStep
) async throws -> AgentPipelineStepExecutionOutput

struct AgentPipelineExecutor: Sendable {
    private let maximumConcurrency: Int
    private let clock: @Sendable () -> Date

    init(
        maximumConcurrency: Int,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        guard (1...8).contains(maximumConcurrency) else {
            throw AgentPipelineError.invalidConcurrency(maximumConcurrency)
        }
        self.maximumConcurrency = maximumConcurrency
        self.clock = clock
    }

    func execute(
        _ pipeline: AgentPipeline,
        runner: @escaping AgentPipelineStepRunner
    ) async -> AgentPipelineRunSummary {
        let startedAt = clock()
        var resultsByID: [String: AgentPipelineStepResult] = [:]
        var pending = Dictionary(uniqueKeysWithValues: pipeline.steps.map { ($0.id, $0) })
        await withTaskGroup(of: AgentPipelineStepResult.self) { group in
            var inFlight: Set<String> = []
            var didCancelPending = false

            while !pending.isEmpty || !inFlight.isEmpty {
                if Task.isCancelled, !didCancelPending {
                    didCancelPending = true
                    group.cancelAll()
                    let finishedAt = clock()
                    for step in pipeline.steps where pending[step.id] != nil {
                        resultsByID[step.id] = AgentPipelineStepResult(
                            stepID: step.id,
                            status: .cancelled,
                            output: nil,
                            error: "Pipeline execution was cancelled",
                            startedAt: nil,
                            finishedAt: finishedAt
                        )
                    }
                    pending.removeAll()
                }

                if !didCancelPending {
                    let blockedIDs = pipeline.steps.compactMap { step -> String? in
                        guard pending[step.id] != nil else { return nil }
                        let dependencyResults = step.dependsOn.compactMap { resultsByID[$0] }
                        return dependencyResults.contains(where: {
                            !$0.status.satisfiesDependency
                        }) ? step.id : nil
                    }
                    if !blockedIDs.isEmpty {
                        let finishedAt = clock()
                        for stepID in blockedIDs {
                            resultsByID[stepID] = AgentPipelineStepResult(
                                stepID: stepID,
                                status: .skipped,
                                output: nil,
                                error: "A dependency did not complete successfully",
                                startedAt: nil,
                                finishedAt: finishedAt
                            )
                            pending.removeValue(forKey: stepID)
                        }
                        continue
                    }

                    while inFlight.count < maximumConcurrency {
                        guard let ready = pipeline.steps.first(where: { step in
                            guard pending[step.id] != nil else { return false }
                            return step.dependsOn.allSatisfy {
                                resultsByID[$0]?.status.satisfiesDependency == true
                            }
                        }) else {
                            break
                        }
                        pending.removeValue(forKey: ready.id)
                        inFlight.insert(ready.id)
                        group.addTask { await executeStep(ready, runner: runner) }
                    }
                }

                guard !inFlight.isEmpty else {
                    if !pending.isEmpty {
                        let finishedAt = clock()
                        for stepID in pending.keys.sorted() {
                            resultsByID[stepID] = AgentPipelineStepResult(
                                stepID: stepID,
                                status: .failed,
                                output: nil,
                                error: "Pipeline dependency graph could not make progress",
                                startedAt: nil,
                                finishedAt: finishedAt
                            )
                        }
                        pending.removeAll()
                    }
                    break
                }

                if let result = await group.next() {
                    inFlight.remove(result.stepID)
                    resultsByID[result.stepID] = result
                }
            }
        }

        let orderedResults = pipeline.steps.compactMap { resultsByID[$0.id] }
        let status: AgentPipelineRunStatus
        if orderedResults.contains(where: { $0.status == .cancelled }) {
            status = .cancelled
        } else if orderedResults.allSatisfy({ $0.status == .succeeded }) {
            status = .succeeded
        } else {
            status = .failed
        }
        return AgentPipelineRunSummary(
            pipelineID: pipeline.id,
            status: status,
            stepResults: orderedResults,
            startedAt: startedAt,
            finishedAt: clock()
        )
    }

    private func executeStep(
        _ step: AgentPipelineStep,
        runner: @escaping AgentPipelineStepRunner
    ) async -> AgentPipelineStepResult {
        let startedAt = clock()
        do {
            let output = try await runner(step)
            return AgentPipelineStepResult(
                stepID: step.id,
                status: .succeeded,
                output: output.summary,
                error: nil,
                startedAt: startedAt,
                finishedAt: clock()
            )
        } catch is CancellationError {
            return AgentPipelineStepResult(
                stepID: step.id,
                status: .cancelled,
                output: nil,
                error: "Pipeline step was cancelled",
                startedAt: startedAt,
                finishedAt: clock()
            )
        } catch {
            return AgentPipelineStepResult(
                stepID: step.id,
                status: .failed,
                output: nil,
                error: String(describing: error),
                startedAt: startedAt,
                finishedAt: clock()
            )
        }
    }
}
