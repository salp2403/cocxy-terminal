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
/// +-- Welcome Overlay (520x420) --------------------+
/// |                                                  |
/// |   [terminal icon]                                |
/// |   Cocxy Terminal                                 |
/// |   Agent-aware terminal for macOS                 |
/// |                                                  |
/// |   KEYBOARD SHORTCUTS                             |
/// |   ────────────────────────                       |
/// |   Cmd+T           New Tab                        |
/// |   Cmd+W           Close Tab                      |
/// |   ...                                            |
/// |                                                  |
/// |   TIPS                                           |
/// |   - Agent states appear in the sidebar...        |
/// |   ...                                            |
/// |                                                  |
/// |          [ Got it! ]                             |
/// +--------------------------------------------------+
/// ```
///
/// ## Design
///
/// - `.ultraThinMaterial` background with 16pt corner radius.
/// - Keyboard shortcut text in monospaced font for alignment.
/// - Section titles in `CocxyColors.blue`.
/// - Dismiss button with `CocxyColors.blue` background and `CocxyColors.crust` text.
///
/// - SeeAlso: `MainWindowController+Overlays` (overlay lifecycle)
/// - SeeAlso: `CocxyColors` (color palette)
struct WelcomeOverlayView: View {

    /// Callback invoked when the user dismisses the overlay.
    let onDismiss: () -> Void

    /// Fixed overlay width.
    private static let overlayWidth: CGFloat = 520

    /// Fixed overlay height.
    private static let overlayHeight: CGFloat = 420

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dimmed background that dismisses on click.
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            overlayContent
                .frame(width: Self.overlayWidth, height: Self.overlayHeight)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Cocxy Terminal")
    }

    // MARK: - Overlay Content

    private var overlayContent: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 20)
                .padding(.bottom, 12)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    keyboardShortcutsSection
                    tipsSection
                }
                .padding(.horizontal, 28)
            }

            dismissButton
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))

            Text("Cocxy Terminal")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.text))

            Text("Agent-aware terminal for macOS")
                .font(.system(size: 14))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext0))
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
                shortcutRow("Cmd+D", "Split Horizontal")
                shortcutRow("Cmd+Shift+D", "Split Vertical")
                shortcutRow("Cmd+Shift+P", "Command Palette")
                shortcutRow("Cmd+Option+D", "Agent Dashboard")
                shortcutRow("Cmd+Shift+T", "Agent Timeline")
                shortcutRow("Cmd+F", "Search")
                shortcutRow("Cmd+`", "Quick Terminal")
                shortcutRow("Cmd+1-9", "Switch Tab")
                shortcutRow("Esc", "Dismiss Overlay")
            }
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("TIPS")

            VStack(alignment: .leading, spacing: 4) {
                tipRow("Agent states appear in the sidebar \u{2014} watch for the pulsing indicator")
                tipRow("Use Command Palette for quick actions")
                tipRow("Dashboard and Timeline can be open at the same time")
            }
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Got it!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.crust))
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
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

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\u{2022}")
                .font(.system(size: 12))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext1))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
