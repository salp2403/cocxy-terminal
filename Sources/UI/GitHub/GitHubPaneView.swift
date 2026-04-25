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
        .background(.thickMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GitHub pane")
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
                    Text("Signed in as @\(login)")
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
                .help("Open \(repo.fullName) on GitHub")
            }

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close pane")
                .help("Close pane (Cmd+Option+G)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Tab picker

    private var tabPicker: some View {
        Picker("GitHub view", selection: $viewModel.selectedTab) {
            ForEach(GitHubPaneViewModel.Tab.allCases) { tab in
                Label(tab.displayName, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
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
                    GitHubPaneBanner(message: error, kind: .error)
                }
                if let mergeInfo = viewModel.lastMergeInfoMessage {
                    GitHubPaneBanner(message: mergeInfo, kind: .info)
                }
                if let info = viewModel.lastInfoMessage {
                    GitHubPaneBanner(message: info, kind: .info)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .pullRequests:
            pullRequestsList
        case .issues:
            issuesList
        case .checks:
            checksList
        }
    }

    private var pullRequestsList: some View {
        Group {
            if viewModel.pullRequests.isEmpty {
                emptyState(title: "No pull requests", systemImage: "arrow.triangle.pull")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.pullRequests) { pr in
                            Button(action: { didActivate(pr) }) {
                                GitHubPullRequestRow(
                                    pullRequest: pr,
                                    isSelected: viewModel.selectedPullRequestNumber == pr.number
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in Browser") { viewModel.open(pr.url) }
                                Button("Copy URL") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        pr.url.absoluteString,
                                        forType: .string
                                    )
                                }
                                if viewModel.canOfferMerge(for: pr) {
                                    Divider()
                                    Button {
                                        presentMergeActionSheet(for: pr)
                                    } label: {
                                        if viewModel.isMerging(pr.number) {
                                            Label("Merging…", systemImage: "hourglass")
                                        } else {
                                            Label(
                                                "Merge Pull Request…",
                                                systemImage: "arrow.triangle.merge"
                                            )
                                        }
                                    }
                                    .disabled(viewModel.isMerging(pr.number))
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

    private var issuesList: some View {
        Group {
            if viewModel.issues.isEmpty {
                emptyState(title: "No issues", systemImage: "exclamationmark.circle")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.issues) { issue in
                            Button(action: { viewModel.open(issue.url) }) {
                                GitHubIssueRow(issue: issue)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Open in Browser") { viewModel.open(issue.url) }
                                Button("Copy URL") {
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
                        ? "Select a pull request to see checks"
                        : "No checks reported",
                    systemImage: "checkmark.circle"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.checks) { check in
                            Button(action: {
                                if let url = check.detailsUrl { viewModel.open(url) }
                            }) {
                                GitHubCheckRow(check: check)
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
                Text("Loading…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else if let auth = viewModel.authStatus, auth.isAuthenticated,
                      viewModel.pullRequests.count + viewModel.issues.count > 0 {
                Text("\(viewModel.pullRequests.count) PRs · \(viewModel.issues.count) issues")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { viewModel.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
            .keyboardShortcut("r", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Actions

    private func didActivate(_ pullRequest: GitHubPullRequest) {
        viewModel.selectPullRequestForChecks(pullRequest)
    }

    private func presentMergeActionSheet(for pullRequest: GitHubPullRequest) {
        guard let decision = MergePullRequestActionSheet.present(
            pullRequestNumber: pullRequest.number
        ) else { return }
        viewModel.requestMergePullRequest(
            number: pullRequest.number,
            method: decision.method,
            deleteBranch: decision.deleteBranch
        )
    }
}
