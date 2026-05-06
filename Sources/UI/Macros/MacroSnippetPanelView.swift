// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroSnippetPanelView.swift - Local macros, snippets, aliases, and clipboard panel.

import SwiftUI

struct MacroSnippetPanelView: View {
    @StateObject private var viewModel: MacroSnippetPanelViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designThemePalette) private var designPalette
    var localizer: AppLocalizer
    let onClose: (() -> Void)?

    init(
        viewModel: MacroSnippetPanelViewModel,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.localizer = localizer
        self.onClose = onClose
        viewModel.updateLocalizer(localizer)
    }

    func updatedLocalizer(_ localizer: AppLocalizer) -> MacroSnippetPanelView {
        var copy = self
        copy.localizer = localizer
        viewModel.updateLocalizer(localizer)
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Picker("", selection: $viewModel.selectedSection) {
                ForEach(MacroSnippetPanelSection.allCases) { section in
                    Text(section.localizedTitle(using: localizer)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
            content
        }
        .glassPanelBackground()
        .onAppear {
            viewModel.updateLocalizer(localizer)
            viewModel.perform {
                try viewModel.refresh()
            }
        }
        .onChange(of: localizer.resolvedLanguage) {
            viewModel.updateLocalizer(localizer)
        }
    }

    private var toolbar: some View {
        GeometryReader { proxy in
            let presentation = AdaptivePanelToolbarPresentation.resolve(width: proxy.size.width)

            HStack(spacing: 8) {
                Label(localized("macros.title", fallback: "Macros"), systemImage: "keyboard")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if presentation.showsStatus {
                    AdaptivePanelToolbarStatusText(
                        text: viewModel.errorText ?? viewModel.statusText,
                        isError: viewModel.errorText != nil
                    )
                    .frame(maxWidth: presentation.usesCompactActions ? 96 : 160, alignment: .trailing)
                }

                AdaptivePanelToolbarButton(
                    title: localized("macros.refresh", fallback: "Refresh"),
                    systemImage: "arrow.clockwise",
                    compact: presentation.usesCompactActions
                ) {
                    viewModel.perform {
                        try viewModel.refresh()
                    }
                }

                AdaptivePanelToolbarButton(
                    title: localized("macros.replay", fallback: "Replay"),
                    systemImage: "play.fill",
                    compact: presentation.usesCompactActions,
                    isDisabled: viewModel.selectedMacro == nil
                ) {
                    viewModel.perform {
                        try viewModel.playSelectedMacro()
                    }
                }

                if let onClose {
                    AdaptivePanelToolbarCloseButton(
                        title: localized("macros.close", fallback: "Close macros"),
                        action: onClose
                    )
                }
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedSection {
        case .macros:
            macrosPane
        case .snippets:
            snippetsPane
        case .aliases:
            aliasesPane
        case .clipboard:
            clipboardPane
        }
    }

    private var macrosPane: some View {
        HSplitView {
            List(selection: $viewModel.selectedMacroID) {
                ForEach(viewModel.macros) { macro in
                    MacroRow(macro: macro, localizer: localizer)
                        .tag(Optional(macro.id))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(localized("macros.macroName", fallback: "Macro name"), text: $viewModel.macroName)
                        .textFieldStyle(.roundedBorder)

                    TextField(localized("macros.textEvent", fallback: "Text event"), text: $viewModel.macroTextDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button {
                            viewModel.perform {
                                try viewModel.startRecordingMacro()
                            }
                        } label: {
                            Label(localized("macros.record", fallback: "Record"), systemImage: "record.circle")
                        }
                        .disabled(viewModel.isRecording)

                        Button {
                            viewModel.perform {
                                try viewModel.recordTextEvent()
                            }
                        } label: {
                            Label(localized("macros.addText", fallback: "Add Text"), systemImage: "text.cursor")
                        }
                        .disabled(!viewModel.isRecording)

                        Button {
                            viewModel.perform {
                                try viewModel.recordKeyEvent("return")
                            }
                        } label: {
                            Label(localized("macros.returnKey", fallback: "Return"), systemImage: "return")
                        }
                        .disabled(!viewModel.isRecording)

                        Button {
                            viewModel.perform {
                                try viewModel.stopRecordingMacro()
                            }
                        } label: {
                            Label(localized("macros.stop", fallback: "Stop"), systemImage: "stop.fill")
                        }
                        .disabled(!viewModel.isRecording)

                        Button {
                            viewModel.cancelRecordingMacro()
                        } label: {
                            Label(localized("common.cancel", fallback: "Cancel"), systemImage: "xmark.circle")
                        }
                        .disabled(!viewModel.isRecording)
                    }
                    .controlSize(.small)

                    Stepper(
                        String(
                            format: localized("macros.repeat", fallback: "Repeat %dx"),
                            viewModel.repeatCount
                        ),
                        value: $viewModel.repeatCount,
                        in: 1...20
                    )

                    eventList(title: localized("macros.playback", fallback: "Playback"), rows: viewModel.playbackEvents)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 360)
        }
    }

    private var snippetsPane: some View {
        HSplitView {
            List(selection: Binding(
                get: { viewModel.selectedSnippetID },
                set: { viewModel.selectSnippet(id: $0) }
            )) {
                ForEach(viewModel.snippets) { snippet in
                    SnippetRow(snippet: snippet)
                        .tag(Optional(snippet.id))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(localized("macros.snippet.name", fallback: "Name"), text: $viewModel.snippetName)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        TextField(localized("macros.snippet.trigger", fallback: "Trigger"), text: $viewModel.snippetTrigger)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("macros.snippet.scope", fallback: "Scope"), text: $viewModel.snippetScope)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextEditor(text: $viewModel.snippetBody)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 8) {
                        Button {
                            viewModel.perform {
                                try viewModel.saveSnippetDraft()
                            }
                        } label: {
                            Label(localized("macros.saveSnippet", fallback: "Save Snippet"), systemImage: "square.and.arrow.down")
                        }

                        Button {
                            viewModel.perform {
                                try viewModel.expandSelectedSnippet()
                            }
                        } label: {
                            Label(localized("macros.expand", fallback: "Expand"), systemImage: "text.append")
                        }

                        Button {
                            viewModel.perform {
                                try viewModel.insertSelectedSnippetIntoTerminal()
                            }
                        } label: {
                            Label(localized("macros.insert", fallback: "Insert"), systemImage: "terminal")
                        }
                    }
                    .controlSize(.small)

                    if !viewModel.snippetExpansionText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localized("macros.expansion", fallback: "Expansion"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(viewModel.snippetExpansionText)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            eventList(title: localized("macros.tabStops", fallback: "Tab Stops"), rows: viewModel.snippetTabStopLabels)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 380)
        }
    }

    private var aliasesPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField(localized("macros.alias.name", fallback: "Alias name"), text: $viewModel.aliasName)
                    .textFieldStyle(.roundedBorder)
                TextField(localized("macros.alias.command", fallback: "Command"), text: $viewModel.aliasValue)
                    .textFieldStyle(.roundedBorder)
                TextField(localized("macros.alias.detail", fallback: "Detail"), text: $viewModel.aliasDetail)
                    .textFieldStyle(.roundedBorder)

                Picker(localized("macros.alias.shell", fallback: "Shell"), selection: $viewModel.selectedShell) {
                    ForEach(ShellKind.allCases, id: \.self) { shell in
                        Text(shell.rawValue).tag(shell)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)

                HStack(spacing: 8) {
                    Button {
                        viewModel.perform {
                            try viewModel.saveAliasDraft()
                        }
                    } label: {
                        Label(localized("macros.saveAlias", fallback: "Save Alias"), systemImage: "plus")
                    }

                    Button {
                        viewModel.perform {
                            try viewModel.renderAliases()
                        }
                    } label: {
                        Label(localized("macros.render", fallback: "Render"), systemImage: "doc.text")
                    }

                    Button {
                        viewModel.perform {
                            try viewModel.applyAliasesToTerminal()
                        }
                    } label: {
                        Label(localized("macros.apply", fallback: "Apply"), systemImage: "terminal")
                    }
                }
                .controlSize(.small)

                eventList(
                    title: localized("macros.aliases", fallback: "Aliases"),
                    rows: viewModel.aliases.map { "\($0.name) -> \($0.value)" }
                )

                if !viewModel.renderedAliasBlock.isEmpty {
                    Text(viewModel.renderedAliasBlock)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(panelSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var clipboardPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(localized("macros.clipboard.text", fallback: "Clipboard text"), text: $viewModel.clipboardDraft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    viewModel.recordClipboardDraft()
                } label: {
                    Label(localized("macros.record", fallback: "Record"), systemImage: "doc.on.clipboard")
                }
                Button(role: .destructive) {
                    viewModel.clearClipboard()
                } label: {
                    Label(localized("macros.clear", fallback: "Clear"), systemImage: "trash")
                }
            }
            .controlSize(.small)

            TextField(localized("common.search", fallback: "Search"), text: $viewModel.clipboardQuery)
                .textFieldStyle(.roundedBorder)

            List(viewModel.filteredClipboardItems) { item in
                Text(item.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
    }

    private var panelSurface: Color {
        Design
            .panelPalette(for: colorScheme, current: designPalette)
            .backgroundSecondary
            .resolvedColor()
    }

    private func eventList(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct MacroRow: View {
    let macro: MacroPresentation
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .lineLimit(1)
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rowDetail: String {
        String(
            format: localizer.string(
                macro.eventCount == 1 ? "macros.row.events.one" : "macros.row.events.many",
                fallback: macro.eventCount == 1 ? "%d event" : "%d events"
            ),
            macro.eventCount
        )
    }
}

private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.append")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.name)
                    .lineLimit(1)
                Text(snippet.trigger)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
