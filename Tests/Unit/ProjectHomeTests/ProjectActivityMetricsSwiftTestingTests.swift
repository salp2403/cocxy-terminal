// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectActivityMetricsSwiftTestingTests.swift - Compact Project Home metric formatting.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project Home activity metrics")
struct ProjectActivityMetricsSwiftTestingTests {
    @Test("duration formatter stays compact and deterministic")
    func durationFormatting() {
        #expect(ProjectActivityMetricsFormatter.duration(0) == "0s")
        #expect(ProjectActivityMetricsFormatter.duration(90_000) == "1m 30s")
        #expect(ProjectActivityMetricsFormatter.duration(3_661_000) == "1h 1m")
    }

    @Test("token formatter preserves useful precision")
    func tokenFormatting() {
        #expect(ProjectActivityMetricsFormatter.tokens(999) == "999")
        #expect(ProjectActivityMetricsFormatter.tokens(1_250) == "1.2K")
        #expect(ProjectActivityMetricsFormatter.tokens(2_000_000) == "2M")
    }

    @Test("cost formatter uses the persisted micro-dollar unit")
    func costFormatting() {
        #expect(ProjectActivityMetricsFormatter.cost(0) == "$0.0000")
        #expect(ProjectActivityMetricsFormatter.cost(1_250_000) == "$1.2500")
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
        try? await Task.sleep(for: .milliseconds(150))

        #expect(viewModel.activitySummaryState == .available(
            expected,
            costTrackingEnabled: true
        ))
    }
}
