// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskHandoffArtifact.swift - Bounded, redacted context shared between local agent tabs.

import Foundation
import CocxyShared

struct TaskHandoffSemanticBlock: Equatable, Sendable {
    let command: String
    let output: String
    let exitCode: Int32?
    let workingDirectory: String?
}

struct TaskHandoffArtifactInput: Equatable, Sendable {
    let tabID: UUID?
    let workingDirectory: String
    let branch: String?
    let worktreeID: String?
    let taskSummary: String?
    let touchedFiles: [String]
    let semanticBlocks: [TaskHandoffSemanticBlock]
}

struct TaskHandoffArtifact: Equatable, Sendable {
    let markdown: String
    let includedBlockCount: Int
    let includedTouchedFileCount: Int

    var byteCount: Int { markdown.utf8.count }
}

enum TaskHandoffArtifactBuilder {
    static let defaultBlockLimit = CocxyTaskHandoffWireContract.defaultBlockLimit
    static let maximumBlockLimit = CocxyTaskHandoffWireContract.maximumBlockLimit
    static let maximumArtifactBytes = CocxyTaskHandoffWireContract.maximumArtifactBytes
    static let maximumSummaryBytes = 3_072
    static let maximumCommandBytes = 1_024
    static let maximumOutputBytesPerBlock = 2_048
    static let maximumTouchedFiles = 32
    static let maximumTouchedFileBytes = 512

    static func make(
        input: TaskHandoffArtifactInput,
        blockLimit: Int = defaultBlockLimit
    ) -> TaskHandoffArtifact {
        let limit = min(max(1, blockLimit), maximumBlockLimit)
        let workingDirectory = inlineValue(input.workingDirectory, maximumBytes: 2_048)
        let branch = inlineValue(input.branch ?? "(unknown)", maximumBytes: 512)
        let worktreeID = inlineValue(input.worktreeID ?? "(none)", maximumBytes: 512)
        let summary = sanitized(input.taskSummary ?? "No task summary is available.")
        let boundedSummary = bounded(summary, maximumBytes: maximumSummaryBytes)

        var markdown = """
        # Task Handoff

        ## Context

        - Tab: `\(input.tabID?.uuidString ?? "(unavailable)")`
        - Working directory: `\(workingDirectory)`
        - Branch: `\(branch)`
        - Worktree: `\(worktreeID)`

        ## Task Summary

        \(fenced(boundedSummary))

        ## Touched Files

        """

        let touchedFiles = Array(Set(input.touchedFiles.map {
            inlineValue($0, maximumBytes: maximumTouchedFileBytes)
        })).filter { !$0.isEmpty }.sorted()
        var includedTouchedFileCount = 0
        if touchedFiles.isEmpty {
            markdown += "No touched files were reported.\n"
        } else {
            for path in touchedFiles.prefix(maximumTouchedFiles) {
                let line = "- `\(path)`\n"
                guard canAppend(line, to: markdown, reservingBytes: 256) else {
                    markdown += "- Additional touched files omitted to keep the artifact bounded.\n"
                    break
                }
                markdown += line
                includedTouchedFileCount += 1
            }
        }

        markdown += "\n## Recent Semantic Blocks\n\n"
        let blocks = Array(input.semanticBlocks.suffix(limit).reversed())
        var includedBlockCount = 0
        if blocks.isEmpty {
            markdown += "No semantic command blocks are available for this terminal surface.\n"
        } else {
            for (index, block) in blocks.enumerated() {
                let command = bounded(
                    sanitized(block.command),
                    maximumBytes: maximumCommandBytes
                )
                let output = bounded(
                    sanitized(block.output),
                    maximumBytes: maximumOutputBytesPerBlock
                )
                let segment = renderBlock(
                    block,
                    sequence: index + 1,
                    command: command,
                    output: output
                )
                guard canAppend(segment, to: markdown, reservingBytes: 160) else {
                    let marker = "Semantic blocks omitted to keep the artifact bounded.\n"
                    if canAppend(marker, to: markdown, reservingBytes: 0) {
                        markdown += marker
                    }
                    break
                }
                markdown += segment
                includedBlockCount += 1
            }
        }

        let boundedMarkdown = bounded(markdown, maximumBytes: maximumArtifactBytes)
        return TaskHandoffArtifact(
            markdown: boundedMarkdown,
            includedBlockCount: includedBlockCount,
            includedTouchedFileCount: includedTouchedFileCount
        )
    }

    private static func renderBlock(
        _ block: TaskHandoffSemanticBlock,
        sequence: Int,
        command: String,
        output: String
    ) -> String {
        var lines = ["### Block \(sequence) (most recent first)", ""]
        if let workingDirectory = block.workingDirectory, !workingDirectory.isEmpty {
            lines.append(
                "Working directory: `\(inlineValue(workingDirectory, maximumBytes: 2_048))`"
            )
        }
        if let exitCode = block.exitCode {
            lines.append("Exit code: `\(exitCode)`")
        }
        if !command.isEmpty {
            lines.append(contentsOf: ["", "Command:", "", fenced(command)])
        }
        if !output.isEmpty {
            lines.append(contentsOf: ["", "Output:", "", fenced(output)])
        }
        if command.isEmpty && output.isEmpty {
            lines.append("No retained command text or output is available for this block.")
        }
        return lines.joined(separator: "\n") + "\n\n"
    }

    private static func sanitized(_ text: String) -> String {
        AgentSensitiveOutputRedactor.redacted(
            text.replacingOccurrences(of: "\0", with: "")
        )
    }

    private static func inlineValue(_ text: String, maximumBytes: Int) -> String {
        bounded(sanitized(text), maximumBytes: maximumBytes)
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func fenced(_ text: String) -> String {
        let fenceLength = max(3, longestBacktickRun(in: text) + 1)
        let fence = String(repeating: "`", count: fenceLength)
        return "\(fence)text\n\(text)\n\(fence)"
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }

    private static func canAppend(
        _ value: String,
        to existing: String,
        reservingBytes: Int
    ) -> Bool {
        existing.utf8.count + value.utf8.count + reservingBytes <= maximumArtifactBytes
    }

    private static func bounded(_ value: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0, value.utf8.count > maximumBytes else {
            return maximumBytes > 0 ? value : ""
        }
        let marker = "\n[truncated]"
        let contentBudget = max(0, maximumBytes - marker.utf8.count)
        var result = ""
        var byteCount = 0
        for character in value {
            let fragment = String(character)
            let fragmentBytes = fragment.utf8.count
            guard byteCount + fragmentBytes <= contentBudget else { break }
            result.append(character)
            byteCount += fragmentBytes
        }
        return result + marker
    }
}
