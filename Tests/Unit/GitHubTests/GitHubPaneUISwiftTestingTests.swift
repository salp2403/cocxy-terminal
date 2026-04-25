// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneUISwiftTestingTests.swift - Smoke tests for the SwiftUI
// banner kinds and row factories. SwiftUI layout is hard to snapshot
// in a plain XCTest-less setup, so the tests focus on the pure helpers
// and on verifying the initialisers produce the expected struct shape.

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import CocxyTerminal

@Suite("GitHubPaneUI")
@MainActor
struct GitHubPaneUISwiftTestingTests {

    // MARK: - Banner kinds

    @Test("GitHubBannerKind exposes stable symbol + accessibility prefix")
    func bannerKind_exposesStableMetadata() {
        #expect(GitHubBannerKind.info.symbolName == "info.circle")
        #expect(GitHubBannerKind.error.symbolName == "exclamationmark.triangle")
        #expect(GitHubBannerKind.info.accessibilityPrefix == "Info")
        #expect(GitHubBannerKind.error.accessibilityPrefix == "Error")
    }

    @Test("GitHubBannerKind distinguishes info from error by color")
    func bannerKind_distinguishesByColor() {
        // We don't compare NSColor values directly (the system returns
        // dynamic instances that do not satisfy equality reliably), but
        // we can at least confirm they differ.
        #expect(GitHubBannerKind.info.backgroundColor != GitHubBannerKind.error.backgroundColor)
    }

    // MARK: - Panel width constants

    @Test("Panel width constants respect the documented invariants")
    func panelWidths_respectInvariants() {
        #expect(GitHubPaneView.minimumPanelWidth < GitHubPaneView.defaultPanelWidth)
        #expect(GitHubPaneView.defaultPanelWidth < GitHubPaneView.maximumPanelWidth)
        #expect(GitHubPaneView.minimumPanelWidth >= 300)
        #expect(GitHubPaneView.maximumPanelWidth <= 900)
    }

    // MARK: - Pane layout

    @Test("Pane layout enum has a stable sidePanel case")
    func paneLayout_hasStableCases() {
        let layout = GitHubPaneView.Layout.sidePanel
        #expect(layout == .sidePanel)
    }

    // MARK: - Banner view factory

    @Test("GitHubPaneBanner accepts optional action title + handler")
    func banner_acceptsOptionalAction() {
        var clicks = 0
        let banner = GitHubPaneBanner(
            message: "Install gh to continue.",
            kind: .info,
            actionTitle: "Copy command",
            onAction: { clicks += 1 }
        )
        // Hosting the view in an NSHostingView would exercise the UI
        // tree; here we simply confirm the struct was assembled with
        // the correct data so the SwiftUI renderer receives it.
        _ = banner.body
        #expect(clicks == 0)
    }

    @Test("GitHub setup actions expose stable button titles")
    func setupActions_exposeStableButtonTitles() {
        #expect(GitHubPaneSetupAction.installCLI.buttonTitle == "Install GitHub CLI")
        #expect(GitHubPaneSetupAction.signIn.buttonTitle == "Sign In with GitHub")
    }

    @Test("GitHub preferences section renders authentication actions")
    func preferencesSection_rendersAuthenticationActions() {
        var signInClicks = 0
        var installClicks = 0
        let viewModel = PreferencesViewModel(config: .defaults)
        let section = GitHubPreferencesSection(
            viewModel: viewModel,
            saveStatus: .constant(nil),
            onGitHubSignIn: { signInClicks += 1 },
            onOpenGitHubCLIInstallGuide: { installClicks += 1 }
        )

        _ = section.body

        #expect(signInClicks == 0)
        #expect(installClicks == 0)
    }

    // MARK: - Row factories

    @Test("GitHubPullRequestRow renders selected state without crashing")
    func pullRequestRow_selectedStateRenders() {
        let pr = GitHubPullRequest(
            number: 1,
            title: "Add GitHub pane",
            state: .open,
            author: GitHubUser(login: "u"),
            headRefName: "feat/github-pane",
            baseRefName: "main",
            labels: [],
            isDraft: false,
            reviewDecision: .none,
            url: URL(string: "https://github.com/u/r/pull/1")!,
            updatedAt: Date()
        )
        let row = GitHubPullRequestRow(pullRequest: pr, isSelected: true)
        _ = row.body
    }

    @Test("GitHubIssueRow renders with a non-zero comment badge")
    func issueRow_rendersWithCommentBadge() {
        let issue = GitHubIssue(
            number: 2,
            title: "Fix flaky test",
            state: .open,
            author: GitHubUser(login: "r"),
            labels: [GitHubLabel(name: "bug", color: "ff0000")],
            commentCount: 3,
            url: URL(string: "https://github.com/u/r/issues/2")!,
            updatedAt: Date()
        )
        let row = GitHubIssueRow(issue: issue)
        _ = row.body
    }

    @Test("GitHubCheckRow renders for failed and success states")
    func checkRow_rendersForFailureAndSuccess() {
        let failed = GitHubCheck(
            name: "build",
            status: .completed,
            conclusion: .failure,
            detailsUrl: URL(string: "https://github.com/u/r/runs/1"),
            startedAt: Date(),
            completedAt: Date()
        )
        let passed = GitHubCheck(
            name: "tests",
            status: .completed,
            conclusion: .success
        )
        let pending = GitHubCheck(
            name: "deploy",
            status: .pending,
            conclusion: .none
        )
        _ = GitHubCheckRow(check: failed).body
        _ = GitHubCheckRow(check: passed).body
        _ = GitHubCheckRow(check: pending).body
    }
}
