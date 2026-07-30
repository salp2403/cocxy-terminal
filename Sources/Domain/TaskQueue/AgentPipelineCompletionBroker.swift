// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPipelineCompletionBroker.swift - Hook-to-pipeline completion rendezvous.

import Foundation

enum AgentPipelineRuntimeError: Error, Equatable, Sendable, CustomStringConvertible {
    case runtimeUnavailable
    case hooksUnavailable
    case worktreeUnavailable(String)
    case launchAlreadyPending(String)
    case launchFailed(String)
    case agentFailed(String)
    case stepTimedOut(String)

    var description: String {
        switch self {
        case .runtimeUnavailable:
            return "Agent pipeline runtime is unavailable"
        case .hooksUnavailable:
            return "Agent pipeline execution requires lifecycle hooks"
        case .worktreeUnavailable(let path):
            return "Agent pipeline worktree is unavailable: \(path)"
        case .launchAlreadyPending(let teamID):
            return "Agent pipeline launch is already pending: \(teamID)"
        case .launchFailed(let message):
            return "Agent pipeline launch failed: \(message)"
        case .agentFailed(let message):
            return "Agent pipeline step failed: \(message)"
        case .stepTimedOut(let teamID):
            return "Agent pipeline step timed out: \(teamID)"
        }
    }
}

enum AgentPipelineHookOutcome: Equatable, Sendable {
    case succeeded(String?)
    case failed(String)

    static func resolve(_ event: HookEvent) -> AgentPipelineHookOutcome? {
        switch event.type {
        case .taskCompleted:
            guard case .taskCompleted(let data) = event.data else {
                return .succeeded(nil)
            }
            return .succeeded(bounded(data.taskDescription))
        case .sessionEnd:
            return .succeeded(nil)
        case .stop:
            guard case .stop(let data) = event.data else {
                return .succeeded(nil)
            }
            let reason = bounded(data.reason)
            if reason.map(isFailureReason) == true {
                return .failed(reason ?? "Agent stopped before completing the pipeline step")
            }
            return .succeeded(bounded(data.lastMessage))
        case .sessionStart,
             .userPromptSubmit,
             .preToolUse,
             .postToolUse,
             .postToolUseFailure,
             .subagentStart,
             .subagentStop,
             .notification,
             .teammateIdle,
             .cwdChanged,
             .fileChanged,
             .richInputDraftSubmitted:
            return nil
        }
    }

    private static func isFailureReason(_ reason: String) -> Bool {
        let normalized = reason.lowercased()
        return [
            "fail", "error", "cancel", "abort", "denied", "terminated",
            "interrupt", "timeout", "timed out", "killed",
        ]
            .contains { normalized.contains($0) }
    }

    private static func bounded(_ value: String?, maximumUTF8Bytes: Int = 2_048) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.utf8.count > maximumUTF8Bytes else { return trimmed }

        var result = ""
        result.reserveCapacity(maximumUTF8Bytes)
        for character in trimmed {
            let candidate = result + String(character)
            guard candidate.utf8.count <= maximumUTF8Bytes else { break }
            result = candidate
        }
        return result.isEmpty ? nil : result
    }
}

actor AgentPipelineCompletionBroker {
    typealias LaunchOperation = @MainActor @Sendable () throws -> Void

    private struct PendingLaunch {
        let token: UUID
        let continuation: CheckedContinuation<AgentPipelineStepExecutionOutput, Error>
        var watchdog: Task<Void, Never>?
    }

    private let stepTimeout: Duration
    private var pendingLaunches: [String: PendingLaunch] = [:]

    init(stepTimeout: Duration = .seconds(30 * 60)) {
        self.stepTimeout = stepTimeout
    }

    func launchAndWait(
        teamID: String,
        launch: @escaping LaunchOperation
    ) async throws -> AgentPipelineStepExecutionOutput {
        try Task.checkCancellation()
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard pendingLaunches[teamID] == nil else {
                    continuation.resume(
                        throwing: AgentPipelineRuntimeError.launchAlreadyPending(teamID)
                    )
                    return
                }
                pendingLaunches[teamID] = PendingLaunch(
                    token: token,
                    continuation: continuation,
                    watchdog: nil
                )
                pendingLaunches[teamID]?.watchdog = Task { [weak self] in
                    do {
                        try await Task.sleep(for: self?.stepTimeout ?? .zero)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    await self?.timeout(teamID: teamID, token: token)
                }
                Task { @MainActor in
                    guard await self.shouldLaunch(teamID: teamID, token: token) else {
                        return
                    }
                    do {
                        try launch()
                    } catch {
                        await self.failLaunch(teamID: teamID, token: token, error: error)
                    }
                }
            }
        } onCancel: {
            Task { await self.cancel(teamID: teamID, token: token) }
        }
    }

    @discardableResult
    func complete(
        teamID: String,
        output: AgentPipelineStepExecutionOutput = AgentPipelineStepExecutionOutput()
    ) -> Bool {
        guard let pending = pendingLaunches.removeValue(forKey: teamID) else {
            return false
        }
        pending.watchdog?.cancel()
        pending.continuation.resume(returning: output)
        return true
    }

    @discardableResult
    func fail(teamID: String, message: String) -> Bool {
        guard let pending = pendingLaunches.removeValue(forKey: teamID) else {
            return false
        }
        pending.watchdog?.cancel()
        pending.continuation.resume(throwing: AgentPipelineRuntimeError.agentFailed(message))
        return true
    }

    @discardableResult
    func cancel(teamID: String) -> Bool {
        guard let pending = pendingLaunches.removeValue(forKey: teamID) else {
            return false
        }
        pending.watchdog?.cancel()
        pending.continuation.resume(throwing: CancellationError())
        return true
    }

    func cancelAll() {
        let pending = pendingLaunches
        pendingLaunches.removeAll()
        for launch in pending.values {
            launch.watchdog?.cancel()
            launch.continuation.resume(throwing: CancellationError())
        }
    }

    var pendingTeamIDs: [String] {
        pendingLaunches.keys.sorted()
    }

    private func shouldLaunch(teamID: String, token: UUID) -> Bool {
        pendingLaunches[teamID]?.token == token
    }

    @discardableResult
    private func cancel(teamID: String, token: UUID) -> Bool {
        guard let pending = pendingLaunches[teamID], pending.token == token else {
            return false
        }
        pendingLaunches.removeValue(forKey: teamID)
        pending.watchdog?.cancel()
        pending.continuation.resume(throwing: CancellationError())
        return true
    }

    private func failLaunch(teamID: String, token: UUID, error: Error) {
        guard let pending = pendingLaunches[teamID], pending.token == token else {
            return
        }
        pendingLaunches.removeValue(forKey: teamID)
        pending.watchdog?.cancel()
        pending.continuation.resume(
            throwing: AgentPipelineRuntimeError.launchFailed(String(describing: error))
        )
    }

    private func timeout(teamID: String, token: UUID) {
        guard let pending = pendingLaunches[teamID], pending.token == token else {
            return
        }
        pendingLaunches.removeValue(forKey: teamID)
        pending.continuation.resume(
            throwing: AgentPipelineRuntimeError.stepTimedOut(teamID)
        )
    }
}
