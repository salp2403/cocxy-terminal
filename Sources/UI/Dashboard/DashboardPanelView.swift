// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DashboardPanelView.swift - SwiftUI panel showing all agent sessions.

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

    /// The ViewModel driving this panel.
    @ObservedObject var viewModel: AgentDashboardViewModel

    /// Callback invoked when the user taps the close button.
    /// When provided, overrides the default viewModel.toggleVisibility() behavior.
    var onDismiss: (() -> Void)? = nil

    /// Fixed width of the dashboard panel.
    static let panelWidth: CGFloat = 320

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
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
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

    // MARK: - Session List

    private var sessionListView: some View {
        Group {
            if viewModel.sessions.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.sessions) { session in
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
            Text("No active agents")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Run an AI agent in the terminal\nto see its activity here.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Visual Effect Background

/// NSVisualEffectView wrapper for SwiftUI.
///
/// Provides the native macOS sidebar material for the dashboard panel background.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
