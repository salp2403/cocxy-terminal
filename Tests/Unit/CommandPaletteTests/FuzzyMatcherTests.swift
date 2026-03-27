// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FuzzyMatcherTests.swift - Tests for the fuzzy matching algorithm used by Command Palette.
//
// Test plan (10 tests):
// 1.  Exact match returns score 100.
// 2.  Prefix match returns high score (>= 80).
// 3.  Fuzzy non-contiguous match returns lower score than prefix.
// 4.  No match returns nil.
// 5.  Case insensitive matching works.
// 6.  Empty query matches everything with score 0.
// 7.  Single character query matches.
// 8.  Word boundary bonus: "sv" matches "Split Vertical" with high score.
// 9.  Consecutive matches score higher than non-consecutive.
// 10. Empty target returns nil for non-empty query.

import XCTest
@testable import CocxyTerminal

final class FuzzyMatcherTests: XCTestCase {

    // MARK: - Test 1: Exact Match

    func testExactMatchReturnsScore100() {
        let result = FuzzyMatcher.fuzzyMatch(query: "Split Vertical", target: "Split Vertical")

        XCTAssertNotNil(result, "Exact match must return a result")
        XCTAssertEqual(result!.score, 100,
                        "Exact match must return score 100")
    }

    // MARK: - Test 2: Prefix Match

    func testPrefixMatchReturnsHighScore() {
        let result = FuzzyMatcher.fuzzyMatch(query: "Split", target: "Split Vertical")

        XCTAssertNotNil(result, "Prefix match must return a result")
        XCTAssertGreaterThanOrEqual(result!.score, 80,
                                     "Prefix match must return score >= 80")
    }

    // MARK: - Test 3: Fuzzy Non-Contiguous Match

    func testFuzzyNonContiguousMatchReturnsLowerScoreThanPrefix() {
        let fuzzyResult = FuzzyMatcher.fuzzyMatch(query: "sptcl", target: "Split Vertical")
        let prefixResult = FuzzyMatcher.fuzzyMatch(query: "Split", target: "Split Vertical")

        XCTAssertNotNil(fuzzyResult, "Fuzzy non-contiguous match must return a result")
        XCTAssertNotNil(prefixResult, "Prefix match must return a result")
        XCTAssertLessThan(fuzzyResult!.score, prefixResult!.score,
                           "Fuzzy non-contiguous match must score lower than prefix match")
    }

    // MARK: - Test 4: No Match

    func testNoMatchReturnsNil() {
        let result = FuzzyMatcher.fuzzyMatch(query: "xyz", target: "Split Vertical")

        XCTAssertNil(result, "No match must return nil")
    }

    // MARK: - Test 5: Case Insensitive

    func testCaseInsensitiveMatchingWorks() {
        let result = FuzzyMatcher.fuzzyMatch(query: "split vertical", target: "Split Vertical")

        XCTAssertNotNil(result, "Case insensitive match must return a result")
        XCTAssertEqual(result!.score, 100,
                        "Case insensitive exact match must return score 100")
    }

    // MARK: - Test 6: Empty Query

    func testEmptyQueryMatchesEverythingWithScoreZero() {
        let result = FuzzyMatcher.fuzzyMatch(query: "", target: "Split Vertical")

        XCTAssertNotNil(result, "Empty query must match everything")
        XCTAssertEqual(result!.score, 0,
                        "Empty query must return score 0")
    }

    // MARK: - Test 7: Single Character Query

    func testSingleCharacterQueryMatches() {
        let result = FuzzyMatcher.fuzzyMatch(query: "s", target: "Split Vertical")

        XCTAssertNotNil(result, "Single character query must match if character exists in target")
        XCTAssertGreaterThan(result!.score, 0,
                              "Single character match must have score > 0")
    }

    // MARK: - Test 8: Word Boundary Bonus

    func testWordBoundaryBonusForInitials() {
        let initialsResult = FuzzyMatcher.fuzzyMatch(query: "sv", target: "Split Vertical")
        let nonBoundaryResult = FuzzyMatcher.fuzzyMatch(query: "pl", target: "Split Vertical")

        XCTAssertNotNil(initialsResult, "Word boundary match must return a result")
        XCTAssertNotNil(nonBoundaryResult, "Non-boundary match must return a result")
        XCTAssertGreaterThan(initialsResult!.score, nonBoundaryResult!.score,
                              "Word boundary match ('sv' for 'Split Vertical') must score higher than non-boundary ('pl')")
    }

    // MARK: - Test 9: Consecutive Matches Score Higher

    func testConsecutiveMatchesScoreHigherThanNonConsecutive() {
        let consecutiveResult = FuzzyMatcher.fuzzyMatch(query: "Spl", target: "Split Vertical")
        let nonConsecutiveResult = FuzzyMatcher.fuzzyMatch(query: "Svl", target: "Split Vertical")

        XCTAssertNotNil(consecutiveResult, "Consecutive match must return a result")
        XCTAssertNotNil(nonConsecutiveResult, "Non-consecutive match must return a result")
        XCTAssertGreaterThan(consecutiveResult!.score, nonConsecutiveResult!.score,
                              "Consecutive matches must score higher than non-consecutive")
    }

    // MARK: - Test 10: Empty Target

    func testEmptyTargetReturnsNilForNonEmptyQuery() {
        let result = FuzzyMatcher.fuzzyMatch(query: "abc", target: "")

        XCTAssertNil(result, "Non-empty query against empty target must return nil")
    }
}
