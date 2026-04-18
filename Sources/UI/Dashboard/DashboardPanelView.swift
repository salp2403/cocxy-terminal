// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardPanelView.swift - SwiftUI panel showing all agent sessions.

import AppKit
import SwiftUI
import Combine

// MARK: - Dashboard Panel View

/// A side panel that displays the status of all active agent sessions.
///
/// ## Layout
///
/// ```
/// +-- Agent Dashboard ----------------+
/// | [x] Close                          |
/// |                                    |
/// | [green] cocxy-terminal  main  2m  |
/// |   Working: Write Sources/...       |
/// |                                    |
/// | [orange] my-api  feat/auth  5m    |
/// |   Waiting for input               |
/// |                                    |
/// | [gray] data-pipeline  develop      |
/// |   Finished 12m ago                |
/// +------------------------------------+
/// ```
///
/// ## Behavior
///
/// - Toggle with Cmd+Shift+D.
/// - Fixed width: 280pt.
/// - Appears to the right of the tab sidebar.
/// - Click on a row navigates to that tab.
/// - Sessions sorted by priority, then state urgency, then time.
/// - Slide-from-right animation on show/hide.
///
/// - SeeAlso: `AgentDashboardViewModel` (drives this view)
/// - SeeAlso: `DashboardSessionRow` (individual row)
/// - SeeAlso: `DashboardStateIndicator` (state -> color/symbol mapping)
struct DashboardPanelView: View {

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

    /// The ViewModel driving this panel.
    @ObservedObject var viewModel: AgentDashboardViewModel

    /// Callback invoked when the user taps the close button.
    /// When provided, overrides the default viewModel.toggleVisibility() behavior.
    var onDismiss: (() -> Void)? = nil

    /// The window hosting this panel. Used for local filtering.
    var currentWindowID: WindowID? = nil

    /// Forced `NSAppearance` for the translucent panel background.
    ///
    /// `nil` preserves the legacy inherit-from-window behaviour; non-nil
    /// values pin the vibrancy view so the dashboard matches the rest of
    /// the chrome when the user forces a transparency theme.
    var vibrancyAppearanceOverride: NSAppearance?

    /// Fixed width of the dashboard panel.
    static let panelWidth: CGFloat = 320

    @State private var selectedScope: WindowScope = .all

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            sessionListView
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
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
        .accessibilityLabel("Agent Dashboard")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Agent Dashboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if currentWindowID != nil {
                scopePicker
            }

            Button(action: {
                if let onDismiss {
                    onDismiss()
                } else {
                    viewModel.toggleVisibility()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close dashboard")
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

    // MARK: - Session List

    private var sessionListView: some View {
        Group {
            if displayedSessions.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(displayedSessions) { session in
                            DashboardSessionRow(
                                session: session,
                                onNavigate: {
                                    viewModel.navigateToSession(session.id)
                                },
                                onSetPriority: { priority in
                                    viewModel.setPriority(priority, for: session.id)
                                }
                            )
                            Divider()
                                .padding(.leading, 32)
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
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(selectedScope == .current ? "No agents in this window" : "No active agents")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(
                selectedScope == .current
                ? "Switch to All Windows to see activity\nfrom the rest of the app."
                : "Run an AI agent in the terminal\nto see its activity here."
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

    private var displayedSessions: [AgentSessionInfo] {
        guard selectedScope == .current, let currentWindowID else {
            return viewModel.sessions
        }
        return viewModel.sessions.filter { $0.windowID == currentWindowID }
    }
}

// MARK: - Visual Effect Background

/// NSVisualEffectView wrapper for SwiftUI.
///
/// Provides the native macOS sidebar material for translucent chrome.
///
/// Pass an explicit `appearanceOverride` to pin the vibrancy view to
/// `.aqua` (light) or `.darkAqua` (dark) independently of the system
/// appearance. Leave it `nil` to inherit from the surrounding view
/// hierarchy, which is the default behaviour.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    /// Optional forced appearance for the vibrancy view.
    ///
    /// `nil` preserves the legacy behaviour (inherit). Non-nil values pin
    /// the view to the supplied appearance so vibrancy renders with the
    /// requested tint regardless of the active system appearance.
    var appearanceOverride: NSAppearance?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = appearanceOverride
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = appearanceOverride
    }
}
