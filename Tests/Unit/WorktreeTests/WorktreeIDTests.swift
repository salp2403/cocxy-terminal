// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeIDTests.swift - Coverage for WorktreeID.generate / isValid.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("WorktreeID")
struct WorktreeIDTests {

    // MARK: - generate

    @Test("generate returns exactly the requested length when in range")
    func generateRespectsRequestedLength() {
        for length in WorktreeID.minLength...WorktreeID.maxLength {
            let id = WorktreeID.generate(length: length)
            #expect(id.count == length)
        }
    }

    @Test("generate clamps length below minimum up to minLength")
    func generateClampsBelowMinimum() {
        let tooShort = WorktreeID.generate(length: 0)
        #expect(tooShort.count == WorktreeID.minLength)
    }

    @Test("generate clamps length above maximum down to maxLength")
    func generateClampsAboveMaximum() {
        let tooLong = WorktreeID.generate(length: 9_999)
        #expect(tooLong.count == WorktreeID.maxLength)
    }

    @Test("generate produces only alphanumeric lowercase characters")
    func generateProducesOnlyAlphanumericLowercase() {
        let allowed = Set(WorktreeID.allowedCharacters)
        for _ in 0..<200 {
            let id = WorktreeID.generate(length: 10)
            for character in id {
                #expect(allowed.contains(character))
            }
        }
    }

    @Test("two consecutive generates almost never collide at length 6")
    func generateProducesDistinctValuesInShortBurst() {
        // The birthday-paradox collision probability for 100 IDs at
        // length 6 is ~1.4 × 10⁻⁶, so the expected number of collisions
        // in a 100-sample burst is essentially zero. The test caps the
        // tolerance at 0 collisions because anything else would mean
        // `randomElement()` is not actually random. Failing this test
        // flags a serious regression.
        let samples = (0..<100).map { _ in WorktreeID.generate(length: 6) }
        let unique = Set(samples)
        #expect(unique.count == samples.count)
    }

    // MARK: - isValid

    @Test("isValid accepts a freshly generated id at every supported length")
    func isValidAcceptsGeneratedIDs() {
        for length in WorktreeID.minLength...WorktreeID.maxLength {
            let id = WorktreeID.generate(length: length)
            #expect(WorktreeID.isValid(id))
        }
    }

    @Test("isValid rejects the empty string")
    func isValidRejectsEmpty() {
        #expect(!WorktreeID.isValid(""))
    }

    @Test("isValid rejects ids shorter than minLength")
    func isValidRejectsTooShort() {
        let tooShort = String(repeating: "a", count: WorktreeID.minLength - 1)
        #expect(!WorktreeID.isValid(tooShort))
    }

    @Test("isValid rejects ids longer than maxLength")
    func isValidRejectsTooLong() {
        let tooLong = String(repeating: "a", count: WorktreeID.maxLength + 1)
        #expect(!WorktreeID.isValid(tooLong))
    }

    @Test("isValid rejects uppercase letters")
    func isValidRejectsUppercase() {
        #expect(!WorktreeID.isValid("ABCDEF"))
        #expect(!WorktreeID.isValid("abcDef"))
    }

    @Test("isValid rejects special characters that would break paths or refs")
    func isValidRejectsSpecialCharacters() {
        #expect(!WorktreeID.isValid("abc/de"))
        #expect(!WorktreeID.isValid("abc-de"))
        #expect(!WorktreeID.isValid("abc.de"))
        #expect(!WorktreeID.isValid("abc de"))
        #expect(!WorktreeID.isValid("abc_de"))
    }
}
