// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubPaneView.swift - SwiftUI container for the GitHub pane overlay
// (Cmd+Option+G) introduced in v0.1.84.
//
// The view is intentionally thin: every piece of state lives inside
// `GitHubPaneViewModel`, which routes all subprocess work through the
// injected `GitHubService`. Here we only map state → widgets.

import SwiftUI
import AppKit

// MARK: - GitHubPaneView

struct GitHubPaneView: View {

    // MARK: Layout

    enum Layout: Equatable {
        /// Right-docked overlay with a fixed width. Mirrors
        /// `CodeReviewPanelView` so both panels can coexist on the
        /// same edge via `layoutRightDockedAgentPanels`.
        case sidePanel
    }

    // MARK: Config

    /// Default width for the right-docked overlay. Mirrors
    /// `BrowserPanelView.panelWidth` so the three docked panels share
    /// a visual rhythm.
    static let defaultPanelWidth: CGFloat = 480

    /// Lower bound enforced by the controller when the user drags the
    /// resize handle. Kept here so Preferences and Overlays stay in
    /// sync without duplicating the constant.
    static let minimumPanelWidth: CGFloat = 360

    /// Upper bound enforced when the window is wide enough. Above
    /// this the pane gets awkward for the list-style content.
    static let maximumPanelWidth: CGFloat = 720

    // MARK: Properties

    @ObservedObject var viewModel: GitHubPaneViewModel
    var layout: Layout = .sidePanel
    var onDismiss: (() -> Void)?
    var panelWidth: CGFloat = GitHubPaneView.defaultPanelWidth
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    @State private var branchSearchText = ""
    @State private var commitSearchText = ""
    @State private var pullRequestSearchText = ""
    @State private var pullRequestState: PullRequestListState = .all
    @State private var includeDraftPullRequests = true
    @State private var diffViewerMode: DiffViewerMode = .unified
    @State private var isCreateBranchSheetPresented = false
    @State private var branchSheetStartPoint: String?
    @State private var isCreatePullRequestSheetPresented = false

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            tabPicker
            Divider().opacity(0.4)
            bannerStack
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: layout == .sidePanel ? panelWidth : nil)
        .frame(maxHeight: .infinity)
        .glassPanelBackground()
        .sheet(isPresented: $isCreateBranchSheetPresented) {
            CreateBranchSheet(
                startPoint: branchSheetStartPoint,
                onCancel: { isCreateBranchSheetPresented = false },
                onCreate: { name, startPoint in
                    isCreateBranchSheetPresented = false
                    Task {
                        await viewModel.createBranch(named: name, startPoint: startPoint)
                    }
                },
                localizer: localizer
            )
        }
        .sheet(isPresented: $isCreatePullRequestSheetPresented) {
            CreatePullRequestSheet(
                defaultBaseBranch: viewModel.repo?.defaultBranch,
                onCancel: { isCreatePullRequestSheetPresented = false },
                onCreate: { request in
                    isCreatePullRequestSheetPresented = false
                    Task {
                        await viewModel.createPullRequest(request)
                    }
                },
                onGenerateDraft: viewModel.canGeneratePullRequestDraft()
                    ? { baseBranch in
                        try await viewModel.generatePullRequestDraft(baseBranch: baseBranch)
                    }
                    : nil,
                onSuggestReviewers: viewModel.canSuggestPullRequestReviewers()
                    ? { baseBranch in
                        try await viewModel.suggestPullRequestReviewers(baseBranch: baseBranch)
                    }
                    : nil,
                localizer: localizer
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("github.pane.accessibility", fallback: "GitHub pane"))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.triangle.pull")
                .foregroundColor(.accentColor)
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text("GitHub")
                    .font(.system(size: 13, weight: .semibold))
                if let repo = viewModel.repo {
                    Text(repo.fullName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let login = viewModel.authStatus?.login {
                    Text(
                        String(
                            format: localized(
                                "github.pane.signedIn",
                                fallback: "Signed in as @%@"
                            ),
                            login
                        )
                    )
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let repo = viewModel.repo {
                Button(action: { viewModel.open(repo.url) }) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help(
                    String(
                        format: localized(
                            "github.pane.openRepo.help",
                            fallback: "Open %@ on GitHub"
                        ),
                        repo.fullName
                    )
                )
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(localized("github.pane.close", fallback: "Close pane"))
                .help(localized("github.pane.close.help", fallback: "Close pane (Cmd+Option+G)"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Tab picker

    private var tabPicker: some View {
        GitHubPaneTabStrip(
            selection: $viewModel.selectedTab,
            localizer: localizer
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Banners

    @ViewBuilder
    private var bannerStack: some View {
        if viewModel.lastErrorMessage == nil
            && viewModel.lastInfoMessage == nil
            && viewModel.lastMergeInfoMessage == nil {
            EmptyView()
        } else {
            VStack(spacing: 6) {
                if let error = viewModel.lastErrorMessage {
                    GitHubPaneBanner(message: error, kind: .error, localizer: localizer)
                }
                if let mergeInfo = viewModel.lastMergeInfoMessage {
                    GitHubPaneBanner(message: mergeInfo, kind: .info, localizer: localizer)
                }
                if let info = viewModel.lastInfoMessage {
                    GitHubPaneBanner(
                        message: info,
                        kind: .info,
                        actionTitle: viewModel.setupAction?.localizedButtonTitle(using: localizer),
                        onAction: setupActionHandler,
                        localizer: localizer
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private var setupActionHandler: (() -> Void)? {
        guard let action = viewModel.setupAction else { return nil }
        return { viewModel.performSetupAction(action) }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .branches:
            branchesView
        case .commits:
            commitsView
        case .diffs:
            diffsView
        case .pullRequests:
            pullRequestsList
        case .issues:
            issuesList
        case .checks:
            checksList
        case .reviewThreads:
            reviewThreadsList
        }
    }

    private var branchesView: some View {
        BranchPickerView(
            branches: viewModel.branches,
            worktreeEntries: viewModel.worktreeEntries,
            selectedBranchName: viewModel.selectedBranchName,
            searchText: $branchSearchText,
            sourceControlErrorMessage: viewModel.sourceControlErrorMessage,
            onRefresh: { viewModel.refreshSourceControl() },
            onSelect: { viewModel.selectBranch($0) },
            onCreateBranch: {
                branchSheetStartPoint = viewModel.selectedBranchName
                isCreateBranchSheetPresented = true
            },
            localizer: localizer
        )
    }

    private var commitsView: some View {
        CommitHistoryView(
            commits: viewModel.commits,
            selectedCommitHash: viewModel.selectedCommitHash,
            searchText: $commitSearchText,
            sourceControlErrorMessage: viewModel.sourceControlErrorMessage,
            onRefresh: { viewModel.refreshSourceControl() },
            onSelect: { viewModel.selectCommit($0) },
            onCreateBranch: { commit in
                branchSheetStartPoint = commit?.hash ?? viewModel.selectedBranchName
                isCreateBranchSheetPresented = true
            },
            localizer: localizer
        )
    }

    private var diffsView: some View {
        DiffViewerView(
            diffs: viewModel.currentDiffs,
            mode: $diffViewerMode,
            onStage: { fileDiff, hunk, action in
                viewModel.stageDiffHunk(
                    fileDiff: fileDiff,
                    hunk: hunk,
                    action: action
                )
            },
            localizer: localizer
        )
    }

    private var pullRequestsList: some View {
        PullRequestsListView(
            pullRequests: viewModel.pullRequests,
            selectedPullRequestNumber: viewModel.selectedPullRequestNumber,
            searchText: $pullRequestSearchText,
            state: $pullRequestState,
            includeDrafts: $includeDraftPullRequests,
            canOfferMerge: { viewModel.canOfferMerge(for: $0) },
            isMerging: { viewModel.isMerging($0) },
            onSelectChecks: { viewModel.selectPullRequestForChecks($0) },
            onReviewThreads: { viewModel.selectPullRequestForReviewThreads($0) },
            onOpen: { viewModel.open($0) },
            onMerge: { presentMergeActionSheet(for: $0) },
            onCreate: { isCreatePullRequestSheetPresented = true },
            localizer: localizer
        )
    }

    private var issuesList: some View {
        Group {
            if viewModel.issues.isEmpty {
                emptyState(
                    title: localized("github.pane.empty.issues", fallback: "No issues"),
                    systemImage: "exclamationmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.issues) { issue in
                            Button(action: { viewModel.open(issue.url) }) {
                                GitHubIssueRow(issue: issue, localizer: localizer)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(
                                    localized(
                                        "github.pane.context.openInBrowser",
                                        fallback: "Open in Browser"
                                    )
                                ) {
                                    viewModel.open(issue.url)
                                }
                                Button(localized("github.pane.context.copyURL", fallback: "Copy URL")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        issue.url.absoluteString,
                                        forType: .string
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var checksList: some View {
        Group {
            if viewModel.checks.isEmpty {
                emptyState(
                    title: viewModel.selectedPullRequestNumber == nil
                        ? localized(
                            "github.pane.empty.selectPullRequest",
                            fallback: "Select a pull request to see checks"
                        )
                        : localized(
                            "github.pane.empty.noChecks",
                            fallback: "No checks reported"
                        ),
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.checks) { check in
                            Button(action: {
                                if let url = check.detailsUrl { viewModel.open(url) }
                            }) {
                                GitHubCheckRow(check: check, localizer: localizer)
                            }
                            .buttonStyle(.plain)
                            .disabled(check.detailsUrl == nil)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var reviewThreadsList: some View {
        Group {
            if viewModel.selectedPullRequestNumber == nil {
                emptyState(
                    title: localized(
                        "github.pane.empty.selectPullRequestReviews",
                        fallback: "Select a pull request to see review threads"
                    ),
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else if viewModel.reviewThreads.isEmpty {
                emptyState(
                    title: localized(
                        "github.pane.empty.noReviewThreads",
                        fallback: "No review threads"
                    ),
                    systemImage: "bubble.left.and.bubble.right"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.reviewThreads) { thread in
                            Button(action: {
                                if let url = thread.comments.first?.url {
                                    viewModel.open(url)
                                }
                            }) {
                                GitHubReviewThreadRow(thread: thread, localizer: localizer)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let url = thread.comments.first?.url {
                                    Button(
                                        localized(
                                            "github.pane.context.openInBrowser",
                                            fallback: "Open in Browser"
                                        )
                                    ) {
                                        viewModel.open(url)
                                    }
                                }
                                if viewModel.reviewThreadSuggestionCount(thread) > 0 {
                                    Divider()
                                    Button {
                                        viewModel.applyReviewThreadSuggestions(thread)
                                    } label: {
                                        Label(
                                            localized(
                                                "github.pane.context.applyReviewThreadSuggestions",
                                                fallback: "Apply Suggestions"
                                            ),
                                            systemImage: "checkmark.rectangle.stack"
                                        )
                                    }
                                    .disabled(!viewModel.canApplyReviewThreadSuggestions(thread))
                                }
                                if viewModel.canOfferResolveReviewThread(thread) {
                                    Divider()
                                    Button {
                                        viewModel.resolveReviewThread(thread)
                                    } label: {
                                        Label(
                                            localized(
                                                "github.pane.context.resolveReviewThread",
                                                fallback: "Resolve Thread"
                                            ),
                                            systemImage: "checkmark.circle"
                                        )
                                    }
                                    .disabled(viewModel.isUpdatingReviewThread(thread.id))
                                }
                                if viewModel.canOfferUnresolveReviewThread(thread) {
                                    Divider()
                                    Button {
                                        viewModel.unresolveReviewThread(thread)
                                    } label: {
                                        Label(
                                            localized(
                                                "github.pane.context.reopenReviewThread",
                                                fallback: "Reopen Thread"
                                            ),
                                            systemImage: "arrow.uturn.backward.circle"
                                        )
                                    }
                                    .disabled(viewModel.isUpdatingReviewThread(thread.id))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func emptyState(title: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary.opacity(0.6))
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .progressViewStyle(.circular)
                Text(localized("github.pane.loading", fallback: "Loading..."))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if let auth = viewModel.authStatus, auth.isAuthenticated,
                      viewModel.pullRequests.count + viewModel.issues.count > 0 {
                Text(
                    String(
                        format: localized(
                            "github.pane.footer.counts",
                            fallback: "%d PRs · %d issues"
                        ),
                        viewModel.pullRequests.count,
                        viewModel.issues.count
                    )
                )
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(localized("github.pane.refresh", fallback: "Refresh"))
            .help(localized("github.pane.refresh", fallback: "Refresh"))
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func didActivate(_ pullRequest: GitHubPullRequest) {
        if viewModel.selectedTab == .reviewThreads {
            viewModel.selectPullRequestForReviewThreads(pullRequest)
        } else {
            viewModel.selectPullRequestForChecks(pullRequest)
        }
    }

    private func presentMergeActionSheet(for pullRequest: GitHubPullRequest) {
        guard let decision = MergePullRequestActionSheet.present(
            pullRequestNumber: pullRequest.number,
            localizer: localizer
        ) else { return }
        viewModel.requestMergePullRequest(
            number: pullRequest.number,
            method: decision.method,
            deleteBranch: decision.deleteBranch
        )
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

// MARK: - Tab Strip

struct GitHubPaneTabStrip: View {
    @Binding var selection: GitHubPaneViewModel.Tab
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        GeometryReader { proxy in
            let presentation = GitHubPaneTabStripPresentation.resolve(width: proxy.size.width)

            HStack(spacing: presentation.itemSpacing) {
                ForEach(GitHubPaneViewModel.Tab.allCases) { tab in
                    tabButton(tab, presentation: presentation)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: GitHubPaneTabStripPresentation.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("github.pane.view", fallback: "GitHub view"))
    }

    private func tabButton(
        _ tab: GitHubPaneViewModel.Tab,
        presentation: GitHubPaneTabStripPresentation
    ) -> some View {
        let fullTitle = tab.localizedTitle(using: localizer)
        let showsTitle = presentation.showsTitle(for: tab, selectedTab: selection)

        return Button {
            selection = tab
        } label: {
            HStack(spacing: showsTitle ? 5 : 0) {
                Image(systemName: tab.systemImage)
                    .imageScale(.small)
                    .frame(width: 14, height: 14)

                if showsTitle {
                    Text(tab.compactLocalizedTitle(using: localizer))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .buttonStyle(
            GitHubPaneTabButtonStyle(
                isSelected: selection == tab,
                presentation: presentation
            )
        )
        .accessibilityLabel(fullTitle)
        .accessibilityValue(selection == tab ? "Selected" : "")
        .help(fullTitle)
    }
}

struct GitHubPaneTabStripPresentation: Equatable {
    enum Mode: Equatable {
        case allLabels
        case selectedLabel
        case iconsOnly
    }

    static let height: CGFloat = 30
    private static let allLabelsMinimumWidth: CGFloat = 840
    private static let selectedLabelMinimumWidth: CGFloat = 340

    let mode: Mode

    static func resolve(width: CGFloat) -> GitHubPaneTabStripPresentation {
        if width >= allLabelsMinimumWidth {
            return GitHubPaneTabStripPresentation(mode: .allLabels)
        }
        if width >= selectedLabelMinimumWidth {
            return GitHubPaneTabStripPresentation(mode: .selectedLabel)
        }
        return GitHubPaneTabStripPresentation(mode: .iconsOnly)
    }

    var itemSpacing: CGFloat {
        switch mode {
        case .allLabels: return 6
        case .selectedLabel: return 4
        case .iconsOnly: return 4
        }
    }

    var horizontalPadding: CGFloat {
        switch mode {
        case .allLabels: return 7
        case .selectedLabel: return 5
        case .iconsOnly: return 5
        }
    }

    var minimumButtonWidth: CGFloat {
        switch mode {
        case .allLabels: return 62
        case .selectedLabel: return 26
        case .iconsOnly: return 26
        }
    }

    var usesFlexibleButtons: Bool {
        mode == .allLabels
    }

    func showsTitle(
        for tab: GitHubPaneViewModel.Tab,
        selectedTab: GitHubPaneViewModel.Tab
    ) -> Bool {
        switch mode {
        case .allLabels:
            return true
        case .selectedLabel:
            return tab == selectedTab
        case .iconsOnly:
            return false
        }
    }
}

struct GitHubPaneTabButtonStyle: ButtonStyle {
    let isSelected: Bool
    let presentation: GitHubPaneTabStripPresentation

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(
                minWidth: presentation.minimumButtonWidth,
                maxWidth: presentation.usesFlexibleButtons ? .infinity : nil,
                minHeight: 28
            )
            .padding(.horizontal, presentation.horizontalPadding)
            .background(background(isPressed: configuration.isPressed))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func background(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(backgroundColor(isPressed: isPressed))
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(isPressed ? 0.28 : 0.20)
        }
        return Color.white.opacity(isPressed ? 0.10 : 0.055)
    }
}
