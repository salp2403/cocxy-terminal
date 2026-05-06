// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorkflowPanelView.swift - SwiftUI workflow editor and run output panel.

import SwiftUI

struct WorkflowPanelView: View {
    @StateObject private var viewModel: WorkflowPanelViewModel
    var localizer: AppLocalizer
    let onClose: (() -> Void)?

    init(
        viewModel: WorkflowPanelViewModel,
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
            HSplitView {
                TextEditor(text: $viewModel.sourceText)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(minWidth: 320)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.stepPresentations) { step in
                            WorkflowStepPanel(step: step)
                        }
                    }
                    .padding(12)
                }
                .frame(minWidth: 280)
            }
        }
        .glassPanelBackground()
        .onAppear {
            viewModel.updateLocalizer(localizer)
        }
        .onChange(of: localizer.resolvedLanguage) {
            viewModel.updateLocalizer(localizer)
        }
    }

    private var toolbar: some View {
        GeometryReader { proxy in
            let presentation = AdaptivePanelToolbarPresentation.resolve(width: proxy.size.width)

            HStack(spacing: 8) {
                Label(viewModel.workflowID, systemImage: "arrow.triangle.branch")
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
                        ? localized("workflow.running", fallback: "Running")
                        : localized("workflow.run", fallback: "Run"),
                    systemImage: "play.fill",
                    compact: presentation.usesCompactActions,
                    isDisabled: viewModel.isRunning
                ) {
                    Task { await viewModel.run() }
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

private struct WorkflowStepPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designThemePalette) private var designPalette
    let step: WorkflowStepPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(step.title ?? step.id)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(step.status)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            Text(step.command.isEmpty ? " " : step.command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            if !step.stdout.isEmpty {
                outputText(step.stdout, background: panelSurfaceElevated)
            }

            if !step.stderr.isEmpty {
                outputText(
                    step.stderr,
                    background: Color(nsColor: CocxyColors.red.withAlphaComponent(0.16))
                )
            }
        }
    }

    private var statusColor: Color {
        switch step.statusKind {
        case .completed:
            return Color(nsColor: CocxyColors.green)
        case .failed:
            return Color(nsColor: CocxyColors.red)
        case .pending, .exited:
            return Color(nsColor: CocxyColors.subtext0)
        }
    }

    private func outputText(_ text: String, background: Color) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
