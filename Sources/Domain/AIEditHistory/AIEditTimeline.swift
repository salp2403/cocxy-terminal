// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditTimeline.swift - Chronological and per-file views over local edit history.

import Foundation

struct AIEditTimeline: Sendable, Equatable {
    let records: [AIEditRecord]

    init(records: [AIEditRecord]) {
        self.records = records.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }
    }

    func records(touching filePath: String) -> [AIEditRecord] {
        records.filter { record in
            record.changes.contains { $0.filePath == filePath }
        }
    }

    func records(for sessionID: String) -> [AIEditRecord] {
        records.filter { $0.sessionID == sessionID }
    }
}
