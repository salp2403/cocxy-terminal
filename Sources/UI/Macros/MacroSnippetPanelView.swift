// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroSnippetPanelView.swift - Local macros, snippets, aliases, and clipboard panel.

import SwiftUI

struct MacroSnippetPanelView: View {
    @StateObject private var viewModel: MacroSnippetPanelViewModel
    let onClose: (() -> Void)?

    init(viewModel: MacroSnippetPanelViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            Picker("", selection: $viewModel.selectedSection) {
                ForEach(MacroSnippetPanelSection.allCases) { section in
                    Text(section.rawValue).tag(section)
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
            viewModel.perform {
                try viewModel.refresh()
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("Macros", systemImage: "keyboard")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else {
                Text(viewModel.statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                viewModel.perform {
                    try viewModel.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button {
                viewModel.perform {
                    try viewModel.playSelectedMacro()
                }
            } label: {
                Label("Replay", systemImage: "play.fill")
            }
            .controlSize(.small)
            .disabled(viewModel.selectedMacro == nil)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .controlSize(.small)
                .help("Close")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
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
                    MacroRow(macro: macro)
                        .tag(Optional(macro.id))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 220, idealWidth: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Macro name", text: $viewModel.macroName)
                        .textFieldStyle(.roundedBorder)

                    TextField("Text event", text: $viewModel.macroTextDraft)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 8) {
                        Button {
                            viewModel.perform {
                                try viewModel.startRecordingMacro()
                            }
                        } label: {
                            Label("Record", systemImage: "record.circle")
                        }
                        .disabled(viewModel.isRecording)

                        Button {
                            viewModel.perform {
                                try viewModel.recordTextEvent()
                            }
                        } label: {
                            Label("Add Text", systemImage: "text.cursor")
                        }
                        .disabled(!viewModel.isRecording)

                        Button {
                            viewModel.perform {
                                try viewModel.recordKeyEvent("return")
                            }
                        } label: {
                            Label("Return", systemImage: "return")
                        }
                        .disabled(!viewModel.isRecording)

                        Button {
                            viewModel.perform {
                                try viewModel.stopRecordingMacro()
                            }
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .disabled(!viewModel.isRecording)

                        Button {
                            viewModel.cancelRecordingMacro()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .disabled(!viewModel.isRecording)
                    }
                    .controlSize(.small)

                    Stepper("Repeat \(viewModel.repeatCount)x", value: $viewModel.repeatCount, in: 1...20)

                    eventList(title: "Playback", rows: viewModel.playbackEvents)
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
                    TextField("Name", text: $viewModel.snippetName)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        TextField("Trigger", text: $viewModel.snippetTrigger)
                            .textFieldStyle(.roundedBorder)
                        TextField("Scope", text: $viewModel.snippetScope)
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
                            Label("Save Snippet", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            viewModel.perform {
                                try viewModel.expandSelectedSnippet()
                            }
                        } label: {
                            Label("Expand", systemImage: "text.append")
                        }

                        Button {
                            viewModel.perform {
                                try viewModel.insertSelectedSnippetIntoTerminal()
                            }
                        } label: {
                            Label("Insert", systemImage: "terminal")
                        }
                    }
                    .controlSize(.small)

                    if !viewModel.snippetExpansionText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Expansion")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(viewModel.snippetExpansionText)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            eventList(title: "Tab Stops", rows: viewModel.snippetTabStopLabels)
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
                TextField("Alias name", text: $viewModel.aliasName)
                    .textFieldStyle(.roundedBorder)
                TextField("Command", text: $viewModel.aliasValue)
                    .textFieldStyle(.roundedBorder)
                TextField("Detail", text: $viewModel.aliasDetail)
                    .textFieldStyle(.roundedBorder)

                Picker("Shell", selection: $viewModel.selectedShell) {
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
                        Label("Save Alias", systemImage: "plus")
                    }

                    Button {
                        viewModel.perform {
                            try viewModel.renderAliases()
                        }
                    } label: {
                        Label("Render", systemImage: "doc.text")
                    }

                    Button {
                        viewModel.perform {
                            try viewModel.applyAliasesToTerminal()
                        }
                    } label: {
                        Label("Apply", systemImage: "terminal")
                    }
                }
                .controlSize(.small)

                eventList(title: "Aliases", rows: viewModel.aliases.map { "\($0.name) -> \($0.value)" })

                if !viewModel.renderedAliasBlock.isEmpty {
                    Text(viewModel.renderedAliasBlock)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(nsColor: CocxyColors.surface0))
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
                TextField("Clipboard text", text: $viewModel.clipboardDraft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    viewModel.recordClipboardDraft()
                } label: {
                    Label("Record", systemImage: "doc.on.clipboard")
                }
                Button(role: .destructive) {
                    viewModel.clearClipboard()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
            .controlSize(.small)

            TextField("Search", text: $viewModel.clipboardQuery)
                .textFieldStyle(.roundedBorder)

            List(viewModel.filteredClipboardItems) { item in
                Text(item.text)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
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
}

private struct MacroRow: View {
    let macro: MacroPresentation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name)
                    .lineLimit(1)
                Text("\(macro.eventCount) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
