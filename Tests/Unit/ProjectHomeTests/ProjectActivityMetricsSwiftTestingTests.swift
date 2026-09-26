// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectActivityMetricsSwiftTestingTests.swift - Compact Project Home metric formatting.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project Home activity metrics")
struct ProjectActivityMetricsSwiftTestingTests {
    @Test("duration formatter stays compact and deterministic")
    func durationFormatting() {
        let english = Locale(identifier: "en_US")
        let spanish = Locale(identifier: "es_ES")
        #expect(ProjectActivityMetricsFormatter.duration(0, locale: english) == "0s")
        #expect(ProjectActivityMetricsFormatter.duration(90_000, locale: english) == "1m 30s")
        #expect(ProjectActivityMetricsFormatter.duration(3_661_000, locale: english) == "1h 1m")
        #expect(ProjectActivityMetricsFormatter.duration(90_000, locale: spanish) == "1 min 30 s")
    }

    @Test("token formatter preserves useful precision")
    func tokenFormatting() {
        let english = Locale(identifier: "en_US")
        let spanish = Locale(identifier: "es_ES")
        #expect(ProjectActivityMetricsFormatter.tokens(999, locale: english) == "999")
        #expect(ProjectActivityMetricsFormatter.tokens(1_250, locale: english) == "1.2K")
        #expect(ProjectActivityMetricsFormatter.tokens(2_000_000, locale: english) == "2M")
        #expect(ProjectActivityMetricsFormatter.tokens(1_250, locale: spanish) == "1,2 mil")
    }

    @Test("cost formatter uses the persisted micro-dollar unit")
    func costFormatting() {
        let english = Locale(identifier: "en_US")
        let spanish = Locale(identifier: "es_ES")
        let arabic = Locale(identifier: "ar")
        #expect(ProjectActivityMetricsFormatter.cost(0, locale: english) == "$0.0000")
        #expect(ProjectActivityMetricsFormatter.cost(1_250_000, locale: english) == "$1.2500")
        #expect(ProjectActivityMetricsFormatter.cost(1_250_000, locale: spanish) == "1,2500 US$")
        #expect(ProjectActivityMetricsFormatter.cost(1_250_000, locale: arabic).contains("US$"))
    }

    @MainActor
    @Test("cancelled metric loads cannot overwrite the newest project snapshot")
    func cancelledMetricLoadCannotOverwriteNewestSnapshot() async {
        var invocation = 0
        let expected = ProjectActivitySummary(
            week: ProjectActivityMetrics(
                durationMilliseconds: 1_000,
                totalTokens: 2,
                totalCostMicros: 3
            ),
            month: .zero
        )
        let viewModel = ProjectHomePanelViewModel(
            projectID: ProjectID(rawValue: "/tmp/project-a"),
            projectRoot: URL(fileURLWithPath: "/tmp/project-a", isDirectory: true),
            displayName: "Project A",
            accent: nil,
            fallbackRemote: nil,
            worktreeConfig: .defaults,
            activitySummaryLoader: { _ in
                invocation += 1
                if invocation == 1 {
                    try? await Task.sleep(for: .milliseconds(100))
                    return .disabled
                }
                return .available(expected, costTrackingEnabled: true)
            },
            recentDiffProvider: { nil },
            actions: ProjectHomeActions(
                createSession: {},
                createWorktree: nil,
                launchTeam: { _ in },
                openCodeReview: {},
                activateEntry: { _ in },
                focusWorktree: nil,
                openRecentDiff: nil
            )
        )

        viewModel.reloadActivitySummary()
        for _ in 0..<20 where invocation == 0 {
            await Task.yield()
        }
        #expect(invocation == 1)
        viewModel.reloadActivitySummary()
        for _ in 0..<1_500 where viewModel.activitySummaryState != .available(expected, costTrackingEnabled: true) { try? await Task.sleep(for: .milliseconds(10)) }
        try? await Task.sleep(for: .milliseconds(150))

        #expect(viewModel.activitySummaryState == .available(
            expected,
            costTrackingEnabled: true
        ))
    }

    @MainActor
    @Test("open Project Home headers follow app-scoped metadata updates")
    func headerMetadataUpdatesLive() async {
        let updates = PassthroughSubject<ProjectHomeHeaderState, Never>()
        let viewModel = ProjectHomePanelViewModel(
            projectID: ProjectID(rawValue: "/tmp/project-header"),
            projectRoot: URL(fileURLWithPath: "/tmp/project-header", isDirectory: true),
            displayName: "Before",
            accent: nil,
            fallbackRemote: nil,
            worktreeConfig: .defaults,
            contextLoader: ProjectHomeContextLoader(
                gitMetadata: { _, fallback in
                    .success(ProjectHomeGitMetadata(
                        remoteOrigin: fallback,
                        statusSummary: CodeReviewGitSummary(
                            branch: "main",
                            changedCount: 0,
                            ahead: 0,
                            behind: 0
                        )
                    ))
                },
                worktrees: { _, _ in .success([]) }
            ),
            headerUpdates: updates.eraseToAnyPublisher(),
            recentDiffProvider: { nil },
            actions: emptyActions()
        )

        updates.send(ProjectHomeHeaderState(
            displayName: "After",
            accent: "#00AA66",
            remoteOrigin: "ssh://owner/repo"
        ))
        viewModel.loadContext()
        for _ in 0..<20 where viewModel.isLoadingContext { await Task.yield() }

        #expect(viewModel.displayName == "After")
        #expect(viewModel.accent == "#00AA66")
        #expect(viewModel.gitMetadata?.remoteOrigin == "ssh://owner/repo")
    }

    @MainActor
    @Test("failed Git context can be retried")
    func failedGitContextRetries() async {
        let attempts = LockedBox(0)
        let viewModel = ProjectHomePanelViewModel(
            projectID: ProjectID(rawValue: "/tmp/project-retry"),
            projectRoot: URL(fileURLWithPath: "/tmp/project-retry", isDirectory: true),
            displayName: "Retry",
            accent: nil,
            fallbackRemote: nil,
            worktreeConfig: .defaults,
            contextLoader: ProjectHomeContextLoader(
                gitMetadata: { _, _ in
                    let attempt = attempts.withValue { value in
                        value += 1
                        return value
                    }
                    return attempt == 1
                        ? .failure(.gitStatusUnavailable)
                        : .success(ProjectHomeGitMetadata(
                            remoteOrigin: nil,
                            statusSummary: CodeReviewGitSummary(
                                branch: "main",
                                changedCount: 0,
                                ahead: 0,
                                behind: 0
                            )
                        ))
                },
                worktrees: { _, _ in .success([]) }
            ),
            recentDiffProvider: { nil },
            actions: emptyActions()
        )

        viewModel.loadContext()
        for _ in 0..<20 where viewModel.isLoadingContext { await Task.yield() }
        #expect(viewModel.gitContextFailed)

        viewModel.loadContext()
        for _ in 0..<20 where viewModel.isLoadingContext { await Task.yield() }
        #expect(!viewModel.gitContextFailed)
        #expect(viewModel.gitMetadata?.branch == "main")
    }

    @MainActor
    private func emptyActions() -> ProjectHomeActions {
        ProjectHomeActions(
            createSession: {},
            createWorktree: nil,
            launchTeam: { _ in },
            openCodeReview: {},
            activateEntry: { _ in },
            focusWorktree: nil,
            openRecentDiff: nil
        )
    }
}
