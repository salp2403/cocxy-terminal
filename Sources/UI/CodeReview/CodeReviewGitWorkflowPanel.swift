// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewGitWorkflowPanel.swift - Inline Git workflow controls for Code Review.

import SwiftUI

struct CodeReviewGitWorkflowPanel: View {
    @ObservedObject var viewModel: CodeReviewPanelViewModel

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
        .accessibilityLabel("Git workflow")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Git Workflow", systemImage: "arrow.triangle.branch")
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
                Label("Refresh", systemImage: "arrow.clockwise")
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
            .help("Hide Git workflow")
        }
    }

    private var statusCard: some View {
        GitWorkflowCard(title: "Repository", systemImage: "externaldrive.connected.to.line.below") {
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
                            miniStat("ahead \(status.ahead)", color: CocxyColors.green)
                        }
                        if status.behind > 0 {
                            miniStat("behind \(status.behind)", color: CocxyColors.yellow)
                        }
                    }

                    HStack(spacing: 7) {
                        miniStat("\(status.changedCount) changed", color: CocxyColors.sky)
                        miniStat("\(status.stagedCount) staged", color: CocxyColors.green)
                        miniStat("\(status.untrackedCount) new", color: CocxyColors.mauve)
                    }
                }
            } else {
                Text("No Git repository was detected for this review context.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var branchCard: some View {
        GitWorkflowCard(title: "Branch", systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 8) {
                TextField("feature/review-fix", text: $viewModel.branchNameDraft)
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.createBranchFromDraft()
                } label: {
                    Label("Create Branch", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.branchNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || viewModel.isGitActionRunning
                )

                Text("Creates and switches to the branch before committing.")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.overlay1))
            }
        }
    }

    private var commitCard: some View {
        GitWorkflowCard(title: "Commit & Push", systemImage: "paperplane") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Commit message")
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
                            Text("fix(review): explain what changed and why")
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
                        Text("Tip: first line = summary, blank line = details.")
                            .font(.system(size: 9))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                        Spacer()
                        Text("\(viewModel.commitMessageDraft.count) chars")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        viewModel.commitAllChangesFromDraft()
                    } label: {
                        Label("Commit All", systemImage: "checkmark.circle")
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
                        Label("Push", systemImage: "arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isGitActionRunning)
                }

                Button {
                    viewModel.requestCreatePullRequest()
                } label: {
                    Label("Create Pull Request", systemImage: "arrow.triangle.pull")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!isCreatePRAvailable)
                .help(
                    viewModel.createPullRequestHandler == nil
                        ? "Open the GitHub pane (Cmd+Option+G) once to enable this action."
                        : "Creates a PR on GitHub via gh using the commit message as title and body."
                )

                Text("Commit All stages current review changes, Push sends the branch to origin, Create Pull Request opens a PR on GitHub via gh.")
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
