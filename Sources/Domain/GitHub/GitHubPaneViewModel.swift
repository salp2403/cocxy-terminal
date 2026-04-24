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

    // MARK: - Dependencies

    private let service: GitHubService

    // MARK: - Lifecycle / concurrency state

    private var autoRefreshCancellable: AnyCancellable?
    private var refreshTask: Task<Void, Never>?

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
                lastErrorMessage = Self.banner(for: error)
                isLoading = false
            }
            return
        } catch {
            guard generation == refreshGeneration else { return }
            applyState {
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
                repo = nil
                pullRequests = []
                issues = []
                checks = []
                selectedPullRequestNumber = nil
                switch error {
                case .noRemote, .notAGitRepository:
                    lastInfoMessage = Self.banner(for: error)
                default:
                    lastErrorMessage = Self.banner(for: error)
                }
                isLoading = false
            }
            return
        } catch {
            guard generation == refreshGeneration else { return }
            applyState {
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
                isLoading = false
            }
        } catch let error as GitHubCLIError {
            guard generation == refreshGeneration else { return }
            applyState {
                lastErrorMessage = Self.banner(for: error)
                isLoading = false
            }
        } catch {
            guard generation == refreshGeneration else { return }
            applyState {
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
        case .commandFailed(_, let stderr, _):
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "The gh command failed." : trimmed
        }
    }
}
