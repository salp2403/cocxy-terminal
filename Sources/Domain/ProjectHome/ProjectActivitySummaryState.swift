// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectActivitySummaryState.swift - Honest Project Home activity availability.

import Foundation

enum ProjectActivitySummaryState: Sendable, Equatable {
    case loading
    case disabled
    case unavailable
    case available(ProjectActivitySummary, costTrackingEnabled: Bool)
}
