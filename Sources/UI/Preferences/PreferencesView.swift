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
            KeybindingsEditorView(viewModel: viewModel.keybindingsEditor)
        case .worktrees:
            WorktreesPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
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
    case worktrees
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
        case .worktrees: return "Worktrees"
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
        case .worktrees: return "arrow.triangle.branch"
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
                .disabled(!viewModel.hasUnsavedChanges)
                .help(
                    viewModel.hasUnsavedChanges
                        ? "Save the modified settings to config.toml."
                        : "No settings have changed."
                )

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

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Thicken font strokes", isOn: $viewModel.fontThicken)
                        .help(
                            "Enables CoreText font smoothing during glyph rasterization, "
                            + "which boosts perceived stroke weight. Off by default for a "
                            + "cleaner, thinner look. Turn on if the rendered text looks "
                            + "too thin on your display."
                        )
                    Text(
                        "Boosts stroke weight via font smoothing. Off keeps glyphs "
                        + "thin and crisp; on makes them look heavier."
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
                Picker("Classic tab position", selection: $viewModel.tabPosition) {
                    Text("Left").tag("left")
                    Text("Top").tag("top")
                    Text("Hidden").tag("hidden")
                }
                .disabled(!viewModel.isClassicTabPositionEditable)
                .help(
                    viewModel.isClassicTabPositionEditable
                        ? "Controls the classic tab navigation: left sidebar, top strip, or hidden tabs."
                        : "Aurora uses its own workspace sidebar. This classic tab position is preserved and applies again when Aurora is disabled."
                )

                Text(
                    viewModel.isClassicTabPositionEditable
                        ? "Top shows the classic horizontal tab strip and collapses the left tab sidebar. Hidden keeps only terminal chrome controls visible."
                        : "Aurora is enabled, so Cocxy keeps the workspace sidebar visible and ignores the classic Left/Top/Hidden layout until Aurora is turned off."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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

            Section("Aurora") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable Aurora chrome", isOn: $viewModel.auroraEnabled)
                        .help(
                            "Switches the window chrome to the experimental Aurora "
                            + "sidebar, status bar, and command palette. Save to "
                            + "apply through the normal config hot-reload path."
                        )
                    Text(
                        "Aurora is an opt-in preview of the redesigned chrome. "
                        + "Turn it off to return to the classic sidebar and status bar."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

                Picker(
                    "Glass chrome tint",
                    selection: $viewModel.transparencyChromeTheme
                ) {
                    Text("Follow System").tag(TransparencyChromeTheme.followSystem)
                    Text("Light").tag(TransparencyChromeTheme.light)
                    Text("Dark").tag(TransparencyChromeTheme.dark)
                }
                .help(
                    viewModel.isTransparencyChromeThemeEditable
                        ? "Pin the translucent sidebar, tab strip, and status bar "
                        + "to a light or dark tint independently of macOS. Only "
                        + "visible while the window is transparent."
                        : "Selection is saved but only takes effect while the "
                        + "window is transparent. Lower the background opacity "
                        + "above to see it live."
                )
                .accessibilityLabel("Glass chrome tint")
                .accessibilityHint(
                    "Choose whether the translucent sidebar, tab strip, and "
                    + "status bar follow the system appearance or stay "
                    + "pinned to a light or dark tint."
                )

                if !viewModel.isTransparencyChromeThemeEditable {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(
                            "Your selection is saved, but you'll only see the "
                            + "tint once the window is transparent. Drop the "
                            + "background opacity above 100% to preview it live."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Information: the glass chrome tint is saved but "
                        + "only visible while the window is transparent."
                    )
                } else {
                    Text(
                        "Pins the sidebar, tab strip, and status bar to a "
                        + "light or dark tint independently of macOS, as "
                        + "long as the window stays transparent."
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
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

// MARK: - Worktrees Section

/// Exposes every `[worktree]` option the user can tune safely through
/// the UI. `base-path` and `branch-template` use text fields so users
/// can follow the docstring placeholders without memorising them;
/// `id-length` uses a stepper because it is bounded, and `on-close`
/// uses a Picker because the three states need explicit naming.
struct WorktreesPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Feature") {
                Toggle("Enable worktrees", isOn: $viewModel.worktreeEnabled)
                Text(
                    "When off, every `cocxy worktree-*` CLI verb and palette action refuses with a hint pointing here. Off by default."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Storage") {
                LabeledContent("Base path") {
                    TextField(
                        "~/.cocxy/worktrees",
                        text: $viewModel.worktreeBasePath
                    )
                    .textFieldStyle(.roundedBorder)
                }
                Text(
                    "Final worktree path: <base-path>/<repo-hash>/<id>/. ~ is expanded at use time."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Branch") {
                LabeledContent("Template") {
                    TextField(
                        "cocxy/{agent}/{id}",
                        text: $viewModel.worktreeBranchTemplate
                    )
                    .textFieldStyle(.roundedBorder)
                }
                LabeledContent("Base ref") {
                    TextField(
                        "HEAD",
                        text: $viewModel.worktreeBaseRef
                    )
                    .textFieldStyle(.roundedBorder)
                }
                Text(
                    "Template placeholders: {agent}, {id}, {date}. Base ref accepts HEAD, main, or any git ref."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Stepper(
                    "Random id length: \(viewModel.worktreeIDLength)",
                    value: $viewModel.worktreeIDLength,
                    in: WorktreeConfig.minIDLength...WorktreeConfig.maxIDLength
                )
            }

            Section("Lifecycle") {
                Picker("On tab close", selection: $viewModel.worktreeOnClose) {
                    Text("Keep").tag(WorktreeOnClose.keep.rawValue)
                    Text("Prompt").tag(WorktreeOnClose.prompt.rawValue)
                    Text("Remove if clean").tag(WorktreeOnClose.remove.rawValue)
                }
                Toggle("Open new tab for each worktree", isOn: $viewModel.worktreeOpenInNewTab)
            }

            Section("Integration") {
                Toggle(
                    "Inherit project config from origin repo",
                    isOn: $viewModel.worktreeInheritProjectConfig
                )
                Text(
                    "When on, .cocxy.toml from the origin repo applies inside the worktree when the worktree tree has none."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Toggle("Show worktree badge on tabs", isOn: $viewModel.worktreeShowBadge)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Worktrees")
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
