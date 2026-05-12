// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PullRequestsListView.swift - Filterable pull-request list for Source Control.

import SwiftUI
import AppKit

enum PullRequestFilterControlsLayout: Equatable {
    case segmented
    case compactMenu

    private static let compactMenuMaximumWidth: CGFloat = 340

    static func resolve(width: CGFloat) -> PullRequestFilterControlsLayout {
        width <= compactMenuMaximumWidth ? .compactMenu : .segmented
    }
}

struct PullRequestsListView: View {
    let pullRequests: [GitHubPullRequest]
    let selectedPullRequestNumber: Int?
    @Binding var searchText: String
    @Binding var state: PullRequestListState
    @Binding var includeDrafts: Bool
    var canOfferMerge: (GitHubPullRequest) -> Bool
    var isMerging: (Int) -> Bool
    var onSelectChecks: (GitHubPullRequest) -> Void
    var onReviewThreads: (GitHubPullRequest) -> Void
    var onOpen: (URL) -> Void
    var onMerge: (GitHubPullRequest) -> Void
    var onCreate: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if filteredPullRequests.isEmpty {
                SourceControlEmptyState(
                    title: localizer.string(
                        "github.pane.empty.pullRequests",
                        fallback: "No pull requests"
                    ),
                    systemImage: "arrow.triangle.pull"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filteredPullRequests) { pr in
                            Button(action: { onSelectChecks(pr) }) {
                                GitHubPullRequestRow(
                                    pullRequest: pr,
                                    isSelected: selectedPullRequestNumber == pr.number,
                                    localizer: localizer
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(
                                    localizer.string(
                                        "github.pane.context.openInBrowser",
                                        fallback: "Open in Browser"
                                    )
                                ) {
                                    onOpen(pr.url)
                                }
                                Button(localizer.string("github.pane.context.copyURL", fallback: "Copy URL")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(
                                        pr.url.absoluteString,
                                        forType: .string
                                    )
                                }
                                Button {
                                    onReviewThreads(pr)
                                } label: {
                                    Label(
                                        localizer.string(
                                            "github.pane.context.reviewThreads",
                                            fallback: "Show Review Threads"
                                        ),
                                        systemImage: "bubble.left.and.bubble.right"
                                    )
                                }
                                if canOfferMerge(pr) {
                                    Divider()
                                    Button {
                                        onMerge(pr)
                                    } label: {
                                        Label(
                                            isMerging(pr.number)
                                                ? localizer.string(
                                                    "github.pane.merge.inProgress",
                                                    fallback: "Merging..."
                                                )
                                                : localizer.string(
                                                    "github.pane.merge.action",
                                                    fallback: "Merge Pull Request..."
                                                ),
                                            systemImage: isMerging(pr.number) ? "hourglass" : "arrow.triangle.merge"
                                        )
                                    }
                                    .disabled(isMerging(pr.number))
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

    static func filteredPullRequests(
        _ pullRequests: [GitHubPullRequest],
        state: PullRequestListState,
        includeDrafts: Bool,
        searchText: String
    ) -> [GitHubPullRequest] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pullRequests.filter { pr in
            let stateMatches: Bool = switch state {
            case .all:
                true
            case .open:
                pr.state == .open
            case .closed:
                pr.state == .closed
            case .merged:
                pr.state == .merged
            }
            guard stateMatches else { return false }
            guard includeDrafts || !pr.isDraft else { return false }
            guard !needle.isEmpty else { return true }
            return pr.title.lowercased().contains(needle) ||
                pr.author.login.lowercased().contains(needle) ||
                pr.headRefName.lowercased().contains(needle) ||
                pr.baseRefName.lowercased().contains(needle) ||
                String(pr.number).contains(needle)
        }
    }

    private var filteredPullRequests: [GitHubPullRequest] {
        Self.filteredPullRequests(
            pullRequests,
            state: state,
            includeDrafts: includeDrafts,
            searchText: searchText
        )
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    localizer.string("github.prs.search", fallback: "Search pull requests"),
                    text: $searchText
                )
                .textFieldStyle(.roundedBorder)

                Button(action: onCreate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(localizer.string("github.prs.create", fallback: "Create pull request"))
            }

            filterControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filterControls: some View {
        GeometryReader { proxy in
            switch PullRequestFilterControlsLayout.resolve(width: proxy.size.width) {
            case .segmented:
                regularFilterControls
            case .compactMenu:
                compactFilterControls
            }
        }
        .frame(height: 28)
    }

    private var regularFilterControls: some View {
        HStack(spacing: 8) {
            segmentedStatePicker
                .layoutPriority(1)
            includeDraftsToggle
        }
    }

    private var compactFilterControls: some View {
        HStack(spacing: 8) {
            compactStatePicker
                .layoutPriority(1)
            includeDraftsToggle
        }
    }

    private var segmentedStatePicker: some View {
        Picker("", selection: $state) {
            ForEach(PullRequestListState.allCases, id: \.self) { state in
                Text(state.rawValue.capitalized).tag(state)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var compactStatePicker: some View {
        Picker(
            localizer.string("github.prs.state", fallback: "State"),
            selection: $state
        ) {
            ForEach(PullRequestListState.allCases, id: \.self) { state in
                Text(state.rawValue.capitalized).tag(state)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var includeDraftsToggle: some View {
        Toggle(localizer.string("github.prs.drafts", fallback: "Drafts"), isOn: $includeDrafts)
            .toggleStyle(.checkbox)
            .fixedSize(horizontal: true, vertical: false)
    }
}
