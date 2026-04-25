// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneViewModel.swift - Observable orchestrator for the GitHub
// pane overlay (Cmd+Option+G) introduced in v0.1.84.
//
// The view model owns every piece of state the SwiftUI layer renders
// and routes every subprocess call through the injected
// `GitHubService`. Providers arrive as closures so the MainWindowController
// can push tab-level context (working directory, worktree root,
// feature flags) without the view model having to reach back into
// AppKit.

@preconcurrency import Combine
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - GitHubPaneViewModel

@MainActor
final class GitHubPaneViewModel: ObservableObject {

    // MARK: - Tabs

    /// The three tabs the pane exposes. Each case carries display
    /// metadata so the SwiftUI view can render the segmented picker
    /// without duplicating copy.
    enum Tab: String, CaseIterable, Identifiable, Sendable {
        case pullRequests
        case issues
        case checks

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .pullRequests: return "Pull Requests"
            case .issues: return "Issues"
            case .checks: return "Checks"
            }
        }
        var systemImage: String {
            switch self {
            case .pullRequests: return "arrow.triangle.pull"
            case .issues: return "exclamationmark.circle"
            case .checks: return "checkmark.circle"
            }
        }
    }

    // MARK: - Published state

    /// Currently visible tab. Selection is preserved across refreshes.
    @Published var selectedTab: Tab = .pullRequests

    /// Repository attached to the active working directory. `nil` when
    /// no git remote is discoverable.
    @Published private(set) var repo: GitHubRepo?

    /// Latest `gh auth status`. `nil` before the first refresh.
    @Published private(set) var authStatus: GitHubAuthStatus?

    @Published private(set) var pullRequests: [GitHubPullRequest] = []
    @Published private(set) var issues: [GitHubIssue] = []
    @Published private(set) var checks: [GitHubCheck] = []

    /// PR number whose checks the view currently highlights. Set by
    /// the UI row selection and read by `refresh()` to decide which
    /// PR's checks to fetch.
    @Published var selectedPullRequestNumber: Int?

    /// `true` while a refresh is in flight. The UI shows a progress
    /// indicator; the view model uses the flag to dedupe refreshes
    /// triggered by overlapping events.
    @Published private(set) var isLoading: Bool = false

    /// Non-fatal banner message (error channel). The view renders this
    /// in red with an error glyph.
    @Published private(set) var lastErrorMessage: String?

    /// Non-fatal banner message (info channel). The view renders this
    /// with a neutral tint; used for recoverable states like
    /// "Install gh" or "No GitHub remote".
    @Published private(set) var lastInfoMessage: String?

    /// Whether the overlay is currently attached to the window. The
    /// auto-refresh loop reads this to suspend polling when the pane
    /// is hidden.
    @Published var isVisible: Bool = false {
        didSet {
            if isVisible {
                startAutoRefreshIfNeeded()
            } else {
                stopAutoRefresh()
            }
        }
    }

    // MARK: - Merge state (v0.1.86)

    /// PR numbers currently in flight for `gh pr merge`. The PR row
    /// disables its context-menu Merge action while its number lives
    /// here. Stored as a Set so we can check membership in O(1) and
    /// support multiple in-flight merges across tabs (rare, but cheap
    /// to allow).
    @Published private(set) var pullRequestsBeingMerged: Set<Int> = []

    /// Last successful merge banner. Lives in its own channel so it
    /// does not collide with the discovery info banner that the pane
    /// already uses for "no remote", "install gh", etc.
    @Published private(set) var lastMergeInfoMessage: String?

    // MARK: - Providers (injected by the MainWindowController)

    /// Returns the working directory the pane should use for `gh`
    /// invocations. Prefer the active tab's worktree root over its
    /// plain working directory so per-worktree PR resolution works.
    var workingDirectoryProvider: (() -> URL?)?

    /// Returns the current `[github]` config snapshot. Called once
    /// per refresh so hot-reloaded config changes are honoured without
    /// restarting the pane.
    var configProvider: () -> GitHubConfig = { .defaults }

    /// Opens the given URL. Injected so the pane does not depend on
    /// `NSWorkspace` directly (keeps the view model testable on a
    /// non-AppKit target if the code ever ships cross-platform).
    var onOpenURL: ((URL) -> Void)?

    /// Invoked when the user triggers "Create Pull Request" from the
    /// code-review integration (Fase 10). The closure receives title,
    /// optional body and optional base branch.
    var onCreatePullRequest: ((_ title: String, _ body: String?, _ baseBranch: String?) async -> Void)?

    /// Handler invoked when the user picks Merge from a PR row's
    /// context menu. The MainWindowController wires this to
    /// `GitHubService.mergePullRequest`. Returning the post-merge PR
    /// lets the pane refresh the list and surface a confirmation
    /// banner without an extra round trip.
    var mergePullRequestHandler: ((_ request: GitHubMergeRequest, _ workingDirectory: URL) async throws -> GitHubPullRequest)?

    // MARK: - Dependencies

    private let service: GitHubService

    // MARK: - Lifecycle / concurrency state

    private var autoRefreshCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

    /// Directory that produced the currently rendered PR rows. Merge
    /// actions use this captured value instead of whatever tab happens
    /// to be visible when the user opens the context menu.
    private var pullRequestsWorkingDirectory: URL?

    /// Monotonic counter bumped before every `refresh()` so in-flight
    /// results can be discarded when the user triggers a new refresh
    /// (or switches tab/worktree) before the previous one completes.
    private var refreshGeneration: UInt64 = 0

    // MARK: - Init

    init(service: GitHubService) {
        self.service = service
    }

    deinit {
        // Cancel the autoconnect subscription synchronously so the
        // Timer publisher releases its RunLoop source immediately.
        autoRefreshCancellable?.cancel()
    }

    // MARK: - Public actions

    /// Triggers a refresh of every visible collection. Safe to call
    /// repeatedly; the previous in-flight task is cancelled and its
    /// results discarded via the `refreshGeneration` guard.
    func refresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.performRefresh(generation: generation)
        }
    }

    /// Convenience wrapper so the SwiftUI view can open a URL through
    /// the injected callback without reaching for `NSWorkspace`.
    func open(_ url: URL) {
        onOpenURL?(url)
    }

    /// Selects a pull request as the current checks target and moves
    /// the pane to Checks. The row's context menu still owns the
    /// browser-open affordance, keeping primary click inside Cocxy.
    func selectPullRequestForChecks(_ pullRequest: GitHubPullRequest) {
        selectedPullRequestNumber = pullRequest.number
        selectedTab = .checks
        checks = []
        refresh()
    }

    /// Forwards a "Create PR" request to the code-review integration.
    /// Validation happens in `GitHubService.createPullRequest`; here we
    /// just decorate the pane state so the user gets loading feedback.
    func requestCreatePullRequest(
        title: String,
        body: String? = nil,
        baseBranch: String? = nil
    ) async {
        await MainActor.run { self.isLoading = true }
        await onCreatePullRequest?(title, body, baseBranch)
        await MainActor.run { self.isLoading = false }
        refresh()
    }

    // MARK: - Merge (v0.1.86)

    /// Drives a merge of `pullRequest` using the injected handler. No-op
    /// when no handler is wired, when the PR number is already being
    /// merged, or when `[github].merge-enabled` is false. Refreshes the
    /// pane after a success so the merged PR drops out of the open list.
    func requestMergePullRequest(
        number: Int,
        method: GitHubMergeMethod,
        deleteBranch: Bool,
        subject: String? = nil,
        body: String? = nil
    ) {
        guard configProvider().mergeEnabled else {
            lastErrorMessage = "Pull request merge is disabled in [github].merge-enabled."
            return
        }
        guard let handler = mergePullRequestHandler else {
            lastErrorMessage = "GitHub integration is not ready yet. Reload the pane to retry."
            return
        }
        guard let workingDirectory = pullRequestsWorkingDirectory else {
            lastErrorMessage = "Reload the GitHub pane before merging this pull request."
            return
        }
        guard !pullRequestsBeingMerged.contains(number) else { return }

        let request = GitHubMergeRequest(
            pullRequestNumber: number,
            method: method,
            deleteBranch: deleteBranch,
            subject: subject,
            body: body
        )

        pullRequestsBeingMerged.insert(number)
        lastErrorMessage = nil
        lastMergeInfoMessage = nil

        Task { [weak self] in
            do {
                let merged = try await handler(request, workingDirectory)
                await MainActor.run {
                    guard let self else { return }
                    self.pullRequestsBeingMerged.remove(number)
                    self.lastMergeInfoMessage = "Merged PR #\(merged.number) via \(method.displayName)."
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.pullRequestsBeingMerged.remove(number)
                    self.lastErrorMessage = Self.userFacingMergeErrorMessage(for: error)
                }
            }
        }
    }

    /// Whether a Merge context-menu item should be enabled for a PR
    /// row. Hides the action when the master flag is off, the PR is
    /// not in `OPEN` state, or the user has a draft selected.
    func canOfferMerge(for pullRequest: GitHubPullRequest) -> Bool {
        guard configProvider().mergeEnabled else { return false }
        guard pullRequest.state == .open else { return false }
        guard !pullRequest.isDraft else { return false }
        guard pullRequestsWorkingDirectory != nil else { return false }
        return mergePullRequestHandler != nil
    }

    /// Whether a specific PR row is currently in flight for merge.
    /// Used by the view to show a spinner / disable the menu item.
    func isMerging(_ number: Int) -> Bool {
        pullRequestsBeingMerged.contains(number)
    }

    /// Maps an `Error` into a user-facing string for the error
    /// banner. Recognises `GitHubMergeError` for typed copy and falls
    /// back to `localizedDescription`.
    nonisolated static func userFacingMergeErrorMessage(for error: Error) -> String {
        if let mergeError = error as? GitHubMergeError {
            return mergeError.errorDescription ?? "Pull request could not be merged."
        }
        if let cliError = error as? GitHubCLIError {
            return banner(for: cliError)
        }
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? "Pull request action failed." : description
    }

    // MARK: - Auto refresh

    /// Gate used to skip timer-driven refreshes under `xctest`. The
    /// Timer publisher keeps the main RunLoop alive which hangs the
    /// swift-test process; the workaround matches the one applied to
    /// the Aurora reconciliation loop.
    nonisolated private static var isRunningUnderXCTest: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        if Bundle.main.bundlePath.hasSuffix(".xctest") { return true }
        let names = [
            ProcessInfo.processInfo.processName,
            URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent,
        ].map { $0.lowercased() }
        if names.contains(where: { name in
            name.contains("xctest")
                || name.contains("swiftpm-testing")
                || name.contains("swift-testing")
        }) { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    /// Starts the periodic refresh publisher when the pane becomes
    /// visible. Idempotent; calling twice without `stopAutoRefresh`
    /// in between is a no-op.
    func startAutoRefreshIfNeeded() {
        guard autoRefreshCancellable == nil else { return }
        guard !Self.isRunningUnderXCTest else { return }

        let interval = configProvider().autoRefreshInterval
        guard interval > 0 else { return }

        autoRefreshCancellable = Timer
            .publish(every: TimeInterval(interval), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isVisible else { return }
                self.refresh()
            }
    }

    func stopAutoRefresh() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil
    }

    // MARK: - Orchestrator

    /// Runs the full refresh pipeline for the current generation.
    /// Each stage aborts when the generation no longer matches, so a
    /// burst of tab switches collapses into a single visible result.
    private func performRefresh(generation: UInt64) async {
        guard configProvider().enabled else {
            applyState {
                lastInfoMessage = "GitHub pane is disabled. Enable it in Preferences > GitHub."
                repo = nil
                authStatus = nil
                pullRequests = []
                issues = []
                checks = []
                selectedPullRequestNumber = nil
                pullRequestsWorkingDirectory = nil
                isLoading = false
            }
            return
        }

        guard let workingDirectory = workingDirectoryProvider?() else {
            applyState {
                lastInfoMessage = "Open a git repository to see pull requests and issues."
                repo = nil
                authStatus = nil
                pullRequests = []
                issues = []
                checks = []
                selectedPullRequestNumber = nil
                pullRequestsWorkingDirectory = nil
                isLoading = false
            }
            return
        }

        applyState {
            isLoading = true
            lastErrorMessage = nil
            lastInfoMessage = nil
        }

        // Stage 1: authentication status. We fetch it every refresh so
        // the pane recovers immediately after `gh auth login` without
        // needing a restart.
        let auth: GitHubAuthStatus
        do {
            auth = try await service.authStatus()
        } catch let error as GitHubCLIError {
            guard generation == refreshGeneration else { return }
            applyState {
                clearLoadedDataIfNeeded(currentWorkingDirectory: workingDirectory)
                lastErrorMessage = Self.banner(for: error)
                isLoading = false
            }
            return
        } catch {
            guard generation == refreshGeneration else { return }
            applyState {
                clearLoadedDataIfNeeded(currentWorkingDirectory: workingDirectory)
                lastErrorMessage = error.localizedDescription
                isLoading = false
            }
            return
        }
        guard generation == refreshGeneration else { return }

        applyState { authStatus = auth }
        guard auth.isAuthenticated else {
            applyState {
                lastInfoMessage = "Sign in with `gh auth login` to load GitHub data."
                repo = nil
                pullRequests = []
                issues = []
                checks = []
                selectedPullRequestNumber = nil
                pullRequestsWorkingDirectory = nil
                isLoading = false
            }
            return
        }

        // Stage 2: repository discovery. Typed `.noRemote` and
        // `.notAGitRepository` are informational, not errors.
        let resolvedRepo: GitHubRepo
        do {
            resolvedRepo = try await service.currentRepo(at: workingDirectory)
        } catch let error as GitHubCLIError {
            guard generation == refreshGeneration else { return }
            applyState {
                switch error {
                case .noRemote, .notAGitRepository:
                    repo = nil
                    pullRequests = []
                    issues = []
                    checks = []
                    selectedPullRequestNumber = nil
                    pullRequestsWorkingDirectory = nil
                    lastInfoMessage = Self.banner(for: error)
                default:
                    clearLoadedDataIfNeeded(currentWorkingDirectory: workingDirectory)
                    lastErrorMessage = Self.banner(for: error)
                }
                isLoading = false
            }
            return
        } catch {
            guard generation == refreshGeneration else { return }
            applyState {
                clearLoadedDataIfNeeded(currentWorkingDirectory: workingDirectory)
                lastErrorMessage = error.localizedDescription
                isLoading = false
            }
            return
        }
        guard generation == refreshGeneration else { return }
        applyState { repo = resolvedRepo }

        // Stage 3: bulk fetch PRs and issues in parallel. The actor
        // serialises the subprocess calls internally, so `async let`
        // just fires them back-to-back without blocking MainActor.
        let ghConfig = configProvider()
        do {
            async let prsTask = service.listPullRequests(
                at: workingDirectory,
                state: Self.clampedState(ghConfig.defaultState, allowed: ["open", "closed", "merged", "all"]),
                limit: ghConfig.maxItems,
                includeDrafts: ghConfig.includeDrafts
            )
            async let issuesTask = service.listIssues(
                at: workingDirectory,
                state: Self.clampedState(ghConfig.defaultState, allowed: ["open", "closed", "all"]),
                limit: ghConfig.maxItems
            )
            let fetchedPRs = try await prsTask
            let fetchedIssues = try await issuesTask
            guard generation == refreshGeneration else { return }

            // Stage 4: checks for whichever PR is currently selected
            // (or the first one if no explicit selection). Failure here
            // is non-fatal — the view still renders PRs and issues.
            let targetNumber: Int?
            if let selectedPullRequestNumber,
               fetchedPRs.contains(where: { $0.number == selectedPullRequestNumber }) {
                targetNumber = selectedPullRequestNumber
            } else {
                targetNumber = fetchedPRs.first?.number
            }
            var fetchedChecks: [GitHubCheck] = []
            if let number = targetNumber {
                fetchedChecks = (try? await service.checksForPullRequest(
                    number: number,
                    at: workingDirectory
                )) ?? []
            }
            guard generation == refreshGeneration else { return }

            applyState {
                pullRequests = fetchedPRs
                issues = fetchedIssues
                checks = fetchedChecks
                selectedPullRequestNumber = targetNumber
                pullRequestsWorkingDirectory = workingDirectory
                isLoading = false
            }
        } catch let error as GitHubCLIError {
            guard generation == refreshGeneration else { return }
            applyState {
                clearLoadedDataIfNeeded(currentWorkingDirectory: workingDirectory)
                lastErrorMessage = Self.banner(for: error)
                isLoading = false
            }
        } catch {
            guard generation == refreshGeneration else { return }
            applyState {
                clearLoadedDataIfNeeded(currentWorkingDirectory: workingDirectory)
                lastErrorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Applies a batch of `@Published` mutations. The helper exists so
    /// every exit path in `performRefresh` is visually aligned and so
    /// future refactors can attach logging to a single choke point
    /// without touching every call site.
    private func applyState(_ mutate: () -> Void) {
        mutate()
    }

    private func clearLoadedDataIfNeeded(currentWorkingDirectory: URL) {
        guard pullRequestsWorkingDirectory != currentWorkingDirectory else { return }
        pullRequests = []
        issues = []
        checks = []
        selectedPullRequestNumber = nil
        pullRequestsWorkingDirectory = nil
    }

    // MARK: - Static helpers

    /// Normalises a `--state` value to the subset the `gh` subcommand
    /// accepts. Falls back to the first allowed value when the user
    /// picked something the verb does not understand (e.g. `merged`
    /// for the issue list).
    nonisolated static func clampedState(_ raw: String, allowed: [String]) -> String {
        let lower = raw.lowercased()
        return allowed.contains(lower) ? lower : (allowed.first ?? "open")
    }

    /// Maps a `GitHubCLIError` to user-facing banner copy. Public so
    /// the code-review integration and the CLI bridge can reuse the
    /// same strings. Marked `nonisolated` because it is a pure
    /// function over the enum and has no dependency on actor state.
    nonisolated static func banner(for error: GitHubCLIError) -> String {
        switch error {
        case .notInstalled:
            return "Install the GitHub CLI: brew install gh"
        case .notAuthenticated:
            return "Sign in with `gh auth login` to enable the GitHub pane."
        case .noRemote:
            return "No GitHub remote detected for this repository."
        case .notAGitRepository:
            return "Open a git repository to see pull requests and issues."
        case .rateLimited:
            return "GitHub rate limit reached. Try again later."
        case .timeout(let seconds):
            return "GitHub CLI timed out after \(Int(seconds))s. Check your network."
        case .invalidJSON(let reason):
            return "Unexpected gh output: \(reason)"
        case .unsupportedVersion:
            return "Update the GitHub CLI (`gh`). Homebrew users can run: brew upgrade gh"
        case .commandFailed(_, let stderr, _):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "The gh command failed." : trimmed
        }
    }
}
