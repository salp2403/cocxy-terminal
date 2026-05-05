// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeAdvancedSwiftTestingTests.swift - Phase W advanced worktree contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Worktree advanced")
struct WorktreeAdvancedSwiftTestingTests {

    @Test("built-in templates expose feature, hotfix, and experiment presets")
    func builtInTemplatesExposeV1Presets() {
        let templates = WorktreeTemplate.builtIns

        #expect(templates.map(\.id) == ["feature", "hotfix", "experiment"])
        #expect(templates.map(\.branchKind) == [.feature, .hotfix, .experiment])
        #expect(templates.allSatisfy { !$0.displayName.isEmpty })
    }

    @Test("branch name generator produces sanitized template previews")
    func branchNameGeneratorProducesPreview() {
        let preview = WorktreeBranchNameGenerator.preview(
            template: .feature,
            summary: "Add Login Flow!",
            issue: "APP-42",
            agent: "Local Agent",
            id: "abc123",
            date: Date(timeIntervalSince1970: 1_773_014_400),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(preview == "feat/add-login-flow-abc123")
    }

    @Test("hotfix template prefers issue key while preserving a readable slug")
    func hotfixTemplateUsesIssueKey() {
        let preview = WorktreeBranchNameGenerator.preview(
            template: .hotfix,
            summary: "Crash on Restore",
            issue: "APP-91",
            agent: nil,
            id: "fix999",
            date: Date(timeIntervalSince1970: 1_773_014_400),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(preview == "fix/APP-91/crash-on-restore")
    }

    @Test("advanced modal view model emits CLI params from selected template")
    func advancedModalViewModelBuildsCLIParams() throws {
        let viewModel = WorktreeAdvancedModalViewModel(
            templates: WorktreeTemplate.builtIns,
            initialBaseRef: "main",
            availableBaseRefs: ["HEAD", "main", "develop"],
            detectedAgent: "Local Agent",
            previewID: "abc123",
            now: Date(timeIntervalSince1970: 1_773_014_400),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        viewModel.selectedTemplateID = "experiment"
        viewModel.summary = "Parser Spike"
        viewModel.baseRef = "develop"

        let request = try #require(viewModel.creationRequest())

        #expect(request.branch == "experiment/parser-spike-abc123")
        #expect(request.baseRef == "develop")
        #expect(request.agent == "Local Agent")
        #expect(request.cliParams == [
            "agent": "Local Agent",
            "branch": "experiment/parser-spike-abc123",
            "base-ref": "develop"
        ])
    }

    @Test("session restore helper finds saved tabs for one worktree and keeps pane metadata")
    func sessionRestoreFindsMatchingWorktreeTabs() {
        let root = URL(fileURLWithPath: "/tmp/cocxy-wt", isDirectory: true)
        let matching = TabState(
            id: TabID(),
            title: "Feature",
            workingDirectory: root,
            splitTree: .leaf(workingDirectory: root, command: nil),
            worktreeID: "wt-1",
            worktreeRoot: root,
            worktreeOriginRepo: URL(fileURLWithPath: "/tmp/origin", isDirectory: true),
            worktreeBranch: "feat/parser",
            paneStates: [
                SplitPaneState(
                    panelInfo: PanelInfo(type: .terminal),
                    title: "Shell"
                )
            ]
        )
        let other = TabState(
            id: TabID(),
            title: "Other",
            workingDirectory: URL(fileURLWithPath: "/tmp/other", isDirectory: true),
            splitTree: .leaf(workingDirectory: URL(fileURLWithPath: "/tmp/other"), command: nil)
        )

        let result = WorktreeSessionRestore.matchingTabs(
            worktreeID: "wt-1",
            worktreeRoot: root,
            in: [other, matching]
        )

        #expect(result.map { $0.id } == [matching.id])
        #expect(result.first?.paneStates.first?.title == "Shell")
    }

    @Test("batch cleanup sheet view model summarizes removable, blocked, and skipped entries")
    func batchCleanupViewModelSummarizesPlan() {
        let removable = makeEntry(id: "merged", branch: "feat/merged")
        let blocked = makeEntry(id: "dirty", branch: "feat/dirty")
        let skipped = makeEntry(id: "open", branch: "feat/open")
        let plan = WorktreeBatchCleanupPlan(
            removable: [removable],
            blocked: [
                WorktreeBatchCleanupBlock(
                    entry: blocked,
                    reason: .uncommittedChanges(statusOutput: " M README.md")
                )
            ],
            skipped: [
                WorktreeBatchCleanupSkip(entry: skipped, reason: .notMerged)
            ]
        )

        let viewModel = WorktreeBatchCleanupSheetViewModel(plan: plan, baseRef: "main")

        #expect(viewModel.primarySummary == "1 merged worktree ready to clean up")
        #expect(viewModel.canCleanUp)
        #expect(viewModel.blockedDetails == ["dirty: uncommitted changes"])
        #expect(viewModel.skippedDetails == ["open: not merged into main"])
    }

    private func makeEntry(id: String, branch: String) -> WorktreeManifest.WorktreeEntry {
        WorktreeManifest.WorktreeEntry(
            id: id,
            branch: branch,
            path: URL(fileURLWithPath: "/tmp/\(id)", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 1_773_014_400),
            agent: nil,
            tabID: nil
        )
    }
}
