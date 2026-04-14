// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("ReviewComment")
struct ReviewCommentSwiftTestingTests {
    @Test("comment anchors to file and line range")
    func anchoredComment() {
        let comment = ReviewComment(
            filePath: "foo.swift",
            lineRange: 10...12,
            body: "Handle the nil case"
        )
        #expect(comment.filePath == "foo.swift")
        #expect(comment.lineRange == 10...12)
        #expect(comment.body == "Handle the nil case")
        #expect(comment.displayLineDescription == "lines 10-12")
    }
}
