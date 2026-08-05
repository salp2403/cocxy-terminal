// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectFanOutFlowViewModel.swift - Embedded fan-out presentation state.

import Foundation

struct ProjectFanOutSnapshot: Equatable, Sendable {
    let run: TaskRun
    let comparisons: [TaskRunCandidateComparison]
    let candidateCollisions: TaskCollisionReport
    let persistenceIssue: String?
}

@MainActor
struct ProjectFanOutActions {
    let launch: (TaskRunRequest) async throws -> TaskRun
    let loadSnapshot: (String) async throws -> ProjectFanOutSnapshot
    let launchCollisions: (String, [String]) async -> TaskLaunchCollisionAnalysis
    let preparePromotion: (String, String) async throws -> TaskRunPromotionPreview
    let executePromotion: (TaskRunPromotionPreview) async throws -> TaskRunPromotionOutcome
    let recycle: (String, String) async throws -> TaskRunRecycleDraft
    let cancel: (String) async throws -> TaskRun
    let forget: (String) async throws -> Void
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
    @Published private(set) var inferredPaths: [String] = []
    @Published private(set) var launchCollisionReport = TaskCollisionReport.empty
    @Published private(set) var isAnalyzingCollisions = false
    @Published private(set) var run: TaskRun?
    @Published private(set) var comparisons: [TaskRunCandidateComparison] = []
    @Published var selectedCandidateID: String?
    @Published private(set) var candidateCollisionReport = TaskCollisionReport.empty
    @Published private(set) var promotionPreview: TaskRunPromotionPreview?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var persistenceIssue: String?

    private let defaultProviders: [AgentTeamProvider]
    private let defaultBaseRef: String
    private var localizer: AppLocalizer
    private let actions: ProjectFanOutActions
    private var loadRevision = 0
    private var collisionRevision = 0
    private var collisionRefreshTask: Task<Void, Never>?
    private var collisionSeedPaths: [String] = []

    init(
        projectID: ProjectID,
        projectRoot: URL,
        availableProviders: [AgentTeamProvider] = AgentTeamProvider.allCases,
        availableBaseRefs: [String],
        defaultBaseRef: String?,
        defaultAgentNames: [String],
        localizer: AppLocalizer = AppLocalizer(languagePreference: .english),
        actions: ProjectFanOutActions
    ) {
        self.projectID = projectID
        self.projectRoot = projectRoot
        self.availableProviders = availableProviders
        let configuredProviders = Array(Self.uniqueProviders(defaultAgentNames.compactMap {
            AgentTeamProvider.resolve(named: $0)
        }).filter(availableProviders.contains).prefix(TaskRunRequest.maximumCandidateCount))
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
        self.localizer = localizer
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
    var canCancelRun: Bool {
        guard let run else { return false }
        return (run.status == .launching || run.status == .running) && !isBusy
    }
    var canForgetRun: Bool { run?.status.isFinished == true && !isBusy }
    var durabilityNotice: String? {
        persistenceIssue ?? (run?.recoveredFromInterruption == true ? run?.failureMessage : nil)
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
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
        collisionRefreshTask?.cancel()
        collisionRevision += 1
        mode = .inbox
        isBusy = false
        isAnalyzingCollisions = false
        errorMessage = nil
        promotionPreview = nil
        persistenceIssue = nil
    }

    func showLaunch(draft: TaskRunRecycleDraft? = nil) {
        loadRevision += 1
        mode = .launch
        isBusy = false
        errorMessage = nil
        successMessage = nil
        promotionPreview = nil
        persistenceIssue = nil
        if let draft {
            prompt = draft.prompt
            selectedProviders = Array(Self.uniqueProviders(draft.providers)
                .filter(availableProviders.contains)
                .prefix(TaskRunRequest.maximumCandidateCount))
            candidateCount = max(
                TaskRunRequest.minimumCandidateCount,
                min(
                    TaskRunRequest.maximumCandidateCount,
                    max(draft.candidateCount, selectedProviders.count)
                )
            )
            baseRef = availableBaseRefs.contains(draft.baseRef) ? draft.baseRef : defaultBaseRef
            collisionSeedPaths = normalizedPaths(draft.plannedPaths)
            inferredPaths = collisionSeedPaths
        } else {
            prompt = ""
            selectedProviders = defaultProviders
            candidateCount = max(TaskRunRequest.minimumCandidateCount, defaultProviders.count)
            baseRef = defaultBaseRef
            collisionSeedPaths = []
            inferredPaths = []
        }
        launchCollisionReport = .empty
        scheduleLaunchCollisionRefresh()
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

    func scheduleLaunchCollisionRefresh() {
        collisionRevision += 1
        let revision = collisionRevision
        let prompt = prompt
        let seedPaths = collisionSeedPaths
        collisionRefreshTask?.cancel()
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !seedPaths.isEmpty else {
            inferredPaths = []
            launchCollisionReport = .empty
            isAnalyzingCollisions = false
            return
        }
        isAnalyzingCollisions = true
        collisionRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.performLaunchCollisionRefresh(
                prompt: prompt,
                seedPaths: seedPaths,
                revision: revision
            )
        }
    }

    func refreshLaunchCollisions() async {
        collisionRefreshTask?.cancel()
        collisionRevision += 1
        let revision = collisionRevision
        let prompt = prompt
        let seedPaths = collisionSeedPaths
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !seedPaths.isEmpty else {
            inferredPaths = []
            launchCollisionReport = .empty
            isAnalyzingCollisions = false
            return
        }
        isAnalyzingCollisions = true
        await performLaunchCollisionRefresh(
            prompt: prompt,
            seedPaths: seedPaths,
            revision: revision
        )
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
            await refreshLaunchCollisions()
            isBusy = true
            errorMessage = nil
            successMessage = nil
            let launchedRun = try await actions.launch(request)
            run = launchedRun
            mode = .comparison
            await loadComparison(runID: launchedRun.id, ownsBusyState: true)
        } catch {
            isBusy = false
            errorMessage = message(for: error)
        }
    }

    func showComparison(runID: String) async {
        collisionRefreshTask?.cancel()
        collisionRevision += 1
        isAnalyzingCollisions = false
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
            errorMessage = message(for: error)
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
            if outcome.cleanupFailures.isEmpty {
                successMessage = localizer.string(
                    "projectHome.fanOut.candidatePromoted",
                    fallback: "Candidate promoted."
                )
            } else {
                let heading = localizer.string(
                    "projectHome.fanOut.candidatePromotedWithWarnings",
                    fallback: "Candidate promoted with cleanup warnings."
                )
                successMessage = ([heading] + outcome.cleanupFailures.map { "- \($0)" })
                    .joined(separator: "\n")
            }
            isBusy = false
            await loadComparison(runID: outcome.run.id, ownsBusyState: false)
        } catch {
            if let executionError = error as? TaskRunExecutionError,
               case .promotionUnavailable = executionError,
               let run,
               let selectedCandidateID {
                await refreshPromotionPreview(
                    runID: run.id,
                    candidateID: selectedCandidateID,
                    originalError: error
                )
            } else {
                isBusy = false
                errorMessage = message(for: error)
            }
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
            errorMessage = message(for: error)
        }
    }

    func cancelRun() async {
        guard let run, canCancelRun else { return }
        isBusy = true
        errorMessage = nil
        do {
            self.run = try await actions.cancel(run.id)
            successMessage = localizer.string(
                "taskRun.status.cancelled",
                fallback: "Task run cancelled."
            )
            isBusy = false
            await loadComparison(runID: run.id, ownsBusyState: false)
        } catch {
            let failure = message(for: error)
            isBusy = false
            await loadComparison(runID: run.id, ownsBusyState: false)
            errorMessage = failure
        }
    }

    func forgetRun() async {
        guard let run, canForgetRun else { return }
        isBusy = true
        errorMessage = nil
        do {
            try await actions.forget(run.id)
            self.run = nil
            comparisons = []
            selectedCandidateID = nil
            persistenceIssue = nil
            showInbox()
        } catch {
            isBusy = false
            errorMessage = message(for: error)
        }
    }

    private func loadComparison(runID: String, ownsBusyState: Bool) async {
        loadRevision += 1
        let revision = loadRevision
        isBusy = true
        errorMessage = nil
        persistenceIssue = nil
        do {
            let snapshot = try await actions.loadSnapshot(runID)
            guard revision == loadRevision else { return }
            run = snapshot.run
            comparisons = snapshot.comparisons
            candidateCollisionReport = snapshot.candidateCollisions
            persistenceIssue = snapshot.persistenceIssue
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
            errorMessage = message(for: error)
            if ownsBusyState { mode = .launch }
        }
    }

    private func performLaunchCollisionRefresh(
        prompt: String,
        seedPaths: [String],
        revision: Int
    ) async {
        let analysis = await actions.launchCollisions(prompt, seedPaths)
        guard revision == collisionRevision else { return }
        inferredPaths = analysis.inferredPaths
        launchCollisionReport = analysis.report
        isAnalyzingCollisions = false
    }

    private func refreshPromotionPreview(
        runID: String,
        candidateID: String,
        originalError: Error
    ) async {
        promotionPreview = nil
        do {
            let refreshed = try await actions.preparePromotion(runID, candidateID)
            run = refreshed.run
            comparisons = refreshed.comparisons
            selectedCandidateID = candidateID
            promotionPreview = refreshed
            mode = .promotion
            errorMessage = localizer.string(
                "projectHome.fanOut.promotionRefreshed",
                fallback: "The task changed. Review the refreshed cleanup plan before continuing."
            )
            isBusy = false
        } catch {
            mode = .comparison
            isBusy = false
            errorMessage = message(for: originalError)
            await loadComparison(runID: runID, ownsBusyState: false)
            if errorMessage == nil {
                errorMessage = message(for: originalError)
            }
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

    private func message(for error: Error) -> String {
        return localizer.projectErrorMessage(for: error, context: .fanOut)
    }
}
