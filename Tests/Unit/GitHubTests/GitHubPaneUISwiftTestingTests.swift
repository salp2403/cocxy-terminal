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

    @Test("GitHubPaneTabStrip renders all tabs without relying on a single segmented control row")
    func tabStrip_rendersAllTabs() {
        let selection = Binding<GitHubPaneViewModel.Tab>(
            get: { .pullRequests },
            set: { _ in }
        )
        let strip = GitHubPaneTabStrip(selection: selection, localizer: AppLocalizer(languagePreference: .english))

        _ = strip.body

        #expect(GitHubPaneViewModel.Tab.allCases.count == 7)
    }

    @Test("GitHubPaneTabStripPresentation avoids clipped tab labels at narrow widths")
    func tabStripPresentation_usesCompactModesBeforeLabelsClip() {
        #expect(
            GitHubPaneTabStripPresentation.resolve(
                width: GitHubPaneView.maximumPanelWidth
            ).mode == .compactLabels
        )
        #expect(GitHubPaneTabStripPresentation.resolve(width: 1080).mode == .allLabels)
        #expect(GitHubPaneTabStripPresentation.resolve(width: 900).mode == .compactLabels)
        #expect(GitHubPaneTabStripPresentation.resolve(width: 480).mode == .selectedLabel)
        #expect(GitHubPaneTabStripPresentation.resolve(width: 280).mode == .iconsOnly)
    }

    @Test("GitHubPaneTabStripPresentation resolves against side panel content width")
    func tabStripPresentation_usesConstrainedPanelWidthBeforeWindowWidth() {
        let measuredWindowWidth: CGFloat = 960
        let sidePanelContentWidth = GitHubPaneTabStripPresentation.contentWidth(
            forPanelWidth: GitHubPaneView.defaultPanelWidth,
            horizontalInset: 20
        )

        #expect(sidePanelContentWidth == 460)
        #expect(
            GitHubPaneTabStripPresentation.effectiveWidth(
                measuredWidth: measuredWindowWidth,
                constrainedWidth: sidePanelContentWidth
            ) == sidePanelContentWidth
        )
        #expect(
            GitHubPaneTabStripPresentation.resolve(
                measuredWidth: measuredWindowWidth,
                constrainedWidth: sidePanelContentWidth
            ).mode == .selectedLabel
        )
    }

    @Test("GitHubPaneTabStripPresentation only labels selected tab in constrained panes")
    func tabStripPresentation_labelsOnlySelectedTabWhenConstrained() {
        let presentation = GitHubPaneTabStripPresentation.resolve(width: 480)

        #expect(
            presentation.showsTitle(
                for: .pullRequests,
                selectedTab: .pullRequests
            )
        )
        #expect(
            presentation.showsTitle(
                for: .reviewThreads,
                selectedTab: .pullRequests
            ) == false
        )
    }

    @Test("GitHubPaneTabStripPresentation labels every tab with compact titles at medium widths")
    func tabStripPresentation_labelsEveryTabWithCompactTitlesAtMediumWidths() {
        let presentation = GitHubPaneTabStripPresentation.resolve(width: 720)
        let localizer = AppLocalizer(languagePreference: .english)

        #expect(presentation.mode == .compactLabels)
        #expect(
            presentation.showsTitle(
                for: .reviewThreads,
                selectedTab: .pullRequests
            )
        )
        #expect(presentation.title(for: .pullRequests, using: localizer) == "PRs")
        #expect(presentation.title(for: .reviewThreads, using: localizer) == "Reviews")
    }

    @Test("Pull request filter controls switch to compact menu before segmented control clips")
    func pullRequestFilterControls_useCompactMenuInNarrowPane() {
        #expect(PullRequestFilterControlsLayout.resolve(width: 300) == .compactMenu)
        #expect(PullRequestFilterControlsLayout.resolve(width: 360) == .segmented)
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

    @Test("GitHubReviewThreadRow renders resolved and unresolved states")
    func reviewThreadRow_rendersResolvedAndUnresolvedStates() {
        let unresolved = GitHubPullRequestReviewThread(
            id: "PRRT_1",
            path: "Sources/App.swift",
            line: 12,
            isResolved: false,
            comments: [
                GitHubPullRequestReviewThreadComment(
                    id: "PRRC_1",
                    body: "Can this return early?",
                    authorLogin: "reviewer"
                ),
            ]
        )
        let resolved = GitHubPullRequestReviewThread(
            id: "PRRT_2",
            path: "Sources/App.swift",
            line: 20,
            isResolved: true,
            isOutdated: true
        )

        let localizer = AppLocalizer(languagePreference: .english)
        #expect(GitHubReviewThreadRow.statusTitle(for: unresolved, using: localizer) == "Unresolved")
        #expect(GitHubReviewThreadRow.statusTitle(for: resolved, using: localizer) == "Resolved")
        #expect(GitHubReviewThreadRow.suggestionCountTitle(count: 1, using: localizer) == "1 suggestion")
        #expect(GitHubReviewThreadRow.suggestionCountTitle(count: 2, using: localizer) == "2 suggestions")
        _ = GitHubReviewThreadRow(thread: unresolved, localizer: localizer).body
        _ = GitHubReviewThreadRow(thread: resolved, localizer: localizer).body
    }

    @Test("Source Control helper filters branches commits and PRs")
    func sourceControlHelpers_filterRows() {
        let branches = [
            GitBranch(name: "main", isCurrent: true),
            GitBranch(name: "feature/source-control", lastCommitSubject: "Diff UI"),
        ]
        #expect(BranchPickerView.filteredBranches(branches, searchText: "source").map(\.name) == ["feature/source-control"])

        let commits = [
            GitCommit(
                hash: "0123456789abcdef",
                shortHash: "0123456",
                subject: "Add source control",
                authorName: "Said Arturo Lopez",
                authorEmail: "dev@cocxy.dev",
                authoredAt: Date(timeIntervalSince1970: 0)
            ),
            GitCommit(
                hash: "abcdef0123456789",
                shortHash: "abcdef0",
                subject: "Fix browser tabs",
                authorName: "Said Arturo Lopez",
                authorEmail: "dev@cocxy.dev",
                authoredAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        #expect(CommitHistoryView.filteredCommits(commits, searchText: "browser").map(\.shortHash) == ["abcdef0"])

        let pullRequests = [
            samplePR(number: 1, title: "Add source control", state: .open, draft: false),
            samplePR(number: 2, title: "Draft diff", state: .open, draft: true),
            samplePR(number: 3, title: "Merged work", state: .merged, draft: false),
        ]
        #expect(PullRequestsListView.filteredPullRequests(
            pullRequests,
            state: .open,
            includeDrafts: false,
            searchText: ""
        ).map(\.number) == [1])
        #expect(PullRequestsListView.filteredPullRequests(
            pullRequests,
            state: .merged,
            includeDrafts: true,
            searchText: "work"
        ).map(\.number) == [3])
        #expect(CreatePullRequestSheet.reviewerList(from: "alice, bob\ncarol") == ["alice", "bob", "carol"])
        #expect(
            CreatePullRequestSheet.mergedReviewerList(
                existingRaw: "alice, bob",
                suggestions: ["bob", "carol", " "]
            ) == "alice, bob, carol"
        )
    }

    @Test("Source Control views render basic state")
    func sourceControlViews_renderBasicState() {
        var branchSearch = ""
        var commitSearch = ""
        var prSearch = ""
        var prState = PullRequestListState.all
        var includeDrafts = true
        var diffMode = DiffViewerMode.unified

        let branches = [GitBranch(name: "main", isCurrent: true)]
        let worktrees = [
            WorktreeManifest.WorktreeEntry(
                id: "wt-1",
                branch: "main",
                path: URL(fileURLWithPath: "/tmp/wt-1"),
                createdAt: Date(timeIntervalSince1970: 0),
                agent: nil,
                tabID: nil
            ),
        ]
        let commits = [
            GitCommit(
                hash: "0123456789abcdef",
                shortHash: "0123456",
                subject: "Add source control",
                authorName: "Said Arturo Lopez",
                authorEmail: "dev@cocxy.dev",
                authoredAt: Date(timeIntervalSince1970: 0)
            ),
        ]
        let pullRequests = [samplePR(number: 1, title: "Add source control", state: .open, draft: false)]
        let diffs = [sampleDiff()]

        _ = BranchPickerView(
            branches: branches,
            worktreeEntries: worktrees,
            selectedBranchName: "main",
            searchText: Binding(get: { branchSearch }, set: { branchSearch = $0 }),
            onRefresh: {},
            onSelect: { _ in },
            onCreateBranch: {}
        ).body
        _ = WorktreeBranchPickerView(entries: worktrees, onSelect: { _ in }).body
        _ = CommitHistoryView(
            commits: commits,
            selectedCommitHash: commits[0].hash,
            searchText: Binding(get: { commitSearch }, set: { commitSearch = $0 }),
            onRefresh: {},
            onSelect: { _ in },
            onCreateBranch: { _ in }
        ).body
        _ = PullRequestsListView(
            pullRequests: pullRequests,
            selectedPullRequestNumber: 1,
            searchText: Binding(get: { prSearch }, set: { prSearch = $0 }),
            state: Binding(get: { prState }, set: { prState = $0 }),
            includeDrafts: Binding(get: { includeDrafts }, set: { includeDrafts = $0 }),
            canOfferMerge: { _ in true },
            isMerging: { _ in false },
            onSelectChecks: { _ in },
            onReviewThreads: { _ in },
            onOpen: { _ in },
            onMerge: { _ in },
            onCreate: {}
        ).body
        _ = DiffViewerView(
            diffs: diffs,
            mode: Binding(get: { diffMode }, set: { diffMode = $0 }),
            onStage: { _, _, _ in }
        ).body
        _ = CreateBranchSheet(startPoint: "main", onCancel: {}, onCreate: { _, _ in }).body
        _ = CreatePullRequestSheet(defaultBaseBranch: "main", onCancel: {}, onCreate: { _ in }).body
    }

    private func samplePR(
        number: Int,
        title: String,
        state: GitHubPullRequestState,
        draft: Bool
    ) -> GitHubPullRequest {
        GitHubPullRequest(
            number: number,
            title: title,
            state: state,
            author: GitHubUser(login: "said"),
            headRefName: "feature/\(number)",
            baseRefName: "main",
            isDraft: draft,
            url: URL(string: "https://github.com/u/r/pull/\(number)")!,
            updatedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private func sampleDiff() -> FileDiff {
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
        )
    }
}
