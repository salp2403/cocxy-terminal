// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineView.swift - SwiftUI view showing agent timeline events chronologically.

import AppKit
import SwiftUI

// MARK: - Timeline View

/// A scrollable panel showing agent actions chronologically.
///
/// ## Layout
///
/// ```
/// +-- Agent Timeline ----------------------+
/// | [Filter] [Export v]                     |
/// |                                        |
/// | 14:32:01  [W] Write  App.swift  120ms  |
/// | 14:32:15  [B] Bash   npm test   3.4s   |
/// | 14:33:00  [R] Read   README.md  5ms    |
/// | 14:33:02  [!] Edit   config..   --     |
/// | 14:33:10  [v] Finished          --     |
/// |                                        |
/// +----------------------------------------+
/// ```
///
/// ## Features
///
/// - Events displayed chronologically with newest at the bottom.
/// - Each row: timestamp + icon + tool name + file + duration.
/// - Color-coded: green (success), red (error), blue (tool), gray (neutral).
/// - Filter by event type via segmented control.
/// - Export button with JSON and Markdown options.
///
/// - SeeAlso: `TimelineEventRow` (individual event row)
/// - SeeAlso: `AgentTimelineStoreImpl` (data source)
/// - SeeAlso: HU-108 (Agent Timeline View)
struct TimelineView: View {

    private enum WindowScope: String, CaseIterable, Identifiable {
        case all
        case current

        var id: String { rawValue }

        func localizedTitle(using localizer: AppLocalizer) -> String {
            switch self {
            case .all:
                return localizer.string("timeline.scope.all", fallback: "All Windows")
            case .current:
                return localizer.string("timeline.scope.current", fallback: "This Window")
            }
        }
    }

    /// Reactive ViewModel for live-updating timeline. Takes priority over static events.
    @ObservedObject var viewModel: TimelineViewModel

    /// Navigation dispatcher for scrolling the terminal to an event's position.
    /// When nil, tap gestures on event rows are inactive.
    var navigationDispatcher: TimelineNavigationDispatcher?

    /// Callback invoked when the user taps the close button.
    /// When nil, no close button is shown (backwards compatible).
    var onDismiss: (() -> Void)? = nil

    /// The window hosting this timeline panel, used for local filtering.
    var currentWindowID: WindowID? = nil

    /// Forced `NSAppearance` for the translucent panel background.
    ///
    /// `nil` preserves the legacy inherit-from-window behaviour; non-nil
    /// values pin the vibrancy view so the timeline panel matches the
    /// rest of the chrome when the user forces a transparency theme.
    var vibrancyAppearanceOverride: NSAppearance?

    /// Local app-language resolver.
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    /// Currently selected event type filter. Nil means show all.
    @State private var selectedFilter: TimelineEventType? = nil

    @State private var selectedScope: WindowScope = .all

    /// Resolved event source from the reactive ViewModel.
    private var events: [TimelineEvent] { viewModel.events }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            filterBar
            Divider()
            eventListView
        }
        .background(
            ZStack {
                // Solid Catppuccin Mantle as reliable fallback.
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(
                    material: .sidebar,
                    blendingMode: .behindWindow,
                    appearanceOverride: vibrancyAppearanceOverride
                )
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("timeline.accessibility", fallback: "Agent Timeline"))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(localized("timeline.title", fallback: "Agent Timeline"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if currentWindowID != nil {
                scopePicker
            }

            Menu {
                Button(localized("timeline.export.json", fallback: "Export JSON")) { viewModel.onExportJSON() }
                Button(localized("timeline.export.markdown", fallback: "Export Markdown")) { viewModel.onExportMarkdown() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel(localized("timeline.export.accessibility", fallback: "Export timeline"))

            if onDismiss != nil {
                Button(action: { onDismiss?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .accessibilityLabel(localized("timeline.close", fallback: "Close timeline"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(WindowScope.allCases) { scope in
                Button(scope.localizedTitle(using: localizer)) {
                    selectedScope = scope
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: selectedScope == scope ? .semibold : .regular))
                .foregroundColor(selectedScope == scope ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(selectedScope == scope
                              ? Color.accentColor.opacity(0.18)
                              : Color.clear)
                )
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                filterChip(
                    label: localized("timeline.filter.all", fallback: "All"),
                    accessibilityLabel: localized("timeline.filter.all.accessibility", fallback: "All filter"),
                    type: nil
                )
                filterChip(
                    label: localized("timeline.filter.tools", fallback: "Tools"),
                    accessibilityLabel: localized("timeline.filter.tools.accessibility", fallback: "Tools filter"),
                    type: .toolUse
                )
                filterChip(
                    label: localized("timeline.filter.errors", fallback: "Errors"),
                    accessibilityLabel: localized("timeline.filter.errors.accessibility", fallback: "Errors filter"),
                    type: .toolFailure
                )
                filterChip(
                    label: localized("timeline.filter.agents", fallback: "Agents"),
                    accessibilityLabel: localized("timeline.filter.agents.accessibility", fallback: "Agents filter"),
                    type: .subagentStart
                )
                filterChip(
                    label: localized("timeline.filter.tasks", fallback: "Tasks"),
                    accessibilityLabel: localized("timeline.filter.tasks.accessibility", fallback: "Tasks filter"),
                    type: .taskCompleted
                )
                filterChip(
                    label: localized("timeline.filter.session", fallback: "Session"),
                    accessibilityLabel: localized("timeline.filter.session.accessibility", fallback: "Session filter"),
                    type: .sessionStart
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// A single filter chip button.
    private func filterChip(
        label: String,
        accessibilityLabel: String,
        type: TimelineEventType?
    ) -> some View {
        Button(action: { selectedFilter = type }) {
            Text(label)
                .font(.system(size: 10, weight: selectedFilter == type ? .semibold : .regular))
                // Catppuccin Crust for selected chip -- high contrast on accent bg.
                .foregroundColor(selectedFilter == type ? CocxyColors.swiftUI(CocxyColors.crust) : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedFilter == type ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selectedFilter == type ? .isSelected : [])
    }

    // MARK: - Event List

    private var eventListView: some View {
        Group {
            if filteredEvents.isEmpty {
                emptyStateView
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredEvents) { event in
                                TimelineEventRow(event: event)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        navigationDispatcher?.dispatchNavigation(for: event)
                                    }
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .onChange(of: filteredEvents.count) {
                        // Scroll to the latest event when new events arrive.
                        if let lastEvent = filteredEvents.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastEvent.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(
                selectedScope == .current
                ? localized("timeline.empty.current.title", fallback: "No events in this window")
                : localized("timeline.empty.all.title", fallback: "No timeline events")
            )
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(
                selectedScope == .current
                ? localized(
                    "timeline.empty.current.detail",
                    fallback: "Switch to All Windows to inspect activity\nfrom every window."
                )
                : localized(
                    "timeline.empty.all.detail",
                    fallback: "Agent actions will appear here\nas they happen in real-time."
                )
            )
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Filtered Events

    /// Events filtered by the selected type, or all if no filter is active.
    ///
    /// The "Agents" filter shows both subagentStart and subagentStop events
    /// to provide a complete view of subagent lifecycle.
    private var filteredEvents: [TimelineEvent] {
        let scopedEvents: [TimelineEvent]
        if selectedScope == .current, let currentWindowID {
            scopedEvents = events.filter { $0.windowID == currentWindowID }
        } else {
            scopedEvents = events
        }

        guard let filter = selectedFilter else { return scopedEvents }
        if filter == .subagentStart {
            return scopedEvents.filter { $0.type == .subagentStart || $0.type == .subagentStop }
        }
        return scopedEvents.filter { $0.type == filter }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
