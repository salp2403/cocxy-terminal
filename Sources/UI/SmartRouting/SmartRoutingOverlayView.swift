// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartRoutingOverlayView.swift - SwiftUI overlay for Smart Agent Routing.

import SwiftUI

// MARK: - Smart Routing Overlay View

/// Overlay that appears on Cmd+Shift+U showing agents needing attention.
///
/// Displays a list of agents with their state, project name, and last
/// activity summary. Each row has a number (1-9) for keyboard selection.
///
/// ## Keyboard Shortcuts
///
/// - `1`-`9`: Select agent by position.
/// - `Enter`: Select highlighted agent.
/// - `Esc`: Close the overlay.
///
/// ## Filters
///
/// - `E`: Show only errors.
/// - `W`: Show only waiting for input.
/// - `A`: Show all agents.
///
/// - SeeAlso: `SmartRoutingOverlayViewModel`
/// - SeeAlso: `SmartRoutingFilterView`
struct SmartRoutingOverlayView: View {

    // MARK: - State

    @ObservedObject var viewModel: SmartRoutingOverlayViewModel
    let onDismiss: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    @State private var selectedIndex: Int = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()

            if viewModel.displayedAgents.isEmpty {
                emptyStateView
            } else {
                agentListView
            }
        }
        .frame(width: 420)
        .frame(maxHeight: 400)
        .background {
            Design.GlassSurface(cornerRadius: .medium) {
                Color.clear
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.localizedTitle(using: localizer))
        .accessibilityHint(Self.localizedAccessibilityHint(using: localizer))
        .focusable()
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onKeyPress(.return) {
            let agents = viewModel.displayedAgents
            guard !agents.isEmpty, selectedIndex < agents.count else {
                return .ignored
            }
            viewModel.selectAgentByNumber(selectedIndex + 1)
            onDismiss()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !viewModel.displayedAgents.isEmpty else { return .ignored }
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !viewModel.displayedAgents.isEmpty else { return .ignored }
            selectedIndex = min(viewModel.displayedAgents.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = Int(press.characters), digit >= 1, digit <= 9 else {
                return .ignored
            }
            guard digit <= viewModel.displayedAgents.count else {
                return .ignored
            }
            viewModel.selectAgentByNumber(digit)
            onDismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "eEwWaA")) { press in
            let ch = press.characters.lowercased()
            switch ch {
            case "e": viewModel.applyFilter(.errorsOnly)
            case "w": viewModel.applyFilter(.waitingOnly)
            case "a": viewModel.applyFilter(.all)
            default: return .ignored
            }
            return .handled
        }
        .onChange(of: viewModel.activeFilter) {
            selectedIndex = 0
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(Self.localizedTitle(using: localizer))
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            SmartRoutingFilterView(
                activeFilter: viewModel.activeFilter,
                onFilterSelected: { filter in
                    viewModel.applyFilter(filter)
                },
                localizer: localizer
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        Text(viewModel.localizedEmptyMessage(using: localizer))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(32)
    }

    // MARK: - Agent List

    private var agentListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(viewModel.displayedAgents.enumerated()), id: \.element.id) { index, agent in
                    SmartRoutingAgentRow(
                        agent: agent,
                        number: index + 1,
                        isSelected: index == selectedIndex,
                        localizer: localizer
                    )
                    .onTapGesture {
                        viewModel.selectAgentByNumber(index + 1)
                        onDismiss()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("smartRouting.title", fallback: "Smart Routing")
    }

    static func localizedAccessibilityHint(using localizer: AppLocalizer) -> String {
        localizer.string(
            "smartRouting.accessibility.hint",
            fallback: "Navigate between AI agents. Use arrow keys to select, Enter to activate."
        )
    }
}

// MARK: - Agent Row

/// A single row in the Smart Routing overlay showing agent info.
struct SmartRoutingAgentRow: View {
    let agent: AgentSessionInfo
    let number: Int
    let isSelected: Bool
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        HStack(spacing: 12) {
            // Number badge (1-9).
            Text("\(number)")
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)

            // State indicator.
            Circle()
                .fill(colorForState(agent.state))
                .frame(width: 8, height: 8)

            // Agent info.
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(agent.projectName)
                        .font(.system(.body, weight: .medium))
                        .lineLimit(1)

                    if let agentName = agent.agentName {
                        Text(agentName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(Self.localizedStateDescription(agent.state, using: localizer))
                    .font(.caption)
                    .foregroundStyle(colorForState(agent.state))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func colorForState(_ state: AgentDashboardState) -> Color {
        switch state {
        case .error:           return Color(nsColor: CocxyColors.red)
        case .blocked:         return Color(nsColor: CocxyColors.peach)
        case .waitingForInput: return Color(nsColor: CocxyColors.yellow)
        case .working:         return Color(nsColor: CocxyColors.blue)
        case .launching:       return Color(nsColor: CocxyColors.sky)
        case .idle:            return Color(nsColor: CocxyColors.overlay2)
        case .finished:        return Color(nsColor: CocxyColors.green)
        }
    }

    static func localizedStateDescription(_ state: AgentDashboardState, using localizer: AppLocalizer) -> String {
        switch state {
        case .error: return localizer.string("smartRouting.state.error", fallback: "Error")
        case .blocked: return localizer.string("smartRouting.state.blocked", fallback: "Blocked")
        case .waitingForInput:
            return localizer.string("smartRouting.state.waitingForInput", fallback: "Waiting for input")
        case .working: return localizer.string("smartRouting.state.working", fallback: "Working")
        case .launching: return localizer.string("smartRouting.state.launching", fallback: "Launching")
        case .idle: return localizer.string("smartRouting.state.idle", fallback: "Idle")
        case .finished: return localizer.string("smartRouting.state.finished", fallback: "Finished")
        }
    }
}
