// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@MainActor
@Suite("CommentStore")
struct CommentStoreSwiftTestingTests {
    @Test("add and retrieve comments by file")
    func addAndRetrieve() {
        let store = CommentStore()
        store.add(ReviewComment(filePath: "a.swift", lineRange: 5...5, body: "fix"))
        store.add(ReviewComment(filePath: "b.swift", lineRange: 1...3, body: "refactor"))
        store.add(ReviewComment(filePath: "a.swift", lineRange: 10...10, body: "rename"))
        #expect(store.comments(for: "a.swift").count == 2)
        #expect(store.allComments.count == 3)
    }

    @Test("remove comment by id")
    func removeById() {
        let store = CommentStore()
        let comment = ReviewComment(filePath: "a.swift", lineRange: 5...5, body: "fix")
        store.add(comment)
        store.remove(id: comment.id)
        #expect(store.allComments.isEmpty)
    }

    @Test("clearAll empties store")
    func clearAll() {
        let store = CommentStore()
        store.add(ReviewComment(filePath: "a.swift", lineRange: 1...1, body: "x"))
        store.clearAll()
        #expect(store.allComments.isEmpty)
    }

    @Test("archive moves pending comments into a review round")
    func archivePendingComments() {
        let store = CommentStore()
        store.add(ReviewComment(filePath: "a.swift", lineRange: 1...1, body: "x"))

        let round = store.archivePendingComments(
            nextRoundID: 1,
            baseRef: "abc123",
            diffs: []
        )

        #expect(round?.id == 1)
        #expect(store.allComments.isEmpty)
        #expect(store.reviewRounds.count == 1)
        #expect(store.reviewRounds[0].comments.count == 1)
    }
}
