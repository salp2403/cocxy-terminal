// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewModels.swift - Shared value types for the agent code review panel.

import Foundation

// MARK: - File Status

enum FileStatus: String, Sendable, Equatable, CaseIterable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case untracked = "?"

    var sortRank: Int {
        switch self {
        case .modified: return 0
        case .added, .untracked: return 1
        case .renamed: return 2
        case .deleted: return 3
        }
    }
}

// MARK: - Diff Line

struct DiffLine: Equatable, Sendable, Identifiable {
    enum Kind: Sendable, Equatable {
        case context
        case addition
        case deletion
    }

    let kind: Kind
    let content: String
    let oldLineNumber: Int?
    let newLineNumber: Int?

    var id: String {
        "\(oldLineNumber.map(String.init) ?? "-"):\(newLineNumber.map(String.init) ?? "-"):\(kind):\(content)"
    }

    var displayLineNumber: Int? {
        newLineNumber ?? oldLineNumber
    }

    var isCommentable: Bool {
        displayLineNumber != nil
    }
}

// MARK: - Diff Hunk

struct DiffHunk: Equatable, Sendable, Identifiable {
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]

    var id: String {
        "\(header)|\(oldStart)|\(newStart)"
    }

    var firstDisplayLine: Int? {
        lines.compactMap(\.displayLineNumber).first
    }

    var additions: Int {
        lines.filter { $0.kind == .addition }.count
    }

    var deletions: Int {
        lines.filter { $0.kind == .deletion }.count
    }
}

// MARK: - File Diff

struct FileDiff: Identifiable, Equatable, Sendable {
    var id: String { filePath }

    let filePath: String
    let originalFilePath: String?
    let status: FileStatus
    let hunks: [DiffHunk]
    let agentName: String?
    let reviewNote: String?

    init(
        filePath: String,
        originalFilePath: String? = nil,
        status: FileStatus,
        hunks: [DiffHunk],
        agentName: String? = nil,
        reviewNote: String? = nil
    ) {
        self.filePath = filePath
        self.originalFilePath = originalFilePath
        self.status = status
        self.hunks = hunks
        self.agentName = agentName
        self.reviewNote = reviewNote
    }

    var additions: Int {
        hunks.reduce(0) { $0 + $1.additions }
    }

    var deletions: Int {
        hunks.reduce(0) { $0 + $1.deletions }
    }

    var displayName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    var totalLineCount: Int {
        hunks.reduce(0) { $0 + $1.lines.count }
    }
}

// MARK: - Review Round

struct ReviewRound: Identifiable, Sendable, Equatable {
    let id: Int
    let timestamp: Date
    let baseRef: String
    let diffs: [FileDiff]
    let comments: [ReviewComment]
}

// MARK: - Diff Mode

enum DiffMode: String, CaseIterable, Sendable {
    case uncommitted
    case sinceSessionStart
    case vsBranch

    var title: String {
        switch self {
        case .uncommitted: return "Working Tree"
        case .sinceSessionStart: return "Agent Session"
        case .vsBranch: return "Reference"
        }
    }
}
