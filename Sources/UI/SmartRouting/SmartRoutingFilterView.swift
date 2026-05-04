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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        HStack(spacing: 8) {
            filterBadge(filter: .all)
            filterBadge(filter: .errorsOnly)
            filterBadge(filter: .waitingOnly)
        }
    }

    // MARK: - Private

    private func filterBadge(filter: SmartRoutingFilter) -> some View {
        let label = filter.localizedTitle(using: localizer)
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
            .accessibilityLabel(Self.localizedFilterAccessibility(label, using: localizer))
    }

    static func localizedFilterAccessibility(_ label: String, using localizer: AppLocalizer) -> String {
        String(
            format: localizer.string("smartRouting.filter.accessibility", fallback: "Filter: %@"),
            label
        )
    }
}

extension SmartRoutingFilter {
    func localizedTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .all: return localizer.string("smartRouting.filter.all", fallback: "All")
        case .errorsOnly: return localizer.string("smartRouting.filter.errors", fallback: "Errors")
        case .waitingOnly: return localizer.string("smartRouting.filter.waiting", fallback: "Waiting")
        }
    }
}
