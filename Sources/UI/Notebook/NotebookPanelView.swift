// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookPanelView.swift - SwiftUI notebook editor and output panel.

import SwiftUI

struct NotebookPanelView: View {
    @StateObject private var viewModel: NotebookPanelViewModel
    let onClose: (() -> Void)?

    init(viewModel: NotebookPanelViewModel, onClose: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                TextEditor(text: $viewModel.sourceText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minWidth: 320)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.cellPresentations) { cell in
                            NotebookCellPanel(cell: cell)
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 260)
            }
        }
        .background(Color(nsColor: CocxyColors.base))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Label(viewModel.title, systemImage: "book")
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
                try? viewModel.save()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)

            Button {
                Task { await viewModel.runAll() }
            } label: {
                Label(viewModel.isRunning ? "Running" : "Run", systemImage: "play.fill")
            }
            .controlSize(.small)
            .disabled(viewModel.isRunning)

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
}

private struct NotebookCellPanel: View {
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
                .background(Color(nsColor: CocxyColors.surface0))
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
            return Color(nsColor: CocxyColors.surface1)
        case .stderr, .error:
            return Color(nsColor: CocxyColors.red.withAlphaComponent(0.16))
        }
    }
}
