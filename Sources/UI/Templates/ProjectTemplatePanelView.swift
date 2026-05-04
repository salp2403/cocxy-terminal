// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplatePanelView.swift - Local scaffold template picker panel.

import SwiftUI

struct ProjectTemplatePanelView: View {
    @ObservedObject private var viewModel: ProjectTemplatePanelViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designThemePalette) private var designPalette
    var localizer: AppLocalizer
    let onClose: (() -> Void)?

    init(
        viewModel: ProjectTemplatePanelViewModel,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.localizer = localizer
        self.onClose = onClose
        viewModel.updateLocalizer(localizer)
    }

    func updatedLocalizer(_ localizer: AppLocalizer) -> ProjectTemplatePanelView {
        var copy = self
        copy.localizer = localizer
        viewModel.updateLocalizer(localizer)
        return copy
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
            Label(localized("templates.title", fallback: "Templates"), systemImage: "square.grid.2x2")
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
                Label(localized("templates.refresh", fallback: "Refresh"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)

            Button {
                viewModel.perform {
                    try viewModel.scaffoldSelected()
                }
            } label: {
                Label(localized("templates.scaffold", fallback: "Scaffold"), systemImage: "plus.square.on.square")
            }
            .controlSize(.small)
            .disabled(viewModel.selectedTemplate == nil)

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .controlSize(.small)
                .help(localized("common.close", fallback: "Close"))
                .accessibilityLabel(localized("templates.close", fallback: "Close templates"))
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
                    ProjectTemplateRow(template: template, localizer: localizer)
                        .tag(Optional(template.id))
                }
            }
            .listStyle(.sidebar)

            if viewModel.templates.isEmpty {
                Text(localized("templates.status.noTemplates", fallback: "No templates"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }

    private var panelSurface: Color {
        Design
            .panelPalette(for: colorScheme, current: designPalette)
            .backgroundSecondary
            .resolvedColor()
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
                        Text(localized("templates.destination", fallback: "Destination"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField(localized("templates.folderName", fallback: "Folder name"), text: $viewModel.destinationName)
                            .textFieldStyle(.roundedBorder)
                        Text(viewModel.destinationRootURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(localized("templates.variables", fallback: "Variables"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.selectedVariables, id: \.name) { variable in
                            ProjectTemplateVariableField(
                                variable: variable,
                                localizer: localizer,
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
                            Text(localized("templates.createdFiles", fallback: "Created Files"))
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
                            Text(localized("templates.pendingHooks", fallback: "Pending Hooks"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            ForEach(viewModel.pendingHookCommands, id: \.self) { command in
                                Text(command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(panelSurface)
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
                Text(localized("templates.empty.noSelection", fallback: "No template selected"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct ProjectTemplateRow: View {
    let template: ProjectTemplatePresentation
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .lineLimit(1)
                Text(rowDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var rowDetail: String {
        String(
            format: localizer.string("templates.row.detail", fallback: "%@ - %d vars"),
            template.source.localizedTitle(using: localizer),
            template.variableCount
        )
    }
}

private struct ProjectTemplateVariableField: View {
    let variable: ProjectTemplateVariable
    let localizer: AppLocalizer
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(variable.prompt)
                    .font(.system(size: 11, weight: .medium))
                if variable.required {
                    Text(localizer.string("templates.variable.required", fallback: "Required"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            TextField(variable.name, text: $value)
                .textFieldStyle(.roundedBorder)
        }
    }
}
