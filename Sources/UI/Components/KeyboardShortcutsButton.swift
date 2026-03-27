// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeyboardShortcutsButton.swift - Status bar button with keyboard shortcuts popover.

import SwiftUI

// MARK: - Keyboard Shortcuts Button

/// A small button in the status bar that shows a popover with all available
/// keyboard shortcuts when clicked.
///
/// Organized into sections: Terminal, Tabs, Splits, Panels, and Navigation.
/// Each shortcut shows a human-readable key combination and a brief description.
struct KeyboardShortcutsButton: View {

    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
        }
        .buttonStyle(.plain)
        .help("Keyboard Shortcuts")
        .accessibilityLabel("Show keyboard shortcuts")
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            KeyboardShortcutsPopover()
        }
    }
}

// MARK: - Shortcuts Popover

/// The popover content showing all keyboard shortcuts organized by section.
private struct KeyboardShortcutsPopover: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                ShortcutSection(title: "Terminal", shortcuts: [
                    Shortcut(keys: "Ctrl+C", description: "Interrupt process"),
                    Shortcut(keys: "Ctrl+D", description: "EOF / close shell"),
                    Shortcut(keys: "Ctrl+Z", description: "Suspend process"),
                    Shortcut(keys: "Ctrl+L", description: "Clear screen"),
                    Shortcut(keys: "Ctrl+R", description: "Reverse search history"),
                    Shortcut(keys: "Ctrl+A", description: "Move cursor to start"),
                    Shortcut(keys: "Ctrl+E", description: "Move cursor to end"),
                    Shortcut(keys: "Tab", description: "Autocomplete"),
                ])

                ShortcutSection(title: "Tabs", shortcuts: [
                    Shortcut(keys: "Cmd+T", description: "New tab"),
                    Shortcut(keys: "Cmd+W", description: "Close tab"),
                    Shortcut(keys: "Cmd+Shift+]", description: "Next tab"),
                    Shortcut(keys: "Cmd+Shift+[", description: "Previous tab"),
                    Shortcut(keys: "Cmd+1-9", description: "Go to tab"),
                ])

                ShortcutSection(title: "Splits", shortcuts: [
                    Shortcut(keys: "Cmd+D", description: "Split horizontal"),
                    Shortcut(keys: "Cmd+Shift+D", description: "Split vertical"),
                    Shortcut(keys: "Cmd+Shift+W", description: "Close split"),
                    Shortcut(keys: "Cmd+Shift+E", description: "Equalize splits"),
                    Shortcut(keys: "Cmd+Opt+Arrow", description: "Navigate splits"),
                ])

                ShortcutSection(title: "Panels", shortcuts: [
                    Shortcut(keys: "Cmd+Shift+P", description: "Command palette"),
                    Shortcut(keys: "Cmd+Opt+D", description: "Agent dashboard"),
                    Shortcut(keys: "Cmd+Shift+T", description: "Agent timeline"),
                    Shortcut(keys: "Cmd+Shift+I", description: "Notifications"),
                    Shortcut(keys: "Cmd+Shift+B", description: "Browser panel"),
                    Shortcut(keys: "Cmd+F", description: "Find in terminal"),
                ])

                ShortcutSection(title: "Window", shortcuts: [
                    Shortcut(keys: "Cmd+N", description: "New window"),
                    Shortcut(keys: "Cmd+,", description: "Preferences"),
                    Shortcut(keys: "Cmd++/-/0", description: "Zoom in/out/reset"),
                    Shortcut(keys: "Esc", description: "Dismiss overlay"),
                ])
            }
            .padding(16)
        }
        .frame(width: 280, height: 420)
        .background(CocxyColors.swiftUI(CocxyColors.base))
    }
}

// MARK: - Shortcut Section

/// A titled group of keyboard shortcuts.
private struct ShortcutSection: View {
    let title: String
    let shortcuts: [Shortcut]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
                .kerning(1.2)

            ForEach(shortcuts) { shortcut in
                HStack {
                    Text(shortcut.keys)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.blue))
                        .frame(width: 120, alignment: .leading)
                    Text(shortcut.description)
                        .font(.system(size: 11))
                        .foregroundColor(CocxyColors.swiftUI(CocxyColors.subtext1))
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Shortcut Model

/// A single keyboard shortcut entry.
private struct Shortcut: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}
