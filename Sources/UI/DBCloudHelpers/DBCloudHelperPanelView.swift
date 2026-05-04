// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperPanelView.swift - Local DB/cloud helper visual panel.

import SwiftUI

struct DBCloudHelperPanelView: View {
    @ObservedObject private var viewModel: DBCloudHelperPanelViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.designThemePalette) private var designPalette
    var localizer: AppLocalizer
    private let onClose: () -> Void

    init(
        viewModel: DBCloudHelperPanelViewModel = DBCloudHelperPanelViewModel(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onClose: @escaping () -> Void = {}
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        self.localizer = localizer
        self.onClose = onClose
        viewModel.updateLocalizer(localizer)
    }

    func updatedLocalizer(_ localizer: AppLocalizer) -> DBCloudHelperPanelView {
        var copy = self
        copy.localizer = localizer
        viewModel.updateLocalizer(localizer)
        return copy
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .glassPanelBackground()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(localized("dbCloud.title", fallback: "DB/Cloud"), systemImage: "externaldrive.connected.to.line.below")
                .font(.headline)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.refresh()
            } label: {
                Label(localized("dbCloud.refresh", fallback: "Refresh"), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(localized("common.close", fallback: "Close"))
            .accessibilityLabel(localized("dbCloud.close", fallback: "Close DB/Cloud helpers"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private var panelDivider: Color {
        panelPalette.divider.resolvedColor()
    }

    private var panelAccent: Color {
        panelPalette.accent.resolvedColor()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(localized("dbCloud.kindPicker", fallback: "Kind"), selection: $viewModel.selectedKind) {
                ForEach(DBCloudHelperKind.allCases) { kind in
                    Label(kind.localizedTitle(using: localizer), systemImage: kind.systemImage).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredDescriptors) { descriptor in
                        Button {
                            viewModel.select(descriptor)
                        } label: {
                            helperRow(descriptor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
    }

    private func helperRow(_ descriptor: DBCloudHelperDescriptor) -> some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.kind.systemImage)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.name)
                    .font(.subheadline.weight(.medium))
                Text(descriptor.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(descriptor.id == viewModel.selectedHelperID ? panelSurfaceElevated : panelSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(descriptor.id == viewModel.selectedHelperID ? panelAccent : panelDivider, lineWidth: 1)
        )
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let descriptor = viewModel.selectedDescriptor {
                Label(descriptor.name, systemImage: descriptor.kind.systemImage)
                    .font(.title3.weight(.semibold))
                Text(descriptor.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                actionFields(for: descriptor.id)

                VStack(alignment: .leading, spacing: 6) {
                    Text(localized("dbCloud.command", fallback: "Command"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.commandPreview)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Button {
                        perform { try viewModel.runSelectedAction() }
                    } label: {
                        Label(localized("dbCloud.run", fallback: "Run"), systemImage: "play.fill")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    Spacer()
                }

                outputArea
            } else {
                ContentUnavailableView(
                    localized("dbCloud.empty.noHelpers", fallback: "No helpers"),
                    systemImage: "externaldrive.badge.xmark"
                )
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func actionFields(for helperID: String) -> some View {
        switch helperID {
        case "cocxy-db-postgres":
            TextField(
                localized("dbCloud.field.postgres", fallback: "Database URL or service"),
                text: $viewModel.postgresDatabase
            )
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $viewModel.sqlText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .background(panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case "cocxy-db-sqlite":
            TextField(
                localized("dbCloud.field.sqlite", fallback: "SQLite database path"),
                text: $viewModel.sqliteDatabasePath
            )
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $viewModel.sqlText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .background(panelSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        case "cocxy-aws-cli-helper":
            TextField(localized("dbCloud.field.awsProfile", fallback: "AWS profile"), text: $viewModel.awsProfile)
                .textFieldStyle(.roundedBorder)
            TextField(localized("dbCloud.field.region", fallback: "Region"), text: $viewModel.awsRegion)
                .textFieldStyle(.roundedBorder)
        default:
            Text(localized("dbCloud.action.pending", fallback: "Visual action pending for this helper."))
                .foregroundStyle(.secondary)
        }
    }

    private var outputArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("dbCloud.output", fallback: "Output"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(
                    viewModel.outputText.isEmpty
                    ? localized("dbCloud.output.empty", fallback: "No output yet.")
                    : viewModel.outputText
                )
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 120)
            .background(panelSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            viewModel.recordFailure(error)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
