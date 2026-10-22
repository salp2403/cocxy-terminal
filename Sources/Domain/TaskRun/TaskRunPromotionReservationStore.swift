// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunPromotionReservationStore.swift - App-scoped single-flight promotion leases.

import Foundation

struct TaskRunPromotionLease: Sendable, Equatable {
    let runID: String
    let revision: Date
    let ownerToken: UUID
}

actor TaskRunPromotionReservationStore {
    private var leasesByRunID: [String: TaskRunPromotionLease] = [:]

    func acquire(runID: String, revision: Date) throws -> TaskRunPromotionLease {
        guard leasesByRunID[runID] == nil else {
            throw TaskRunExecutionError.promotionUnavailable(
                "task run \(runID) already has a promotion in progress"
            )
        }
        let lease = TaskRunPromotionLease(
            runID: runID,
            revision: revision,
            ownerToken: UUID()
        )
        leasesByRunID[runID] = lease
        return lease
    }

    func owns(_ lease: TaskRunPromotionLease) -> Bool {
        leasesByRunID[lease.runID] == lease
    }

    func release(_ lease: TaskRunPromotionLease) {
        guard leasesByRunID[lease.runID] == lease else { return }
        leasesByRunID.removeValue(forKey: lease.runID)
    }
}
