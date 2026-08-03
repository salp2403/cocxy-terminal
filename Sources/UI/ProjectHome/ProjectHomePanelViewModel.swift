// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomePanelViewModel.swift - Per-panel context and action state.

import Combine
import Foundation

struct ProjectHomeHeaderState: Equatable {
    let displayName: String
    let accent: String?
    let remoteOrigin: String?
}

@MainActor
struct ProjectHomeActions {
    let createSession: () -> Void
    let createWorktree: (() -> Void)?
    let launchTeam: (ProjectTeamLaunchRequest) async throws -> Void
    let openCodeReview: () -> Void
    let activateEntry: (TaskInboxNavigation) -> Void
    let focusWorktree: ((String) async throws -> Void)?
    let openRecentDiff: ((String) -> Void)?
}

@MainActor
final class ProjectHomePanelViewModel: ObservableObject {
    let projectID: ProjectID
    let projectRoot: URL
    let worktreeConfig: WorktreeConfig
    let actions: ProjectHomeActions

    @Published private(set) var displayName: String
    @Published private(set) var accent: String?
    @Published private(set) var gitMetadata: ProjectHomeGitMetadata?
    @Published private(set) var worktrees: [WorktreeManifest.WorktreeEntry] = []
    @Published private(set) var recentDiffSessionID: String?
    @Published private(set) var gitContextFailed = false
    @Published private(set) var worktreeContextFailed = false
    @Published private(set) var activitySummaryState: ProjectActivitySummaryState = .loading
    @Published private(set) var isLoadingContext = true
    @Published private(set) var isLaunchingTeam = false
    @Published var isTeamSheetPresented = false
    @Published var actionErrorMessage: String?

    private var fallbackRemote: String?
    private let localizer: AppLocalizer
    private let contextLoader: ProjectHomeContextLoader
    private let activitySummaryLoader: @MainActor (ProjectID) async -> ProjectActivitySummaryState
    private let recentDiffProvider: () -> String?
    private var loadTask: Task<Void, Never>?
    private var activityLoadTask: Task<Void, Never>?
    private var headerCancellable: AnyCancellable?

    init(
        projectID: ProjectID,
        projectRoot: URL,
        displayName: String,
        accent: String?,
        fallbackRemote: String?,
        worktreeConfig: WorktreeConfig,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .english),
        contextLoader: ProjectHomeContextLoader = .live,
        headerUpdates: AnyPublisher<ProjectHomeHeaderState, Never>? = nil,
        activitySummaryLoader: @escaping @MainActor (
            ProjectID
        ) async -> ProjectActivitySummaryState = { _ in .disabled },
        recentDiffProvider: @escaping () -> String?,
        actions: ProjectHomeActions
    ) {
        self.projectID = projectID
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.accent = accent
        self.fallbackRemote = fallbackRemote
        self.worktreeConfig = worktreeConfig
        self.localizer = localizer
        self.contextLoader = contextLoader
        self.activitySummaryLoader = activitySummaryLoader
        self.recentDiffProvider = recentDiffProvider
        self.actions = actions
        headerCancellable = headerUpdates?.removeDuplicates().sink { [weak self] state in
            self?.applyHeaderState(state)
        }
    }

    func loadContext() {
        loadTask?.cancel()
        isLoadingContext = true
        recentDiffSessionID = recentDiffProvider()
        reloadActivitySummary()
        let root = projectRoot
        let remote = fallbackRemote
        let config = worktreeConfig
        let loader = contextLoader
        loadTask = Task { [weak self] in
            async let metadataResult = loader.gitMetadata(root, remote)
            async let worktreeResult = loader.worktrees(root, config)
            let (metadata, worktrees) = await (metadataResult, worktreeResult)
            guard !Task.isCancelled, let self else { return }
            switch metadata {
            case .success(let value):
                gitMetadata = value
                gitContextFailed = false
            case .failure:
                gitMetadata = nil
                gitContextFailed = true
            }
            switch worktrees {
            case .success(let values):
                self.worktrees = values
                worktreeContextFailed = false
            case .failure:
                self.worktrees = []
                worktreeContextFailed = config.enabled
            }
            isLoadingContext = false
        }
    }

    func reloadActivitySummary(after delay: Duration = .zero) {
        activityLoadTask?.cancel()
        activitySummaryState = .loading
        let projectID = projectID
        let loader = activitySummaryLoader
        activityLoadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            let state = await loader(projectID)
            guard !Task.isCancelled else { return }
            self?.activitySummaryState = state
        }
    }

    private func applyHeaderState(_ state: ProjectHomeHeaderState) {
        let previousFallback = fallbackRemote
        displayName = state.displayName
        accent = state.accent
        fallbackRemote = state.remoteOrigin
        guard let metadata = gitMetadata,
              metadata.remoteOrigin == nil || metadata.remoteOrigin == previousFallback else {
            return
        }
        gitMetadata = ProjectHomeGitMetadata(
            remoteOrigin: state.remoteOrigin,
            statusSummary: metadata.statusSummary
        )
    }

    func launchTeam(_ request: ProjectTeamLaunchRequest) async {
        guard !isLaunchingTeam else { return }
        isLaunchingTeam = true
        actionErrorMessage = nil
        defer { isLaunchingTeam = false }
        do {
            try await actions.launchTeam(request)
            isTeamSheetPresented = false
        } catch {
            actionErrorMessage = localizer.projectErrorMessage(for: error, context: .teamLaunch)
        }
    }

    func focusWorktree(_ id: String) async {
        guard let focusWorktree = actions.focusWorktree else { return }
        actionErrorMessage = nil
        do {
            try await focusWorktree(id)
        } catch {
            actionErrorMessage = localizer.projectErrorMessage(for: error, context: .worktreeOpen)
        }
    }
}
