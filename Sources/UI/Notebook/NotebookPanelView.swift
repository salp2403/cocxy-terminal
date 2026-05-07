// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookPanelView.swift - SwiftUI notebook editor and output panel.

import SwiftUI

struct NotebookPanelView: View {
    @StateObject private var viewModel: NotebookPanelViewModel
    var localizer: AppLocalizer
    let onClose: (() -> Void)?

    init(
        viewModel: NotebookPanelViewModel,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onClose: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.localizer = localizer
        self.onClose = onClose
        viewModel.updateLocalizer(localizer)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .glassPanelBackground()
        .onAppear {
            viewModel.updateLocalizer(localizer)
        }
        .onChange(of: localizer.resolvedLanguage) {
            viewModel.updateLocalizer(localizer)
        }
    }

    private var content: some View {
        GeometryReader { proxy in
            let layout = AdaptiveEditorResultPanelLayout.resolve(width: proxy.size.width)

            if layout.stacksVertically {
                VSplitView {
                    sourceEditor
                        .frame(minHeight: 180)
                    cellList
                        .frame(minHeight: 180)
                }
            } else {
                HSplitView {
                    sourceEditor
                        .frame(minWidth: 320)
                    cellList
                        .frame(minWidth: 260)
                }
            }
        }
    }

    private var sourceEditor: some View {
        TextEditor(text: $viewModel.sourceText)
            .font(.system(.body, design: .monospaced))
            .padding(8)
    }

    private var cellList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(viewModel.cellPresentations) { cell in
                    NotebookCellPanel(cell: cell)
                }
            }
            .padding(12)
        }
    }

    private var toolbar: some View {
        GeometryReader { proxy in
            let presentation = AdaptivePanelToolbarPresentation.resolve(width: proxy.size.width)

            HStack(spacing: 8) {
                Label(viewModel.title, systemImage: "book")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .truncationMode(.middle)
                    .layoutPriority(1)

                Spacer(minLength: 6)

                if presentation.showsStatus {
                    statusText
                        .frame(maxWidth: presentation.usesCompactActions ? 96 : 160, alignment: .trailing)
                }

                AdaptivePanelToolbarButton(
                    title: localized("common.save", fallback: "Save"),
                    systemImage: "square.and.arrow.down",
                    compact: presentation.usesCompactActions
                ) {
                    try? viewModel.save()
                }

                AdaptivePanelToolbarButton(
                    title: viewModel.isRunning
                        ? localized("notebook.running", fallback: "Running")
                        : localized("notebook.run", fallback: "Run"),
                    systemImage: "play.fill",
                    compact: presentation.usesCompactActions,
                    isDisabled: viewModel.isRunning
                ) {
                    Task { await viewModel.runAll() }
                }

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .frame(width: 16, height: 16)
                    }
                    .controlSize(.small)
                    .help(localized("common.close", fallback: "Close"))
                    .accessibilityLabel(localized("common.close", fallback: "Close"))
                }
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var statusText: some View {
        if let errorText = viewModel.errorText {
            Text(errorText)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text(viewModel.statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct NotebookCellPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designThemePalette) private var designPalette
    let cell: NotebookCellPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(cell.kind == .code ? (cell.language ?? "code") : "markdown")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("#\(cell.index + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text(cell.source.isEmpty ? " " : cell.source)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            ForEach(cell.outputs) { output in
                Text(output.text.isEmpty ? " " : output.text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(outputBackground(for: output.kind))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func outputBackground(for kind: NotebookCellOutputKind) -> Color {
        switch kind {
        case .stdout, .displayData:
            return panelSurfaceElevated
        case .stderr, .error:
            return Color(nsColor: CocxyColors.red.withAlphaComponent(0.16))
        }
    }

    private var panelPalette: Design.ThemePalette {
        Design.panelPalette(for: colorScheme, current: designPalette)
    }

    private var panelSurface: Color {
        panelPalette.backgroundSecondary.resolvedColor()
    }

    private var panelSurfaceElevated: Color {
        panelPalette.backgroundTertiary.resolvedColor()
    }
}
