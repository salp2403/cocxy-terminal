// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewGitWorkflowPanel.swift - Inline Git workflow controls for Code Review.

import SwiftUI

struct CodeReviewGitWorkflowPanel: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    statusCard
                        .frame(width: 270)

                    branchCard
                        .frame(width: 250)

                    commitCard
                        .frame(minWidth: 420)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        statusCard
                            .frame(maxWidth: .infinity)
                        branchCard
                            .frame(maxWidth: .infinity)
                    }
                    commitCard
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: CocxyColors.surface0).opacity(0.82),
                    Color(nsColor: CocxyColors.base).opacity(0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(nsColor: CocxyColors.blue).opacity(0.18))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            localized("codeReview.gitWorkflow.accessibility", fallback: "Git workflow")
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(
                localized("codeReview.gitWorkflow.title", fallback: "Git Workflow"),
                systemImage: "arrow.triangle.branch"
            )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(nsColor: CocxyColors.text))

            if viewModel.isGitActionRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            Spacer()

            Button {
                viewModel.refreshGitStatus()
            } label: {
                Label(
                    localized("codeReview.gitWorkflow.refresh", fallback: "Refresh"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isGitActionRunning)

            Button {
                viewModel.isGitWorkflowVisible = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help(localized("codeReview.gitWorkflow.hide", fallback: "Hide Git workflow"))
        }
    }

    private var statusCard: some View {
        GitWorkflowCard(
            title: localized("codeReview.gitWorkflow.repository", fallback: "Repository"),
            systemImage: "externaldrive.connected.to.line.below"
        ) {
            if let status = viewModel.gitStatus {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(status.branch)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(nsColor: CocxyColors.blue))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 6)

                        if status.ahead > 0 {
                            miniStat(
                                localizedCount("codeReview.gitWorkflow.stat.ahead", fallback: "ahead %d", status.ahead),
                                color: CocxyColors.green
                            )
                        }
                        if status.behind > 0 {
                            miniStat(
                                localizedCount(
                                    "codeReview.gitWorkflow.stat.behind",
                                    fallback: "behind %d",
                                    status.behind
                                ),
                                color: CocxyColors.yellow
                            )
                        }
                    }

                    HStack(spacing: 7) {
                        miniStat(
                            localizedCount(
                                "codeReview.gitWorkflow.stat.changed",
                                fallback: "%d changed",
                                status.changedCount
                            ),
                            color: CocxyColors.sky
                        )
                        miniStat(
                            localizedCount(
                                "codeReview.gitWorkflow.stat.staged",
                                fallback: "%d staged",
                                status.stagedCount
                            ),
                            color: CocxyColors.green
                        )
                        miniStat(
                            localizedCount(
                                "codeReview.gitWorkflow.stat.new",
                                fallback: "%d new",
                                status.untrackedCount
                            ),
                            color: CocxyColors.mauve
                        )
                    }
                }
            } else {
                Text(
                    localized(
                        "codeReview.gitWorkflow.noRepository",
                        fallback: "No Git repository was detected for this review context."
                    )
                )
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var branchCard: some View {
        GitWorkflowCard(
            title: localized("codeReview.gitWorkflow.branch", fallback: "Branch"),
            systemImage: "point.3.connected.trianglepath.dotted"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextField(
                    localized("codeReview.gitWorkflow.placeholder.branch", fallback: "feature/review-fix"),
                    text: $viewModel.branchNameDraft
                )
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.createBranchFromDraft()
                } label: {
                    Label(
                        localized("codeReview.gitWorkflow.createBranch", fallback: "Create Branch"),
                        systemImage: "plus"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.branchNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isGitActionRunning
                )

                Text(
                    localized(
                        "codeReview.gitWorkflow.createBranch.help",
                        fallback: "Creates and switches to the branch before committing."
                    )
                )
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }
        }
    }

    private var commitCard: some View {
        GitWorkflowCard(
            title: localized("codeReview.gitWorkflow.commitPush", fallback: "Commit & Push"),
            systemImage: "paperplane"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("codeReview.gitWorkflow.commitMessage", fallback: "Commit message"))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        .textCase(.uppercase)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: CocxyColors.base).opacity(0.76))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color(nsColor: CocxyColors.surface1), lineWidth: 1)
                            )

                        if viewModel.commitMessageDraft.isEmpty {
                            Text(
                                localized(
                                    "codeReview.gitWorkflow.commitPlaceholder",
                                    fallback: "fix(review): explain what changed and why"
                                )
                            )
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                        }

                        TextEditor(text: $viewModel.commitMessageDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(4)
                    }
                    .frame(minHeight: 78, maxHeight: 104)

                    HStack(spacing: 6) {
                        Text(
                            localized(
                                "codeReview.gitWorkflow.commitTip",
                                fallback: "Tip: first line = summary, blank line = details."
                            )
                        )
                            .font(.system(size: 9))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        Spacer()
                        Text(
                            localizedCount(
                                "codeReview.gitWorkflow.chars",
                                fallback: "%d chars",
                                viewModel.commitMessageDraft.count
                            )
                        )
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.commitAllChangesFromDraft()
                    } label: {
                        Label(
                            localized("codeReview.gitWorkflow.commitAll", fallback: "Commit All"),
                            systemImage: "checkmark.circle"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.commitMessageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || viewModel.isGitActionRunning
                    )

                    Button {
                        viewModel.pushCurrentBranch()
                    } label: {
                        Label(
                            localized("codeReview.gitWorkflow.push", fallback: "Push"),
                            systemImage: "arrow.up.circle"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isGitActionRunning)
                }

                Button {
                    viewModel.requestCreatePullRequest()
                } label: {
                    Label(
                        localized("codeReview.gitWorkflow.createPR", fallback: "Create Pull Request"),
                        systemImage: "arrow.triangle.pull"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isCreatePRAvailable)
                .help(
                    viewModel.createPullRequestHandler == nil
                        ? localized(
                            "codeReview.gitWorkflow.createPR.enableHelp",
                            fallback: "Open the GitHub pane (Cmd+Option+G) once to enable this action."
                        )
                        : localized(
                            "codeReview.gitWorkflow.createPR.help",
                            fallback: "Creates a PR on GitHub via gh using the commit message as title and body."
                        )
                )

                Text(
                    localized(
                        "codeReview.gitWorkflow.footer",
                        fallback: "Commit All stages current review changes, Push sends the branch to origin, Create Pull Request opens a PR on GitHub via gh."
                    )
                )
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }
        }
    }

    /// Whether the Create PR button should be tappable. Requires a
    /// non-empty commit draft (so the PR has a title), no other git
    /// action running, and that `MainWindowController` has wired the
    /// GitHub handler (which happens automatically the first time the
    /// GitHub pane is opened).
    private var isCreatePRAvailable: Bool {
        let hasDraft = !viewModel.commitMessageDraft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        return hasDraft
            && !viewModel.isGitActionRunning
            && viewModel.createPullRequestHandler != nil
    }

    private func miniStat(_ text: String, color: NSColor) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(Color(nsColor: color))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color(nsColor: color).opacity(0.12))
            )
            .lineLimit(1)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    private func localizedCount(_ key: String, fallback: String, _ count: Int) -> String {
        String(format: localized(key, fallback: fallback), count)
    }
}

private struct GitWorkflowCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .textCase(.uppercase)

            content
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: CocxyColors.mantle).opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color(nsColor: CocxyColors.surface1).opacity(0.8), lineWidth: 1)
        )
    }
}
