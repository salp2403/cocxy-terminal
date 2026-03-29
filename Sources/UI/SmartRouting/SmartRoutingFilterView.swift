// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartRoutingFilterView.swift - Filter controls for the Smart Routing overlay.

import SwiftUI

// MARK: - Smart Routing Filter View

/// Displays the current filter state in the overlay header.
///
/// Shows filter shortcuts (when overlay has focus):
/// - `E`: Show only errors.
/// - `W`: Show only waiting for input.
/// - `A`: Show all agents.
///
/// The active filter is highlighted with accent color.
///
/// - SeeAlso: `SmartRoutingOverlayView`
/// - SeeAlso: `SmartRoutingFilter`
struct SmartRoutingFilterView: View {

    let activeFilter: SmartRoutingFilter
    let onFilterSelected: (SmartRoutingFilter) -> Void

    var body: some View {
        HStack(spacing: 8) {
            filterBadge(label: "All", filter: .all)
            filterBadge(label: "Errors", filter: .errorsOnly)
            filterBadge(label: "Waiting", filter: .waitingOnly)
        }
    }

    // MARK: - Private

    private func filterBadge(label: String, filter: SmartRoutingFilter) -> some View {
        let isActive = activeFilter == filter
        return Text(label)
            .font(.caption2)
            .fontWeight(isActive ? .bold : .regular)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isActive ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(Capsule())
            .foregroundStyle(isActive ? .primary : .secondary)
            .contentShape(Capsule())
            .onTapGesture { onFilterSelected(filter) }
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityLabel("Filter: \(label)")
    }
}
