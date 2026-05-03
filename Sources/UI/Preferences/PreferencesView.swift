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
/// - Agent Mode: local-first built-in agent provider and safety settings
/// - Code Review: review panel visibility behaviour
/// - Notifications: toggles for each notification type
/// - Terminal: runtime protocol settings such as inline images
/// - Editor: editor-only input preferences
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

    /// Starts the interactive `gh auth login` flow from the owning
    /// window controller. Nil when the view is constructed in tests or
    /// previews without a live terminal window.
    private let onGitHubSignIn: (() -> Void)?

    /// Opens the GitHub CLI install guide. Kept injectable so tests and
    /// future windows can swap the side effect without touching the
    /// preference section.
    private let onOpenGitHubCLIInstallGuide: (() -> Void)?

    /// Shared plugin manager from the app delegate, used by the Plugins section.
    private let pluginManager: PluginManager?

    /// Currently selected section in the sidebar.
    @State private var selectedSection: PreferencesSection = .general

    /// Status message shown after save attempts.
    @State private var saveStatus: String?

    // MARK: - Legacy Init

    /// Backwards-compatible initializer that wraps a read-only config in a view model.
    init(
        config: CocxyConfig,
        onGitHubSignIn: (() -> Void)? = nil,
        onOpenGitHubCLIInstallGuide: (() -> Void)? = nil,
        pluginManager: PluginManager? = nil
    ) {
        self.viewModel = PreferencesViewModel(config: config)
        self.onGitHubSignIn = onGitHubSignIn
        self.onOpenGitHubCLIInstallGuide = onOpenGitHubCLIInstallGuide
        self.pluginManager = pluginManager
    }

    /// Primary initializer with an editable view model.
    init(
        viewModel: PreferencesViewModel,
        onGitHubSignIn: (() -> Void)? = nil,
        onOpenGitHubCLIInstallGuide: (() -> Void)? = nil,
        pluginManager: PluginManager? = nil
    ) {
        self.viewModel = viewModel
        self.onGitHubSignIn = onGitHubSignIn
        self.onOpenGitHubCLIInstallGuide = onOpenGitHubCLIInstallGuide
        self.pluginManager = pluginManager
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
        case .agentMode:
            AgentModePreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .mcpServers:
            MCPServersPreferencesSection(viewModel: viewModel)
        case .voice:
            VoicePreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .activity:
            ActivityPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .sessionReplay:
            SessionReplayPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .iCloudSync:
            ICloudSyncPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .codeReview:
            CodeReviewPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .notifications:
            EditableNotificationsSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .terminal:
            TerminalPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .languageServers:
            LanguageServersPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .editor:
            EditorPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .keybindings:
            KeybindingsEditorView(viewModel: viewModel.keybindingsEditor)
        case .worktrees:
            WorktreesPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .plugins:
            PluginMarketplaceView(pluginManager: pluginManager)
        case .github:
            GitHubPreferencesSection(
                viewModel: viewModel,
                saveStatus: $saveStatus,
                onGitHubSignIn: onGitHubSignIn,
                onOpenGitHubCLIInstallGuide: onOpenGitHubCLIInstallGuide
            )
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
    case agentMode
    case mcpServers
    case voice
    case activity
    case sessionReplay
    case iCloudSync
    case codeReview
    case notifications
    case terminal
    case languageServers
    case editor
    case keybindings
    case worktrees
    case plugins
    case github
    case about

    var id: String { rawValue }

    /// Human-readable title for the sidebar label.
    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .agentDetection: return "Agent Detection"
        case .agentMode: return "Agent Mode"
        case .mcpServers: return "MCP Servers"
        case .voice: return "Voice"
        case .activity: return "Activity"
        case .sessionReplay: return "Session Replay"
        case .iCloudSync: return "iCloud Sync"
        case .codeReview: return "Code Review"
        case .notifications: return "Notifications"
        case .terminal: return "Terminal"
        case .languageServers: return "Language Servers"
        case .editor: return "Editor"
        case .keybindings: return "Keybindings"
        case .worktrees: return "Worktrees"
        case .plugins: return "Plugins"
        case .github: return "GitHub"
        case .about: return "About"
        }
    }

    /// SF Symbol name for the sidebar icon.
    var iconName: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "paintbrush"
        case .agentDetection: return "brain.head.profile"
        case .agentMode: return "sparkles"
        case .mcpServers: return "link"
        case .voice: return "mic"
        case .activity: return "chart.bar"
        case .sessionReplay: return "record.circle"
        case .iCloudSync: return "icloud"
        case .codeReview: return "doc.text.magnifyingglass"
        case .notifications: return "bell"
        case .terminal: return "terminal"
        case .languageServers: return "curlybraces.square"
        case .editor: return "text.cursor"
        case .keybindings: return "keyboard"
        case .worktrees: return "arrow.triangle.branch"
        case .plugins: return "shippingbox"
        case .github: return "arrow.triangle.pull"
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
                Picker("Sidebar density", selection: $viewModel.auroraSidebarDisplayMode) {
                    ForEach(AuroraSidebarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.preferencesLabel).tag(mode)
                    }
                }
                Picker("Sidebar row detail", selection: $viewModel.auroraSidebarPrimaryInfo) {
                    ForEach(AuroraSidebarPrimaryInfo.allCases, id: \.self) { info in
                        Text(info.preferencesLabel).tag(info)
                    }
                }
            }

            Section("Status bar") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        "Show rate-limit indicator",
                        isOn: $viewModel.rateLimitIndicatorEnabled
                    )
                    .help(
                        "Displays a status-bar pill with locally-estimated "
                        + "usage for the active agent. The pill only appears "
                        + "when the active agent has a registered local "
                        + "provider with available data — turning this off "
                        + "hides it for every agent."
                    )
                    Text(
                        "Reads only local files the agent's CLI already keeps "
                        + "on disk. No data leaves your machine."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Notes") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable workspace notes", isOn: $viewModel.notesEnabled)
                        .help("Shows the Notes panel and enables the configured notes shortcut.")

                    Picker("Format", selection: $viewModel.notesFormat) {
                        ForEach(NoteFormat.allCases, id: \.rawValue) { format in
                            Text(format.rawValue).tag(format.rawValue)
                        }
                    }
                    .disabled(!viewModel.notesEnabled)

                    Picker("Search", selection: $viewModel.notesSearchEngine) {
                        ForEach(NoteSearchEngineKind.allCases, id: \.rawValue) { engine in
                            Text(engine.rawValue).tag(engine.rawValue)
                        }
                    }
                    .disabled(!viewModel.notesEnabled)

                    TextField("Storage directory", text: $viewModel.notesStorageDir)
                        .disabled(!viewModel.notesEnabled)

                    TextField("Shortcut", text: $viewModel.notesShortcut)
                        .disabled(!viewModel.notesEnabled)

                    Toggle("Auto-save notes", isOn: $viewModel.notesAutoSave)
                        .disabled(!viewModel.notesEnabled)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Auto-save interval")
                            Spacer()
                            Text("\(viewModel.notesAutoSaveIntervalSeconds, specifier: "%.1f") s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $viewModel.notesAutoSaveIntervalSeconds,
                            in: 0.1...60,
                            step: 0.1
                        )
                        .disabled(!viewModel.notesEnabled || !viewModel.notesAutoSave)
                    }

                    Text("Notes are stored per workspace under the configured local folder.")
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

// MARK: - Agent Mode Section

/// Editable built-in Agent Mode preferences.
struct AgentModePreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Feature") {
                Toggle("Enable Agent Mode", isOn: $viewModel.agentModeEnabled)
                    .help("Enables the built-in local Agent Mode entry points.")

                Toggle("Auto mode", isOn: $viewModel.agentAutoMode)
                    .help("Allows the agent loop to continue after approved actions without changing write or command approval rules.")

                Toggle("Confirm computer actions", isOn: $viewModel.agentComputerUseConfirm)
                    .help("Requires explicit approval before local mouse, keyboard, or screenshot actions run.")
            }

            Section("Provider") {
                Picker("Preferred provider", selection: $viewModel.agentPreferredProvider) {
                    ForEach(AgentProviderKind.allCases, id: \.self) { provider in
                        Text(providerTitle(provider)).tag(provider)
                    }
                }

                Text(providerDetail(viewModel.agentPreferredProvider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("API Key") {
                if viewModel.agentPreferredProvider.requiresAPIKey {
                    SecureField("API key", text: $viewModel.agentAPIKeyDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save API Key") {
                            saveAPIKey()
                        }
                        .disabled(trimmedAPIKeyDraft.isEmpty)

                        Button("Delete Saved Key") {
                            deleteAPIKey()
                        }
                        .disabled(!viewModel.hasSavedAgentAPIKey(for: viewModel.agentPreferredProvider))

                        Spacer()
                    }

                    Text(
                        viewModel.hasSavedAgentAPIKey(for: viewModel.agentPreferredProvider)
                            ? "A key is saved in the macOS Keychain for this provider."
                            : "No key is saved for this provider."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Foundation Models does not use an API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let status = viewModel.agentAPIKeyStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Limits") {
                Stepper(
                    "Max iterations: \(viewModel.agentMaxIterations)",
                    value: $viewModel.agentMaxIterations,
                    in: AgentModeConfig.minMaxIterations...AgentModeConfig.maxMaxIterations
                )
            }

            Section("Storage") {
                TextField("Conversation storage", text: $viewModel.agentConversationStorageDir)
                    .textFieldStyle(.roundedBorder)

                Picker("Conversation encryption", selection: $viewModel.agentConversationEncryption) {
                    ForEach(AgentConversationEncryptionMode.allCases, id: \.self) { mode in
                        Text(conversationEncryptionTitle(mode)).tag(mode)
                    }
                }

                if viewModel.agentConversationEncryption == .masterPassword {
                    SecureField("Master password", text: $viewModel.agentConversationMasterPasswordDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save Master Password") {
                            saveConversationMasterPassword()
                        }
                        .disabled(trimmedConversationMasterPasswordDraft.isEmpty)

                        Button("Delete Saved Password") {
                            deleteConversationMasterPassword()
                        }
                        .disabled(!viewModel.hasSavedAgentConversationMasterPassword())

                        Spacer()
                    }

                    Text(
                        viewModel.hasSavedAgentConversationMasterPassword()
                            ? "A master password is saved in the macOS Keychain."
                            : "No master password is saved."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let status = viewModel.agentConversationMasterPasswordStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Agent Mode")
    }

    private var trimmedAPIKeyDraft: String {
        viewModel.agentAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedConversationMasterPasswordDraft: String {
        viewModel.agentConversationMasterPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveAPIKey() {
        do {
            try viewModel.saveAgentAPIKeyDraft(for: viewModel.agentPreferredProvider)
        } catch {
            viewModel.agentAPIKeyStatus = "Failed to save API key: \(error.localizedDescription)"
        }
    }

    private func deleteAPIKey() {
        do {
            try viewModel.deleteAgentAPIKey(for: viewModel.agentPreferredProvider)
        } catch {
            viewModel.agentAPIKeyStatus = "Failed to delete API key: \(error.localizedDescription)"
        }
    }

    private func saveConversationMasterPassword() {
        do {
            try viewModel.saveAgentConversationMasterPasswordDraft()
        } catch {
            viewModel.agentConversationMasterPasswordStatus = "Failed to save master password: \(error.localizedDescription)"
        }
    }

    private func deleteConversationMasterPassword() {
        do {
            try viewModel.deleteAgentConversationMasterPassword()
        } catch {
            viewModel.agentConversationMasterPasswordStatus = "Failed to delete master password: \(error.localizedDescription)"
        }
    }

    private func conversationEncryptionTitle(_ mode: AgentConversationEncryptionMode) -> String {
        switch mode {
        case .disabled:
            return "Disabled"
        case .masterPassword:
            return "Master Password"
        }
    }

    private func providerTitle(_ provider: AgentProviderKind) -> String {
        switch provider {
        case .foundationModelsOnDevice:
            return "Foundation Models"
        case .anthropic:
            return "Anthropic"
        case .openai:
            return "OpenAI"
        case .google:
            return "Google"
        }
    }

    private func providerDetail(_ provider: AgentProviderKind) -> String {
        switch provider {
        case .foundationModelsOnDevice:
            return "Runs on device when supported. If unavailable, Cocxy asks you to choose another provider instead of falling back silently."
        case .anthropic, .openai, .google:
            return "Uses your provider API key from the macOS Keychain. Requests go directly from this Mac to the selected provider."
        }
    }
}

// MARK: - MCP Servers Section

/// Editable user-managed MCP server configuration.
struct MCPServersPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section("Config File") {
                LabeledContent("Path") {
                    Text(viewModel.mcpConfigPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Reload") {
                        viewModel.reloadMCPConfig()
                    }

                    Button("Open Folder") {
                        let url = URL(fileURLWithPath: viewModel.mcpConfigPath)
                            .deletingLastPathComponent()
                        NSWorkspace.shared.open(url)
                    }

                    Spacer()
                }
            }

            Section("Configured Servers") {
                if viewModel.mcpConfiguredServers.isEmpty {
                    Text("No MCP servers configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.mcpConfiguredServers) { server in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(server.displayName)
                                .font(.headline)
                            Text(server.id)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(viewModel.mcpServerSummary(for: server))
                                .font(.caption)
                                .foregroundStyle(server.enabled ? .secondary : .tertiary)
                        }
                    }
                }
            }

            Section("JSON") {
                TextEditor(text: $viewModel.mcpConfigText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 240)

                HStack {
                    Button("Validate") {
                        validate()
                    }

                    Button("Save MCP Config") {
                        save()
                    }
                    .disabled(!viewModel.hasUnsavedMCPConfigChanges)

                    Spacer()
                }

                if let status = viewModel.mcpConfigStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("MCP Servers")
    }

    private func validate() {
        do {
            try viewModel.validateMCPConfigDraft()
        } catch {
            viewModel.mcpConfigStatus = "Invalid MCP config: \(error.localizedDescription)"
        }
    }

    private func save() {
        do {
            try viewModel.saveMCPConfig()
        } catch {
            viewModel.mcpConfigStatus = "Failed to save MCP config: \(error.localizedDescription)"
        }
    }
}

// MARK: - Voice Section

/// Editable local Voice input preferences.
struct VoicePreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Feature") {
                Toggle("Enable Voice input", isOn: $viewModel.voiceEnabled)
                    .help("Enables local dictation entry points when supported by macOS.")
            }

            Section("Locale") {
                Picker("Recognition locale", selection: $viewModel.voiceLocaleIdentifier) {
                    Text(systemLocaleTitle).tag(VoiceConfig.systemLocaleIdentifier)
                    ForEach(viewModel.availableVoiceLocales) { option in
                        Text(optionTitle(option)).tag(option.identifier)
                    }
                }

                Text(resolutionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Voice")
    }

    private var systemLocaleTitle: String {
        let resolution = viewModel.resolvedVoiceLocale
        guard viewModel.voiceLocaleIdentifier == VoiceConfig.systemLocaleIdentifier,
              let localeIdentifier = resolution.localeIdentifier
        else {
            return "System"
        }
        return "System (\(localeIdentifier))"
    }

    private var resolutionDetail: String {
        switch viewModel.resolvedVoiceLocale.source {
        case .systemExact:
            return "Using the current system locale."
        case .systemLanguageFallback:
            return "Using the nearest supported locale for the current system language."
        case .systemUnsupportedFallback:
            return "The current system language is not listed by Speech; using the first supported local recognizer."
        case .manualOverride:
            return "Using the selected locale override."
        case .manualUnsupportedSystemFallback(let requested):
            return "\(requested) is not listed by Speech; using the system locale fallback."
        case .unavailable:
            return "macOS did not report any local Speech recognition locales."
        }
    }

    private func optionTitle(_ option: VoiceLocaleOption) -> String {
        "\(option.localizedName) (\(option.identifier))"
    }
}

// MARK: - Activity Section

/// Editable local Activity dashboard privacy preferences.
struct ActivityPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Enable local Activity dashboard", isOn: $viewModel.activityTrackingEnabled)
                    .help("Stores activity data locally for dashboards and manual export.")
                Toggle("Track token usage and estimated costs", isOn: $viewModel.activityCostTrackingEnabled)
                    .disabled(!viewModel.activityTrackingEnabled)
                    .help("Uses local token counts and model rates; no data is uploaded.")
            }

            Section("Cost Rates") {
                LabeledContent("Input / 1M tokens") {
                    TextField(
                        "0",
                        value: $viewModel.activityInputCostMicrosPerMillionTokens,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.activityTrackingEnabled || !viewModel.activityCostTrackingEnabled)
                }
                LabeledContent("Output / 1M tokens") {
                    TextField(
                        "0",
                        value: $viewModel.activityOutputCostMicrosPerMillionTokens,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.activityTrackingEnabled || !viewModel.activityCostTrackingEnabled)
                }
                Text("Rates are micro-dollars per one million tokens and stay local in config.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Storage") {
                LabeledContent("Local directory", value: ActivityConfig.defaults.storageDirectory)
                Text("Disable the Activity dashboard to stop future writes. Existing local records can be cleared from the Activity dashboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Activity")
    }
}

// MARK: - Session Replay Section

/// Editable local session replay privacy preferences.
struct SessionReplayPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Privacy") {
                Toggle("Enable Session Replay", isOn: $viewModel.sessionReplayEnabled)
                Toggle("Record new terminal sessions automatically", isOn: $viewModel.sessionReplayAutoRecord)
                    .disabled(!viewModel.sessionReplayEnabled)
                Toggle("Allow automatic recording", isOn: $viewModel.sessionReplayConsentGranted)
                    .disabled(!viewModel.sessionReplayEnabled || !viewModel.sessionReplayAutoRecord)
            }

            Section("Storage") {
                TextField("Storage directory", text: $viewModel.sessionReplayStorageDirectory)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.sessionReplayEnabled)
                LabeledContent("Max recording bytes") {
                    TextField(
                        "536870912",
                        value: $viewModel.sessionReplayMaxRecordingBytes,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.sessionReplayEnabled)
                }
                Text("Recordings stay local unless exported manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Session Replay")
    }
}

// MARK: - iCloud Sync Section

/// Editable encrypted iCloud Drive sync preferences.
struct ICloudSyncPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Opt-In") {
                Toggle("Enable iCloud Drive sync", isOn: $viewModel.iCloudSyncEnabled)
                    .help("Exports selected local Cocxy artifacts to the user's iCloud Drive.")
            }

            Section("Encryption") {
                Toggle("Encrypt synced artifacts", isOn: .constant(true))
                    .disabled(true)
                    .help("Encryption is required for iCloud Sync.")

                SecureField("Master password", text: $viewModel.iCloudSyncMasterPasswordDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save Master Password") {
                        saveICloudSyncMasterPassword()
                    }
                    .disabled(trimmedICloudSyncMasterPasswordDraft.isEmpty)

                    Button("Delete Saved Password") {
                        deleteICloudSyncMasterPassword()
                    }
                    .disabled(!viewModel.hasSavedICloudSyncMasterPassword())

                    Spacer()
                }

                Text(
                    viewModel.hasSavedICloudSyncMasterPassword()
                        ? "A master password is saved in the macOS Keychain."
                        : "No master password is saved."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let status = viewModel.iCloudSyncMasterPasswordStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Location") {
                TextField("Folder name", text: $viewModel.iCloudSyncDirectoryName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.iCloudSyncEnabled)
                LabeledContent("Conflict policy", value: ICloudSyncConflictPolicy.manual.rawValue)
            }

            Section("Artifacts") {
                ForEach(ICloudSyncArtifactKind.allCases, id: \.self) { kind in
                    Toggle(
                        iCloudSyncArtifactTitle(kind),
                        isOn: Binding(
                            get: { viewModel.isICloudSyncArtifactKindEnabled(kind) },
                            set: { viewModel.setICloudSyncArtifactKind(kind, enabled: $0) }
                        )
                    )
                    .disabled(!viewModel.iCloudSyncEnabled)
                }
            }

            Section("Manual Export") {
                Button("Export Encrypted Artifacts") {
                    exportICloudSyncArtifacts()
                }
                .disabled(!viewModel.iCloudSyncEnabled || !viewModel.hasSavedICloudSyncMasterPassword())

                if let status = viewModel.iCloudSyncExportStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Manual Import") {
                Button("Import Remote Artifacts") {
                    importICloudSyncArtifacts()
                }
                .disabled(!viewModel.iCloudSyncEnabled || !viewModel.hasSavedICloudSyncMasterPassword())

                if let status = viewModel.iCloudSyncImportStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if !viewModel.iCloudSyncConflicts.isEmpty {
                    ForEach(Array(viewModel.iCloudSyncConflicts.enumerated()), id: \.offset) { _, conflict in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conflict.remote.relativePath)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("Local and remote versions differ.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("Keep Local") {
                                    resolveICloudSyncConflict(conflict, resolution: .keepLocal)
                                }

                                Button("Use Remote") {
                                    resolveICloudSyncConflict(conflict, resolution: .useRemote)
                                }
                                .disabled(!viewModel.hasSavedICloudSyncMasterPassword())
                            }
                        }
                    }
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("iCloud Sync")
    }

    private func iCloudSyncArtifactTitle(_ kind: ICloudSyncArtifactKind) -> String {
        switch kind {
        case .notebooks: return "Notebooks"
        case .workflows: return "Workflows"
        case .skills: return "Skills"
        case .settings: return "Settings"
        case .themes: return "Themes"
        }
    }

    private var trimmedICloudSyncMasterPasswordDraft: String {
        viewModel.iCloudSyncMasterPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveICloudSyncMasterPassword() {
        do {
            try viewModel.saveICloudSyncMasterPasswordDraft()
        } catch {
            viewModel.iCloudSyncMasterPasswordStatus = "Failed to save master password: \(error.localizedDescription)"
        }
    }

    private func deleteICloudSyncMasterPassword() {
        do {
            try viewModel.deleteICloudSyncMasterPassword()
        } catch {
            viewModel.iCloudSyncMasterPasswordStatus = "Failed to delete master password: \(error.localizedDescription)"
        }
    }

    private func exportICloudSyncArtifacts() {
        do {
            _ = try viewModel.exportICloudSyncArtifactsNow()
        } catch {
            viewModel.iCloudSyncExportStatus = "Failed to export encrypted artifacts: \(error.localizedDescription)"
        }
    }

    private func importICloudSyncArtifacts() {
        do {
            _ = try viewModel.importICloudSyncArtifactsNow()
        } catch {
            viewModel.iCloudSyncImportStatus = "Failed to import encrypted artifacts: \(error.localizedDescription)"
        }
    }

    private func resolveICloudSyncConflict(
        _ conflict: ICloudSyncImportConflict,
        resolution: ICloudSyncConflictResolution
    ) {
        do {
            _ = try viewModel.resolveICloudSyncConflict(conflict, resolution: resolution)
        } catch {
            viewModel.iCloudSyncImportStatus = "Failed to resolve conflict: \(error.localizedDescription)"
        }
    }
}

// MARK: - Code Review Section

/// Editable Code Review panel preferences.
struct CodeReviewPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Panel") {
                Toggle(
                    "Auto-show review panel when an agent session ends",
                    isOn: $viewModel.codeReviewAutoShowOnSessionEnd
                )
                Text(
                    "When on, Cocxy opens the Code Review panel automatically after a tracked agent session produces changes. Turn it off if you prefer opening the panel manually with Cmd+Option+R."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Code Review")
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
                Toggle("Enable iTerm2 images", isOn: $viewModel.enableITerm2Images)
                Toggle("Enable file transfer", isOn: $viewModel.imageFileTransfer)
                Stepper(
                    "Image memory budget: \(viewModel.imageMemoryLimitMB) MiB",
                    value: $viewModel.imageMemoryLimitMB,
                    in: 1...4096
                )
                TextField("Disk cache directory", text: $viewModel.imageDiskCacheDirectory)
                Stepper(
                    "Disk cache budget: \(viewModel.imageDiskCacheLimitMB) MiB",
                    value: $viewModel.imageDiskCacheLimitMB,
                    in: 1...8192
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Terminal")
    }
}

// MARK: - Language Servers Section

/// Editable opt-in gates for local Language Server Protocol clients.
struct LanguageServersPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Feature") {
                Toggle("Enable language servers", isOn: $viewModel.lspEnabled)
                    .help("Starts only the local language servers selected below.")
                Text(
                    "Cocxy never auto-installs language servers. Enabled servers run locally and receive opened document text plus workspace URIs."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Languages") {
                ForEach(viewModel.availableLSPLanguages, id: \.languageID) { server in
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(
                            isOn: Binding(
                                get: {
                                    viewModel.isLSPLanguageEnabled(server.languageID)
                                },
                                set: { enabled in
                                    viewModel.setLSPLanguage(
                                        server.languageID,
                                        enabled: enabled
                                    )
                                }
                            )
                        ) {
                            Text(server.displayName)
                        }

                        Text(languageDetail(for: server))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(installDetail(for: server))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Language Servers")
    }

    private func languageDetail(for server: LSPServerConfiguration) -> String {
        let extensions = server.fileExtensions.map { ".\($0)" }.joined(separator: ", ")
        return "\(server.languageID) - \(extensions)"
    }

    private func installDetail(for server: LSPServerConfiguration) -> String {
        if let command = server.installSuggestion.command {
            return command
        }
        return server.installSuggestion.message
    }
}

// MARK: - Editor Section

/// Editable editor-only preferences.
struct EditorPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section("Input") {
                Toggle("Enable Vim mode", isOn: $viewModel.vimEnabled)
                    .help("Routes editor text input through the Vim state machine.")
                Text("Applies only to editor tabs. Terminal panes keep standard shell input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Inline Completions") {
                Toggle("Enable inline AI completions", isOn: $viewModel.completionInlineAIEnabled)
                    .help("Uses the local Foundation Models provider when available.")

                HStack {
                    Text("Provider")
                    Spacer()
                    Text("Foundation Models")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Idle delay")
                    Slider(
                        value: $viewModel.completionIdleDelaySeconds,
                        in: CompletionConfig.minIdleDelaySeconds...CompletionConfig.maxIdleDelaySeconds,
                        step: 0.05
                    )
                    Text("\(viewModel.completionIdleDelaySeconds, specifier: "%.2f")s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Stepper(
                    value: $viewModel.completionMaxContextUTF16Length,
                    in: CompletionConfig.minContextUTF16Length...CompletionConfig.maxContextUTF16Length,
                    step: 256
                ) {
                    Text("Context window: \(viewModel.completionMaxContextUTF16Length) UTF-16")
                }
            }

            Section("Completion Languages") {
                ForEach(viewModel.availableCompletionLanguageIDs, id: \.self) { languageID in
                    Toggle(
                        languageID,
                        isOn: Binding(
                            get: {
                                viewModel.isCompletionLanguageEnabled(languageID)
                            },
                            set: { enabled in
                                viewModel.setCompletionLanguage(languageID, enabled: enabled)
                            }
                        )
                    )
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("Editor")
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

// MARK: - GitHub Section (v0.1.84)

/// Editable settings for the inline GitHub pane and `cocxy github`
/// CLI verbs.
///
/// Authentication is handled by the user's `gh auth status`; Cocxy
/// never stores tokens of its own, so the UI surfaces only the knobs
/// that affect request shape and auto-refresh cadence.
struct GitHubPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?
    var onGitHubSignIn: (() -> Void)?
    var onOpenGitHubCLIInstallGuide: (() -> Void)?

    var body: some View {
        Form {
            Section("Feature") {
                Toggle("Enable GitHub pane", isOn: $viewModel.githubEnabled)
                Text(
                    "Powers Cmd+Option+G and the `cocxy github` CLI verbs. Turning this off stops every `gh` subprocess invocation and hides the pane. Authentication is delegated to `gh auth status`; Cocxy never stores GitHub tokens of its own."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Authentication") {
                Button {
                    onGitHubSignIn?()
                } label: {
                    Label("Sign In with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(onGitHubSignIn == nil)
                .help("Open a Cocxy tab and run gh auth login.")

                Button {
                    openGitHubCLIInstallGuide()
                } label: {
                    Label("Install GitHub CLI", systemImage: "arrow.down.circle")
                }
                .help("Open the official GitHub CLI install guide.")

                Text(
                    "Cocxy uses the official GitHub CLI login. Tokens stay in gh/keychain storage; Cocxy only reads `gh auth status`."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Refresh") {
                Stepper(
                    "Auto-refresh every \(viewModel.githubAutoRefreshInterval) s",
                    value: $viewModel.githubAutoRefreshInterval,
                    in: GitHubConfig.minAutoRefreshInterval...GitHubConfig.maxAutoRefreshInterval,
                    step: 15
                )
                Text(
                    "Seconds between silent background refreshes while the pane is visible. Set to 0 to disable auto-refresh entirely (the pane still reloads on manual toggle)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Stepper(
                    "Max rows per list: \(viewModel.githubMaxItems)",
                    value: $viewModel.githubMaxItems,
                    in: GitHubConfig.minMaxItems...GitHubConfig.maxMaxItems,
                    step: 5
                )
                Text(
                    "Maximum rows requested from `gh pr list` / `gh issue list` on each refresh. Clamped to the upstream gh CLI hard cap."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Filters") {
                Toggle("Include draft pull requests", isOn: $viewModel.githubIncludeDrafts)
                Text(
                    "When off, drafts are filtered out client-side because `gh` does not expose a --hide-drafts flag."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Picker("Default state", selection: $viewModel.githubDefaultState) {
                    Text("Open").tag("open")
                    Text("Closed").tag("closed")
                    Text("Merged (PRs only)").tag("merged")
                    Text("All").tag("all")
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle("GitHub")
    }

    private func openGitHubCLIInstallGuide() {
        if let onOpenGitHubCLIInstallGuide {
            onOpenGitHubCLIInstallGuide()
            return
        }
        guard let url = URL(string: "https://cli.github.com/") else { return }
        NSWorkspace.shared.open(url)
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

private extension AuroraSidebarDisplayMode {
    var preferencesLabel: String {
        switch self {
        case .detailed: return "Detailed"
        case .summary: return "Summary"
        case .compact: return "Compact"
        }
    }
}

private extension AuroraSidebarPrimaryInfo {
    var preferencesLabel: String {
        switch self {
        case .state: return "State"
        case .directory: return "Directory"
        case .process: return "Process"
        case .command: return "Command"
        }
    }
}
