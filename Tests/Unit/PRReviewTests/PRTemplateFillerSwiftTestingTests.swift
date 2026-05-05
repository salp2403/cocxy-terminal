// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("PR template filler")
struct PRTemplateFillerSwiftTestingTests {

    @Test("explicit body wins without reading template")
    func explicitBodyWinsWithoutReadingTemplate() throws {
        let root = try makePRTemplateFillerTemporaryDirectory(named: "pr-template-explicit-body")
        defer { try? FileManager.default.removeItem(at: root) }

        let filler = PRTemplateFiller(commitSummaryProvider: { _, _ in
            Issue.record("Commit summaries should not be read when body is explicit")
            return ["Should not appear"]
        })

        let body = filler.body(
            root: root,
            explicitBody: "  Ready for review.  ",
            baseBranch: "main"
        )

        #expect(body == "  Ready for review.  ")
    }

    @Test("template is filled with local commit summaries")
    func templateIsFilledWithLocalCommitSummaries() throws {
        let root = try makePRTemplateFillerTemporaryDirectory(named: "pr-template-commits")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTemplate(
            """
            ## Summary

            -
            """,
            at: root
        )

        let filler = PRTemplateFiller(commitSummaryProvider: { receivedRoot, receivedBase in
            #expect(receivedRoot == root)
            #expect(receivedBase == "main")
            return [
                "Add review template support",
                "  ",
                "Harden create pull request flow",
                "Add review template support",
            ]
        })

        let body = filler.body(root: root, explicitBody: nil, baseBranch: "main")

        #expect(body == """
        ## Summary

        -

        ## Commits

        - Add review template support
        - Harden create pull request flow
        """)
    }

    @Test("template with commits heading is not duplicated")
    func templateWithCommitsHeadingIsNotDuplicated() throws {
        let root = try makePRTemplateFillerTemporaryDirectory(named: "pr-template-existing-commits")
        defer { try? FileManager.default.removeItem(at: root) }
        try writeTemplate(
            """
            ## Summary

            Fill this in.

            ## Commits

            - Existing item
            """,
            at: root
        )

        let filler = PRTemplateFiller(commitSummaryProvider: { _, _ in
            ["New item"]
        })

        let body = filler.body(root: root, explicitBody: nil, baseBranch: nil)

        #expect(body == """
        ## Summary

        Fill this in.

        ## Commits

        - Existing item
        """)
    }

    @Test("missing template preserves nil body")
    func missingTemplatePreservesNilBody() throws {
        let root = try makePRTemplateFillerTemporaryDirectory(named: "pr-template-missing")
        defer { try? FileManager.default.removeItem(at: root) }

        let filler = PRTemplateFiller(commitSummaryProvider: { _, _ in
            ["No template should use this"]
        })

        #expect(filler.body(root: root, explicitBody: nil, baseBranch: "main") == nil)
    }
}

private func makePRTemplateFillerTemporaryDirectory(named name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func writeTemplate(_ content: String, at root: URL) throws {
    let directory = root.appendingPathComponent(".github", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try content.write(
        to: directory.appendingPathComponent("pull_request_template.md"),
        atomically: true,
        encoding: .utf8
    )
}
