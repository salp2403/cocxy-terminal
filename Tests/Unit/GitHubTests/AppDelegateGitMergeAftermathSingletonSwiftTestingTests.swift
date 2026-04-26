// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegateGitMergeAftermathSingletonSwiftTestingTests.swift
// Pins the AppDelegate-level singleton wired in v0.1.87 to drive the
// post-merge auto-pull from both the Code Review panel and the GitHub
// pane. The test deliberately stays at the singleton level (no
// MainWindowController setup) because the per-surface handler wiring
// is exercised end-to-end by the CodeReview and GitHubPane suites
// added alongside this one — what we need to guarantee here is that
// the AppDelegate exposes the actor and that it is genuinely usable.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AppDelegate GitMergeAftermath singleton (v0.1.87)")
struct AppDelegateGitMergeAftermathSingletonSwiftTestingTests {

    @Test("AppDelegate exposes a process-wide GitMergeAftermathService singleton")
    func singletonExists() {
        // Type assertion at compile time + identity check at run time.
        let service: GitMergeAftermathService = AppDelegate.sharedGitMergeAftermathService
        let again: GitMergeAftermathService = AppDelegate.sharedGitMergeAftermathService
        #expect(service === again)
    }

    @Test("singleton honours the public sync contract on a non-git directory")
    func singletonHonoursContractOnNonGitDirectory() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aftermath-singleton-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let outcome = try await AppDelegate.sharedGitMergeAftermathService.sync(
            at: scratch,
            baseBranch: "main",
            timeoutSeconds: 15
        )
        #expect(outcome == .skippedNotInRepo)
    }
}
