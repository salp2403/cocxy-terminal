// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubModelsSwiftTestingTests.swift - Unit tests for domain value types
// decoded from `gh` JSON output.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitHubModels")
struct GitHubModelsSwiftTestingTests {

    // MARK: - JSON decoder helper

    @Test("JSON decoder parses ISO8601 timestamps without fractional seconds")
    func jsonDecoder_parsesISO8601WithoutFraction() throws {
        struct Wrapper: Decodable { let ts: Date }
        let wrapper = try GitHubJSONDecoder.decode(
            Wrapper.self,
            from: #"{"ts":"2026-04-23T15:47:21Z"}"#
        )

        // Reference: parse the same string with a vanilla ISO8601 formatter
        // and ensure both values match to the second. Comparing against a
        // hard-coded epoch is brittle because Foundation's second count for
        // 2026 differs depending on how the test host's calendar resolves
        // leap seconds.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expected = formatter.date(from: "2026-04-23T15:47:21Z")

        try #require(expected != nil)
        #expect(Int(wrapper.ts.timeIntervalSince1970) == Int(expected!.timeIntervalSince1970))
    }

    @Test("JSON decoder parses ISO8601 timestamps with fractional seconds")
    func jsonDecoder_parsesISO8601WithFraction() throws {
        struct Wrapper: Decodable { let ts: Date }
        let wrapper = try GitHubJSONDecoder.decode(
            Wrapper.self,
            from: #"{"ts":"2026-04-23T15:47:21.5Z"}"#
        )

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let truncated = formatter.date(from: "2026-04-23T15:47:21Z")
        try #require(truncated != nil)

        // Fractional component must push the decoded date strictly past
        // the truncated-to-second reference.
        #expect(wrapper.ts.timeIntervalSince1970 > truncated!.timeIntervalSince1970)
    }

    @Test("JSON decoder surfaces decoding errors as invalidJSON")
    func jsonDecoder_surfacesDecodingErrorsAsInvalidJSON() {
        struct Required: Decodable { let name: String }

        #expect {
            _ = try GitHubJSONDecoder.decode(Required.self, from: #"{}"#)
        } throws: { error in
            guard case GitHubCLIError.invalidJSON = error else { return false }
            return true
        }
    }

    // MARK: - Repo

    @Test("GitHubRepo decodes the real gh repo view payload")
    func gitHubRepo_decodesRealGhPayload() throws {
        let json = #"""
        {
          "defaultBranchRef": {"name": "main"},
          "description": "Native macOS terminal built for AI coding agents.",
          "hasIssuesEnabled": true,
          "isEmpty": false,
          "isPrivate": false,
          "name": "cocxy-terminal",
          "owner": {"id": "MDQ6VXNlcjcwNDE4Ng==", "login": "salp2403"},
          "url": "https://github.com/salp2403/cocxy-terminal"
        }
        """#
        let repo = try GitHubJSONDecoder.decode(GitHubRepo.self, from: json)

        #expect(repo.owner.login == "salp2403")
        #expect(repo.name == "cocxy-terminal")
        #expect(repo.defaultBranch == "main")
        #expect(repo.hasIssuesEnabled == true)
        #expect(repo.isPrivate == false)
        #expect(repo.isEmpty == false)
        #expect(repo.fullName == "salp2403/cocxy-terminal")
        #expect(repo.url.absoluteString == "https://github.com/salp2403/cocxy-terminal")
    }

    @Test("GitHubRepo falls back to main when defaultBranchRef is missing")
    func gitHubRepo_fallsBackWhenDefaultBranchRefMissing() throws {
        let json = #"""
        {
          "name": "x",
          "owner": {"login": "u"},
          "url": "https://github.com/u/x"
        }
        """#
        let repo = try GitHubJSONDecoder.decode(GitHubRepo.self, from: json)
        #expect(repo.defaultBranch == "main")
        #expect(repo.hasIssuesEnabled == true)
    }

    // MARK: - Pull request

    @Test("GitHubPullRequest decodes full payload with all fields")
    func gitHubPullRequest_decodesFullPayload() throws {
        let json = #"""
        {
          "number": 42,
          "title": "Add GitHub pane",
          "state": "OPEN",
          "author": {"login": "salp2403", "id": "MDQ6VXNlcjE="},
          "headRefName": "feat/github-pane",
          "baseRefName": "main",
          "labels": [
            {"name": "enhancement", "color": "a2eeef", "description": "New feature"}
          ],
          "isDraft": false,
          "reviewDecision": "APPROVED",
          "url": "https://github.com/u/x/pull/42",
          "updatedAt": "2026-04-23T15:47:21Z"
        }
        """#
        let pr = try GitHubJSONDecoder.decode(GitHubPullRequest.self, from: json)

        #expect(pr.number == 42)
        #expect(pr.title == "Add GitHub pane")
        #expect(pr.state == .open)
        #expect(pr.author.login == "salp2403")
        #expect(pr.headRefName == "feat/github-pane")
        #expect(pr.baseRefName == "main")
        #expect(pr.labels.count == 1)
        #expect(pr.labels.first?.name == "enhancement")
        #expect(pr.isDraft == false)
        #expect(pr.reviewDecision == .approved)
    }

    @Test("GitHubPullRequest decodes null reviewDecision as .none")
    func gitHubPullRequest_decodesNullReviewDecisionAsNone() throws {
        let json = #"""
        {
          "number": 1,
          "title": "x",
          "state": "OPEN",
          "author": {"login": "u"},
          "headRefName": "a",
          "baseRefName": "b",
          "labels": [],
          "isDraft": true,
          "reviewDecision": null,
          "url": "https://github.com/u/x/pull/1",
          "updatedAt": "2026-04-23T15:47:21Z"
        }
        """#
        let pr = try GitHubJSONDecoder.decode(GitHubPullRequest.self, from: json)
        #expect(pr.reviewDecision == .none)
        #expect(pr.isDraft == true)
    }

    @Test("GitHubPullRequest decodes unknown state as .unknown without failing")
    func gitHubPullRequest_decodesUnknownStateTolerantly() throws {
        let json = #"""
        {
          "number": 1,
          "title": "x",
          "state": "DRAFT_INVENTED",
          "author": {"login": "u"},
          "headRefName": "a",
          "baseRefName": "b",
          "labels": [],
          "isDraft": false,
          "url": "https://github.com/u/x/pull/1",
          "updatedAt": "2026-04-23T15:47:21Z"
        }
        """#
        let pr = try GitHubJSONDecoder.decode(GitHubPullRequest.self, from: json)
        #expect(pr.state == .unknown)
    }

    @Test("GitHubPullRequest survives missing optional fields")
    func gitHubPullRequest_survivesMissingOptionals() throws {
        let json = #"""
        {
          "number": 1,
          "title": "x",
          "url": "https://github.com/u/x/pull/1",
          "updatedAt": "2026-04-23T15:47:21Z"
        }
        """#
        let pr = try GitHubJSONDecoder.decode(GitHubPullRequest.self, from: json)
        #expect(pr.state == .unknown)
        #expect(pr.author.login == "—")
        #expect(pr.headRefName == "")
        #expect(pr.baseRefName == "")
        #expect(pr.labels.isEmpty)
        #expect(pr.isDraft == false)
        #expect(pr.reviewDecision == .none)
    }

    // MARK: - Issue

    @Test("GitHubIssue folds comments array into commentCount")
    func gitHubIssue_foldsCommentsArrayIntoCount() throws {
        let json = #"""
        {
          "number": 7,
          "title": "Broken worktree",
          "state": "OPEN",
          "author": {"login": "reporter"},
          "labels": [{"name": "bug"}],
          "comments": [{"body": "a"}, {"body": "b"}, {"body": "c"}],
          "url": "https://github.com/u/x/issues/7",
          "updatedAt": "2026-04-23T15:47:21Z"
        }
        """#
        let issue = try GitHubJSONDecoder.decode(GitHubIssue.self, from: json)
        #expect(issue.number == 7)
        #expect(issue.state == .open)
        #expect(issue.commentCount == 3)
        #expect(issue.labels.first?.name == "bug")
    }

    @Test("GitHubIssue accepts comments as integer count (older gh)")
    func gitHubIssue_acceptsCommentsAsIntegerCount() throws {
        let json = #"""
        {
          "number": 8,
          "title": "x",
          "state": "CLOSED",
          "author": {"login": "u"},
          "labels": [],
          "comments": 5,
          "url": "https://github.com/u/x/issues/8",
          "updatedAt": "2026-04-23T15:47:21Z"
        }
        """#
        let issue = try GitHubJSONDecoder.decode(GitHubIssue.self, from: json)
        #expect(issue.commentCount == 5)
        #expect(issue.state == .closed)
    }

    // MARK: - Checks

    @Test("GitHubCheck decodes completed success")
    func gitHubCheck_decodesCompletedSuccess() throws {
        let json = #"""
        {
          "name": "ci / build",
          "status": "COMPLETED",
          "conclusion": "SUCCESS",
          "detailsUrl": "https://github.com/u/x/runs/1",
          "startedAt": "2026-04-23T10:00:00Z",
          "completedAt": "2026-04-23T10:05:12Z"
        }
        """#
        let check = try GitHubJSONDecoder.decode(GitHubCheck.self, from: json)
        #expect(check.name == "ci / build")
        #expect(check.status == .completed)
        #expect(check.conclusion == .success)
        #expect(check.detailsUrl?.absoluteString == "https://github.com/u/x/runs/1")
        #expect(check.startedAt != nil)
        #expect(check.completedAt != nil)
    }

    @Test("GitHubCheck decodes in-progress with no conclusion")
    func gitHubCheck_decodesInProgress() throws {
        let json = #"""
        {
          "name": "ci / tests",
          "status": "IN_PROGRESS"
        }
        """#
        let check = try GitHubJSONDecoder.decode(GitHubCheck.self, from: json)
        #expect(check.status == .inProgress)
        #expect(check.conclusion == .none)
        #expect(check.detailsUrl == nil)
    }

    @Test("GitHubCheck accepts 'link' field as alias for detailsUrl")
    func gitHubCheck_acceptsLinkFieldAsAlias() throws {
        let json = #"""
        {
          "name": "ci / lint",
          "status": "COMPLETED",
          "conclusion": "FAILURE",
          "link": "https://github.com/u/x/runs/2"
        }
        """#
        let check = try GitHubJSONDecoder.decode(GitHubCheck.self, from: json)
        #expect(check.detailsUrl?.absoluteString == "https://github.com/u/x/runs/2")
        #expect(check.conclusion == .failure)
    }

    // MARK: - Auth status parser

    @Test("GitHubAuthStatusParser parses the modern 'account' wording")
    func authStatusParser_parsesAccountWording() {
        let output = """
        github.com
          ✓ Logged in to github.com account salp2403 (keyring)
          - Active account: true
          - Git operations protocol: https
          - Token: ghp_************************************
          - Token scopes: 'gist', 'repo', 'workflow'
        """
        let status = GitHubAuthStatusParser.parse(output)

        #expect(status.isAuthenticated == true)
        #expect(status.host == "github.com")
        #expect(status.login == "salp2403")
        #expect(status.scopes.contains("repo"))
        #expect(status.scopes.contains("workflow"))
        #expect(status.scopes.contains("gist"))
        #expect(status.hasRepoScope == true)
        #expect(status.hasWorkflowScope == true)
    }

    @Test("GitHubAuthStatusParser parses the legacy 'as' wording")
    func authStatusParser_parsesLegacyAsWording() {
        let output = """
        github.com
          ✓ Logged in to github.com as octocat (oauth_token)
          ✓ Token scopes: 'repo'
        """
        let status = GitHubAuthStatusParser.parse(output)
        #expect(status.isAuthenticated == true)
        #expect(status.login == "octocat")
        #expect(status.hasRepoScope == true)
        #expect(status.hasWorkflowScope == false)
    }

    @Test("GitHubAuthStatusParser returns loggedOut when output lacks login line")
    func authStatusParser_returnsLoggedOutWhenNoLoginLine() {
        let output = """
        You are not logged into any GitHub hosts. Run gh auth login to authenticate.
        """
        let status = GitHubAuthStatusParser.parse(output)
        #expect(status.isAuthenticated == false)
        #expect(status.login == nil)
        #expect(status.scopes.isEmpty)
    }

    @Test("GitHubAuthStatusParser returns loggedOut for empty input")
    func authStatusParser_returnsLoggedOutForEmptyInput() {
        #expect(GitHubAuthStatusParser.parse("") == .loggedOut)
        #expect(GitHubAuthStatusParser.parse("   \n   ") == .loggedOut)
    }

    // MARK: - Enum niceties

    @Test("Enum displayName values stay stable for every state")
    func enum_displayNameValuesStable() {
        #expect(GitHubPullRequestState.open.displayName == "Open")
        #expect(GitHubPullRequestState.closed.displayName == "Closed")
        #expect(GitHubPullRequestState.merged.displayName == "Merged")
        #expect(GitHubPullRequestState.unknown.displayName == "Unknown")

        #expect(GitHubIssueState.open.displayName == "Open")
        #expect(GitHubIssueState.closed.displayName == "Closed")

        #expect(GitHubCheckStatus.completed.displayName == "Completed")
        #expect(GitHubCheckStatus.inProgress.displayName == "In progress")

        #expect(GitHubCheckConclusion.success.displayName == "Success")
        #expect(GitHubCheckConclusion.failure.displayName == "Failure")
        #expect(GitHubCheckConclusion.none.displayName == "—")

        #expect(GitHubReviewDecision.approved.displayName == "Approved")
        #expect(GitHubReviewDecision.none.displayName == "—")
    }
}
