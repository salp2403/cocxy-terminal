// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityRecorder.swift - Privacy gate for local activity writes.

import Foundation

struct ActivityPrivacyPolicy: Sendable, Equatable {
    let activityTrackingEnabled: Bool
    let tokenCostTrackingEnabled: Bool

    static let disabled = ActivityPrivacyPolicy(
        activityTrackingEnabled: false,
        tokenCostTrackingEnabled: false
    )

    static let enabled = ActivityPrivacyPolicy(
        activityTrackingEnabled: true,
        tokenCostTrackingEnabled: true
    )
}

final class ActivityRecorder {
    private let store: ActivityStoring
    private let policyProvider: () -> ActivityPrivacyPolicy

    init(
        store: ActivityStoring,
        policyProvider: @escaping () -> ActivityPrivacyPolicy = { .disabled }
    ) {
        self.store = store
        self.policyProvider = policyProvider
    }

    func record(_ event: ActivityEvent) throws {
        guard policyProvider().activityTrackingEnabled else { return }
        try store.recordEvent(event)
    }

    func recordTokenUsage(_ record: TokenUsageRecord) throws {
        guard policyProvider().tokenCostTrackingEnabled else { return }
        try store.recordTokenUsage(record)
    }

    func deleteAllLocalActivity() throws {
        try store.deleteAll()
    }
}
