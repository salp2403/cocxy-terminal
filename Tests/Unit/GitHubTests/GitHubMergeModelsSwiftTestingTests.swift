// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubMergeModelsSwiftTestingTests.swift - Tolerant decoder + business
// logic tests for the merge model surface introduced in v0.1.86.

import Testing
import Foundation
@testable import CocxyTerminal

// MARK: - GitHubMergeMethod

@Suite("GitHubMergeMethod")
struct GitHubMergeMethodSwiftTestingTests {

    @Test("ghFlag returns the correct CLI flag for each method")
    func ghFlagMapsToTheCorrectFlagPerMethod() {
        #expect(GitHubMergeMethod.squash.ghFlag == "--squash")
        #expect(GitHubMergeMethod.merge.ghFlag == "--merge")
        #expect(GitHubMergeMethod.rebase.ghFlag == "--rebase")
    }

    @Test("displayName matches the strings used by GitHub web")
    func displayNameMatchesGitHubWebCopy() {
        #expect(GitHubMergeMethod.squash.displayName == "Squash & Merge")
        #expect(GitHubMergeMethod.merge.displayName == "Merge Commit")
        #expect(GitHubMergeMethod.rebase.displayName == "Rebase & Merge")
    }

    @Test("allCases exposes exactly squash, merge, rebase in declaration order")
    func allCasesExposesThreeKnownStrategies() {
        #expect(GitHubMergeMethod.allCases == [.squash, .merge, .rebase])
    }

    @Test("rawValue round-trips through Codable")
    func rawValueRoundTripsThroughCodable() throws {
        let original = GitHubMergeMethod.squash
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubMergeMethod.self, from: encoded)
        #expect(decoded == original)
    }
}

// MARK: - GitHubMergeableStatus

@Suite("GitHubMergeableStatus")
struct GitHubMergeableStatusSwiftTestingTests {

    @Test("decodes known uppercase values")
    func decodesKnownUppercaseValues() throws {
        let mergeable = try decodeStatus(json: "\"MERGEABLE\"")
        let conflicting = try decodeStatus(json: "\"CONFLICTING\"")
        let unknown = try decodeStatus(json: "\"UNKNOWN\"")
        #expect(mergeable == .mergeable)
        #expect(conflicting == .conflicting)
        #expect(unknown == .unknown)
    }

    @Test("decodes mixed-case input by upper-casing")
    func decodesMixedCaseInputByUppercasing() throws {
        let value = try decodeStatus(json: "\"Mergeable\"")
        #expect(value == .mergeable)
    }

    @Test("falls back to unknown when value is null")
    func fallsBackToUnknownWhenValueIsNull() throws {
        let value = try decodeStatus(json: "null")
        #expect(value == .unknown)
    }

    @Test("falls back to unknown for unrecognised values")
    func fallsBackToUnknownForUnrecognisedValues() throws {
        let value = try decodeStatus(json: "\"FOOBAR\"")
        #expect(value == .unknown)
    }

    private func decodeStatus(json: String) throws -> GitHubMergeableStatus {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(GitHubMergeableStatus.self, from: data)
    }
}

// MARK: - GitHubMergeStateStatus

@Suite("GitHubMergeStateStatus")
struct GitHubMergeStateStatusSwiftTestingTests {

    @Test("decodes every documented state from gh pr view")
    func decodesEveryDocumentedState() throws {
        let cases: [(String, GitHubMergeStateStatus)] = [
            ("CLEAN", .clean),
            ("BLOCKED", .blocked),
            ("BEHIND", .behind),
            ("DIRTY", .dirty),
            ("UNSTABLE", .unstable),
            ("HAS_HOOKS", .hasHooks),
            ("UNKNOWN", .unknown),
        ]
        for (raw, expected) in cases {
            let json = "\"\(raw)\"".data(using: .utf8) ?? Data()
            let decoded = try JSONDecoder().decode(GitHubMergeStateStatus.self, from: json)
            #expect(decoded == expected, "Failed to decode \(raw)")
        }
    }

    @Test("falls back to unknown for null and unrecognised values")
    func fallsBackToUnknownForNullAndUnrecognisedValues() throws {
        let nullValue = try JSONDecoder().decode(
            GitHubMergeStateStatus.self,
            from: "null".data(using: .utf8) ?? Data()
        )
        let unknownValue = try JSONDecoder().decode(
            GitHubMergeStateStatus.self,
            from: "\"FOOBAR\"".data(using: .utf8) ?? Data()
        )
        #expect(nullValue == .unknown)
        #expect(unknownValue == .unknown)
    }

    @Test("allowsMerge is true only for CLEAN and HAS_HOOKS")
    func allowsMergeIsTrueOnlyForCleanAndHasHooks() {
        #expect(GitHubMergeStateStatus.clean.allowsMerge)
        #expect(GitHubMergeStateStatus.hasHooks.allowsMerge)
        #expect(!GitHubMergeStateStatus.blocked.allowsMerge)
        #expect(!GitHubMergeStateStatus.behind.allowsMerge)
        #expect(!GitHubMergeStateStatus.dirty.allowsMerge)
        #expect(!GitHubMergeStateStatus.unstable.allowsMerge)
        #expect(!GitHubMergeStateStatus.unknown.allowsMerge)
    }
}

// MARK: - GitHubStatusCheckRollupEntry

@Suite("GitHubStatusCheckRollupEntry")
struct GitHubStatusCheckRollupEntrySwiftTestingTests {

    @Test("decodes new gh shape with state field")
    func decodesNewGhShapeWithStateField() throws {
        let json = """
        {"state": "SUCCESS", "conclusion": "SUCCESS"}
        """
        let entry = try decode(json)
        #expect(entry.state == "SUCCESS")
        #expect(entry.conclusion == "SUCCESS")
        #expect(entry.isPassing)
        #expect(!entry.isPending)
    }

    @Test("decodes older gh shape that uses status as in-progress label")
    func decodesOlderGhShapeWithStatusKey() throws {
        let json = """
        {"status": "IN_PROGRESS", "conclusion": null}
        """
        let entry = try decode(json)
        #expect(entry.state == "IN_PROGRESS")
        #expect(entry.conclusion == nil)
        #expect(!entry.isPassing)
        #expect(entry.isPending)
    }

    @Test("isPassing accepts NEUTRAL and SKIPPED as passing")
    func isPassingAcceptsNeutralAndSkippedAsPassing() throws {
        let neutral = try decode(#"{"state": "NEUTRAL", "conclusion": "NEUTRAL"}"#)
        let skipped = try decode(#"{"state": "SKIPPED", "conclusion": "SKIPPED"}"#)
        #expect(neutral.isPassing)
        #expect(skipped.isPassing)
    }

    @Test("isPassing returns false for FAILURE and CANCELLED")
    func isPassingReturnsFalseForFailureAndCancelled() throws {
        let failure = try decode(#"{"state": "FAILURE", "conclusion": "FAILURE"}"#)
        let cancelled = try decode(#"{"state": "CANCELLED", "conclusion": "CANCELLED"}"#)
        #expect(!failure.isPassing)
        #expect(!cancelled.isPassing)
    }

    @Test("isPending recognises QUEUED and EXPECTED as pending")
    func isPendingRecognisesQueuedAndExpectedAsPending() throws {
        let queued = try decode(#"{"state": "QUEUED", "conclusion": null}"#)
        let expected = try decode(#"{"state": "EXPECTED", "conclusion": null}"#)
        #expect(queued.isPending)
        #expect(expected.isPending)
    }

    @Test("encoder round-trips state and conclusion without crashing on absent status")
    func encoderRoundTripsStateAndConclusion() throws {
        let original = GitHubStatusCheckRollupEntry(state: "SUCCESS", conclusion: "SUCCESS")
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubStatusCheckRollupEntry.self, from: encoded)
        #expect(decoded == original)
    }

    private func decode(_ json: String) throws -> GitHubStatusCheckRollupEntry {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(GitHubStatusCheckRollupEntry.self, from: data)
    }
}

// MARK: - GitHubMergeability — pure logic

@Suite("GitHubMergeability logic")
struct GitHubMergeabilityLogicSwiftTestingTests {

    @Test("canMerge true when clean, mergeable, approved, checks passed")
    func canMergeTrueWhenCleanMergeableApprovedChecksPassed() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: true
        )
        #expect(mergeability.canMerge)
        #expect(mergeability.reasonIfBlocked == nil)
        #expect(mergeability.chipKind == .ready)
    }

    @Test("canMerge true when no review configured (decision = none)")
    func canMergeTrueWhenNoReviewConfigured() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .none,
            checksPassed: true
        )
        #expect(mergeability.canMerge)
    }

    @Test("canMerge false when conflict status is conflicting")
    func canMergeFalseWhenConflictStatusIsConflicting() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .conflicting,
            stateStatus: .dirty,
            reviewDecision: .approved,
            checksPassed: true
        )
        #expect(!mergeability.canMerge)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("merge conflicts"))
        #expect(mergeability.chipKind == .conflicting)
    }

    @Test("canMerge false when state is behind base")
    func canMergeFalseWhenStateIsBehind() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .behind,
            reviewDecision: .approved,
            checksPassed: true
        )
        #expect(!mergeability.canMerge)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("behind"))
    }

    @Test("canMerge false when state is blocked")
    func canMergeFalseWhenStateIsBlocked() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .blocked,
            reviewDecision: .approved,
            checksPassed: true
        )
        #expect(!mergeability.canMerge)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("branch protection"))
    }

    @Test("canMerge false when checks have not passed")
    func canMergeFalseWhenChecksHaveNotPassed() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: false
        )
        #expect(!mergeability.canMerge)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("failing checks"))
    }

    @Test("canMerge false when reviewer requested changes")
    func canMergeFalseWhenReviewerRequestedChanges() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .changesRequested,
            checksPassed: true
        )
        #expect(!mergeability.canMerge)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("changes requested"))
    }

    @Test("canMerge false when review still required")
    func canMergeFalseWhenReviewStillRequired() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .reviewRequired,
            checksPassed: true
        )
        #expect(!mergeability.canMerge)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("review required"))
    }

    @Test("canMerge false when PR is already merged")
    func canMergeFalseWhenPullRequestIsAlreadyMerged() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: true,
            isAlreadyMerged: true
        )
        #expect(!mergeability.canMerge)
        #expect(mergeability.chipKind == .merged)
        #expect(mergeability.reasonIfBlocked == "Pull request is already merged.")
    }

    @Test("canMerge false when PR is closed")
    func canMergeFalseWhenPullRequestIsClosed() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: true,
            isClosed: true
        )
        #expect(!mergeability.canMerge)
        #expect(mergeability.chipKind == .closed)
        #expect(mergeability.reasonIfBlocked == "Pull request is closed.")
    }

    @Test("chipKind is pending when checks are still running with unstable state")
    func chipKindIsPendingWhenChecksAreStillRunning() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .unstable,
            reviewDecision: .approved,
            checksPassed: false,
            checksPending: true
        )
        #expect(!mergeability.canMerge)
        #expect(mergeability.chipKind == .pending)
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("checks in progress"))
    }

    @Test("reasonIfBlocked composes multiple blockers with comma separator")
    func reasonIfBlockedComposesMultipleBlockers() {
        let mergeability = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .conflicting,
            stateStatus: .behind,
            reviewDecision: .changesRequested,
            checksPassed: false
        )
        let reason = mergeability.reasonIfBlocked ?? ""
        #expect(reason.contains("merge conflicts"))
        #expect(reason.contains("behind base"))
        #expect(reason.contains("changes requested"))
        #expect(reason.contains(", "))
    }
}

// MARK: - GitHubMergeability — Codable

@Suite("GitHubMergeability decoder")
struct GitHubMergeabilityDecoderSwiftTestingTests {

    @Test("decodes a clean PR JSON from gh pr view")
    func decodesACleanPullRequestJsonFromGhPrView() throws {
        let json = """
        {
            "number": 42,
            "state": "OPEN",
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": "APPROVED",
            "statusCheckRollup": [
                {"state": "SUCCESS", "conclusion": "SUCCESS"},
                {"state": "SUCCESS", "conclusion": "SUCCESS"}
            ]
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.pullRequestNumber == 42)
        #expect(mergeability.conflictStatus == .mergeable)
        #expect(mergeability.stateStatus == .clean)
        #expect(mergeability.reviewDecision == .approved)
        #expect(mergeability.checksPassed)
        #expect(!mergeability.checksPending)
        #expect(!mergeability.isAlreadyMerged)
        #expect(!mergeability.isClosed)
        #expect(mergeability.canMerge)
    }

    @Test("decodes a conflicting PR with dirty merge state")
    func decodesAConflictingPullRequest() throws {
        let json = """
        {
            "number": 7,
            "state": "OPEN",
            "mergeable": "CONFLICTING",
            "mergeStateStatus": "DIRTY",
            "reviewDecision": "APPROVED",
            "statusCheckRollup": []
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.conflictStatus == .conflicting)
        #expect(mergeability.stateStatus == .dirty)
        #expect(!mergeability.canMerge)
    }

    @Test("decodes a PR with pending checks as unstable")
    func decodesAPullRequestWithPendingChecks() throws {
        let json = """
        {
            "number": 7,
            "state": "OPEN",
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "UNSTABLE",
            "reviewDecision": "APPROVED",
            "statusCheckRollup": [
                {"state": "SUCCESS", "conclusion": "SUCCESS"},
                {"status": "IN_PROGRESS", "conclusion": null}
            ]
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.checksPending)
        #expect(mergeability.checksPassed,
                "Pending entries should not be counted as failures.")
        #expect(!mergeability.canMerge,
                "Unstable state alone blocks the merge button.")
    }

    @Test("decodes a PR with failing checks as not passed")
    func decodesAPullRequestWithFailingChecks() throws {
        let json = """
        {
            "number": 7,
            "state": "OPEN",
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "BLOCKED",
            "reviewDecision": "APPROVED",
            "statusCheckRollup": [
                {"state": "FAILURE", "conclusion": "FAILURE"}
            ]
        }
        """
        let mergeability = try decode(json)
        #expect(!mergeability.checksPassed)
        #expect(!mergeability.canMerge)
    }

    @Test("decodes a merged PR setting isAlreadyMerged")
    func decodesAMergedPullRequestSettingIsAlreadyMerged() throws {
        let json = """
        {
            "number": 1,
            "state": "MERGED",
            "mergeable": "UNKNOWN",
            "mergeStateStatus": "UNKNOWN",
            "reviewDecision": null,
            "statusCheckRollup": []
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.isAlreadyMerged)
        #expect(!mergeability.isClosed)
        #expect(!mergeability.canMerge)
        #expect(mergeability.chipKind == .merged)
    }

    @Test("decodes a closed PR setting isClosed")
    func decodesAClosedPullRequestSettingIsClosed() throws {
        let json = """
        {
            "number": 1,
            "state": "CLOSED",
            "mergeable": "UNKNOWN",
            "mergeStateStatus": "UNKNOWN",
            "reviewDecision": null,
            "statusCheckRollup": []
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.isClosed)
        #expect(!mergeability.isAlreadyMerged)
        #expect(!mergeability.canMerge)
        #expect(mergeability.chipKind == .closed)
    }

    @Test("missing optional fields collapse to safe defaults")
    func missingOptionalFieldsCollapseToSafeDefaults() throws {
        // Older gh releases may omit mergeStateStatus and reviewDecision.
        let json = """
        {
            "number": 1,
            "mergeable": null
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.conflictStatus == .unknown)
        #expect(mergeability.stateStatus == .unknown)
        #expect(mergeability.reviewDecision == .none)
        // Empty rollup means "no checks configured" which is OK.
        #expect(mergeability.checksPassed)
    }

    @Test("missing statusCheckRollup defaults to checks passed")
    func missingStatusCheckRollupDefaultsToChecksPassed() throws {
        let json = """
        {
            "number": 1,
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewDecision": "APPROVED"
        }
        """
        let mergeability = try decode(json)
        #expect(mergeability.checksPassed)
        #expect(!mergeability.checksPending)
        #expect(mergeability.canMerge)
    }

    @Test("encode preserves derived booleans for socket round-trip")
    func encodePreservesDerivedBooleansForSocketRoundTrip() throws {
        let original = GitHubMergeability(
            pullRequestNumber: 42,
            conflictStatus: .mergeable,
            stateStatus: .clean,
            reviewDecision: .approved,
            checksPassed: true,
            checksPending: false,
            isAlreadyMerged: false,
            isClosed: false
        )
        let encoded = try JSONEncoder().encode(original)
        let json = try #require(String(data: encoded, encoding: .utf8))
        #expect(json.contains("\"checksPassed\""))
        #expect(json.contains("\"isAlreadyMerged\""))
    }

    private func decode(_ json: String) throws -> GitHubMergeability {
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(GitHubMergeability.self, from: data)
    }
}

// MARK: - GitHubMergeRequest

@Suite("GitHubMergeRequest")
struct GitHubMergeRequestSwiftTestingTests {

    @Test("default deleteBranch is true (industry default)")
    func defaultDeleteBranchIsTrue() {
        let request = GitHubMergeRequest(
            pullRequestNumber: 42,
            method: .squash
        )
        #expect(request.deleteBranch)
        #expect(request.subject == nil)
        #expect(request.body == nil)
    }

    @Test("preserves explicit deleteBranch override")
    func preservesExplicitDeleteBranchOverride() {
        let request = GitHubMergeRequest(
            pullRequestNumber: 42,
            method: .merge,
            deleteBranch: false
        )
        #expect(!request.deleteBranch)
    }

    @Test("round-trips through JSON without losing fields")
    func roundTripsThroughJsonWithoutLosingFields() throws {
        let original = GitHubMergeRequest(
            pullRequestNumber: 42,
            method: .rebase,
            deleteBranch: false,
            subject: "Custom subject",
            body: "Custom body"
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubMergeRequest.self, from: encoded)
        #expect(decoded == original)
    }
}
