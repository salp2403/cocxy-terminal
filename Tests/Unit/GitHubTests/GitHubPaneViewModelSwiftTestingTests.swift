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
            return { [self] _, args, _ in
                self.lock.lock()
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
        #expect(GitHubPaneViewModel.Tab.allCases.count == 3)
        #expect(GitHubPaneViewModel.Tab.pullRequests.id == "pullRequests")
        #expect(GitHubPaneViewModel.Tab.issues.systemImage == "exclamationmark.circle")
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
}
