// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectFanOutFlowViewModel.swift - Embedded fan-out presentation state.

import Foundation

struct ProjectFanOutSnapshot: Equatable, Sendable {
    let run: TaskRun
    let comparisons: [TaskRunCandidateComparison]
    let candidateCollisions: TaskCollisionReport
}

@MainActor
struct ProjectFanOutActions {
    let launch: (TaskRunRequest) async throws -> TaskRun
    let loadSnapshot: (String) async throws -> ProjectFanOutSnapshot
    let launchCollisions: ([String]) -> TaskCollisionReport
    let preparePromotion: (String, String) async throws -> TaskRunPromotionPreview
    let executePromotion: (TaskRunPromotionPreview) async throws -> TaskRunPromotionOutcome
    let recycle: (String, String) async throws -> TaskRunRecycleDraft
}

@MainActor
final class ProjectFanOutFlowViewModel: ObservableObject {
    enum Mode: Equatable {
        case inbox
        case launch
        case comparison
        case promotion
    }

    let projectID: ProjectID
    let projectRoot: URL
    let availableProviders: [AgentTeamProvider]
    let availableBaseRefs: [String]

    @Published private(set) var mode: Mode = .inbox
    @Published var prompt = ""
    @Published private(set) var selectedProviders: [AgentTeamProvider]
    @Published var candidateCount: Int
    @Published var baseRef: String
    @Published var pendingPath = ""
    @Published private(set) var plannedPaths: [String] = []
    @Published private(set) var launchCollisionReport = TaskCollisionReport.empty
    @Published private(set) var run: TaskRun?
    @Published private(set) var comparisons: [TaskRunCandidateComparison] = []
    @Published var selectedCandidateID: String?
    @Published private(set) var candidateCollisionReport = TaskCollisionReport.empty
    @Published private(set) var promotionPreview: TaskRunPromotionPreview?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?

    private let defaultProviders: [AgentTeamProvider]
    private let defaultBaseRef: String
    private let actions: ProjectFanOutActions
    private var loadRevision = 0

    init(
        projectID: ProjectID,
        projectRoot: URL,
        availableProviders: [AgentTeamProvider] = AgentTeamProvider.allCases,
        availableBaseRefs: [String],
        defaultBaseRef: String?,
        defaultAgentNames: [String],
        actions: ProjectFanOutActions
    ) {
        self.projectID = projectID
        self.projectRoot = projectRoot
        self.availableProviders = availableProviders
        let configuredProviders = Self.uniqueProviders(defaultAgentNames.compactMap {
            AgentTeamProvider.resolve(named: $0)
        }).filter(availableProviders.contains)
        let fallbackProviders = [AgentTeamProvider.claudeCode, .codex]
            .filter(availableProviders.contains)
        self.defaultProviders = configuredProviders.isEmpty
            ? (fallbackProviders.isEmpty ? Array(availableProviders.prefix(1)) : fallbackProviders)
            : configuredProviders
        let normalizedBase = Self.normalized(defaultBaseRef) ?? "HEAD"
        self.defaultBaseRef = normalizedBase
        self.availableBaseRefs = Self.uniqueBaseRefs(
            [normalizedBase] + availableBaseRefs + ["HEAD"]
        )
        self.selectedProviders = self.defaultProviders
        self.candidateCount = max(
            TaskRunRequest.minimumCandidateCount,
            self.defaultProviders.count
        )
        self.baseRef = normalizedBase
        self.actions = actions
    }

    var canLaunch: Bool { !isBusy && (try? makeRequest()) != nil }
    var selectedComparison: TaskRunCandidateComparison? {
        guard let selectedCandidateID else { return comparisons.first }
        return comparisons.first { $0.id == selectedCandidateID }
    }
    var selectedCandidate: TaskRunCandidate? {
        guard let run else { return nil }
        guard let selectedCandidateID else { return run.candidates.first }
        return run.candidates.first { $0.id == selectedCandidateID }
    }
    var canPreparePromotion: Bool {
        run?.status == .running
            && selectedCandidate?.status != .orphaned
            && selectedCandidate?.worktree != nil
            && !isBusy
    }
    var canRecycleSelectedCandidate: Bool {
        selectedCandidate?.status == .discarded && !isBusy
    }

    func handle(_ destination: ProjectFanOutDestination) async {
        switch destination {
        case .launch(let draft):
            showLaunch(draft: draft)
        case .comparison(let runID):
            await showComparison(runID: runID)
        }
    }

    func showInbox() {
        loadRevision += 1
        mode = .inbox
        isBusy = false
        errorMessage = nil
        promotionPreview = nil
    }

    func showLaunch(draft: TaskRunRecycleDraft? = nil) {
        loadRevision += 1
        mode = .launch
        isBusy = false
        errorMessage = nil
        successMessage = nil
        promotionPreview = nil
        if let draft {
            prompt = draft.prompt
            selectedProviders = Self.uniqueProviders(draft.providers)
            candidateCount = max(
                TaskRunRequest.minimumCandidateCount,
                min(TaskRunRequest.maximumCandidateCount, draft.candidateCount)
            )
            baseRef = availableBaseRefs.contains(draft.baseRef) ? draft.baseRef : defaultBaseRef
            plannedPaths = normalizedPaths(draft.plannedPaths)
        } else {
            prompt = ""
            selectedProviders = defaultProviders
            candidateCount = max(TaskRunRequest.minimumCandidateCount, defaultProviders.count)
            baseRef = defaultBaseRef
            plannedPaths = []
        }
        pendingPath = ""
        refreshLaunchCollisions()
    }

    func isSelected(_ provider: AgentTeamProvider) -> Bool {
        selectedProviders.contains(provider)
    }

    func isSelectionDisabled(_ provider: AgentTeamProvider) -> Bool {
        !isSelected(provider)
            && selectedProviders.count >= TaskRunRequest.maximumCandidateCount
    }

    func setProvider(_ provider: AgentTeamProvider, selected: Bool) {
        if selected {
            guard !selectedProviders.contains(provider), !isSelectionDisabled(provider) else { return }
            selectedProviders.append(provider)
            selectedProviders.sort {
                (availableProviders.firstIndex(of: $0) ?? .max)
                    < (availableProviders.firstIndex(of: $1) ?? .max)
            }
            candidateCount = max(candidateCount, selectedProviders.count)
        } else {
            selectedProviders.removeAll { $0 == provider }
        }
        candidateCount = min(
            TaskRunRequest.maximumCandidateCount,
            max(TaskRunRequest.minimumCandidateCount, candidateCount)
        )
        errorMessage = nil
    }

    func addPendingPath() {
        let paths = normalizedPaths([pendingPath])
        guard let path = paths.first else {
            errorMessage = "The file path must stay inside this project."
            return
        }
        if !plannedPaths.contains(path) {
            plannedPaths.append(path)
            plannedPaths.sort()
        }
        pendingPath = ""
        errorMessage = nil
        refreshLaunchCollisions()
    }

    func removePlannedPath(_ path: String) {
        plannedPaths.removeAll { $0 == path }
        refreshLaunchCollisions()
    }

    func refreshLaunchCollisions() {
        launchCollisionReport = actions.launchCollisions(plannedPaths)
    }

    func makeRequest() throws -> TaskRunRequest {
        try TaskRunRequest.make(
            prompt: prompt,
            agents: selectedProviders.map(\.rawValue).joined(separator: ","),
            count: candidateCount,
            baseRef: baseRef
        )
    }

    func launch() async {
        guard !isBusy else { return }
        do {
            let request = try makeRequest()
            refreshLaunchCollisions()
            isBusy = true
            errorMessage = nil
            successMessage = nil
            let launchedRun = try await actions.launch(request)
            run = launchedRun
            mode = .comparison
            await loadComparison(runID: launchedRun.id, ownsBusyState: true)
        } catch {
            isBusy = false
            errorMessage = Self.message(for: error)
        }
    }

    func showComparison(runID: String) async {
        mode = .comparison
        successMessage = nil
        promotionPreview = nil
        await loadComparison(runID: runID, ownsBusyState: false)
    }

    func refreshComparison() async {
        guard let run else { return }
        await loadComparison(runID: run.id, ownsBusyState: false)
    }

    func preparePromotion() async {
        guard let run, let selectedCandidateID, canPreparePromotion else { return }
        isBusy = true
        errorMessage = nil
        do {
            promotionPreview = try await actions.preparePromotion(run.id, selectedCandidateID)
            mode = .promotion
            isBusy = false
        } catch {
            isBusy = false
            errorMessage = Self.message(for: error)
        }
    }

    func cancelPromotion() {
        promotionPreview = nil
        mode = .comparison
        errorMessage = nil
    }

    func confirmPromotion() async {
        guard let preview = promotionPreview, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            let outcome = try await actions.executePromotion(preview)
            run = outcome.run
            mode = .comparison
            promotionPreview = nil
            successMessage = outcome.cleanupFailures.isEmpty
                ? "Candidate promoted."
                : "Candidate promoted with cleanup warnings."
            isBusy = false
            await loadComparison(runID: outcome.run.id, ownsBusyState: false)
        } catch {
            isBusy = false
            errorMessage = Self.message(for: error)
        }
    }

    func recycleSelectedCandidate() async {
        guard let run, let selectedCandidateID, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        do {
            let draft = try await actions.recycle(run.id, selectedCandidateID)
            showLaunch(draft: draft)
        } catch {
            isBusy = false
            errorMessage = Self.message(for: error)
        }
    }

    private func loadComparison(runID: String, ownsBusyState: Bool) async {
        loadRevision += 1
        let revision = loadRevision
        isBusy = true
        errorMessage = nil
        do {
            let snapshot = try await actions.loadSnapshot(runID)
            guard revision == loadRevision else { return }
            run = snapshot.run
            comparisons = snapshot.comparisons
            candidateCollisionReport = snapshot.candidateCollisions
            if let selectedCandidateID,
               snapshot.run.candidates.contains(where: { $0.id == selectedCandidateID }) {
                self.selectedCandidateID = selectedCandidateID
            } else {
                selectedCandidateID = snapshot.run.candidates.first {
                    $0.status != .orphaned && $0.worktree != nil
                }?.id
            }
            isBusy = false
        } catch {
            guard revision == loadRevision else { return }
            isBusy = false
            errorMessage = Self.message(for: error)
            if ownsBusyState { mode = .launch }
        }
    }

    private func normalizedPaths(_ paths: [String]) -> [String] {
        TaskCollisionDetector.normalize(paths, projectRoot: projectRoot).sorted()
    }

    private static func uniqueProviders(
        _ providers: [AgentTeamProvider]
    ) -> [AgentTeamProvider] {
        providers.reduce(into: []) { result, provider in
            if !result.contains(provider) { result.append(provider) }
        }
    }

    private static func uniqueBaseRefs(_ values: [String]) -> [String] {
        values.reduce(into: []) { result, raw in
            guard let value = normalized(raw), !result.contains(value) else { return }
            result.append(value)
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
