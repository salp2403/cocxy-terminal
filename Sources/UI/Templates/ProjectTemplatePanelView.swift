// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplatePanelView.swift - Local scaffold template picker panel.

import SwiftUI

struct ProjectTemplatePanelView: View {
    @StateObject private var viewModel: ProjectTemplatePanelViewModel
    let onClose: (() -> Void)?

    init(viewModel: ProjectTemplatePanelViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                templateList
                    .frame(minWidth: 240, idealWidth: 280)

                detailPane
                    .frame(minWidth: 380)
            }
        }
        .glassPanelBackground()
        .onAppear {
            if viewModel.templates.isEmpty {
                viewModel.perform {
                    try viewModel.refresh()
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label("Templates", systemImage: "square.grid.2x2")
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
                    try viewModel.scaffoldSelected()
                }
            } label: {
                Label("Scaffold", systemImage: "plus.square.on.square")
            }
            .controlSize(.small)
            .disabled(viewModel.selectedTemplate == nil)

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

    private var templateList: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { viewModel.selectedTemplateID },
                set: { viewModel.select(templateID: $0) }
            )) {
                ForEach(viewModel.templates) { template in
                    ProjectTemplateRow(template: template)
                        .tag(Optional(template.id))
                }
            }
            .listStyle(.sidebar)

            if viewModel.templates.isEmpty {
                Text("No templates")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let template = viewModel.selectedTemplate {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        Text(template.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Destination")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Folder name", text: $viewModel.destinationName)
                            .textFieldStyle(.roundedBorder)
                        Text(viewModel.destinationRootURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Variables")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.selectedVariables, id: \.name) { variable in
                            ProjectTemplateVariableField(
                                variable: variable,
                                value: Binding(
                                    get: { viewModel.value(for: variable.name) },
                                    set: { viewModel.setValue($0, for: variable.name) }
                                )
                            )
                        }
                    }

                    if !viewModel.createdFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: viewModel.progress)
                            Text("Created Files")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(viewModel.createdFiles, id: \.self) { file in
                                Text(file)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                    }

                    if !viewModel.pendingHookCommands.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pending Hooks")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(viewModel.pendingHookCommands, id: \.self) { command in
                                Text(command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(nsColor: CocxyColors.surface0))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Spacer()
                Text("No template selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ProjectTemplateRow: View {
    let template: ProjectTemplatePresentation

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .lineLimit(1)
                Text("\(template.source.rawValue) - \(template.variableCount) vars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ProjectTemplateVariableField: View {
    let variable: ProjectTemplateVariable
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(variable.prompt)
                    .font(.system(size: 11, weight: .medium))
                if variable.required {
                    Text("Required")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            TextField(variable.name, text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}
