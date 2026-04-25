// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MergePullRequestActionSheetSwiftTestingTests.swift - Pure-function
// tests for the v0.1.86 NSAlert wrapper. The actual UI presentation
// is exercised only by smoke testing — this suite covers the
// decision mapping and the UserDefaults round-trip the wrapper uses.

import AppKit
import Testing
import Foundation
@testable import CocxyTerminal

@Suite("MergePullRequestActionSheet")
struct MergePullRequestActionSheetSwiftTestingTests {

    // MARK: - decode(response:deleteBranch:)

    @Test("first button maps to .squash")
    func firstButtonMapsToSquash() {
        let decision = MergePullRequestActionSheet.decode(
            response: .alertFirstButtonReturn,
            deleteBranch: true
        )
        #expect(decision == MergePullRequestActionSheet.Decision(method: .squash, deleteBranch: true))
    }

    @Test("second button maps to .merge")
    func secondButtonMapsToMerge() {
        let decision = MergePullRequestActionSheet.decode(
            response: .alertSecondButtonReturn,
            deleteBranch: false
        )
        #expect(decision == MergePullRequestActionSheet.Decision(method: .merge, deleteBranch: false))
    }

    @Test("third button maps to .rebase")
    func thirdButtonMapsToRebase() {
        let decision = MergePullRequestActionSheet.decode(
            response: .alertThirdButtonReturn,
            deleteBranch: true
        )
        #expect(decision == MergePullRequestActionSheet.Decision(method: .rebase, deleteBranch: true))
    }

    @Test("fourth button (Cancel) maps to nil")
    func fourthButtonMapsToNil() {
        // AppKit only declares the first three button responses by
        // name. Buttons beyond the third use the next sequential
        // raw value (1003 for the fourth, which is our Cancel).
        let cancelResponse = NSApplication.ModalResponse(rawValue: 1003)
        let decision = MergePullRequestActionSheet.decode(
            response: cancelResponse,
            deleteBranch: true
        )
        #expect(decision == nil)
    }

    @Test("unrecognised modal responses (Esc, .cancel) map to nil")
    func unrecognisedModalResponsesMapToNil() {
        let cancelDecision = MergePullRequestActionSheet.decode(
            response: .cancel,
            deleteBranch: true
        )
        let stopDecision = MergePullRequestActionSheet.decode(
            response: .stop,
            deleteBranch: false
        )
        #expect(cancelDecision == nil)
        #expect(stopDecision == nil)
    }

    @Test("decode preserves the deleteBranch flag verbatim")
    func decodePreservesDeleteBranchFlag() {
        let withTrue = MergePullRequestActionSheet.decode(
            response: .alertFirstButtonReturn,
            deleteBranch: true
        )
        let withFalse = MergePullRequestActionSheet.decode(
            response: .alertFirstButtonReturn,
            deleteBranch: false
        )
        #expect(withTrue?.deleteBranch == true)
        #expect(withFalse?.deleteBranch == false)
    }

    // MARK: - storedDeleteBranchPreference

    @Test("storedDeleteBranchPreference defaults to true when never written")
    func storedPreferenceDefaultsToTrueWhenNeverWritten() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defer {
            defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().description)
        }

        // Sanity check: the key is unset before we test.
        #expect(defaults.object(forKey: MergePullRequestActionSheet.deleteBranchPreferenceKey) == nil)

        let value = MergePullRequestActionSheet.storedDeleteBranchPreference(in: defaults)
        #expect(value == true, "Industry default: delete branch after merge.")
    }

    @Test("storedDeleteBranchPreference returns explicit false")
    func storedPreferenceReturnsExplicitFalse() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: MergePullRequestActionSheet.deleteBranchPreferenceKey)
        let value = MergePullRequestActionSheet.storedDeleteBranchPreference(in: defaults)
        #expect(value == false)
    }

    @Test("storedDeleteBranchPreference returns explicit true")
    func storedPreferenceReturnsExplicitTrue() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: MergePullRequestActionSheet.deleteBranchPreferenceKey)
        let value = MergePullRequestActionSheet.storedDeleteBranchPreference(in: defaults)
        #expect(value == true)
    }

    @Test("storeDeleteBranchPreference persists the chosen value")
    func storePreferencePersistsChosenValue() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        MergePullRequestActionSheet.storeDeleteBranchPreference(false, in: defaults)
        #expect(defaults.bool(forKey: MergePullRequestActionSheet.deleteBranchPreferenceKey) == false)

        MergePullRequestActionSheet.storeDeleteBranchPreference(true, in: defaults)
        #expect(defaults.bool(forKey: MergePullRequestActionSheet.deleteBranchPreferenceKey) == true)
    }

    @Test("preference round-trips through store/load")
    func preferenceRoundTripsThroughStoreLoad() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        for value in [true, false, true] {
            MergePullRequestActionSheet.storeDeleteBranchPreference(value, in: defaults)
            let read = MergePullRequestActionSheet.storedDeleteBranchPreference(in: defaults)
            #expect(read == value, "Round-trip failed for value=\(value)")
        }
    }

    // MARK: - Decision shape

    @Test("Decision is Equatable across method and deleteBranch fields")
    func decisionIsEquatableAcrossFields() {
        let a = MergePullRequestActionSheet.Decision(method: .squash, deleteBranch: true)
        let b = MergePullRequestActionSheet.Decision(method: .squash, deleteBranch: true)
        let c = MergePullRequestActionSheet.Decision(method: .squash, deleteBranch: false)
        let d = MergePullRequestActionSheet.Decision(method: .merge, deleteBranch: true)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
    }
}
