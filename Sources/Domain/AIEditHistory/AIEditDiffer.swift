// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditDiffer.swift - Summaries for recorded local agent edits.

import Foundation

struct AIEditDiffer: Sendable {
    func fileSummaries(for record: AIEditRecord) -> [AIEditFileSummary] {
        record.changes.map { change in
            let counts = lineChangeCounts(before: change.beforeContent, after: change.afterContent)
            return AIEditFileSummary(
                filePath: change.filePath,
                additions: counts.additions,
                deletions: counts.deletions
            )
        }
    }

    func touchedFiles(for records: [AIEditRecord]) -> [String] {
        Array(Set(records.flatMap { $0.changes.map(\.filePath) })).sorted()
    }

    private func lineChangeCounts(before: String?, after: String?) -> (additions: Int, deletions: Int) {
        let difference = lines(after).difference(from: lines(before))
        return difference.reduce(into: (additions: 0, deletions: 0)) { result, change in
            switch change {
            case .insert:
                result.additions += 1
            case .remove:
                result.deletions += 1
            }
        }
    }

    private func lines(_ value: String?) -> [String] {
        guard let value, !value.isEmpty else { return [] }
        var result = value.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if result.last == "" {
            result.removeLast()
        }
        return result
    }
}
