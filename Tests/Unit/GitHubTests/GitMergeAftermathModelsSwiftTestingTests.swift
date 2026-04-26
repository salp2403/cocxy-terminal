// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitMergeAftermathModelsSwiftTestingTests.swift - Coverage for the
// outcome/error value types added in v0.1.87 for the post-merge
// auto-pull feature.

import Testing
import Foundation
@testable import CocxyTerminal

@Suite("GitMergeAftermathModels.outcome")
struct GitMergeAftermathOutcomeSwiftTestingTests {

    // MARK: - Equatable / Sendable smoke

    @Test("synced outcomes with same payload are equal")
    func syncedEquatable() {
        let a = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 3)
        let b = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 3)
        let c = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 4)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("dirty tree outcomes compare structurally")
    func dirtyEquatable() {
        let a = GitMergeAftermathOutcome.skippedDirtyTree(branch: "main", modifiedCount: 2, untrackedCount: 1)
        let b = GitMergeAftermathOutcome.skippedDirtyTree(branch: "main", modifiedCount: 2, untrackedCount: 1)
        let c = GitMergeAftermathOutcome.skippedDirtyTree(branch: "main", modifiedCount: 3, untrackedCount: 1)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("non fast-forward outcomes compare structurally")
    func nonFFEquatable() {
        let a = GitMergeAftermathOutcome.skippedNonFastForward(branch: "main", ahead: 1, behind: 2)
        let b = GitMergeAftermathOutcome.skippedNonFastForward(branch: "main", ahead: 1, behind: 2)
        #expect(a == b)
    }

    // MARK: - displayMessage shape

    @Test("synced (clean ff) message reports pull count")
    func syncedMessageBehind() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 3)
        let message = outcome.displayMessage
        #expect(message.contains("`main`"))
        #expect(message.contains("3 commits pulled"))
    }

    @Test("synced (single commit) message uses singular form")
    func syncedMessageSingular() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 1)
        let message = outcome.displayMessage
        #expect(message.contains("1 commit pulled"))
        #expect(!message.contains("commits pulled"))
    }

    @Test("synced (no delta) message says already in sync")
    func syncedMessageNoDelta() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 0, behind: 0)
        let message = outcome.displayMessage.lowercased()
        #expect(message.contains("already") || message.contains("in sync"))
    }

    @Test("synced (ahead only) message says no pull needed")
    func syncedMessageAheadOnly() {
        let outcome = GitMergeAftermathOutcome.synced(branch: "main", ahead: 2, behind: 0)
        let message = outcome.displayMessage.lowercased()
        #expect(message.contains("no pull needed") || message.contains("ahead"))
    }

    @Test("fetchedOnly mentions both branches and absence of pull")
    func fetchedOnlyMessage() {
        let outcome = GitMergeAftermathOutcome.fetchedOnly(currentBranch: "feat/x", baseBranch: "main")
        let message = outcome.displayMessage
        #expect(message.contains("`main`"))
        #expect(message.contains("`feat/x`"))
        let lower = message.lowercased()
        #expect(lower.contains("fetched"))
    }

    @Test("dirtyTree message includes counts and guidance")
    func dirtyMessage() {
        let outcome = GitMergeAftermathOutcome.skippedDirtyTree(branch: "main", modifiedCount: 2, untrackedCount: 3)
        let message = outcome.displayMessage
        #expect(message.contains("2 modified"))
        #expect(message.contains("3 untracked"))
        let lower = message.lowercased()
        #expect(lower.contains("commit") || lower.contains("stash"))
    }

    @Test("dirtyTree without branch falls back to current branch wording")
    func dirtyMessageNoBranch() {
        let outcome = GitMergeAftermathOutcome.skippedDirtyTree(branch: nil, modifiedCount: 1, untrackedCount: 0)
        let message = outcome.displayMessage.lowercased()
        #expect(message.contains("current branch"))
    }

    @Test("detached HEAD message is explicit")
    func detachedMessage() {
        let outcome = GitMergeAftermathOutcome.skippedDetachedHead
        let message = outcome.displayMessage.lowercased()
        #expect(message.contains("detached"))
    }

    @Test("not in repo message mentions git repository")
    func notInRepoMessage() {
        let outcome = GitMergeAftermathOutcome.skippedNotInRepo
        let message = outcome.displayMessage.lowercased()
        #expect(message.contains("not a git repository") || message.contains("git repository"))
    }

    @Test("non-fast-forward message lists ahead/behind and points at manual sync")
    func nonFFMessage() {
        let outcome = GitMergeAftermathOutcome.skippedNonFastForward(branch: "main", ahead: 2, behind: 4)
        let message = outcome.displayMessage
        #expect(message.contains("2 ahead"))
        #expect(message.contains("4 behind"))
        let lower = message.lowercased()
        #expect(lower.contains("manual"))
    }

    @Test("workspace vanished message mentions missing directory")
    func vanishedMessage() {
        let outcome = GitMergeAftermathOutcome.workspaceVanished
        let lower = outcome.displayMessage.lowercased()
        #expect(lower.contains("no longer") || lower.contains("does not exist"))
    }
}

@Suite("GitMergeAftermathModels.error")
struct GitMergeAftermathErrorSwiftTestingTests {

    @Test("gitUnavailable error description mentions binary")
    func gitUnavailableMessage() {
        let error = GitMergeAftermathError.gitUnavailable
        let lower = (error.errorDescription ?? "").lowercased()
        #expect(lower.contains("git"))
        #expect(lower.contains("path") || lower.contains("binary"))
    }

    @Test("fetchFailed error includes stderr content when present")
    func fetchFailedMessage() {
        let error = GitMergeAftermathError.fetchFailed(
            stderr: "fatal: unable to access 'https://github.com/'",
            exitCode: 128
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("fatal"))
        let lower = description.lowercased()
        #expect(lower.contains("fetch"))
    }

    @Test("fetchFailed error falls back when stderr empty")
    func fetchFailedEmptyStderr() {
        let error = GitMergeAftermathError.fetchFailed(stderr: "", exitCode: 1)
        let description = error.errorDescription ?? ""
        #expect(description.contains("1"))
        let lower = description.lowercased()
        #expect(lower.contains("fetch"))
    }

    @Test("pullFailed error includes stderr")
    func pullFailedMessage() {
        let error = GitMergeAftermathError.pullFailed(
            stderr: "error: Your local changes would be overwritten",
            exitCode: 1
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("Your local changes"))
    }

    @Test("timedOut error names the operation and elapsed seconds")
    func timedOutMessage() {
        let error = GitMergeAftermathError.timedOut(operation: "fetch", after: 30)
        let description = error.errorDescription ?? ""
        #expect(description.contains("fetch"))
        #expect(description.contains("30"))
    }

    @Test("invalidPorcelainOutput preserves a preview of the raw string")
    func invalidPorcelainMessage() {
        let raw = "?? path/to/sneakyfile-with-very-long-name-and-special-chars-1234567890"
        let error = GitMergeAftermathError.invalidPorcelainOutput(raw: raw)
        let description = error.errorDescription ?? ""
        #expect(description.contains("path/to/sneakyfile"))
    }

    @Test("equality compares typed associated values")
    func errorEquatable() {
        let a = GitMergeAftermathError.fetchFailed(stderr: "x", exitCode: 1)
        let b = GitMergeAftermathError.fetchFailed(stderr: "x", exitCode: 1)
        let c = GitMergeAftermathError.fetchFailed(stderr: "x", exitCode: 2)
        #expect(a == b)
        #expect(a != c)
    }
}
