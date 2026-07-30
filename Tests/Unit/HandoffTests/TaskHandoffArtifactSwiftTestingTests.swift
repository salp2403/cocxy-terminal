// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task handoff artifact")
struct TaskHandoffArtifactSwiftTestingTests {
    @Test("artifact includes context and newest semantic blocks with local redaction")
    func artifactIncludesRequiredContextAndRedactsSecrets() throws {
        let input = TaskHandoffArtifactInput(
            tabID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            workingDirectory: "/tmp/project",
            branch: "feature/handoff",
            worktreeID: "wt-123",
            taskSummary: "Continue implementation with token=super-secret-value",
            touchedFiles: ["Sources/B.swift", "Sources/A.swift", "Sources/A.swift"],
            semanticBlocks: [
                TaskHandoffSemanticBlock(
                    command: "first",
                    output: "older output",
                    exitCode: 0,
                    workingDirectory: "/tmp/project"
                ),
                TaskHandoffSemanticBlock(
                    command: "second",
                    output: "Authorization: Bearer abcdefghijklmnop",
                    exitCode: 1,
                    workingDirectory: "/tmp/project"
                ),
            ]
        )

        let artifact = TaskHandoffArtifactBuilder.make(input: input, blockLimit: 2)

        #expect(artifact.markdown.contains("# Task Handoff"))
        #expect(artifact.markdown.contains("feature/handoff"))
        #expect(artifact.markdown.contains("wt-123"))
        #expect(artifact.markdown.contains("Sources/A.swift"))
        #expect(artifact.markdown.contains("token=[redacted]"))
        #expect(artifact.markdown.contains("Authorization: Bearer [redacted]"))
        #expect(!artifact.markdown.contains("super-secret-value"))
        #expect(!artifact.markdown.contains("abcdefghijklmnop"))
        let secondCommand = try #require(
            artifact.markdown.range(of: "Command:\n\n```text\nsecond\n```")
        )
        let firstCommand = try #require(
            artifact.markdown.range(of: "Command:\n\n```text\nfirst\n```")
        )
        #expect(secondCommand.lowerBound < firstCommand.lowerBound)
        #expect(artifact.includedBlockCount == 2)
        #expect(artifact.includedTouchedFileCount == 2)
    }

    @Test("artifact remains valid UTF-8 and bounded under adversarial content")
    func artifactIsBounded() {
        let huge = String(repeating: "secret=value-\u{1F680}`\n", count: 10_000)
        let blocks = (0..<TaskHandoffArtifactBuilder.maximumBlockLimit).map { index in
            TaskHandoffSemanticBlock(
                command: "command-\(index) \(huge)",
                output: huge,
                exitCode: Int32(index),
                workingDirectory: "/tmp/\(index)"
            )
        }
        let input = TaskHandoffArtifactInput(
            tabID: UUID(),
            workingDirectory: huge,
            branch: huge,
            worktreeID: huge,
            taskSummary: huge,
            touchedFiles: (0..<100).map { "\($0)-\(huge)" },
            semanticBlocks: blocks
        )

        let artifact = TaskHandoffArtifactBuilder.make(
            input: input,
            blockLimit: TaskHandoffArtifactBuilder.maximumBlockLimit
        )

        #expect(artifact.byteCount <= TaskHandoffArtifactBuilder.maximumArtifactBytes)
        #expect(
            String(data: Data(artifact.markdown.utf8), encoding: .utf8) == artifact.markdown
        )
        #expect(artifact.markdown.contains("[truncated]"))
        #expect(
            artifact.includedTouchedFileCount <= TaskHandoffArtifactBuilder.maximumTouchedFiles
        )
        #expect(artifact.includedBlockCount <= TaskHandoffArtifactBuilder.maximumBlockLimit)
    }

    @Test("artifact fences remain balanced when retained text contains backticks")
    func artifactUsesSafeMarkdownFences() {
        let artifact = TaskHandoffArtifactBuilder.make(input: TaskHandoffArtifactInput(
            tabID: UUID(),
            workingDirectory: "/tmp/project",
            branch: "feature/handoff",
            worktreeID: nil,
            taskSummary: "Inspect ```nested``` content.",
            touchedFiles: [],
            semanticBlocks: [
                TaskHandoffSemanticBlock(
                    command: "printf '````'",
                    output: "```output```",
                    exitCode: 0,
                    workingDirectory: "/tmp/project"
                ),
            ]
        ))

        #expect(artifact.markdown.contains("````text\nInspect ```nested``` content.\n````"))
        #expect(artifact.markdown.contains("`````text\nprintf '````'\n`````"))
        #expect(artifact.markdown.contains("````text\n```output```\n````"))
    }

    @Test("empty observations remain explicit instead of fabricating context")
    func emptyObservationsAreExplicit() {
        let artifact = TaskHandoffArtifactBuilder.make(input: TaskHandoffArtifactInput(
            tabID: UUID(),
            workingDirectory: "/tmp/project",
            branch: nil,
            worktreeID: nil,
            taskSummary: nil,
            touchedFiles: [],
            semanticBlocks: []
        ))

        #expect(artifact.markdown.contains("No task summary is available."))
        #expect(artifact.markdown.contains("No touched files were reported."))
        #expect(artifact.markdown.contains("No semantic command blocks are available"))
        #expect(artifact.includedBlockCount == 0)
    }
}
