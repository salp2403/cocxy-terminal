// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeCLIIntegrationHelperTests.swift - Covers the CLI-side
// adaptation layer before it calls WorktreeService.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Worktree CLI integration helpers")
struct WorktreeCLIIntegrationHelperTests {

    @Test("add params override branch template and base ref only for that request")
    func addParamsOverrideBranchAndBaseRef() {
        let base = WorktreeConfig(
            enabled: true,
            basePath: "/tmp/cocxy-worktrees",
            branchTemplate: "cocxy/{agent}/{id}",
            baseRef: "HEAD",
            onClose: .keep,
            openInNewTab: true,
            idLength: 6,
            inheritProjectConfig: true,
            showBadge: true
        )

        let effective = AppDelegate.worktreeConfig(
            base,
            applyingAddParams: [
                "branch": "feature/{id}",
                "base-ref": "develop",
            ]
        )

        #expect(effective.branchTemplate == "feature/{id}")
        #expect(effective.baseRef == "develop")
        #expect(effective.basePath == base.basePath)
        #expect(effective.openInNewTab == base.openInNewTab)
        #expect(effective.onClose == base.onClose)
    }

    @Test("empty add params preserve the saved worktree config")
    func emptyAddParamsPreserveConfig() {
        let base = WorktreeConfig.defaults
        let effective = AppDelegate.worktreeConfig(base, applyingAddParams: [
            "branch": "   ",
            "base-ref": "",
        ])

        #expect(effective == base)
    }

    @Test("origin resolver walks from repo subdirectory to repository root")
    func originResolverFindsRepositoryRootFromSubdirectory() throws {
        let repo = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "cocxy-worktree-cli-root-\(UUID().uuidString)",
                isDirectory: true
            )
        let subdir = repo.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(
            at: subdir,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: repo) }

        try runGit(in: repo, arguments: ["init"])
        try runGit(in: repo, arguments: ["config", "user.email", "dev@cocxy.dev"])
        try runGit(in: repo, arguments: ["config", "user.name", "Cocxy Tests"])

        let resolved = AppDelegate.resolveOriginRepoRoot(from: subdir)

        #expect(resolved.path == repo.standardizedFileURL.path)
    }

    private func runGit(in directory: URL, arguments: [String]) throws {
        let result = try CodeReviewGit.run(
            workingDirectory: directory,
            arguments: arguments
        )
        #expect(result.terminationStatus == 0)
    }
}
