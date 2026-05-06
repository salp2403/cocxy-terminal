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

        func title(using localizer: AppLocalizer) -> String {
            switch self {
            case .all:
                return localizer.string("agentDashboard.scope.allWindows", fallback: "All Windows")
            case .current:
                return localizer.string("agentDashboard.scope.currentWindow", fallback: "This Window")
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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

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
        .glassPanelBackground(vibrancyAppearanceOverride: vibrancyAppearanceOverride)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("agentDashboard.accessibility", fallback: "Agent Dashboard"))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text(Self.localizedPanelTitle(using: localizer))
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
            .accessibilityLabel(localized("agentDashboard.close", fallback: "Close dashboard"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(WindowScope.allCases) { scope in
                Button(scope.title(using: localizer)) {
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
                                },
                                localizer: localizer
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
            Text(localizedEmptyTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text(localizedEmptyMessage)
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

    static func localizedPanelTitle(using localizer: AppLocalizer) -> String {
        localizer.string("agentDashboard.title", fallback: "Agent Dashboard")
    }

    static func localizedCurrentWindowScopeTitle(using localizer: AppLocalizer) -> String {
        WindowScope.current.title(using: localizer)
    }

    private var localizedEmptyTitle: String {
        selectedScope == .current
            ? localized("agentDashboard.empty.current.title", fallback: "No agents in this window")
            : localized("agentDashboard.empty.all.title", fallback: "No active agents")
    }

    private var localizedEmptyMessage: String {
        selectedScope == .current
            ? localized(
                "agentDashboard.empty.current.message",
                fallback: "Switch to All Windows to see activity\nfrom the rest of the app."
            )
            : localized(
                "agentDashboard.empty.all.message",
                fallback: "Run an AI agent in the terminal\nto see its activity here."
            )
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
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
