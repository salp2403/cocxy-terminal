// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WelcomeOverlayView.swift - Welcome overlay shown on first launch and via Help menu.

import SwiftUI

// MARK: - Welcome Overlay View

/// A centered overlay that introduces the user to Cocxy Terminal.
///
/// ## When it appears
///
/// - **First launch:** Automatically shown when `cocxy.welcomeShown` is false.
/// - **Help menu:** Shown when the user presses Cmd+? (Help > Cocxy Terminal Help).
///
/// ## Layout
///
/// ```
/// +-- Welcome Overlay (540x520) --------------------+
/// |                                                  |
/// |   [terminal icon with glow]                      |
/// |   Cocxy Terminal              v0.1.30            |
/// |   Agent-aware terminal for macOS                 |
/// |                                                  |
/// |   HIGHLIGHTS                                     |
/// |   ────────────────────────                       |
/// |   [icon] Agent Detection  [icon] Subagent Panels |
/// |   [icon] Dashboard        [icon] Smart Routing   |
/// |                                                  |
/// |   KEYBOARD SHORTCUTS                             |
/// |   ────────────────────────                       |
/// |   Cmd+T           New Tab                        |
/// |   ...                                            |
/// |                                                  |
/// |          [ Get Started ]                         |
/// +--------------------------------------------------+
/// ```
///
/// ## Design
///
/// - `.ultraThinMaterial` background with 16pt corner radius.
/// - Animated entrance: scale 0.95→1.0 + fade-in (0.35s).
/// - Header icon with subtle gradient glow.
/// - Feature highlights grid before keyboard shortcuts.
/// - Section titles in `CocxyColors.blue` with tracking.
/// - Dismiss button with `CocxyColors.blue` background and `CocxyColors.crust` text.
///
/// - SeeAlso: `MainWindowController+Overlays` (overlay lifecycle)
/// - SeeAlso: `CocxyColors` (color palette)
struct WelcomeOverlayView: View {

    /// Callback invoked when the user dismisses the overlay.
    let onDismiss: () -> Void

    /// Fixed overlay width.
    private static let overlayWidth: CGFloat = 540

    /// Fixed overlay height.
    private static let overlayHeight: CGFloat = 520

    /// Controls the entrance animation state.
    @State private var isVisible = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmed background that dismisses on click.
            Color.black.opacity(isVisible ? 0.35 : 0.0)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .animation(.easeOut(duration: 0.3), value: isVisible)

            overlayContent
                .frame(width: Self.overlayWidth, height: Self.overlayHeight)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                .scaleEffect(isVisible ? 1.0 : 0.95)
                .opacity(isVisible ? 1.0 : 0.0)
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.85),
                    value: isVisible
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Cocxy Terminal")
        .onAppear { isVisible = true }
    }

    // MARK: - Overlay Content

    private var overlayContent: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    highlightsSection
                    keyboardShortcutsSection
                }
                .padding(.horizontal, 28)
            }

            dismissButton
                .padding(.top, 14)
                .padding(.bottom, 18)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                // Subtle glow behind the icon.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                CocxyColors.swiftUI(CocxyColors.blue).opacity(0.25),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        )
                    )
                    .frame(width: 80, height: 80)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Cocxy Terminal")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.text))

                Text(appVersionString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
            }

            Text("Agent-aware terminal for macOS")
                .font(.system(size: 14))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
        }
    }

    // MARK: - Feature Highlights

    private var highlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("HIGHLIGHTS")
            sectionDivider

            let columns = [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ]

            LazyVGrid(columns: columns, spacing: 10) {
                highlightCard(
                    icon: "bolt.fill",
                    color: CocxyColors.blue,
                    title: "Agent Detection",
                    subtitle: "Auto-detects Claude, Codex, Aider and more"
                )
                highlightCard(
                    icon: "rectangle.split.2x1",
                    color: CocxyColors.green,
                    title: "Subagent Panels",
                    subtitle: "Live split panels for each subagent"
                )
                highlightCard(
                    icon: "chart.bar.fill",
                    color: CocxyColors.mauve,
                    title: "Dashboard",
                    subtitle: "Tools, errors, files and activity at a glance"
                )
                highlightCard(
                    icon: "arrow.triangle.branch",
                    color: CocxyColors.teal,
                    title: "Smart Routing",
                    subtitle: "Switch between agents instantly"
                )
            }
        }
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("KEYBOARD SHORTCUTS")
            sectionDivider

            VStack(alignment: .leading, spacing: 4) {
                shortcutRow("Cmd+T", "New Tab")
                shortcutRow("Cmd+W", "Close Tab")
                shortcutRow("Cmd+D", "Split Side by Side")
                shortcutRow("Cmd+Shift+D", "Split Stacked")
                shortcutRow("Cmd+Shift+P", "Command Palette")
                shortcutRow("Cmd+Option+A", "Agent Dashboard")
                shortcutRow("Cmd+Shift+T", "Agent Timeline")
                shortcutRow("Cmd+F", "Search")
                shortcutRow("Cmd+`", "Quick Terminal")
                shortcutRow("Cmd+1-9", "Switch Tab")
                shortcutRow("Esc", "Dismiss Overlay")
            }
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Get Started")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.crust))
                .padding(.horizontal, 28)
                .padding(.vertical, 10)
                .background(CocxyColors.swiftUI(CocxyColors.blue))
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss welcome overlay")
    }

    // MARK: - Reusable Components

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
            .tracking(1.2)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(CocxyColors.swiftUI(CocxyColors.surface1))
            .frame(height: 1)
    }

    private func shortcutRow(_ shortcut: String, _ description: String) -> some View {
        HStack(spacing: 0) {
            Text(shortcut)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.lavender))
                .frame(width: 140, alignment: .leading)

            Text(description)
                .font(.system(size: 12))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext1))
        }
    }

    private func highlightCard(
        icon: String,
        color: NSColor,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(CocxyColors.swiftUI(color))
                .frame(width: 28, height: 28)
                .background(CocxyColors.swiftUI(color).opacity(0.12))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.text))

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CocxyColors.swiftUI(CocxyColors.surface0).opacity(0.4))
        .cornerRadius(8)
    }

    // MARK: - Helpers

    private var appVersionString: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "dev"
        return "v\(version)"
    }
}
