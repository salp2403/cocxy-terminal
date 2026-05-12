// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneViewModelSwiftTestingTests.swift - Unit tests for the
// orchestrator the GitHub pane binds against.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubPaneViewModel", .serialized)
@MainActor
struct GitHubPaneViewModelSwiftTestingTests {

    // MARK: - Runner spy reuse

    /// Local copy of the runner spy pattern used by the actor tests.
    /// Declared per-suite so the two test files stay independent.
    final class RunnerSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var invocations: [(directory: URL, args: [String], timeout: TimeInterval)] = []
        private var stubs: [(predicate: @Sendable ([String]) -> Bool, result: GitHubCLIResult)] = []

        func stub(
            matching predicate: @escaping @Sendable ([String]) -> Bool,
            result: GitHubCLIResult
        ) {
            lock.lock()
            stubs.append((predicate, result))
            lock.unlock()
        }

        var runner: GitHubService.Runner {
            return { [self] directory, args, timeout in
                self.lock.lock()
                self.invocations.append((directory: directory, args: args, timeout: timeout))
                let stubs = self.stubs
                self.lock.unlock()
                for stub in stubs where stub.predicate(args) {
                    return stub.result
                }
                return GitHubCLIResult(
                    stdout: "",
                    stderr: "no stub matched for args: \(args)",
                    terminationStatus: 1
                )
            }
        }

        var allInvocations: [(directory: URL, args: [String], timeout: TimeInterval)] {
            lock.lock()
            defer { lock.unlock() }
            return invocations
        }
    }

    final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func incrementAndGet() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private func makeService(configure: (RunnerSpy) -> Void) -> GitHubService {
        let spy = RunnerSpy()
        configure(spy)
        return GitHubService(runner: spy.runner)
    }

    /// Drive the view model past the asynchronous `refresh` hop. The
    /// polling happens on the main run loop so a short sleep is
    /// enough to let every awaited continuation resume.
    private func flush() async {
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 20_000_000)
            if !Task.isCancelled { /* give the loop a chance */ }
        }
    }

    // MARK: - Tab shape

    @Test("Tab cases expose stable id + icon for the segmented picker")
    func tab_casesExposeStableIdAndIcon() {
        #expect(GitHubPaneViewModel.Tab.allCases.count == 7)
        #expect(GitHubPaneViewModel.Tab.branches.id == "branches")
        #expect(GitHubPaneViewModel.Tab.commits.id == "commits")
        #expect(GitHubPaneViewModel.Tab.diffs.systemImage == "doc.text.magnifyingglass")
        #expect(GitHubPaneViewModel.Tab.pullRequests.id == "pullRequests")
        #expect(GitHubPaneViewModel.Tab.issues.systemImage == "exclamationmark.circle")
        #expect(GitHubPaneViewModel.Tab.reviewThreads.systemImage == "bubble.left.and.bubble.right")
    }

    @Test("Tab compact titles keep the side panel strip from overflowing")
    func tab_compactTitlesKeepSidePanelUsable() {
        let localizer = AppLocalizer(languagePreference: .english)

        #expect(GitHubPaneViewModel.Tab.pullRequests.compactLocalizedTitle(using: localizer) == "PRs")
        #expect(GitHubPaneViewModel.Tab.reviewThreads.compactLocalizedTitle(using: localizer) == "Threads")
        #expect(
            GitHubPaneViewModel.Tab.allCases
                .map { $0.compactLocalizedTitle(using: localizer) }
                .allSatisfy { !$0.isEmpty && $0.count <= 8 }
        )
    }

    // MARK: - clampedState

    @Test("clampedState returns the raw value when allowed")
    func clampedState_returnsRawWhenAllowed() {
        #expect(GitHubPaneViewModel.clampedState("open", allowed: ["open", "closed"]) == "open")
        #expect(GitHubPaneViewModel.clampedState("CLOSED", allowed: ["open", "closed"]) == "closed")
    }

    @Test("clampedState falls back to the first allowed value otherwise")
    func clampedState_fallsBackToFirstAllowedValue() {
        #expect(GitHubPaneViewModel.clampedState("merged", allowed: ["open", "closed", "all"]) == "open")
        #expect(GitHubPaneViewModel.clampedState("", allowed: ["open"]) == "open")
    }

    // MARK: - Source Control

    @Test("refresh loads local source control state beside GitHub data")
    func refresh_loadsLocalSourceControlState() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp/source-control") }
        viewModel.branchListProvider = { _, _ in [
            GitBranch(name: "main", isCurrent: true, isRemote: false, lastCommitHash: "abc1234"),
            GitBranch(name: "origin/main", isCurrent: false, isRemote: true),
        ] }
        viewModel.commitHistoryProvider = { _, _ in [
            GitCommit(
                hash: "0123456789abcdef",
                shortHash: "0123456",
                subject: "Add source control",
                authorName: "Said Arturo Lopez",
                authorEmail: "dev@cocxy.dev",
                authoredAt: Date(timeIntervalSince1970: 0)
            ),
        ] }
        viewModel.diffListProvider = { _ in [
            FileDiff(
                filePath: "Sources/App.swift",
                status: .modified,
                hunks: [
                    DiffHunk(
                        header: "@@ -1 +1 @@",
                        oldStart: 1,
                        oldCount: 1,
                        newStart: 1,
                        newCount: 1,
                        lines: [
                            DiffLine(kind: .deletion, content: "old", oldLineNumber: 1, newLineNumber: nil),
                            DiffLine(kind: .addition, content: "new", oldLineNumber: nil, newLineNumber: 1),
                        ]
                    ),
                ]
            ),
        ] }
        viewModel.worktreeEntriesProvider = {
            [
                WorktreeManifest.WorktreeEntry(
                    id: "wt-1",
                    branch: "feature/source-control",
                    path: URL(fileURLWithPath: "/tmp/wt-1"),
                    createdAt: Date(timeIntervalSince1970: 0),
                    agent: nil,
                    tabID: nil
                ),
            ]
        }

        viewModel.refresh()
        await flush()

        #expect(viewModel.branches.map(\.name) == ["main", "origin/main"])
        #expect(viewModel.commits.map(\.shortHash) == ["0123456"])
        #expect(viewModel.currentDiffs.map(\.filePath) == ["Sources/App.swift"])
        #expect(viewModel.worktreeEntries.map(\.branch) == ["feature/source-control"])
        #expect(viewModel.selectedBranchName == "main")
        #expect(viewModel.selectedCommitHash == "0123456789abcdef")
        #expect(viewModel.sourceControlErrorMessage == nil)
    }

    @Test("generate pull request draft resolves base and current head branch")
    func generatePullRequestDraft_resolvesBaseAndHeadBranch() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        let directory = URL(fileURLWithPath: "/tmp/git-assistant-pane")
        let captured = LockedBox<(directory: URL?, base: String?, head: String?, settings: GitAssistantSettings?)>(
            (nil, nil, nil, nil)
        )
        viewModel.workingDirectoryProvider = { directory }
        viewModel.branchListProvider = { _, _ in [
            GitBranch(name: "main", isCurrent: false, isRemote: false),
            GitBranch(name: "feature/git-assistant", isCurrent: true, isRemote: false),
        ] }
        viewModel.gitAssistantConfigProvider = {
            GitAssistantSettings(enabled: true, maxDiffLines: 240)
        }
        viewModel.generatePullRequestDraftProvider = { directory, base, head, settings in
            captured.withValue { value in
                value = (directory, base, head, settings)
            }
            return GitAssistantPullRequestDraft(title: "Improve source control", body: "Summary")
        }

        viewModel.refresh()
        await flush()

        #expect(viewModel.canGeneratePullRequestDraft())
        let draft = try await viewModel.generatePullRequestDraft(baseBranch: nil)
        let snapshot = captured.withValue { $0 }

        #expect(draft.title == "Improve source control")
        #expect(snapshot.directory == directory)
        #expect(snapshot.base == "main")
        #expect(snapshot.head == "feature/git-assistant")
        #expect(snapshot.settings?.maxDiffLines == 240)
    }

    @Test("generate pull request draft is gated when Git Assistant is disabled")
    func generatePullRequestDraft_requiresEnabledSettings() async throws {
        let viewModel = GitHubPaneViewModel(service: makeService { _ in })
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp/git-assistant-disabled") }
        viewModel.gitAssistantConfigProvider = { GitAssistantSettings(enabled: false) }
        viewModel.generatePullRequestDraftProvider = { _, _, _, _ in
            Issue.record("Provider must not run while Git Assistant is disabled")
            return GitAssistantPullRequestDraft(title: "", body: "")
        }

        #expect(!viewModel.canGeneratePullRequestDraft())
        do {
            _ = try await viewModel.generatePullRequestDraft(baseBranch: nil)
            Issue.record("Expected disabled Git Assistant to throw")
        } catch {
            #expect(error.localizedDescription.contains("disabled"))
        }
    }

    @Test("create branch uses provider then refreshes source control")
    func createBranch_usesProviderThenRefreshes() async throws {
        let viewModel = GitHubPaneViewModel(service: makeService { _ in })
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp/source-control") }
        var created: (name: String, startPoint: String?)?
        viewModel.createBranchProvider = { name, _, startPoint, checkout in
            #expect(checkout)
            created = (name, startPoint)
            return GitBranch(name: name, isCurrent: true, isRemote: false)
        }
        viewModel.branchListProvider = { _, _ in [GitBranch(name: "feature/ui", isCurrent: true)] }
        viewModel.commitHistoryProvider = { _, _ in [] }
        viewModel.diffListProvider = { _ in [] }

        await viewModel.createBranch(named: "feature/ui", startPoint: "main")

        #expect(created?.name == "feature/ui")
        #expect(created?.startPoint == "main")
        #expect(viewModel.selectedBranchName == "feature/ui")
        #expect(viewModel.branches.map(\.name) == ["feature/ui"])
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test("create pull request uses provider and selects hydrated PR")
    func createPullRequest_usesProviderAndSelectsHydratedPR() async throws {
        let viewModel = GitHubPaneViewModel(service: makeService { _ in })
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp/source-control") }
        var capturedRequest: PullRequestCreateRequest?
        viewModel.createPullRequestProvider = { request, _ in
            capturedRequest = request
            return GitHubPullRequest(
                number: 44,
                title: request.title,
                state: .open,
                author: GitHubUser(login: "said"),
                headRefName: "feature/source-control",
                baseRefName: request.baseBranch ?? "main",
                isDraft: request.draft,
                url: URL(string: "https://github.com/u/r/pull/44")!,
                updatedAt: Date()
            )
        }

        await viewModel.createPullRequest(
            PullRequestCreateRequest(
                title: "Add source control",
                body: "Body",
                baseBranch: "main",
                reviewers: ["reviewer"],
                draft: true
            )
        )

        #expect(capturedRequest?.title == "Add source control")
        #expect(capturedRequest?.reviewers == ["reviewer"])
        #expect(viewModel.pullRequests.map(\.number) == [44])
        #expect(viewModel.selectedPullRequestNumber == 44)
        #expect(viewModel.selectedTab == .pullRequests)
        #expect(viewModel.lastInfoMessage?.contains("#44") == true)
    }

    @Test("stage diff hunk uses provider then refreshes source control")
    func stageDiffHunk_usesProviderThenRefreshes() async throws {
        let viewModel = GitHubPaneViewModel(service: makeService { _ in })
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp/source-control") }
        let diff = FileDiff(filePath: "Sources/App.swift", status: .modified, hunks: [
            DiffHunk(
                header: "@@ -1 +1 @@",
                oldStart: 1,
                oldCount: 1,
                newStart: 1,
                newCount: 1,
                lines: [
                    DiffLine(kind: .deletion, content: "old", oldLineNumber: 1, newLineNumber: nil),
                    DiffLine(kind: .addition, content: "new", oldLineNumber: nil, newLineNumber: 1),
                ]
            ),
        ])
        var stagedAction: DiffStagingAction?
        viewModel.diffStagingProvider = { _, fileDiff, _, action in
            #expect(fileDiff.filePath == "Sources/App.swift")
            stagedAction = action
        }
        viewModel.branchListProvider = { _, _ in [] }
        viewModel.commitHistoryProvider = { _, _ in [] }
        viewModel.diffListProvider = { _ in [] }

        viewModel.stageDiffHunk(fileDiff: diff, hunk: diff.hunks[0], action: .stage)
        await flush()

        #expect(stagedAction == .stage)
        #expect(viewModel.sourceControlErrorMessage == nil)
    }

    // MARK: - banner copy

    @Test("banner copy covers every GitHubCLIError case")
    func banner_coversEveryErrorCase() {
        #expect(GitHubPaneViewModel.banner(for: .notInstalled).contains("brew install gh"))
        #expect(GitHubPaneViewModel.banner(for: .notAuthenticated(stderr: "")).contains("gh auth login"))
        #expect(GitHubPaneViewModel.banner(for: .noRemote).contains("GitHub remote"))
        #expect(GitHubPaneViewModel.banner(for: .notAGitRepository(path: "")).contains("git repository"))
        #expect(GitHubPaneViewModel.banner(for: .rateLimited(resetAt: nil)).contains("rate limit"))
        #expect(GitHubPaneViewModel.banner(for: .timeout(seconds: 5)).contains("timed out"))
        #expect(GitHubPaneViewModel.banner(for: .invalidJSON(reason: "bad")).contains("bad"))
        let unsupportedVersionBanner = GitHubPaneViewModel.banner(for: .unsupportedVersion(stderr: ""))
        #expect(unsupportedVersionBanner.contains("Update the GitHub CLI"))
        #expect(unsupportedVersionBanner.contains("brew upgrade gh"))

        let failure = GitHubPaneViewModel.banner(for: .commandFailed(
            command: "gh repo view",
            stderr: "unknown flag --foo",
            exitCode: 1
        ))
        #expect(failure.contains("unknown flag --foo"))
    }

    // MARK: - Refresh flows

    @Test("refresh loads PRs and issues when authenticated + repo present")
    func refresh_loadsPRsAndIssuesOnHappyPath() async throws {
        let service = makeService { spy in
            // gh auth status: logged in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            // gh repo view
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            // gh pr list
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            // gh issue list
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 10, "title": "bug", "state": "OPEN", "author": {"login": "r"}, "labels": [], "comments": 2, "url": "https://github.com/u/r/issues/10", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            // gh pr checks 1
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") && $0.contains("1") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.refresh()
        await flush()

        #expect(viewModel.repo?.fullName == "u/r")
        #expect(viewModel.pullRequests.count == 1)
        #expect(viewModel.issues.count == 1)
        #expect(viewModel.authStatus?.isAuthenticated == true)
        #expect(viewModel.isLoading == false)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.lastInfoMessage == nil)
        #expect(viewModel.setupAction == nil)
    }

    @Test("refresh loads PRs when repository issues are disabled")
    func refresh_loadsPRsWhenIssuesAreDisabled() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": false,
                  "isEmpty": false,
                  "isPrivate": true,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") && $0.contains("1") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.refresh()
        await flush()

        #expect(viewModel.repo?.fullName == "u/r")
        #expect(viewModel.repo?.hasIssuesEnabled == false)
        #expect(viewModel.pullRequests.count == 1)
        #expect(viewModel.issues.isEmpty)
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test("refresh surfaces .noRemote as an informational banner")
    func refresh_surfacesNoRemoteAsInfo() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account u (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: "",
                stderr: "unable to determine the repository to use",
                terminationStatus: 1
            ))
        }
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.refresh()
        await flush()

        #expect(viewModel.repo == nil)
        #expect(viewModel.lastInfoMessage != nil)
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test("refresh surfaces .notAuthenticated as an info banner and clears data")
    func refresh_surfacesNotAuthenticatedAsInfo() async throws {
        let service = makeService { spy in
            spy.stub(matching: { _ in true }, result: GitHubCLIResult(
                stdout: "",
                stderr: "You are not logged into any GitHub hosts. Run gh auth login.",
                terminationStatus: 1
            ))
        }
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        // Seed some stale state so we can assert it clears.
        viewModel.refresh()
        await flush()

        #expect(viewModel.pullRequests.isEmpty)
        #expect(viewModel.issues.isEmpty)
        #expect(viewModel.lastInfoMessage?.contains("gh auth login") == true)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.setupAction == .signIn)
    }

    @Test("missing gh surfaces install setup action as info")
    func refresh_missingGHSurfacesInstallSetupAction() async throws {
        let service = GitHubService { _, _, _ in
            throw GitHubCLIError.notInstalled
        }
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }

        viewModel.refresh()
        await flush()

        #expect(viewModel.lastInfoMessage?.contains("Install the GitHub CLI") == true)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.setupAction == .installCLI)
    }

    @Test("sign-in setup action starts gh auth login in the provided directory")
    func setupAction_signInStartsAuthenticationInProvidedDirectory() {
        let viewModel = GitHubPaneViewModel(service: makeService { _ in })
        let directory = URL(fileURLWithPath: "/tmp/github-auth")
        var launchedDirectory: URL?
        viewModel.workingDirectoryProvider = { directory }
        viewModel.onStartAuthentication = { workingDirectory in
            launchedDirectory = workingDirectory
            return true
        }

        viewModel.performSetupAction(.signIn)

        #expect(launchedDirectory == directory)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.lastInfoMessage?.contains("new tab") == true)
        #expect(viewModel.setupAction == nil)
    }

    @Test("install setup action opens the GitHub CLI guide")
    func setupAction_installOpensCLIWebsite() {
        let viewModel = GitHubPaneViewModel(service: makeService { _ in })
        var openedURL: URL?
        viewModel.onOpenURL = { openedURL = $0 }

        viewModel.performSetupAction(.installCLI)

        #expect(openedURL?.host == "cli.github.com")
        #expect(viewModel.lastInfoMessage?.contains("install guide") == true)
    }

    @Test("refresh with disabled config short-circuits before any gh call")
    func refresh_disabledConfigShortCircuits() async throws {
        let service = makeService { spy in
            spy.stub(matching: { _ in true }, result: GitHubCLIResult(
                stdout: "",
                stderr: "should not be reached",
                terminationStatus: 1
            ))
        }
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.configProvider = {
            GitHubConfig(
                enabled: false,
                autoRefreshInterval: 0,
                maxItems: 30,
                includeDrafts: true,
                defaultState: "open"
            )
        }
        viewModel.refresh()
        await flush()

        #expect(viewModel.lastInfoMessage?.contains("disabled") == true)
        #expect(viewModel.pullRequests.isEmpty)
    }

    @Test("refresh with missing working directory surfaces a friendly banner")
    func refresh_missingWorkingDirectoryIsInformational() async throws {
        let service = makeService { _ in }
        let viewModel = GitHubPaneViewModel(service: service)
        // No workingDirectoryProvider attached.
        viewModel.refresh()
        await flush()

        #expect(viewModel.lastInfoMessage?.contains("git repository") == true)
    }

    @Test("missing working directory clears stale GitHub data")
    func refresh_missingWorkingDirectoryClearsStaleData() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 10, "title": "bug", "state": "OPEN", "author": {"login": "r"}, "labels": [], "comments": 2, "url": "https://github.com/u/r/issues/10", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") }, result: GitHubCLIResult(
                stdout: #"[{"name":"build","state":"SUCCESS","bucket":"pass","link":"https://github.com/u/r/actions/runs/1"}]"#,
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        var directory: URL? = URL(fileURLWithPath: "/tmp")
        viewModel.workingDirectoryProvider = { directory }
        viewModel.refresh()
        await flush()

        #expect(viewModel.repo?.fullName == "u/r")
        #expect(viewModel.pullRequests.count == 1)
        #expect(viewModel.issues.count == 1)
        #expect(viewModel.checks.count == 1)
        #expect(viewModel.selectedPullRequestNumber == 1)

        directory = nil
        viewModel.refresh()
        await flush()

        #expect(viewModel.repo == nil)
        #expect(viewModel.authStatus == nil)
        #expect(viewModel.pullRequests.isEmpty)
        #expect(viewModel.issues.isEmpty)
        #expect(viewModel.checks.isEmpty)
        #expect(viewModel.selectedPullRequestNumber == nil)
        #expect(viewModel.lastInfoMessage?.contains("git repository") == true)
    }

    @Test("repo discovery timeout preserves loaded data for the same working directory")
    func refresh_repoTimeoutPreservesLoadedDataForSameWorkingDirectory() async throws {
        let repoViewCalls = LockedCounter()
        let service = GitHubService { _, args, _ in
            if args.first == "auth", args.dropFirst().first == "status" {
                return GitHubCLIResult(
                    stdout: "",
                    stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                    terminationStatus: 0
                )
            }
            if args.contains("repo"), args.contains("view") {
                if repoViewCalls.incrementAndGet() > 1 {
                    throw GitHubCLIError.timeout(seconds: 10)
                }
                return GitHubCLIResult(
                    stdout: #"""
                    {
                      "defaultBranchRef": {"name": "main"},
                      "description": "",
                      "hasIssuesEnabled": true,
                      "isEmpty": false,
                      "isPrivate": false,
                      "name": "r",
                      "owner": {"login": "u"},
                      "url": "https://github.com/u/r"
                    }
                    """#,
                    stderr: "",
                    terminationStatus: 0
                )
            }
            if args.contains("pr"), args.contains("list") {
                return GitHubCLIResult(
                    stdout: #"""
                    [
                      {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
                    ]
                    """#,
                    stderr: "",
                    terminationStatus: 0
                )
            }
            if args.contains("issue"), args.contains("list") {
                return GitHubCLIResult(
                    stdout: #"""
                    [
                      {"number": 10, "title": "bug", "state": "OPEN", "author": {"login": "r"}, "labels": [], "comments": 2, "url": "https://github.com/u/r/issues/10", "updatedAt": "2026-04-23T15:47:21Z"}
                    ]
                    """#,
                    stderr: "",
                    terminationStatus: 0
                )
            }
            if args.contains("pr"), args.contains("checks") {
                return GitHubCLIResult(stdout: "[]", stderr: "", terminationStatus: 0)
            }
            return GitHubCLIResult(stdout: "", stderr: "unexpected gh invocation: \(args.joined(separator: " "))", terminationStatus: 1)
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp/github-pane") }
        viewModel.refresh()
        await flush()

        #expect(viewModel.repo?.fullName == "u/r")
        #expect(viewModel.pullRequests.count == 1)
        #expect(viewModel.issues.count == 1)

        viewModel.refresh()
        await flush()

        #expect(viewModel.repo?.fullName == "u/r")
        #expect(viewModel.pullRequests.count == 1)
        #expect(viewModel.issues.count == 1)
        #expect(viewModel.lastErrorMessage?.contains("timed out") == true)
        #expect(viewModel.isLoading == false)
    }

    @Test("selectPullRequestForChecks targets the selected PR checks")
    func selectPullRequestForChecks_refreshesSelectedPRChecks() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"},
                  {"number": 2, "title": "second", "state": "OPEN", "author": {"login": "u"}, "headRefName": "b", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/2", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") && $0.contains("1") }, result: GitHubCLIResult(
                stdout: #"[{"name":"first-check","state":"SUCCESS","bucket":"pass","link":"https://github.com/u/r/actions/runs/1"}]"#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") && $0.contains("2") }, result: GitHubCLIResult(
                stdout: #"[{"name":"second-check","state":"PENDING","bucket":"pending","link":"https://github.com/u/r/actions/runs/2"}]"#,
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.refresh()
        await flush()
        #expect(viewModel.selectedPullRequestNumber == 1)
        #expect(viewModel.checks.first?.name == "first-check")

        let second = try #require(viewModel.pullRequests.first(where: { $0.number == 2 }))
        viewModel.selectPullRequestForChecks(second)
        await flush()

        #expect(viewModel.selectedTab == .checks)
        #expect(viewModel.selectedPullRequestNumber == 2)
        #expect(viewModel.checks.first?.name == "second-check")
        #expect(viewModel.checks.first?.status == .pending)
    }

    @Test("selectPullRequestForReviewThreads targets remote unresolved and resolved conversations")
    func selectPullRequestForReviewThreads_refreshesSelectedPRThreads() async throws {
        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"},
                  {"number": 2, "title": "second", "state": "OPEN", "author": {"login": "u"}, "headRefName": "b", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/2", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("api") && $0.contains("graphql") && $0.contains("number=1") }, result: GitHubCLIResult(
                stdout: #"{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}"#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("api") && $0.contains("graphql") && $0.contains("number=2") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "data": {
                    "repository": {
                      "pullRequest": {
                        "reviewThreads": {
                          "nodes": [
                            {
                              "id": "PRRT_2",
                              "isResolved": false,
                              "isOutdated": false,
                              "viewerCanResolve": true,
                              "viewerCanUnresolve": false,
                              "path": "Sources/App.swift",
                              "line": 7,
                              "startLine": null,
                              "comments": {
                                "nodes": [
                                  {
                                    "id": "PRRC_2",
                                    "body": "Can this branch return early?",
                                    "author": {"login": "reviewer"},
                                    "createdAt": "2026-05-05T10:00:00Z",
                                    "url": "https://github.com/u/r/pull/2#discussion_r2"
                                  }
                                ]
                              }
                            }
                          ],
                          "pageInfo": {"hasNextPage": false, "endCursor": null}
                        }
                      }
                    }
                  }
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.refresh()
        await flush()
        #expect(viewModel.selectedPullRequestNumber == 1)
        #expect(viewModel.reviewThreads.isEmpty)

        let second = try #require(viewModel.pullRequests.first(where: { $0.number == 2 }))
        viewModel.selectPullRequestForReviewThreads(second)
        await flush()

        #expect(viewModel.selectedTab == .reviewThreads)
        #expect(viewModel.selectedPullRequestNumber == 2)
        #expect(viewModel.reviewThreads.map(\.id) == ["PRRT_2"])
        #expect(viewModel.reviewThreads[0].state == .unresolved)
        #expect(viewModel.reviewThreads[0].comments.count == 1)
        #expect(viewModel.reviewThreads[0].comments.first?.body == "Can this branch return early?")
    }

    @Test("review thread resolution actions mutate GitHub and update the local row")
    func reviewThreadResolutionActions_updateLocalThreadState() async throws {
        let spy = RunnerSpy()
        spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
            stdout: "",
            stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "defaultBranchRef": {"name": "main"},
              "description": "",
              "hasIssuesEnabled": true,
              "isEmpty": false,
              "isPrivate": false,
              "name": "r",
              "owner": {"login": "u"},
              "url": "https://github.com/u/r"
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
            stdout: #"""
            [
              {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
            ]
            """#,
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
            stdout: "[]",
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("pr") && $0.contains("checks") }, result: GitHubCLIResult(
            stdout: "[]",
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: { $0.contains("api") && $0.contains("graphql") && $0.contains("number=1") }, result: GitHubCLIResult(
            stdout: #"""
            {
              "data": {
                "repository": {
                  "pullRequest": {
                    "reviewThreads": {
                      "nodes": [
                        {
                          "id": "PRRT_1",
                          "isResolved": false,
                          "isOutdated": false,
                          "viewerCanResolve": true,
                          "viewerCanUnresolve": false,
                          "path": "Sources/App.swift",
                          "line": 7,
                          "startLine": null,
                          "comments": {
                            "nodes": [
                              {
                                "id": "PRRC_1",
                                "body": "Can this branch return early?",
                                "author": {"login": "reviewer"},
                                "createdAt": "2026-05-05T10:00:00Z",
                                "url": "https://github.com/u/r/pull/1#discussion_r1"
                              }
                            ]
                          }
                        }
                      ],
                      "pageInfo": {"hasNextPage": false, "endCursor": null}
                    }
                  }
                }
              }
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: {
            $0.contains("api")
                && $0.contains("graphql")
                && $0.contains("threadId=PRRT_1")
                && $0.contains { $0.contains("CocxyResolveReviewThread") }
        }, result: GitHubCLIResult(
            stdout: #"""
            {
              "data": {
                "resolveReviewThread": {
                  "thread": {
                    "id": "PRRT_1",
                    "isResolved": true,
                    "isOutdated": false,
                    "viewerCanResolve": false,
                    "viewerCanUnresolve": true,
                    "path": "Sources/App.swift",
                    "line": 7,
                    "startLine": null,
                    "comments": {"nodes": []}
                  }
                }
              }
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))
        spy.stub(matching: {
            $0.contains("api")
                && $0.contains("graphql")
                && $0.contains("threadId=PRRT_1")
                && $0.contains { $0.contains("CocxyUnresolveReviewThread") }
        }, result: GitHubCLIResult(
            stdout: #"""
            {
              "data": {
                "unresolveReviewThread": {
                  "thread": {
                    "id": "PRRT_1",
                    "isResolved": false,
                    "isOutdated": false,
                    "viewerCanResolve": true,
                    "viewerCanUnresolve": false,
                    "path": "Sources/App.swift",
                    "line": 7,
                    "startLine": null,
                    "comments": {"nodes": []}
                  }
                }
              }
            }
            """#,
            stderr: "",
            terminationStatus: 0
        ))

        let service = GitHubService(runner: spy.runner)
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { URL(fileURLWithPath: "/tmp") }
        viewModel.refresh()
        await flush()

        let unresolved = try #require(viewModel.reviewThreads.first)
        #expect(viewModel.canOfferResolveReviewThread(unresolved))
        #expect(unresolved.comments.first?.body == "Can this branch return early?")

        viewModel.resolveReviewThread(unresolved)
        await flush()

        let updated = try #require(viewModel.reviewThreads.first)
        #expect(updated.state == .resolved)
        #expect(updated.viewerCanResolve == false)
        #expect(updated.viewerCanUnresolve)
        #expect(updated.comments.first?.body == "Can this branch return early?")
        #expect(viewModel.lastInfoMessage?.contains("Resolved review thread") == true)
        #expect(viewModel.reviewThreadsBeingUpdated.isEmpty)
        #expect(viewModel.canOfferUnresolveReviewThread(updated))

        let mutationArgs = try #require(
            spy.allInvocations.first(where: {
                $0.args.contains("threadId=PRRT_1")
                    && $0.args.contains { $0.contains("CocxyResolveReviewThread") }
            })?.args
        )
        #expect(mutationArgs.contains { $0.contains("resolveReviewThread") })

        viewModel.unresolveReviewThread(updated)
        await flush()

        let reopened = try #require(viewModel.reviewThreads.first)
        #expect(reopened.state == .unresolved)
        #expect(reopened.viewerCanResolve)
        #expect(reopened.viewerCanUnresolve == false)
        #expect(reopened.comments.first?.body == "Can this branch return early?")
        #expect(viewModel.lastInfoMessage?.contains("Reopened review thread") == true)
    }

    @Test("review thread suggestions apply to the local working tree")
    func reviewThreadSuggestionsApplyToLocalWorkingTree() async throws {
        let root = try makeTemporaryDirectory(named: "github-review-thread-suggestions")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "let enabled = false\nprint(enabled)\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("api") && $0.contains("graphql") && $0.contains("number=1") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "data": {
                    "repository": {
                      "pullRequest": {
                        "reviewThreads": {
                          "nodes": [
                            {
                              "id": "PRRT_1",
                              "isResolved": false,
                              "isOutdated": false,
                              "viewerCanResolve": true,
                              "viewerCanUnresolve": false,
                              "path": "Sources/App.swift",
                              "line": 1,
                              "startLine": null,
                              "comments": {
                                "nodes": [
                                  {
                                    "id": "PRRC_1",
                                    "body": "Please apply this change.\n\n```suggestion\nlet enabled = true\n```",
                                    "author": {"login": "reviewer"},
                                    "createdAt": "2026-05-05T10:00:00Z",
                                    "url": "https://github.com/u/r/pull/1#discussion_r1"
                                  }
                                ]
                              }
                            }
                          ],
                          "pageInfo": {"hasNextPage": false, "endCursor": null}
                        }
                      }
                    }
                  }
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { root }
        viewModel.refresh()
        await flush()

        let thread = try #require(viewModel.reviewThreads.first)
        #expect(viewModel.reviewThreadSuggestionCount(thread) == 1)
        #expect(viewModel.canApplyReviewThreadSuggestions(thread))

        viewModel.applyReviewThreadSuggestions(thread)
        await flush()

        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == "let enabled = true\nprint(enabled)\n")
        #expect(viewModel.reviewThreadSuggestionsBeingApplied.isEmpty)
        #expect(viewModel.lastInfoMessage?.contains("Applied 1 review suggestion") == true)
        #expect(viewModel.lastErrorMessage == nil)
    }

    @Test("review thread suggestions reject symlink paths that escape the working tree")
    func reviewThreadSuggestionsRejectSymlinkEscapes() async throws {
        let root = try makeTemporaryDirectory(named: "github-review-thread-symlink")
        let outside = try makeTemporaryDirectory(named: "github-review-thread-outside")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let sourceDirectory = root.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let externalURL = outside.appendingPathComponent("Escaped.swift")
        try "let enabled = false\n".write(to: externalURL, atomically: true, encoding: .utf8)
        let symlinkURL = sourceDirectory.appendingPathComponent("App.swift")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: externalURL)

        let service = makeService { spy in
            spy.stub(matching: { $0.first == "auth" && $0.dropFirst().first == "status" }, result: GitHubCLIResult(
                stdout: "",
                stderr: "github.com\n  ✓ Logged in to github.com account octocat (keyring)",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("repo") && $0.contains("view") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "defaultBranchRef": {"name": "main"},
                  "description": "",
                  "hasIssuesEnabled": true,
                  "isEmpty": false,
                  "isPrivate": false,
                  "name": "r",
                  "owner": {"login": "u"},
                  "url": "https://github.com/u/r"
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: #"""
                [
                  {"number": 1, "title": "first", "state": "OPEN", "author": {"login": "u"}, "headRefName": "a", "baseRefName": "main", "labels": [], "isDraft": false, "reviewDecision": null, "url": "https://github.com/u/r/pull/1", "updatedAt": "2026-04-23T15:47:21Z"}
                ]
                """#,
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("issue") && $0.contains("list") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("pr") && $0.contains("checks") }, result: GitHubCLIResult(
                stdout: "[]",
                stderr: "",
                terminationStatus: 0
            ))
            spy.stub(matching: { $0.contains("api") && $0.contains("graphql") && $0.contains("number=1") }, result: GitHubCLIResult(
                stdout: #"""
                {
                  "data": {
                    "repository": {
                      "pullRequest": {
                        "reviewThreads": {
                          "nodes": [
                            {
                              "id": "PRRT_1",
                              "isResolved": false,
                              "isOutdated": false,
                              "viewerCanResolve": true,
                              "viewerCanUnresolve": false,
                              "path": "Sources/App.swift",
                              "line": 1,
                              "startLine": null,
                              "comments": {
                                "nodes": [
                                  {
                                    "id": "PRRC_1",
                                    "body": "Please apply this change.\n\n```suggestion\nlet enabled = true\n```",
                                    "author": {"login": "reviewer"},
                                    "createdAt": "2026-05-05T10:00:00Z",
                                    "url": "https://github.com/u/r/pull/1#discussion_r1"
                                  }
                                ]
                              }
                            }
                          ],
                          "pageInfo": {"hasNextPage": false, "endCursor": null}
                        }
                      }
                    }
                  }
                }
                """#,
                stderr: "",
                terminationStatus: 0
            ))
        }

        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.workingDirectoryProvider = { root }
        viewModel.refresh()
        await flush()

        let thread = try #require(viewModel.reviewThreads.first)
        viewModel.applyReviewThreadSuggestions(thread)
        await flush()

        #expect(try String(contentsOf: externalURL, encoding: .utf8) == "let enabled = false\n")
        #expect(viewModel.lastErrorMessage?.contains("outside the working directory") == true)
        #expect(viewModel.lastInfoMessage == nil)
    }

    @Test("isVisible toggle starts and stops auto-refresh without crashing")
    func isVisible_togglesAutoRefreshLifecycle() {
        let service = makeService { _ in }
        let viewModel = GitHubPaneViewModel(service: service)
        viewModel.configProvider = {
            GitHubConfig(
                enabled: true,
                autoRefreshInterval: 60,
                maxItems: 30,
                includeDrafts: true,
                defaultState: "open"
            )
        }

        // Under xctest the gate should prevent a timer from being
        // installed at all — toggling should be a pure no-op.
        viewModel.isVisible = true
        viewModel.isVisible = false
        viewModel.isVisible = true
        viewModel.isVisible = false
        #expect(viewModel.isVisible == false)
    }

    @Test("open forwards the URL to the injected callback")
    func open_forwardsURLToCallback() {
        let service = makeService { _ in }
        let viewModel = GitHubPaneViewModel(service: service)
        var opened: [URL] = []
        viewModel.onOpenURL = { opened.append($0) }
        viewModel.open(URL(string: "https://github.com/u/r/pull/1")!)
        #expect(opened.count == 1)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
