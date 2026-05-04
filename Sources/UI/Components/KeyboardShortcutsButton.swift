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
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(CocxyColors.swiftUI(CocxyColors.overlay1))
        }
        .buttonStyle(.plain)
        .help(Self.localizedTitle(using: localizer))
        .accessibilityLabel(localizer.string("keyboardShortcuts.show", fallback: "Show keyboard shortcuts"))
        .popover(isPresented: $isShowingPopover, arrowEdge: .top) {
            KeyboardShortcutsPopover(localizer: localizer)
        }
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("keyboardShortcuts.title", fallback: "Keyboard Shortcuts")
    }
}

// MARK: - Shortcuts Popover

/// The popover content showing all keyboard shortcuts organized by section.
private struct KeyboardShortcutsPopover: View {
    let localizer: AppLocalizer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(KeyboardShortcutsButton.localizedTitle(using: localizer))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                ShortcutSection(title: localized("keyboardShortcuts.section.terminal", fallback: "Terminal"), shortcuts: [
                    Shortcut(keys: "Ctrl+C", description: localized("keyboardShortcuts.terminal.interrupt", fallback: "Interrupt process")),
                    Shortcut(keys: "Ctrl+D", description: localized("keyboardShortcuts.terminal.eof", fallback: "EOF / close shell")),
                    Shortcut(keys: "Ctrl+Z", description: localized("keyboardShortcuts.terminal.suspend", fallback: "Suspend process")),
                    Shortcut(keys: "Ctrl+L", description: localized("keyboardShortcuts.terminal.clear", fallback: "Clear screen")),
                    Shortcut(keys: "Ctrl+R", description: localized("keyboardShortcuts.terminal.reverseSearch", fallback: "Reverse search history")),
                    Shortcut(keys: "Ctrl+A", description: localized("keyboardShortcuts.terminal.cursorStart", fallback: "Move cursor to start")),
                    Shortcut(keys: "Ctrl+E", description: localized("keyboardShortcuts.terminal.cursorEnd", fallback: "Move cursor to end")),
                    Shortcut(keys: "Tab", description: localized("keyboardShortcuts.terminal.autocomplete", fallback: "Autocomplete")),
                ])

                ShortcutSection(title: localized("keyboardShortcuts.section.tabs", fallback: "Tabs"), shortcuts: [
                    Shortcut(keys: "Cmd+T", description: localized("keyboardShortcuts.tabs.new", fallback: "New tab")),
                    Shortcut(keys: "Cmd+W", description: localized("keyboardShortcuts.tabs.close", fallback: "Close tab")),
                    Shortcut(keys: "Cmd+Shift+]", description: localized("keyboardShortcuts.tabs.next", fallback: "Next tab")),
                    Shortcut(keys: "Cmd+Shift+[", description: localized("keyboardShortcuts.tabs.previous", fallback: "Previous tab")),
                    Shortcut(keys: "Cmd+1-9", description: localized("keyboardShortcuts.tabs.goTo", fallback: "Go to tab")),
                ])

                ShortcutSection(title: localized("keyboardShortcuts.section.splits", fallback: "Splits"), shortcuts: [
                    Shortcut(keys: "Cmd+D", description: localized("keyboardShortcuts.splits.horizontal", fallback: "Split horizontal")),
                    Shortcut(keys: "Cmd+Shift+D", description: localized("keyboardShortcuts.splits.vertical", fallback: "Split vertical")),
                    Shortcut(keys: "Cmd+Shift+W", description: localized("keyboardShortcuts.splits.close", fallback: "Close split")),
                    Shortcut(keys: "Cmd+Shift+E", description: localized("keyboardShortcuts.splits.equalize", fallback: "Equalize splits")),
                    Shortcut(keys: "Cmd+Opt+Arrow", description: localized("keyboardShortcuts.splits.navigate", fallback: "Navigate splits")),
                ])

                ShortcutSection(title: localized("keyboardShortcuts.section.panels", fallback: "Panels"), shortcuts: [
                    Shortcut(keys: "Cmd+Shift+P", description: localized("keyboardShortcuts.panels.commandPalette", fallback: "Command palette")),
                    Shortcut(keys: "Cmd+Opt+D", description: localized("keyboardShortcuts.panels.agentDashboard", fallback: "Agent dashboard")),
                    Shortcut(keys: "Cmd+Shift+T", description: localized("keyboardShortcuts.panels.agentTimeline", fallback: "Agent timeline")),
                    Shortcut(keys: "Cmd+Shift+I", description: localized("keyboardShortcuts.panels.notifications", fallback: "Notifications")),
                    Shortcut(keys: "Cmd+Shift+B", description: localized("keyboardShortcuts.panels.browser", fallback: "Browser panel")),
                    Shortcut(keys: "Cmd+F", description: localized("keyboardShortcuts.panels.find", fallback: "Find in terminal")),
                ])

                ShortcutSection(title: localized("keyboardShortcuts.section.window", fallback: "Window"), shortcuts: [
                    Shortcut(keys: "Cmd+N", description: localized("keyboardShortcuts.window.new", fallback: "New window")),
                    Shortcut(keys: "Cmd+,", description: localized("keyboardShortcuts.window.preferences", fallback: "Preferences")),
                    Shortcut(keys: "Cmd++/-/0", description: localized("keyboardShortcuts.window.zoom", fallback: "Zoom in/out/reset")),
                    Shortcut(keys: "Esc", description: localized("keyboardShortcuts.window.dismiss", fallback: "Dismiss overlay")),
                ])
            }
            .padding(16)
        }
        .frame(width: 280, height: 420)
        .background(CocxyColors.swiftUI(CocxyColors.base))
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
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
