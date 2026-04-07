// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineView.swift - SwiftUI view showing agent timeline events chronologically.

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

        var title: String {
            switch self {
            case .all:
                return "All Windows"
            case .current:
                return "This Window"
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
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent Timeline")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Agent Timeline")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if currentWindowID != nil {
                scopePicker
            }

            Menu {
                Button("Export JSON") { viewModel.onExportJSON() }
                Button("Export Markdown") { viewModel.onExportMarkdown() }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel("Export timeline")

            if onDismiss != nil {
                Button(action: { onDismiss?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .accessibilityLabel("Close timeline")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(WindowScope.allCases) { scope in
                Button(scope.title) {
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
                filterChip(label: "All", type: nil)
                filterChip(label: "Tools", type: .toolUse)
                filterChip(label: "Errors", type: .toolFailure)
                filterChip(label: "Agents", type: .subagentStart)
                filterChip(label: "Tasks", type: .taskCompleted)
                filterChip(label: "Session", type: .sessionStart)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    /// A single filter chip button.
    private func filterChip(label: String, type: TimelineEventType?) -> some View {
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
        .accessibilityLabel("\(label) filter")
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
            Text(selectedScope == .current ? "No events in this window" : "No timeline events")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(
                selectedScope == .current
                ? "Switch to All Windows to inspect activity\nfrom every window."
                : "Agent actions will appear here\nas they happen in real-time."
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
}
