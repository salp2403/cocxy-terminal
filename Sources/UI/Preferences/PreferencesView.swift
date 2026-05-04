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
            Label(section.localizedTitle(viewModel), systemImage: section.iconName)
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
        case .backup:
            BackupPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
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
            KeybindingsEditorView(
                viewModel: viewModel.keybindingsEditor,
                localizer: viewModel.appLocalizer()
            )
        case .worktrees:
            WorktreesPreferencesSection(viewModel: viewModel, saveStatus: $saveStatus)
        case .plugins:
            PluginMarketplaceView(
                pluginManager: pluginManager,
                localizer: viewModel.appLocalizer()
            )
        case .github:
            GitHubPreferencesSection(
                viewModel: viewModel,
                saveStatus: $saveStatus,
                onGitHubSignIn: onGitHubSignIn,
                onOpenGitHubCLIInstallGuide: onOpenGitHubCLIInstallGuide
            )
        case .about:
            AboutPreferencesSection(viewModel: viewModel)
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
    case backup
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

    @MainActor
    func localizedTitle(_ viewModel: PreferencesViewModel) -> String {
        viewModel.localizedString("preferences.section.\(rawValue)", fallback: title)
    }

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
        case .backup: return "Backups"
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
        case .backup: return "externaldrive"
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
                Button(viewModel.localizedString("preferences.save.button", fallback: "Save")) {
                    do {
                        try viewModel.save()
                        saveStatus = viewModel.localizedString(
                            "preferences.save.status.saved",
                            fallback: "Settings saved."
                        )
                    } catch {
                        let format = viewModel.localizedString(
                            "preferences.save.status.failed",
                            fallback: "Failed to save: %@"
                        )
                        saveStatus = String(format: format, error.localizedDescription)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        saveStatus = nil
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!viewModel.hasUnsavedChanges)
                .help(
                    viewModel.hasUnsavedChanges
                        ? viewModel.localizedString(
                            "preferences.save.help.changed",
                            fallback: "Save the modified settings to config.toml."
                        )
                        : viewModel.localizedString(
                            "preferences.save.help.unchanged",
                            fallback: "No settings have changed."
                        )
                )

                if let status = saveStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                Spacer()

                Button(viewModel.localizedString("preferences.save.openConfig", fallback: "Open config.toml")) {
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
            Section(viewModel.localizedString("preferences.general.shell.section", fallback: "Shell")) {
                TextField(
                    viewModel.localizedString("preferences.general.shellPath", fallback: "Shell path"),
                    text: $viewModel.shell
                )
                    .textFieldStyle(.roundedBorder)
                TextField(
                    viewModel.localizedString("preferences.general.workingDirectory", fallback: "Working directory"),
                    text: $viewModel.workingDirectory
                )
                    .textFieldStyle(.roundedBorder)
                Toggle(
                    viewModel.localizedString(
                        "preferences.general.confirmBeforeClosing",
                        fallback: "Confirm before closing"
                    ),
                    isOn: $viewModel.confirmCloseProcess
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.general", fallback: "General"))
    }
}

// MARK: - Editable Appearance Section

/// Editable appearance preferences (theme, font, padding).
struct EditableAppearanceSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.appearance.theme.section", fallback: "Theme")) {
                Picker(
                    viewModel.localizedString("preferences.appearance.activeTheme", fallback: "Active theme"),
                    selection: $viewModel.theme
                ) {
                    ForEach(viewModel.availableThemes, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }

            Section(viewModel.localizedString(.preferencesAppearanceLanguageTitle)) {
                Picker(
                    viewModel.localizedString(.preferencesAppearanceLanguagePicker),
                    selection: $viewModel.appLanguage
                ) {
                    ForEach(viewModel.availableAppLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Text(viewModel.localizedString(.preferencesAppearanceLanguageHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.appearance.font.section", fallback: "Font")) {
                FontFamilyComboBox(
                    text: $viewModel.fontFamily,
                    options: viewModel.availableFontFamilies,
                    accessibilityLabel: viewModel.localizedString(
                        "preferences.appearance.fontFamily",
                        fallback: "Font family"
                    )
                )
                .frame(height: 24)

                Text(
                    viewModel.localizedString(
                        "preferences.appearance.fontHelp",
                        fallback: "Choose any installed monospaced font. The dropdown is filtered to terminal-safe families, but you can still type a custom family name manually."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !viewModel.bundledFontFamilies.isEmpty {
                    Text(
                        String(
                            format: viewModel.localizedString(
                                "preferences.appearance.includedFonts",
                                fallback: "Included with Cocxy: %@"
                            ),
                            viewModel.bundledFontFamilies.joined(separator: ", ")
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !viewModel.recommendedFontFamilies.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewModel.localizedString("preferences.appearance.recommended", fallback: "Recommended"))
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
                                        },
                                        bundledLabel: viewModel.localizedString(
                                            "preferences.appearance.bundled",
                                            fallback: "Bundled"
                                        )
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
                    Toggle(
                        viewModel.localizedString(
                            "preferences.appearance.enableLigatures",
                            fallback: "Enable ligatures"
                        ),
                        isOn: $viewModel.ligatures
                    )
                        .help(
                            viewModel.localizedString(
                                "preferences.appearance.enableLigatures.help",
                                fallback: "Some fonts combine symbol pairs like --, ==, -> into a single wider glyph. Disable this option if command text such as --dangerously-skip-permissions looks misaligned or crowded in your prompt."
                            )
                        )
                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.enableLigatures.caption",
                            fallback: "Some fonts combine symbol pairs like --, ==, -> into a single glyph. Disable if command text appears misaligned in the prompt."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        viewModel.localizedString(
                            "preferences.appearance.thickenFontStrokes",
                            fallback: "Thicken font strokes"
                        ),
                        isOn: $viewModel.fontThicken
                    )
                        .help(
                            viewModel.localizedString(
                                "preferences.appearance.thickenFontStrokes.help",
                                fallback: "Enables CoreText font smoothing during glyph rasterization, which boosts perceived stroke weight. Off by default for a cleaner, thinner look. Turn on if the rendered text looks too thin on your display."
                            )
                        )
                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.thickenFontStrokes.caption",
                            fallback: "Boosts stroke weight via font smoothing. Off keeps glyphs thin and crisp; on makes them look heavier."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text(viewModel.localizedString("preferences.appearance.fontSize", fallback: "Font size"))
                        Spacer()
                        Text("\(Int(viewModel.fontSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.fontSize, in: 8...32, step: 1)
                }
            }

            Section(viewModel.localizedString("preferences.appearance.layout.section", fallback: "Layout")) {
                Picker(
                    viewModel.localizedString(
                        "preferences.appearance.classicTabPosition",
                        fallback: "Classic tab position"
                    ),
                    selection: $viewModel.tabPosition
                ) {
                    Text(viewModel.localizedString("preferences.appearance.tabPosition.left", fallback: "Left"))
                        .tag("left")
                    Text(viewModel.localizedString("preferences.appearance.tabPosition.top", fallback: "Top"))
                        .tag("top")
                    Text(viewModel.localizedString("preferences.appearance.tabPosition.hidden", fallback: "Hidden"))
                        .tag("hidden")
                }
                .disabled(!viewModel.isClassicTabPositionEditable)
                .help(
                    viewModel.isClassicTabPositionEditable
                        ? viewModel.localizedString(
                            "preferences.appearance.classicTabPosition.help.enabled",
                            fallback: "Controls the classic tab navigation: left sidebar, top strip, or hidden tabs."
                        )
                        : viewModel.localizedString(
                            "preferences.appearance.classicTabPosition.help.disabled",
                            fallback: "Aurora uses its own workspace sidebar. This classic tab position is preserved and applies again when Aurora is disabled."
                        )
                )

                Text(
                    viewModel.isClassicTabPositionEditable
                        ? viewModel.localizedString(
                            "preferences.appearance.classicTabPosition.caption.enabled",
                            fallback: "Top shows the classic horizontal tab strip and collapses the left tab sidebar. Hidden keeps only terminal chrome controls visible."
                        )
                        : viewModel.localizedString(
                            "preferences.appearance.classicTabPosition.caption.disabled",
                            fallback: "Aurora is enabled, so Cocxy keeps the workspace sidebar visible and ignores the classic Left/Top/Hidden layout until Aurora is turned off."
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading) {
                    HStack {
                        Text(
                            viewModel.localizedString(
                                "preferences.appearance.windowPadding",
                                fallback: "Window padding"
                            )
                        )
                        Spacer()
                        Text("\(Int(viewModel.windowPadding)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.windowPadding, in: 0...40, step: 1)
                }
            }

            Section(viewModel.localizedString("preferences.appearance.aurora.section", fallback: "Aurora")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        viewModel.localizedString(
                            "preferences.appearance.enableAurora",
                            fallback: "Enable Aurora chrome"
                        ),
                        isOn: $viewModel.auroraEnabled
                    )
                        .help(
                            viewModel.localizedString(
                                "preferences.appearance.enableAurora.help",
                                fallback: "Switches the window chrome to the experimental Aurora sidebar, status bar, and command palette. Save to apply through the normal config hot-reload path."
                            )
                        )
                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.enableAurora.caption",
                            fallback: "Aurora is an opt-in preview of the redesigned chrome. Turn it off to return to the classic sidebar and status bar."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Picker(
                    viewModel.localizedString(
                        "preferences.appearance.sidebarDensity",
                        fallback: "Sidebar density"
                    ),
                    selection: $viewModel.auroraSidebarDisplayMode
                ) {
                    ForEach(AuroraSidebarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.localizedPreferencesLabel(viewModel)).tag(mode)
                    }
                }
                Picker(
                    viewModel.localizedString(
                        "preferences.appearance.sidebarRowDetail",
                        fallback: "Sidebar row detail"
                    ),
                    selection: $viewModel.auroraSidebarPrimaryInfo
                ) {
                    ForEach(AuroraSidebarPrimaryInfo.allCases, id: \.self) { info in
                        Text(info.localizedPreferencesLabel(viewModel)).tag(info)
                    }
                }
            }

            Section(viewModel.localizedString("preferences.appearance.statusBar.section", fallback: "Status bar")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        viewModel.localizedString(
                            "preferences.appearance.showRateLimitIndicator",
                            fallback: "Show rate-limit indicator"
                        ),
                        isOn: $viewModel.rateLimitIndicatorEnabled
                    )
                    .help(
                        viewModel.localizedString(
                            "preferences.appearance.showRateLimitIndicator.help",
                            fallback: "Displays a status-bar pill with locally-estimated usage for the active agent. The pill only appears when the active agent has a registered local provider with available data; turning this off hides it for every agent."
                        )
                    )
                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.showRateLimitIndicator.caption",
                            fallback: "Reads only local files the agent's CLI already keeps on disk. No data leaves your machine."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(viewModel.localizedString("preferences.appearance.notes.section", fallback: "Notes")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(
                        viewModel.localizedString(
                            "preferences.appearance.enableWorkspaceNotes",
                            fallback: "Enable workspace notes"
                        ),
                        isOn: $viewModel.notesEnabled
                    )
                    .help(
                        viewModel.localizedString(
                            "preferences.appearance.enableWorkspaceNotes.help",
                            fallback: "Shows the Notes panel and enables the configured notes shortcut."
                        )
                    )

                    Picker(
                        viewModel.localizedString("preferences.appearance.notesFormat", fallback: "Format"),
                        selection: $viewModel.notesFormat
                    ) {
                        ForEach(NoteFormat.allCases, id: \.rawValue) { format in
                            Text(format.rawValue).tag(format.rawValue)
                        }
                    }
                    .disabled(!viewModel.notesEnabled)

                    Picker(
                        viewModel.localizedString("preferences.appearance.notesSearch", fallback: "Search"),
                        selection: $viewModel.notesSearchEngine
                    ) {
                        ForEach(NoteSearchEngineKind.allCases, id: \.rawValue) { engine in
                            Text(engine.rawValue).tag(engine.rawValue)
                        }
                    }
                    .disabled(!viewModel.notesEnabled)

                    TextField(
                        viewModel.localizedString(
                            "preferences.appearance.notesStorageDirectory",
                            fallback: "Storage directory"
                        ),
                        text: $viewModel.notesStorageDir
                    )
                        .disabled(!viewModel.notesEnabled)

                    TextField(
                        viewModel.localizedString("preferences.appearance.notesShortcut", fallback: "Shortcut"),
                        text: $viewModel.notesShortcut
                    )
                        .disabled(!viewModel.notesEnabled)

                    Toggle(
                        viewModel.localizedString(
                            "preferences.appearance.autoSaveNotes",
                            fallback: "Auto-save notes"
                        ),
                        isOn: $viewModel.notesAutoSave
                    )
                        .disabled(!viewModel.notesEnabled)

                    VStack(alignment: .leading) {
                        HStack {
                            Text(
                                viewModel.localizedString(
                                    "preferences.appearance.autoSaveInterval",
                                    fallback: "Auto-save interval"
                                )
                            )
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

                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.notes.caption",
                            fallback: "Notes are stored per workspace under the configured local folder."
                        )
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(viewModel.localizedString("preferences.appearance.transparency.section", fallback: "Transparency")) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(
                            viewModel.localizedString(
                                "preferences.appearance.backgroundOpacity",
                                fallback: "Background opacity"
                            )
                        )
                        Spacer()
                        Text("\(Int(viewModel.backgroundOpacity * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $viewModel.backgroundOpacity, in: 0.3...1.0, step: 0.05)
                }
                Text(
                    viewModel.localizedString(
                        "preferences.appearance.backgroundOpacity.caption",
                        fallback: "Lower values enable a glass effect on the sidebar, tab strip, and status bar."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Picker(
                    viewModel.localizedString(
                        "preferences.appearance.glassChromeTint",
                        fallback: "Glass chrome tint"
                    ),
                    selection: $viewModel.transparencyChromeTheme
                ) {
                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.glassChromeTint.followSystem",
                            fallback: "Follow System"
                        )
                    )
                    .tag(TransparencyChromeTheme.followSystem)
                    Text(viewModel.localizedString("preferences.appearance.glassChromeTint.light", fallback: "Light"))
                        .tag(TransparencyChromeTheme.light)
                    Text(viewModel.localizedString("preferences.appearance.glassChromeTint.dark", fallback: "Dark"))
                        .tag(TransparencyChromeTheme.dark)
                }
                .help(
                    viewModel.isTransparencyChromeThemeEditable
                        ? viewModel.localizedString(
                            "preferences.appearance.glassChromeTint.help.enabled",
                            fallback: "Pin the translucent sidebar, tab strip, and status bar to a light or dark tint independently of macOS. Only visible while the window is transparent."
                        )
                        : viewModel.localizedString(
                            "preferences.appearance.glassChromeTint.help.disabled",
                            fallback: "Selection is saved but only takes effect while the window is transparent. Lower the background opacity above to see it live."
                        )
                )
                .accessibilityLabel(
                    viewModel.localizedString(
                        "preferences.appearance.glassChromeTint",
                        fallback: "Glass chrome tint"
                    )
                )
                .accessibilityHint(
                    viewModel.localizedString(
                        "preferences.appearance.glassChromeTint.accessibilityHint",
                        fallback: "Choose whether the translucent sidebar, tab strip, and status bar follow the system appearance or stay pinned to a light or dark tint."
                    )
                )

                if !viewModel.isTransparencyChromeThemeEditable {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text(
                            viewModel.localizedString(
                                "preferences.appearance.glassChromeTint.hidden.caption",
                                fallback: "Your selection is saved, but you'll only see the tint once the window is transparent. Drop the background opacity below 100% to preview it live."
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        viewModel.localizedString(
                            "preferences.appearance.glassChromeTint.hidden.accessibilityLabel",
                            fallback: "Information: the glass chrome tint is saved but only visible while the window is transparent."
                        )
                    )
                } else {
                    Text(
                        viewModel.localizedString(
                            "preferences.appearance.glassChromeTint.pinned.caption",
                            fallback: "Pins the sidebar, tab strip, and status bar to a light or dark tint independently of macOS, as long as the window stays transparent."
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.appearance", fallback: "Appearance"))
    }
}

// MARK: - Font Picker Helpers

/// Native macOS combo box for selecting or typing a font family.
struct FontFamilyComboBox: NSViewRepresentable {
    @Binding var text: String
    let options: [String]
    let accessibilityLabel: String

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
        comboBox.setAccessibilityLabel(accessibilityLabel)
        comboBox.placeholderString = accessibilityLabel
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
            Text(viewModel.localizedString("preferences.appearance.preview", fallback: "Preview"))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("0Oo Il1 | [] {} () => -> == != --")
                .font(previewFont)

            Text("claude --dangerously-skip-permissions")
                .font(previewFont)
                .textSelection(.enabled)

            Text(viewModel.localizedFontResolutionSummary)
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
    let bundledLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(family)
                    .font(.caption)
                    .lineLimit(1)
                if isBundled {
                    Text(bundledLabel)
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
            Section(viewModel.localizedString("preferences.agentDetection.detection.section", fallback: "Detection")) {
                Toggle(
                    viewModel.localizedString("preferences.agentDetection.enabled", fallback: "Enabled"),
                    isOn: $viewModel.agentDetectionEnabled
                )
                Toggle(
                    viewModel.localizedString(
                        "preferences.agentDetection.oscNotifications",
                        fallback: "OSC notifications"
                    ),
                    isOn: $viewModel.oscNotifications
                )
                Toggle(
                    viewModel.localizedString("preferences.agentDetection.patternMatching", fallback: "Pattern matching"),
                    isOn: $viewModel.patternMatching
                )
                Toggle(
                    viewModel.localizedString(
                        "preferences.agentDetection.timingHeuristics",
                        fallback: "Timing heuristics"
                    ),
                    isOn: $viewModel.timingHeuristics
                )
            }

            Section(viewModel.localizedString("preferences.agentDetection.timing.section", fallback: "Timing")) {
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.agentDetection.idleTimeout",
                            fallback: "Idle timeout: %d s"
                        ),
                        viewModel.idleTimeoutSeconds
                    ),
                    value: $viewModel.idleTimeoutSeconds,
                    in: 1...300
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.agentDetection", fallback: "Agent Detection"))
    }
}

// MARK: - Agent Mode Section

/// Editable built-in Agent Mode preferences.
struct AgentModePreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.agentMode.feature.section", fallback: "Feature")) {
                Toggle(
                    viewModel.localizedString("preferences.agentMode.enable", fallback: "Enable Agent Mode"),
                    isOn: $viewModel.agentModeEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.agentMode.enable.help",
                        fallback: "Enables the built-in local Agent Mode entry points."
                    )
                )

                Toggle(
                    viewModel.localizedString("preferences.agentMode.autoMode", fallback: "Auto mode"),
                    isOn: $viewModel.agentAutoMode
                )
                .help(
                    viewModel.localizedString(
                        "preferences.agentMode.autoMode.help",
                        fallback: "Allows the agent loop to continue after approved actions without changing write or command approval rules."
                    )
                )

                Toggle(
                    viewModel.localizedString(
                        "preferences.agentMode.confirmComputerActions",
                        fallback: "Confirm computer actions"
                    ),
                    isOn: $viewModel.agentComputerUseConfirm
                )
                .help(
                    viewModel.localizedString(
                        "preferences.agentMode.confirmComputerActions.help",
                        fallback: "Requires explicit approval before local mouse, keyboard, or screenshot actions run."
                    )
                )
            }

            Section(viewModel.localizedString("preferences.agentMode.provider.section", fallback: "Provider")) {
                Picker(
                    viewModel.localizedString("preferences.agentMode.preferredProvider", fallback: "Preferred provider"),
                    selection: $viewModel.agentPreferredProvider
                ) {
                    ForEach(AgentProviderKind.allCases, id: \.self) { provider in
                        Text(providerTitle(provider)).tag(provider)
                    }
                }

                Text(providerDetail(viewModel.agentPreferredProvider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.agentMode.apiKey.section", fallback: "API Key")) {
                if viewModel.agentPreferredProvider.requiresAPIKey {
                    SecureField(
                        viewModel.localizedString("preferences.agentMode.apiKey", fallback: "API key"),
                        text: $viewModel.agentAPIKeyDraft
                    )
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(viewModel.localizedString("preferences.agentMode.apiKey.save", fallback: "Save API Key")) {
                            saveAPIKey()
                        }
                        .disabled(trimmedAPIKeyDraft.isEmpty)

                        Button(
                            viewModel.localizedString(
                                "preferences.agentMode.apiKey.delete",
                                fallback: "Delete Saved Key"
                            )
                        ) {
                            deleteAPIKey()
                        }
                        .disabled(!viewModel.hasSavedAgentAPIKey(for: viewModel.agentPreferredProvider))

                        Spacer()
                    }

                    Text(
                        viewModel.hasSavedAgentAPIKey(for: viewModel.agentPreferredProvider)
                            ? viewModel.localizedString(
                                "preferences.agentMode.apiKey.saved",
                                fallback: "A key is saved in the macOS Keychain for this provider."
                            )
                            : viewModel.localizedString(
                                "preferences.agentMode.apiKey.notSaved",
                                fallback: "No key is saved for this provider."
                            )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text(
                        viewModel.localizedString(
                            "preferences.agentMode.apiKey.foundationModels.none",
                            fallback: "Foundation Models does not use an API key."
                        )
                    )
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

            Section(viewModel.localizedString("preferences.agentMode.limits.section", fallback: "Limits")) {
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.agentMode.maxIterations",
                            fallback: "Max iterations: %d"
                        ),
                        viewModel.agentMaxIterations
                    ),
                    value: $viewModel.agentMaxIterations,
                    in: AgentModeConfig.minMaxIterations...AgentModeConfig.maxMaxIterations
                )
            }

            Section(viewModel.localizedString("preferences.agentMode.storage.section", fallback: "Storage")) {
                TextField(
                    viewModel.localizedString(
                        "preferences.agentMode.conversationStorage",
                        fallback: "Conversation storage"
                    ),
                    text: $viewModel.agentConversationStorageDir
                )
                    .textFieldStyle(.roundedBorder)

                Picker(
                    viewModel.localizedString(
                        "preferences.agentMode.conversationEncryption",
                        fallback: "Conversation encryption"
                    ),
                    selection: $viewModel.agentConversationEncryption
                ) {
                    ForEach(AgentConversationEncryptionMode.allCases, id: \.self) { mode in
                        Text(conversationEncryptionTitle(mode)).tag(mode)
                    }
                }

                if viewModel.agentConversationEncryption == .masterPassword {
                    SecureField(
                        viewModel.localizedString("preferences.agentMode.masterPassword", fallback: "Master password"),
                        text: $viewModel.agentConversationMasterPasswordDraft
                    )
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button(
                            viewModel.localizedString(
                                "preferences.agentMode.masterPassword.save",
                                fallback: "Save Master Password"
                            )
                        ) {
                            saveConversationMasterPassword()
                        }
                        .disabled(trimmedConversationMasterPasswordDraft.isEmpty)

                        Button(
                            viewModel.localizedString(
                                "preferences.agentMode.masterPassword.delete",
                                fallback: "Delete Saved Password"
                            )
                        ) {
                            deleteConversationMasterPassword()
                        }
                        .disabled(!viewModel.hasSavedAgentConversationMasterPassword())

                        Spacer()
                    }

                    Text(
                        viewModel.hasSavedAgentConversationMasterPassword()
                            ? viewModel.localizedString(
                                "preferences.agentMode.masterPassword.saved",
                                fallback: "A master password is saved in the macOS Keychain."
                            )
                            : viewModel.localizedString(
                                "preferences.agentMode.masterPassword.notSaved",
                                fallback: "No master password is saved."
                            )
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
        .navigationTitle(viewModel.localizedString("preferences.section.agentMode", fallback: "Agent Mode"))
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
            viewModel.agentAPIKeyStatus = String(
                format: viewModel.localizedString(
                    "preferences.agentMode.apiKey.save.failed",
                    fallback: "Failed to save API key: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func deleteAPIKey() {
        do {
            try viewModel.deleteAgentAPIKey(for: viewModel.agentPreferredProvider)
        } catch {
            viewModel.agentAPIKeyStatus = String(
                format: viewModel.localizedString(
                    "preferences.agentMode.apiKey.delete.failed",
                    fallback: "Failed to delete API key: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func saveConversationMasterPassword() {
        do {
            try viewModel.saveAgentConversationMasterPasswordDraft()
        } catch {
            viewModel.agentConversationMasterPasswordStatus = String(
                format: viewModel.localizedString(
                    "preferences.agentMode.masterPassword.save.failed",
                    fallback: "Failed to save master password: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func deleteConversationMasterPassword() {
        do {
            try viewModel.deleteAgentConversationMasterPassword()
        } catch {
            viewModel.agentConversationMasterPasswordStatus = String(
                format: viewModel.localizedString(
                    "preferences.agentMode.masterPassword.delete.failed",
                    fallback: "Failed to delete master password: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func conversationEncryptionTitle(_ mode: AgentConversationEncryptionMode) -> String {
        switch mode {
        case .disabled:
            return viewModel.localizedString("preferences.agentMode.encryption.disabled", fallback: "Disabled")
        case .masterPassword:
            return viewModel.localizedString("preferences.agentMode.encryption.masterPassword", fallback: "Master Password")
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
            return viewModel.localizedString(
                "preferences.agentMode.provider.detail.foundationModels",
                fallback: "Runs on device when supported. If unavailable, Cocxy asks you to choose another provider instead of falling back silently."
            )
        case .anthropic, .openai, .google:
            return viewModel.localizedString(
                "preferences.agentMode.provider.detail.remote",
                fallback: "Uses your provider API key from the macOS Keychain. Requests go directly from this Mac to the selected provider."
            )
        }
    }
}

// MARK: - MCP Servers Section

/// Editable user-managed MCP server configuration.
struct MCPServersPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.mcp.configFile.section", fallback: "Config File")) {
                LabeledContent(viewModel.localizedString("preferences.mcp.path", fallback: "Path")) {
                    Text(viewModel.mcpConfigPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                HStack {
                    Button(viewModel.localizedString("preferences.mcp.reload", fallback: "Reload")) {
                        viewModel.reloadMCPConfig()
                    }

                    Button(viewModel.localizedString("preferences.mcp.openFolder", fallback: "Open Folder")) {
                        let url = URL(fileURLWithPath: viewModel.mcpConfigPath)
                            .deletingLastPathComponent()
                        NSWorkspace.shared.open(url)
                    }

                    Spacer()
                }
            }

            Section(viewModel.localizedString("preferences.mcp.configuredServers.section", fallback: "Configured Servers")) {
                if viewModel.mcpConfiguredServers.isEmpty {
                    Text(viewModel.localizedString("preferences.mcp.noServers", fallback: "No MCP servers configured."))
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
                    Button(viewModel.localizedString("preferences.mcp.validate", fallback: "Validate")) {
                        validate()
                    }

                    Button(viewModel.localizedString("preferences.mcp.save", fallback: "Save MCP Config")) {
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
        .navigationTitle(viewModel.localizedString("preferences.section.mcpServers", fallback: "MCP Servers"))
    }

    private func validate() {
        do {
            try viewModel.validateMCPConfigDraft()
        } catch {
            viewModel.mcpConfigStatus = String(
                format: viewModel.localizedString(
                    "preferences.mcp.validate.failed",
                    fallback: "Invalid MCP config: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func save() {
        do {
            try viewModel.saveMCPConfig()
        } catch {
            viewModel.mcpConfigStatus = String(
                format: viewModel.localizedString(
                    "preferences.mcp.save.failed",
                    fallback: "Failed to save MCP config: %@"
                ),
                error.localizedDescription
            )
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
            Section(viewModel.localizedString("preferences.voice.feature.section", fallback: "Feature")) {
                Toggle(
                    viewModel.localizedString("preferences.voice.enable", fallback: "Enable Voice input"),
                    isOn: $viewModel.voiceEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.voice.enable.help",
                        fallback: "Enables local dictation entry points when supported by macOS."
                    )
                )
            }

            Section(viewModel.localizedString("preferences.voice.locale.section", fallback: "Locale")) {
                Picker(
                    viewModel.localizedString("preferences.voice.recognitionLocale", fallback: "Recognition locale"),
                    selection: $viewModel.voiceLocaleIdentifier
                ) {
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
        .navigationTitle(viewModel.localizedString("preferences.section.voice", fallback: "Voice"))
    }

    private var systemLocaleTitle: String {
        let resolution = viewModel.resolvedVoiceLocale
        guard viewModel.voiceLocaleIdentifier == VoiceConfig.systemLocaleIdentifier,
              let localeIdentifier = resolution.localeIdentifier
        else {
            return viewModel.localizedString("preferences.voice.systemLocale", fallback: "System")
        }
        return String(
            format: viewModel.localizedString("preferences.voice.systemLocaleFormat", fallback: "System (%@)"),
            localeIdentifier
        )
    }

    private var resolutionDetail: String {
        switch viewModel.resolvedVoiceLocale.source {
        case .systemExact:
            return viewModel.localizedString(
                "preferences.voice.resolution.systemExact",
                fallback: "Using the current system locale."
            )
        case .systemLanguageFallback:
            return viewModel.localizedString(
                "preferences.voice.resolution.systemLanguageFallback",
                fallback: "Using the nearest supported locale for the current system language."
            )
        case .systemUnsupportedFallback:
            return viewModel.localizedString(
                "preferences.voice.resolution.systemUnsupportedFallback",
                fallback: "The current system language is not listed by Speech; using the first supported local recognizer."
            )
        case .manualOverride:
            return viewModel.localizedString(
                "preferences.voice.resolution.manualOverride",
                fallback: "Using the selected locale override."
            )
        case .manualUnsupportedSystemFallback(let requested):
            return String(
                format: viewModel.localizedString(
                    "preferences.voice.resolution.manualUnsupportedSystemFallback",
                    fallback: "%@ is not listed by Speech; using the system locale fallback."
                ),
                requested
            )
        case .unavailable:
            return viewModel.localizedString(
                "preferences.voice.resolution.unavailable",
                fallback: "macOS did not report any local Speech recognition locales."
            )
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
            Section(viewModel.localizedString("preferences.activity.privacy.section", fallback: "Privacy")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.activity.enable",
                        fallback: "Enable local Activity dashboard"
                    ),
                    isOn: $viewModel.activityTrackingEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.activity.enable.help",
                        fallback: "Stores activity data locally for dashboards and manual export."
                    )
                )
                Toggle(
                    viewModel.localizedString(
                        "preferences.activity.trackCosts",
                        fallback: "Track token usage and estimated costs"
                    ),
                    isOn: $viewModel.activityCostTrackingEnabled
                )
                    .disabled(!viewModel.activityTrackingEnabled)
                    .help(
                        viewModel.localizedString(
                            "preferences.activity.trackCosts.help",
                            fallback: "Uses local token counts and model rates; no data is uploaded."
                        )
                    )
            }

            Section(viewModel.localizedString("preferences.activity.costRates.section", fallback: "Cost Rates")) {
                LabeledContent(viewModel.localizedString("preferences.activity.inputCost", fallback: "Input / 1M tokens")) {
                    TextField(
                        "0",
                        value: $viewModel.activityInputCostMicrosPerMillionTokens,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.activityTrackingEnabled || !viewModel.activityCostTrackingEnabled)
                }
                LabeledContent(viewModel.localizedString("preferences.activity.outputCost", fallback: "Output / 1M tokens")) {
                    TextField(
                        "0",
                        value: $viewModel.activityOutputCostMicrosPerMillionTokens,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.activityTrackingEnabled || !viewModel.activityCostTrackingEnabled)
                }
                Text(
                    viewModel.localizedString(
                        "preferences.activity.costRates.caption",
                        fallback: "Rates are micro-dollars per one million tokens and stay local in config."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.activity.storage.section", fallback: "Storage")) {
                LabeledContent(
                    viewModel.localizedString("preferences.activity.localDirectory", fallback: "Local directory"),
                    value: ActivityConfig.defaults.storageDirectory
                )
                Text(
                    viewModel.localizedString(
                        "preferences.activity.storage.caption",
                        fallback: "Disable the Activity dashboard to stop future writes. Existing local records can be cleared from the Activity dashboard."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.activity", fallback: "Activity"))
    }
}

// MARK: - Session Replay Section

/// Editable local session replay privacy preferences.
struct SessionReplayPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.sessionReplay.privacy.section", fallback: "Privacy")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.sessionReplay.enable",
                        fallback: "Enable Session Replay"
                    ),
                    isOn: $viewModel.sessionReplayEnabled
                )
                Toggle(
                    viewModel.localizedString(
                        "preferences.sessionReplay.autoRecord",
                        fallback: "Record new terminal sessions automatically"
                    ),
                    isOn: $viewModel.sessionReplayAutoRecord
                )
                    .disabled(!viewModel.sessionReplayEnabled)
                Toggle(
                    viewModel.localizedString(
                        "preferences.sessionReplay.consent",
                        fallback: "Allow automatic recording"
                    ),
                    isOn: $viewModel.sessionReplayConsentGranted
                )
                    .disabled(!viewModel.sessionReplayEnabled || !viewModel.sessionReplayAutoRecord)
            }

            Section(viewModel.localizedString("preferences.sessionReplay.storage.section", fallback: "Storage")) {
                TextField(
                    viewModel.localizedString(
                        "preferences.sessionReplay.storageDirectory",
                        fallback: "Storage directory"
                    ),
                    text: $viewModel.sessionReplayStorageDirectory
                )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.sessionReplayEnabled)
                LabeledContent(
                    viewModel.localizedString(
                        "preferences.sessionReplay.maxRecordingBytes",
                        fallback: "Max recording bytes"
                    )
                ) {
                    TextField(
                        "536870912",
                        value: $viewModel.sessionReplayMaxRecordingBytes,
                        format: .number
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.sessionReplayEnabled)
                }
                Text(
                    viewModel.localizedString(
                        "preferences.sessionReplay.storage.caption",
                        fallback: "Recordings stay local unless exported manually."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.sessionReplay", fallback: "Session Replay"))
    }
}

// MARK: - iCloud Sync Section

/// Editable encrypted iCloud Drive sync preferences.
struct ICloudSyncPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.iCloud.optIn.section", fallback: "Opt-In")) {
                Toggle(
                    viewModel.localizedString("preferences.iCloud.enable", fallback: "Enable iCloud Drive sync"),
                    isOn: $viewModel.iCloudSyncEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.iCloud.enable.help",
                        fallback: "Exports selected local Cocxy artifacts to the user's iCloud Drive."
                    )
                )
            }

            Section(viewModel.localizedString("preferences.iCloud.encryption.section", fallback: "Encryption")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.iCloud.encryptArtifacts",
                        fallback: "Encrypt synced artifacts"
                    ),
                    isOn: .constant(true)
                )
                    .disabled(true)
                    .help(
                        viewModel.localizedString(
                            "preferences.iCloud.encryptArtifacts.help",
                            fallback: "Encryption is required for iCloud Sync."
                        )
                    )

                SecureField(
                    viewModel.localizedString("preferences.iCloud.masterPassword", fallback: "Master password"),
                    text: $viewModel.iCloudSyncMasterPasswordDraft
                )
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(
                        viewModel.localizedString(
                            "preferences.iCloud.masterPassword.save",
                            fallback: "Save Master Password"
                        )
                    ) {
                        saveICloudSyncMasterPassword()
                    }
                    .disabled(trimmedICloudSyncMasterPasswordDraft.isEmpty)

                    Button(
                        viewModel.localizedString(
                            "preferences.iCloud.masterPassword.delete",
                            fallback: "Delete Saved Password"
                        )
                    ) {
                        deleteICloudSyncMasterPassword()
                    }
                    .disabled(!viewModel.hasSavedICloudSyncMasterPassword())

                    Spacer()
                }

                Text(
                    viewModel.hasSavedICloudSyncMasterPassword()
                        ? viewModel.localizedString(
                            "preferences.iCloud.masterPassword.saved",
                            fallback: "A master password is saved in the macOS Keychain."
                        )
                        : viewModel.localizedString(
                            "preferences.iCloud.masterPassword.notSaved",
                            fallback: "No master password is saved."
                        )
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

            Section(viewModel.localizedString("preferences.iCloud.location.section", fallback: "Location")) {
                TextField(
                    viewModel.localizedString("preferences.iCloud.folderName", fallback: "Folder name"),
                    text: $viewModel.iCloudSyncDirectoryName
                )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.iCloudSyncEnabled)
                LabeledContent(
                    viewModel.localizedString("preferences.iCloud.conflictPolicy", fallback: "Conflict policy"),
                    value: viewModel.localizedString("preferences.iCloud.conflictPolicy.manual", fallback: "manual")
                )
            }

            Section(viewModel.localizedString("preferences.iCloud.artifacts.section", fallback: "Artifacts")) {
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

            Section(viewModel.localizedString("preferences.iCloud.manualExport.section", fallback: "Manual Export")) {
                Button(viewModel.localizedString("preferences.iCloud.export", fallback: "Export Encrypted Artifacts")) {
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

            Section(viewModel.localizedString("preferences.iCloud.manualImport.section", fallback: "Manual Import")) {
                Button(viewModel.localizedString("preferences.iCloud.import", fallback: "Import Remote Artifacts")) {
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
                            Text(
                                viewModel.localizedString(
                                    "preferences.iCloud.conflict.versionsDiffer",
                                    fallback: "Local and remote versions differ."
                                )
                            )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button(
                                    viewModel.localizedString(
                                        "preferences.iCloud.conflict.keepLocal",
                                        fallback: "Keep Local"
                                    )
                                ) {
                                    resolveICloudSyncConflict(conflict, resolution: .keepLocal)
                                }

                                Button(
                                    viewModel.localizedString(
                                        "preferences.iCloud.conflict.useRemote",
                                        fallback: "Use Remote"
                                    )
                                ) {
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
        .navigationTitle(viewModel.localizedString("preferences.section.iCloudSync", fallback: "iCloud Sync"))
    }

    private func iCloudSyncArtifactTitle(_ kind: ICloudSyncArtifactKind) -> String {
        switch kind {
        case .notebooks:
            return viewModel.localizedString("preferences.iCloud.artifact.notebooks", fallback: "Notebooks")
        case .workflows:
            return viewModel.localizedString("preferences.iCloud.artifact.workflows", fallback: "Workflows")
        case .skills:
            return viewModel.localizedString("preferences.iCloud.artifact.skills", fallback: "Skills")
        case .settings:
            return viewModel.localizedString("preferences.iCloud.artifact.settings", fallback: "Settings")
        case .themes:
            return viewModel.localizedString("preferences.iCloud.artifact.themes", fallback: "Themes")
        }
    }

    private var trimmedICloudSyncMasterPasswordDraft: String {
        viewModel.iCloudSyncMasterPasswordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveICloudSyncMasterPassword() {
        do {
            try viewModel.saveICloudSyncMasterPasswordDraft()
        } catch {
            viewModel.iCloudSyncMasterPasswordStatus = String(
                format: viewModel.localizedString(
                    "preferences.iCloud.masterPassword.save.failed",
                    fallback: "Failed to save master password: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func deleteICloudSyncMasterPassword() {
        do {
            try viewModel.deleteICloudSyncMasterPassword()
        } catch {
            viewModel.iCloudSyncMasterPasswordStatus = String(
                format: viewModel.localizedString(
                    "preferences.iCloud.masterPassword.delete.failed",
                    fallback: "Failed to delete master password: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func exportICloudSyncArtifacts() {
        do {
            _ = try viewModel.exportICloudSyncArtifactsNow()
        } catch {
            viewModel.iCloudSyncExportStatus = String(
                format: viewModel.localizedString(
                    "preferences.iCloud.export.failed",
                    fallback: "Failed to export encrypted artifacts: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func importICloudSyncArtifacts() {
        do {
            _ = try viewModel.importICloudSyncArtifactsNow()
        } catch {
            viewModel.iCloudSyncImportStatus = String(
                format: viewModel.localizedString(
                    "preferences.iCloud.import.failed",
                    fallback: "Failed to import encrypted artifacts: %@"
                ),
                error.localizedDescription
            )
        }
    }

    private func resolveICloudSyncConflict(
        _ conflict: ICloudSyncImportConflict,
        resolution: ICloudSyncConflictResolution
    ) {
        do {
            _ = try viewModel.resolveICloudSyncConflict(conflict, resolution: resolution)
        } catch {
            viewModel.iCloudSyncImportStatus = String(
                format: viewModel.localizedString(
                    "preferences.iCloud.conflict.resolve.failed",
                    fallback: "Failed to resolve conflict: %@"
                ),
                error.localizedDescription
            )
        }
    }
}

// MARK: - Local Backups Section

struct BackupPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.backup.automatic.section", fallback: "Automatic Backups")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.backup.enable",
                        fallback: "Enable local automatic backups"
                    ),
                    isOn: $viewModel.backupEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.backup.enable.help",
                        fallback: "Writes timestamped backups to a local folder. No network service is used."
                    )
                )
            }

            Section(viewModel.localizedString("preferences.backup.location.section", fallback: "Location")) {
                TextField(
                    viewModel.localizedString(
                        "preferences.backup.storageDirectory",
                        fallback: "Storage directory"
                    ),
                    text: $viewModel.backupStorageDirectory
                )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.backupEnabled)
                Text(
                    String(
                        format: viewModel.localizedString(
                            "preferences.backup.defaultLocation",
                            fallback: "Default location: %@"
                        ),
                        BackupConfig.defaultStorageDirectory
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section(viewModel.localizedString("preferences.backup.retention.section", fallback: "Retention")) {
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.backup.dailySnapshots",
                            fallback: "Daily snapshots: %d"
                        ),
                        viewModel.backupDailyRetentionCount
                    ),
                    value: $viewModel.backupDailyRetentionCount,
                    in: 1...365
                )
                .disabled(!viewModel.backupEnabled)

                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.backup.monthlySnapshots",
                            fallback: "Monthly snapshots: %d"
                        ),
                        viewModel.backupMonthlyRetentionCount
                    ),
                    value: $viewModel.backupMonthlyRetentionCount,
                    in: 0...120
                )
                .disabled(!viewModel.backupEnabled)
            }

            Section(viewModel.localizedString("preferences.backup.artifacts.section", fallback: "Artifacts")) {
                ForEach(BackupArtifactKind.allCases, id: \.self) { kind in
                    Toggle(
                        backupArtifactTitle(kind),
                        isOn: Binding(
                            get: { viewModel.isBackupArtifactKindEnabled(kind) },
                            set: { viewModel.setBackupArtifactKind(kind, enabled: $0) }
                        )
                    )
                    .disabled(!viewModel.backupEnabled)
                    .help(backupArtifactHelp(kind))
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.backup", fallback: "Backups"))
    }

    @MainActor
    private func backupArtifactTitle(_ kind: BackupArtifactKind) -> String {
        switch kind {
        case .settings:
            return viewModel.localizedString("preferences.backup.artifact.settings", fallback: "Settings")
        case .notebooks:
            return viewModel.localizedString("preferences.backup.artifact.notebooks", fallback: "Notebooks")
        case .workflows:
            return viewModel.localizedString("preferences.backup.artifact.workflows", fallback: "Workflows")
        case .skills:
            return viewModel.localizedString("preferences.backup.artifact.skills", fallback: "Custom skills")
        case .notes:
            return viewModel.localizedString("preferences.backup.artifact.notes", fallback: "Notes")
        case .macros:
            return viewModel.localizedString("preferences.backup.artifact.macros", fallback: "Macros and snippets")
        case .themes:
            return viewModel.localizedString("preferences.backup.artifact.themes", fallback: "Custom themes")
        case .encryptedSSHHosts:
            return viewModel.localizedString(
                "preferences.backup.artifact.encryptedSSHHosts",
                fallback: "Encrypted SSH hosts"
            )
        case .aiConversations:
            return viewModel.localizedString("preferences.backup.artifact.aiConversations", fallback: "AI conversations")
        }
    }

    @MainActor
    private func backupArtifactHelp(_ kind: BackupArtifactKind) -> String {
        switch kind {
        case .aiConversations:
            return viewModel.localizedString(
                "preferences.backup.artifact.help.aiConversations",
                fallback: "Off by default. Enable only when you want local conversation history included."
            )
        case .encryptedSSHHosts:
            return viewModel.localizedString(
                "preferences.backup.artifact.help.encryptedSSHHosts",
                fallback: "Backs up encrypted host metadata only. SSH keys remain in Keychain."
            )
        default:
            return viewModel.localizedString(
                "preferences.backup.artifact.help.default",
                fallback: "Included in the local backup snapshot when the source exists."
            )
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
            Section(viewModel.localizedString("preferences.codeReview.panel.section", fallback: "Panel")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.codeReview.autoShow",
                        fallback: "Auto-show review panel when an agent session ends"
                    ),
                    isOn: $viewModel.codeReviewAutoShowOnSessionEnd
                )
                Text(
                    viewModel.localizedString(
                        "preferences.codeReview.autoShow.caption",
                        fallback: "When on, Cocxy opens the Code Review panel automatically after a tracked agent session produces changes. Turn it off if you prefer opening the panel manually with Cmd+Option+R."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.codeReview", fallback: "Code Review"))
    }
}

// MARK: - Editable Notifications Section

/// Editable notification preferences.
struct EditableNotificationsSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.notifications.system.section", fallback: "System Notifications")) {
                Toggle(
                    viewModel.localizedString("preferences.notifications.macos", fallback: "macOS notifications"),
                    isOn: $viewModel.macosNotifications
                )
                Toggle(
                    viewModel.localizedString("preferences.notifications.sound", fallback: "Sound"),
                    isOn: $viewModel.sound
                )
            }

            Section(viewModel.localizedString("preferences.notifications.visual.section", fallback: "Visual Indicators")) {
                Toggle(
                    viewModel.localizedString("preferences.notifications.badgeOnTab", fallback: "Badge on tab"),
                    isOn: $viewModel.badgeOnTab
                )
                Toggle(
                    viewModel.localizedString("preferences.notifications.flashTab", fallback: "Flash tab"),
                    isOn: $viewModel.flashTab
                )
                Toggle(
                    viewModel.localizedString("preferences.notifications.dockBadge", fallback: "Dock badge"),
                    isOn: $viewModel.showDockBadge
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.notifications", fallback: "Notifications"))
    }
}

// MARK: - Terminal Section

struct TerminalPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.terminal.core.section", fallback: "Core Defaults")) {
                LabeledContent(viewModel.localizedString("preferences.terminal.scrollbackLines", fallback: "Scrollback lines")) {
                    Text("\(viewModel.scrollbackLines)")
                        .foregroundStyle(.secondary)
                }
                LabeledContent(viewModel.localizedString("preferences.terminal.cursorStyle", fallback: "Cursor style")) {
                    Text(viewModel.cursorStyle)
                        .foregroundStyle(.secondary)
                }
                LabeledContent(viewModel.localizedString("preferences.terminal.cursorBlink", fallback: "Cursor blink")) {
                    Text(
                        viewModel.cursorBlink
                            ? viewModel.localizedString("preferences.terminal.cursorBlink.on", fallback: "On")
                            : viewModel.localizedString("preferences.terminal.cursorBlink.off", fallback: "Off")
                    )
                        .foregroundStyle(.secondary)
                }
            }

            Section(viewModel.localizedString("preferences.terminal.inlineImages.section", fallback: "Inline Images")) {
                Toggle(
                    viewModel.localizedString("preferences.terminal.enableSixelImages", fallback: "Enable Sixel images"),
                    isOn: $viewModel.enableSixelImages
                )
                Toggle(
                    viewModel.localizedString("preferences.terminal.enableKittyImages", fallback: "Enable Kitty images"),
                    isOn: $viewModel.enableKittyImages
                )
                Toggle(
                    viewModel.localizedString("preferences.terminal.enableITerm2Images", fallback: "Enable iTerm2 images"),
                    isOn: $viewModel.enableITerm2Images
                )
                Toggle(
                    viewModel.localizedString("preferences.terminal.enableFileTransfer", fallback: "Enable file transfer"),
                    isOn: $viewModel.imageFileTransfer
                )
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.terminal.imageMemoryBudget",
                            fallback: "Image memory budget: %d MiB"
                        ),
                        viewModel.imageMemoryLimitMB
                    ),
                    value: $viewModel.imageMemoryLimitMB,
                    in: 1...4096
                )
                TextField(
                    viewModel.localizedString(
                        "preferences.terminal.diskCacheDirectory",
                        fallback: "Disk cache directory"
                    ),
                    text: $viewModel.imageDiskCacheDirectory
                )
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.terminal.diskCacheBudget",
                            fallback: "Disk cache budget: %d MiB"
                        ),
                        viewModel.imageDiskCacheLimitMB
                    ),
                    value: $viewModel.imageDiskCacheLimitMB,
                    in: 1...8192
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.terminal", fallback: "Terminal"))
    }
}

// MARK: - Language Servers Section

/// Editable opt-in gates for local Language Server Protocol clients.
struct LanguageServersPreferencesSection: View {
    @ObservedObject var viewModel: PreferencesViewModel
    @Binding var saveStatus: String?

    var body: some View {
        Form {
            Section(viewModel.localizedString("preferences.lsp.feature.section", fallback: "Feature")) {
                Toggle(
                    viewModel.localizedString("preferences.lsp.enable", fallback: "Enable language servers"),
                    isOn: $viewModel.lspEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.lsp.enable.help",
                        fallback: "Starts only the local language servers selected below."
                    )
                )
                Text(
                    viewModel.localizedString(
                        "preferences.lsp.feature.caption",
                        fallback: "Cocxy never auto-installs language servers. Enabled servers run locally and receive opened document text plus workspace URIs."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.lsp.languages.section", fallback: "Languages")) {
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
        .navigationTitle(viewModel.localizedString("preferences.section.languageServers", fallback: "Language Servers"))
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
            Section(viewModel.localizedString("preferences.editor.input.section", fallback: "Input")) {
                Toggle(
                    viewModel.localizedString("preferences.editor.enableVimMode", fallback: "Enable Vim mode"),
                    isOn: $viewModel.vimEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.editor.enableVimMode.help",
                        fallback: "Routes editor text input through the Vim state machine."
                    )
                )
                Text(
                    viewModel.localizedString(
                        "preferences.editor.input.caption",
                        fallback: "Applies only to editor tabs. Terminal panes keep standard shell input."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.editor.inlineCompletions.section", fallback: "Inline Completions")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.editor.enableInlineAICompletions",
                        fallback: "Enable inline AI completions"
                    ),
                    isOn: $viewModel.completionInlineAIEnabled
                )
                .help(
                    viewModel.localizedString(
                        "preferences.editor.enableInlineAICompletions.help",
                        fallback: "Uses the local Foundation Models provider when available."
                    )
                )

                HStack {
                    Text(viewModel.localizedString("preferences.editor.provider", fallback: "Provider"))
                    Spacer()
                    Text(viewModel.localizedString("preferences.editor.foundationModels", fallback: "Foundation Models"))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(viewModel.localizedString("preferences.editor.idleDelay", fallback: "Idle delay"))
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
                    Text(
                        String(
                            format: viewModel.localizedString(
                                "preferences.editor.contextWindow",
                                fallback: "Context window: %d UTF-16"
                            ),
                            viewModel.completionMaxContextUTF16Length
                        )
                    )
                }
            }

            Section(viewModel.localizedString("preferences.editor.completionLanguages.section", fallback: "Completion Languages")) {
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
        .navigationTitle(viewModel.localizedString("preferences.section.editor", fallback: "Editor"))
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
            Section(viewModel.localizedString("preferences.worktrees.feature.section", fallback: "Feature")) {
                Toggle(
                    viewModel.localizedString("preferences.worktrees.enable", fallback: "Enable worktrees"),
                    isOn: $viewModel.worktreeEnabled
                )
                Text(
                    viewModel.localizedString(
                        "preferences.worktrees.feature.caption",
                        fallback: "When off, every `cocxy worktree-*` CLI verb and palette action refuses with a hint pointing here. Off by default."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.worktrees.storage.section", fallback: "Storage")) {
                LabeledContent(viewModel.localizedString("preferences.worktrees.basePath", fallback: "Base path")) {
                    TextField(
                        "~/.cocxy/worktrees",
                        text: $viewModel.worktreeBasePath
                    )
                    .textFieldStyle(.roundedBorder)
                }
                Text(
                    viewModel.localizedString(
                        "preferences.worktrees.finalPath.caption",
                        fallback: "Final worktree path: <base-path>/<repo-hash>/<id>/. ~ is expanded at use time."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.worktrees.branch.section", fallback: "Branch")) {
                LabeledContent(viewModel.localizedString("preferences.worktrees.template", fallback: "Template")) {
                    TextField(
                        "cocxy/{agent}/{id}",
                        text: $viewModel.worktreeBranchTemplate
                    )
                    .textFieldStyle(.roundedBorder)
                }
                LabeledContent(viewModel.localizedString("preferences.worktrees.baseRef", fallback: "Base ref")) {
                    TextField(
                        "HEAD",
                        text: $viewModel.worktreeBaseRef
                    )
                    .textFieldStyle(.roundedBorder)
                }
                Text(
                    viewModel.localizedString(
                        "preferences.worktrees.branch.caption",
                        fallback: "Template placeholders: {agent}, {id}, {date}. Base ref accepts HEAD, main, or any git ref."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.worktrees.randomIDLength",
                            fallback: "Random id length: %d"
                        ),
                        viewModel.worktreeIDLength
                    ),
                    value: $viewModel.worktreeIDLength,
                    in: WorktreeConfig.minIDLength...WorktreeConfig.maxIDLength
                )
            }

            Section(viewModel.localizedString("preferences.worktrees.lifecycle.section", fallback: "Lifecycle")) {
                Picker(
                    viewModel.localizedString("preferences.worktrees.onClose", fallback: "On tab close"),
                    selection: $viewModel.worktreeOnClose
                ) {
                    Text(viewModel.localizedString("preferences.worktrees.onClose.keep", fallback: "Keep"))
                        .tag(WorktreeOnClose.keep.rawValue)
                    Text(viewModel.localizedString("preferences.worktrees.onClose.prompt", fallback: "Prompt"))
                        .tag(WorktreeOnClose.prompt.rawValue)
                    Text(viewModel.localizedString("preferences.worktrees.onClose.remove", fallback: "Remove if clean"))
                        .tag(WorktreeOnClose.remove.rawValue)
                }
                Toggle(
                    viewModel.localizedString(
                        "preferences.worktrees.openNewTab",
                        fallback: "Open new tab for each worktree"
                    ),
                    isOn: $viewModel.worktreeOpenInNewTab
                )
            }

            Section(viewModel.localizedString("preferences.worktrees.integration.section", fallback: "Integration")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.worktrees.inheritProjectConfig",
                        fallback: "Inherit project config from origin repo"
                    ),
                    isOn: $viewModel.worktreeInheritProjectConfig
                )
                Text(
                    viewModel.localizedString(
                        "preferences.worktrees.inheritProjectConfig.caption",
                        fallback: "When on, .cocxy.toml from the origin repo applies inside the worktree when the worktree tree has none."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Toggle(
                    viewModel.localizedString("preferences.worktrees.showBadge", fallback: "Show worktree badge on tabs"),
                    isOn: $viewModel.worktreeShowBadge
                )
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.worktrees", fallback: "Worktrees"))
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
            Section(viewModel.localizedString("preferences.github.feature.section", fallback: "Feature")) {
                Toggle(
                    viewModel.localizedString("preferences.github.enable", fallback: "Enable GitHub pane"),
                    isOn: $viewModel.githubEnabled
                )
                Text(
                    viewModel.localizedString(
                        "preferences.github.feature.caption",
                        fallback: "Powers Cmd+Option+G and the `cocxy github` CLI verbs. Turning this off stops every `gh` subprocess invocation and hides the pane. Authentication is delegated to `gh auth status`; Cocxy never stores GitHub tokens of its own."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.github.authentication.section", fallback: "Authentication")) {
                Button {
                    onGitHubSignIn?()
                } label: {
                    Label(
                        viewModel.localizedString("preferences.github.signIn", fallback: "Sign In with GitHub"),
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                }
                .disabled(onGitHubSignIn == nil)
                .help(
                    viewModel.localizedString(
                        "preferences.github.signIn.help",
                        fallback: "Open a Cocxy tab and run gh auth login."
                    )
                )

                Button {
                    openGitHubCLIInstallGuide()
                } label: {
                    Label(
                        viewModel.localizedString("preferences.github.installCLI", fallback: "Install GitHub CLI"),
                        systemImage: "arrow.down.circle"
                    )
                }
                .help(
                    viewModel.localizedString(
                        "preferences.github.installCLI.help",
                        fallback: "Open the official GitHub CLI install guide."
                    )
                )

                Text(
                    viewModel.localizedString(
                        "preferences.github.authentication.caption",
                        fallback: "Cocxy uses the official GitHub CLI login. Tokens stay in gh/keychain storage; Cocxy only reads `gh auth status`."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.github.refresh.section", fallback: "Refresh")) {
                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.github.autoRefresh",
                            fallback: "Auto-refresh every %d s"
                        ),
                        viewModel.githubAutoRefreshInterval
                    ),
                    value: $viewModel.githubAutoRefreshInterval,
                    in: GitHubConfig.minAutoRefreshInterval...GitHubConfig.maxAutoRefreshInterval,
                    step: 15
                )
                Text(
                    viewModel.localizedString(
                        "preferences.github.autoRefresh.caption",
                        fallback: "Seconds between silent background refreshes while the pane is visible. Set to 0 to disable auto-refresh entirely (the pane still reloads on manual toggle)."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Stepper(
                    String(
                        format: viewModel.localizedString(
                            "preferences.github.maxRows",
                            fallback: "Max rows per list: %d"
                        ),
                        viewModel.githubMaxItems
                    ),
                    value: $viewModel.githubMaxItems,
                    in: GitHubConfig.minMaxItems...GitHubConfig.maxMaxItems,
                    step: 5
                )
                Text(
                    viewModel.localizedString(
                        "preferences.github.maxRows.caption",
                        fallback: "Maximum rows requested from `gh pr list` / `gh issue list` on each refresh. Clamped to the upstream gh CLI hard cap."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section(viewModel.localizedString("preferences.github.filters.section", fallback: "Filters")) {
                Toggle(
                    viewModel.localizedString(
                        "preferences.github.includeDrafts",
                        fallback: "Include draft pull requests"
                    ),
                    isOn: $viewModel.githubIncludeDrafts
                )
                Text(
                    viewModel.localizedString(
                        "preferences.github.includeDrafts.caption",
                        fallback: "When off, drafts are filtered out client-side because `gh` does not expose a --hide-drafts flag."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Picker(
                    viewModel.localizedString("preferences.github.defaultState", fallback: "Default state"),
                    selection: $viewModel.githubDefaultState
                ) {
                    Text(viewModel.localizedString("preferences.github.defaultState.open", fallback: "Open"))
                        .tag("open")
                    Text(viewModel.localizedString("preferences.github.defaultState.closed", fallback: "Closed"))
                        .tag("closed")
                    Text(viewModel.localizedString("preferences.github.defaultState.merged", fallback: "Merged (PRs only)"))
                        .tag("merged")
                    Text(viewModel.localizedString("preferences.github.defaultState.all", fallback: "All"))
                        .tag("all")
                }
            }

            PreferencesSaveButton(viewModel: viewModel, saveStatus: $saveStatus)
        }
        .formStyle(.grouped)
        .navigationTitle(viewModel.localizedString("preferences.section.github", fallback: "GitHub"))
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
    @ObservedObject var viewModel: PreferencesViewModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Cocxy Terminal")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(
                String(
                    format: viewModel.localizedString("preferences.about.version", fallback: "Version %@"),
                    CocxyVersion.current
                )
            )
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(viewModel.localizedString("preferences.about.subtitle", fallback: "Agent-aware terminal for macOS"))
                .font(.body)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 200)

            VStack(spacing: 4) {
                Text(
                    viewModel.localizedString(
                        "preferences.about.createdBy",
                        fallback: "Created by Said Arturo Lopez"
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(viewModel.localizedString("preferences.about.license", fallback: "MIT License"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(viewModel.localizedString("preferences.about.zeroTelemetry", fallback: "Zero telemetry. Zero tracking."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Divider()
                .padding(.vertical, 8)

            VStack(spacing: 8) {
                Text(viewModel.localizedString("preferences.about.updates", fallback: "Updates"))
                    .font(.headline)

                Button(viewModel.localizedString("preferences.about.checkForUpdates", fallback: "Check for Updates")) {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.sparkleUpdater?.checkForUpdates()
                    }
                }
                .buttonStyle(.borderedProminent)

                Text(
                    viewModel.localizedString(
                        "preferences.about.autoUpdates",
                        fallback: "Cocxy checks for updates automatically."
                    )
                )
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .navigationTitle(viewModel.localizedString("preferences.section.about", fallback: "About"))
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

    @MainActor
    func localizedPreferencesLabel(_ viewModel: PreferencesViewModel) -> String {
        viewModel.localizedString(
            "preferences.appearance.sidebarDensity.\(rawValue)",
            fallback: preferencesLabel
        )
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

    @MainActor
    func localizedPreferencesLabel(_ viewModel: PreferencesViewModel) -> String {
        viewModel.localizedString(
            "preferences.appearance.sidebarRowDetail.\(rawValue)",
            fallback: preferencesLabel
        )
    }
}
