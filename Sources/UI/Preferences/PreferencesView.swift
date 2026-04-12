// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PreferencesView.swift - SwiftUI preferences window with editable settings.

import SwiftUI
import AppKit

// MARK: - Preferences View

/// SwiftUI preferences window with fully editable settings.
///
/// Organized in sections with a sidebar navigation pattern:
/// - General: shell path, working directory, confirm close
/// - Appearance: theme picker, font family, ligatures, font size slider, padding
/// - Agent Detection: toggles for each detection layer, idle timeout
/// - Notifications: toggles for each notification type
/// - Terminal: runtime protocol settings such as inline images
/// - Keybindings: read-only display of keyboard shortcuts
/// - About: version, license
///
/// ## Usage
///
/// ```swift
/// let vm = PreferencesViewModel(config: configService.current)
/// vm.onSave = { try? configService.reload() }
/// let prefsView = PreferencesView(viewModel: vm)
/// ```
///
/// - SeeAlso: `PreferencesViewModel` for the editable state.
/// - SeeAlso: `CocxyConfig` for the configuration model.
struct PreferencesView: View {

    /// The view model holding editable state for all preferences.
    @ObservedObject var viewModel: PreferencesViewModel

    /// Currently selected section in the sidebar.
    @State private var selectedSection: PreferencesSection = .general

    /// Status message shown after save attempts.
    @State private var saveStatus: String?

    // MARK: - Legacy Init

    /// Backwards-compatible initializer that wraps a read-only config in a view model.
    init(config: CocxyConfig) {
        self.viewModel = PreferencesViewModel(config: config)
    }

    /// Primary initializer with an editable view model.
    init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(PreferencesSection.allCases, selection: $selectedSection) { section in
            Label(section.title, systemImage: section.iconName)
                .tag(section)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 160)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .general:
            EditableGeneralSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .appearance:
            EditableAppearanceSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .agentDetection:
            EditableAgentDetectionSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .notifications:
            EditableNotificationsSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .terminal:
            TerminalPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .keybindings:
            KeybindingsPreferencesSection(viewModel: viewModel)
        case .about:
            AboutPreferencesSection()
        }
    }
}

// MARK: - Preferences Section Enum

/// The sections available in the preferences sidebar.
enum PreferencesSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case agentDetection
    case notifications
    case terminal
    case keybindings
    case about

    var id: String { rawValue }

    /// Human-readable title for the sidebar label.
    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .agentDetection: return "Agent Detection"
        case .notifications: return "Notifications"
        case .terminal: return "Terminal"
        case .keybindings: return "Keybindings"
        case .about: return "About"
        }
    }

    /// SF Symbol name for the sidebar icon.
    var iconName: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush"
        case .agentDetection: return "brain.head.profile"
        case .notifications: return "bell"
        case .terminal: return "terminal"
        case .keybindings: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Save Button

/// Reusable save button that writes the config and shows feedback.
struct PreferencesSaveButton: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Section {
            HStack {
                Button("Save") {
                    do {
                        try viewModel.save()
                        saveStatus = "Settings saved."
                    } catch {
                        saveStatus = "Failed to save: \(error.localizedDescription)"
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        saveStatus = nil
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)

                if let status = saveStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Spacer()

                Button("Open config.toml") {
                    let configPath = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".config/cocxy/config.toml")
                    NSWorkspace.shared.open(configPath)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Editable General Section

/// Editable general preferences (shell, working directory, confirm close).
struct EditableGeneralSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Shell") {
                TextField("Shell path", text: $viewModel.shell)
                    .textFieldStyle(.roundedBorder)
                TextField("Working directory", text: $viewModel.workingDirectory)
                    .textFieldStyle(.roundedBorder)
                Toggle("Confirm before closing", isOn: $viewModel.confirmCloseProcess)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: - Editable Appearance Section

/// Editable appearance preferences (theme, font, padding).
struct EditableAppearanceSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Active theme", selection: $viewModel.theme) {
                    ForEach(viewModel.availableThemes, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section("Font") {
                FontFamilyComboBox(
                    text: $viewModel.fontFamily,
                    options: viewModel.availableFontFamilies
                )
                .frame(height: 24)

                Text("Choose any installed monospaced font. The dropdown is filtered to terminal-safe families, but you can still type a custom family name manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !viewModel.bundledFontFamilies.isEmpty {
                    Text("Included with Cocxy: \(viewModel.bundledFontFamilies.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !viewModel.recommendedFontFamilies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recommended")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.recommendedFontFamilies, id: \.self) { family in
                                    FontQuickPickButton(
                                        family: family,
                                        isSelected: viewModel.fontFamily == family,
                                        isBundled: viewModel.bundledFontFamilies.contains { bundled in
                                            bundled.caseInsensitiveCompare(family) == .orderedSame
                                        }
                                    ) {
                                        viewModel.fontFamily = family
                                    }
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }

                FontPreviewCard(viewModel: viewModel)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable ligatures", isOn: $viewModel.ligatures)
                        .help(
                            "Some fonts combine symbol pairs like --, ==, -> "
                            + "into a single wider glyph. Disable this option "
                            + "if command text such as --dangerously-skip-permissions "
                            + "looks misaligned or crowded in your prompt."
                        )
                    Text(
                        "Some fonts combine symbol pairs like --, ==, -> "
                        + "into a single glyph. Disable if command text "
                        + "appears misaligned in the prompt."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(Int(viewModel.fontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.fontSize, in: 8...32, step: 1)
                }
            }

            Section("Layout") {
                Picker("Tab position", selection: $viewModel.tabPosition) {
                    Text("Left").tag("left")
                    Text("Top").tag("top")
                    Text("Hidden").tag("hidden")
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Window padding")
                        Spacer()
                        Text("\(Int(viewModel.windowPadding)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.windowPadding, in: 0...40, step: 1)
                }
            }

            Section("Transparency") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Background opacity")
                        Spacer()
                        Text("\(Int(viewModel.backgroundOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.backgroundOpacity, in: 0.3...1.0, step: 0.05)
                }
                Text("Lower values enable a glass effect on the sidebar, tab strip, and status bar.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

// MARK: - Font Picker Helpers

/// Native macOS combo box for selecting or typing a font family.
struct FontFamilyComboBox: NSViewRepresentable {
    @Binding var text: String
    let options: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.numberOfVisibleItems = min(max(options.count, 8), 14)
        comboBox.delegate = context.coordinator
        comboBox.setAccessibilityLabel("Font family")
        comboBox.placeholderString = "Font family"
        comboBox.addItems(withObjectValues: options)
        comboBox.stringValue = text
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        if context.coordinator.cachedOptions != options {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: options)
            comboBox.numberOfVisibleItems = min(max(options.count, 8), 14)
            context.coordinator.cachedOptions = options
        }

        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate, NSControlTextEditingDelegate {
        var parent: FontFamilyComboBox
        var cachedOptions: [String]

        init(_ parent: FontFamilyComboBox) {
            self.parent = parent
            self.cachedOptions = parent.options
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            if parent.text != comboBox.stringValue {
                parent.text = comboBox.stringValue
            }
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            if parent.text != comboBox.stringValue {
                parent.text = comboBox.stringValue
            }
        }
    }
}

/// Live preview for the currently selected font family and size.
struct FontPreviewCard: View {
    @ObservedObject var viewModel: PreferencesViewModel

    private var previewFont: Font {
        .custom(viewModel.effectiveFontFamily, size: CGFloat(max(viewModel.fontSize, 12)))
    }

    private var summaryColor: Color {
        viewModel.isSelectedFontInstalled ? .secondary : .orange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("0Oo Il1 | [] {} () => -> == != --")
                .font(previewFont)

            Text("claude --dangerously-skip-permissions")
                .font(previewFont)
                .textSelection(.enabled)

            Text(viewModel.fontResolutionSummary)
                .font(.caption)
                .foregroundStyle(summaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FontQuickPickButton: View {
    let family: String
    let isSelected: Bool
    let isBundled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(family)
                    .font(.caption)
                    .lineLimit(1)
                if isBundled {
                    Text("Bundled")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.22)
                    : Color.secondary.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Editable Agent Detection Section

/// Editable agent detection preferences.
struct EditableAgentDetectionSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Detection") {
                Toggle("Enabled", isOn: $viewModel.agentDetectionEnabled)
                Toggle("OSC notifications", isOn: $viewModel.oscNotifications)
                Toggle("Pattern matching", isOn: $viewModel.patternMatching)
                Toggle("Timing heuristics", isOn: $viewModel.timingHeuristics)
            }

            Section("Timing") {
                Stepper(
                    "Idle timeout: \(viewModel.idleTimeoutSeconds) s",
                    value: $viewModel.idleTimeoutSeconds,
                    in: 1...300
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Agent Detection")
    }
}

// MARK: - Editable Notifications Section

/// Editable notification preferences.
struct EditableNotificationsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("System Notifications") {
                Toggle("macOS notifications", isOn: $viewModel.macosNotifications)
                Toggle("Sound", isOn: $viewModel.sound)
            }

            Section("Visual Indicators") {
                Toggle("Badge on tab", isOn: $viewModel.badgeOnTab)
                Toggle("Flash tab", isOn: $viewModel.flashTab)
                Toggle("Dock badge", isOn: $viewModel.showDockBadge)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Notifications")
    }
}

// MARK: - Terminal Section

struct TerminalPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Core Defaults") {
                LabeledContent("Scrollback lines") {
                    Text("\(viewModel.scrollbackLines)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Cursor style") {
                    Text(viewModel.cursorStyle)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Cursor blink") {
                    Text(viewModel.cursorBlink ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Inline Images") {
                Toggle("Enable Sixel images", isOn: $viewModel.enableSixelImages)
                Toggle("Enable Kitty images", isOn: $viewModel.enableKittyImages)
                Toggle("Enable file transfer", isOn: $viewModel.imageFileTransfer)
                Stepper(
                    "Image memory budget: \(viewModel.imageMemoryLimitMB) MiB",
                    value: $viewModel.imageMemoryLimitMB,
                    in: 1...4096
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal")
    }
}

// MARK: - Keybindings Section (Read-Only)

/// Read-only display of keyboard shortcuts from config.toml.
///
/// Shows all configurable keybindings in monospaced font.
/// Users edit these values directly in config.toml.
struct KeybindingsPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Shortcuts") {
                keybindingRow("New Tab", shortcut: viewModel.keybindingNewTab)
                keybindingRow("Close Tab", shortcut: viewModel.keybindingCloseTab)
                keybindingRow("Next Tab", shortcut: viewModel.keybindingNextTab)
                keybindingRow("Previous Tab", shortcut: viewModel.keybindingPrevTab)
                keybindingRow("Split Vertical", shortcut: viewModel.keybindingSplitVertical)
                keybindingRow("Split Horizontal", shortcut: viewModel.keybindingSplitHorizontal)
                keybindingRow("Go to Attention", shortcut: viewModel.keybindingGotoAttention)
                keybindingRow("Quick Terminal", shortcut: viewModel.keybindingQuickTerminal)
            }

            Section {
                Text("Edit config.toml directly to customize keybindings.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Keybindings")
    }

    private func keybindingRow(_ label: String, shortcut: String) -> some View {
        LabeledContent(label) {
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - About Section

/// Displays application info: version, license, author.
struct AboutPreferencesSection: View {

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Cocxy Terminal")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(CocxyVersion.current)")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Agent-aware terminal for macOS")
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text("Created by Said Arturo Lopez")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("MIT License")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("Zero telemetry. Zero tracking.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .padding(.vertical, 8)

            VStack(spacing: 8) {
                Text("Updates")
                    .font(.headline)

                Button("Check for Updates") {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.sparkleUpdater?.checkForUpdates()
                    }
                }
                .buttonStyle(.borderedProminent)

                Text("Cocxy checks for updates automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle("About")
    }
}
