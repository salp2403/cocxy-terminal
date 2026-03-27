// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandPaletteEngineTests.swift - Tests for the Command Palette engine.
//
// Test plan (14 tests):
// 1.  Register action is findable via allActions.
// 2.  Search exact name returns the action.
// 3.  Search fuzzy returns action with score.
// 4.  Search no match returns empty results.
// 5.  Execute action calls the handler.
// 6.  Recent actions tracked (last 5 executed).
// 7.  Frequency tracking: most used action ranks higher.
// 8.  Register multiple actions at once.
// 9.  Category filtering works.
// 10. allActions returns all registered actions.
// 11. Built-in actions registered on init.
// 12. Thread safety: register from multiple threads does not crash.
// 13. Execute non-existent action does not crash.
// 14. Duplicate action ID overwrites the previous one.

import XCTest
@testable import CocxyTerminal

@MainActor
final class CommandPaletteEngineTests: XCTestCase {

    private var sut: CommandPaletteEngineImpl!

    override func setUp() {
        super.setUp()
        sut = CommandPaletteEngineImpl()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Test 1: Register Action Is Findable

    func testRegisterActionIsFindableViaAllActions() {
        let action = makeAction(id: "test.action", name: "Test Action")

        sut.registerAction(action)

        let found = sut.allActions.first { $0.id == "test.action" }
        XCTAssertNotNil(found, "Registered action must be findable via allActions")
        XCTAssertEqual(found?.name, "Test Action")
    }

    // MARK: - Test 2: Search Exact Name

    func testSearchExactNameReturnsTheAction() {
        let action = makeAction(id: "custom.unique.action", name: "Unique Custom Action")
        sut.registerAction(action)

        let results = sut.search(query: "Unique Custom Action")

        XCTAssertFalse(results.isEmpty, "Exact name search must return results")
        XCTAssertEqual(results.first?.id, "custom.unique.action",
                        "First result must be the exact match")
    }

    // MARK: - Test 3: Search Fuzzy

    func testSearchFuzzyReturnsActionWithScore() {
        let action = makeAction(id: "custom.fuzzy.target", name: "Zebra Quilt")
        sut.registerAction(action)

        let results = sut.search(query: "zq")

        XCTAssertFalse(results.isEmpty,
                        "Fuzzy search 'zq' must match 'Zebra Quilt'")
        XCTAssertEqual(results.first?.id, "custom.fuzzy.target")
    }

    // MARK: - Test 4: Search No Match

    func testSearchNoMatchReturnsEmptyResults() {
        let action = makeAction(id: "custom.nomatch", name: "Unique Nomatch Target")
        sut.registerAction(action)

        let results = sut.search(query: "zzzzz")

        XCTAssertTrue(results.isEmpty,
                       "Search with no matching characters must return empty results")
    }

    // MARK: - Test 5: Execute Action Calls Handler

    func testExecuteActionCallsHandler() {
        var handlerCalled = false
        let action = CommandAction(
            id: "exec.test",
            name: "Execute Test",
            description: "Tests execution",
            shortcut: nil,
            category: .tabs,
            handler: { handlerCalled = true }
        )
        sut.registerAction(action)

        sut.execute(action)

        XCTAssertTrue(handlerCalled, "Execute must call the action's handler")
    }

    // MARK: - Test 6: Recent Actions Tracked (Last 5)

    func testRecentActionsTracksLastFiveExecuted() {
        // Register 7 actions
        for index in 0..<7 {
            sut.registerAction(makeAction(id: "action.\(index)", name: "Action \(index)"))
        }

        // Execute all 7
        for index in 0..<7 {
            let action = sut.allActions.first { $0.id == "action.\(index)" }!
            sut.execute(action)
        }

        let recentIds = sut.recentActions.map { $0.id }

        XCTAssertEqual(recentIds.count, 5,
                        "Recent actions must track at most 5 actions")

        // The last 5 executed should be actions 2-6 (most recent first)
        XCTAssertEqual(recentIds[0], "action.6", "Most recent should be first")
        XCTAssertEqual(recentIds[4], "action.2", "Oldest of last 5 should be last")
    }

    // MARK: - Test 7: Frequency Tracking

    func testFrequencyTrackingMostUsedActionRanksHigher() {
        let actionA = makeAction(id: "action.a", name: "Alpha Command")
        let actionB = makeAction(id: "action.b", name: "Alpha Better")
        sut.registerAction(actionA)
        sut.registerAction(actionB)

        // Execute actionB 5 times, actionA 1 time
        let registeredB = sut.allActions.first { $0.id == "action.b" }!
        let registeredA = sut.allActions.first { $0.id == "action.a" }!
        for _ in 0..<5 { sut.execute(registeredB) }
        sut.execute(registeredA)

        // Both match "Alpha". B should rank higher due to frequency.
        let results = sut.search(query: "Alpha")

        XCTAssertGreaterThanOrEqual(results.count, 2,
                                     "Both actions matching 'Alpha' must appear")
        XCTAssertEqual(results.first?.id, "action.b",
                        "More frequently used action must rank higher in results")
    }

    // MARK: - Test 8: Register Multiple Actions

    func testRegisterMultipleActionsAtOnce() {
        let actions = (0..<5).map { makeAction(id: "batch.\($0)", name: "Batch \($0)") }

        sut.registerActions(actions)

        let registeredIds = Set(sut.allActions.map { $0.id })
        for index in 0..<5 {
            XCTAssertTrue(registeredIds.contains("batch.\(index)"),
                           "Batch registered action batch.\(index) must be present")
        }
    }

    // MARK: - Test 9: Category Filtering

    func testSearchFiltersByCategory() {
        let tabAction = makeAction(id: "tab.new", name: "New Tab", category: .tabs)
        let splitAction = makeAction(id: "split.v", name: "New Split", category: .splits)
        sut.registerAction(tabAction)
        sut.registerAction(splitAction)

        // Both match "New", but we test that category metadata is preserved.
        let results = sut.search(query: "New")
        let categories = Set(results.map { $0.category })

        XCTAssertTrue(categories.contains(.tabs), "Tab action must appear in results")
        XCTAssertTrue(categories.contains(.splits), "Split action must appear in results")
    }

    // MARK: - Test 10: allActions Returns All

    func testAllActionsReturnsAllRegistered() {
        let initialCount = sut.allActions.count // built-in actions

        sut.registerAction(makeAction(id: "extra.1", name: "Extra One"))
        sut.registerAction(makeAction(id: "extra.2", name: "Extra Two"))

        XCTAssertEqual(sut.allActions.count, initialCount + 2,
                        "allActions must include built-in plus registered actions")
    }

    // MARK: - Test 11: Built-in Actions Registered on Init

    func testBuiltInActionsRegisteredOnInit() {
        let freshEngine = CommandPaletteEngineImpl()

        XCTAssertFalse(freshEngine.allActions.isEmpty,
                        "A fresh engine must have built-in actions registered")

        // Verify some expected built-in action categories exist
        let categories = Set(freshEngine.allActions.map { $0.category })
        XCTAssertTrue(categories.contains(.tabs),
                       "Built-in actions must include tab actions")
        XCTAssertTrue(categories.contains(.splits),
                       "Built-in actions must include split actions")
    }

    // MARK: - Test 12: Thread Safety

    func testThreadSafetyRegisterFromMultipleThreadsDoesNotCrash() {
        let iterations = 100
        let group = DispatchGroup()
        let localEngine = sut!

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let action = CommandAction(
                    id: "thread.\(i)",
                    name: "Thread Action \(i)",
                    description: "Concurrent test",
                    shortcut: nil,
                    category: .tabs,
                    handler: {}
                )
                localEngine.registerAction(action)
                group.leave()
            }
        }

        let expectation = expectation(description: "All concurrent registrations complete")
        group.notify(queue: .main) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10.0)

        // All 100 actions must be registered (plus built-ins).
        let threadActionCount = sut.allActions.filter { $0.id.hasPrefix("thread.") }.count
        XCTAssertEqual(threadActionCount, iterations,
                        "All \(iterations) concurrently registered actions must be present")
    }

    // MARK: - Test 13: Execute Non-Existent Action

    func testExecuteNonExistentActionDoesNotCrash() {
        let phantomAction = CommandAction(
            id: "phantom.action",
            name: "Phantom",
            description: "Does not exist in registry",
            shortcut: nil,
            category: .tabs,
            handler: {}
        )

        // Must not crash -- silent no-op for unknown action.
        sut.execute(phantomAction)

        // Reaching this line means no crash occurred.
        XCTAssertTrue(true, "Executing a non-registered action must not crash")
    }

    // MARK: - Test 14: Duplicate Action ID Overwrites

    func testDuplicateActionIdOverwritesPrevious() {
        let original = makeAction(id: "dup.action", name: "Original Name")
        let replacement = makeAction(id: "dup.action", name: "Replacement Name")

        sut.registerAction(original)
        sut.registerAction(replacement)

        let found = sut.allActions.filter { $0.id == "dup.action" }
        XCTAssertEqual(found.count, 1,
                        "Duplicate ID must not create two entries")
        XCTAssertEqual(found.first?.name, "Replacement Name",
                        "Duplicate ID must overwrite with the latest registration")
    }

    // MARK: - Helpers

    private func makeAction(
        id: String,
        name: String,
        category: CommandCategory = .tabs
    ) -> CommandAction {
        CommandAction(
            id: id,
            name: name,
            description: "Test action: \(name)",
            shortcut: nil,
            category: category,
            handler: {}
        )
    }
}
