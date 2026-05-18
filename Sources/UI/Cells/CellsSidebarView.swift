// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellsSidebarView.swift - SwiftUI sidebar for user-owned Cocxy Cells.

import AppKit
import Foundation
import SwiftUI

struct CellSidebarRowPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let provider: CellProviderKind
    let status: CellStatus
    let metadataSummary: String

    var subtitle: String {
        "\(provider.rawValue), \(status.rawValue)"
    }

    var accessibilityLabel: String {
        metadataSummary.isEmpty
            ? "\(title), \(provider.rawValue) cell, \(status.rawValue)"
            : "\(title), \(provider.rawValue) cell, \(status.rawValue), \(metadataSummary)"
    }
}

struct CellsSidebarPresentation: Equatable {
    let rows: [CellSidebarRowPresentation]
    let runningCount: Int

    init(cells: [Cell]) {
        let sortedCells = cells.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        self.rows = sortedCells.map { cell in
            CellSidebarRowPresentation(
                id: cell.id.uuidString,
                title: cell.name,
                provider: cell.provider,
                status: cell.status,
                metadataSummary: Self.metadataSummary(cell.safeMetadata)
            )
        }
        self.runningCount = cells.filter { $0.status == .running }.count
    }

    private static func metadataSummary(_ metadata: [String: String]) -> String {
        metadata
            .filter { _, value in value != CellMetadataRedactor.redactedValue }
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "  ")
    }
}

struct CellsSidebarView: View {
    let cells: [Cell]
    let onCreate: () -> Void
    let onRefresh: () -> Void
    let onDestroy: (String) -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    var vibrancyAppearanceOverride: NSAppearance?

    private var presentation: CellsSidebarPresentation {
        CellsSidebarPresentation(cells: cells)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CellsToolbar(
                runningCount: presentation.runningCount,
                onCreate: onCreate,
                onRefresh: onRefresh,
                localizer: localizer
            )
            Divider()
            if presentation.rows.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(presentation.rows) { row in
                            CellCard(row: row, onDestroy: { onDestroy(row.id) }, localizer: localizer)
                            Divider()
                                .padding(.leading, 36)
                        }
                    }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .glassPanelBackground(vibrancyAppearanceOverride: vibrancyAppearanceOverride)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localizer.string("cells.sidebar.accessibility", fallback: "Cocxy Cells"))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(localizer.string("cells.sidebar.empty.title", fallback: "No cells"))
                .font(.system(size: 13, weight: .medium))
            Text(localizer.string(
                "cells.sidebar.empty.message",
                fallback: "Create a local or user-owned cloud cell."
            ))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct CellsToolbar: View {
    let runningCount: Int
    let onCreate: () -> Void
    let onRefresh: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(localizer.string("cells.toolbar.title", fallback: "Cells"))
                    .font(.system(size: 13, weight: .semibold))
                Text(String(
                    format: localizer.string("cells.toolbar.running", fallback: "%d running"),
                    locale: localizer.locale,
                    runningCount
                ))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(localizer.string("cells.toolbar.refresh", fallback: "Refresh cells"))
            .accessibilityLabel(localizer.string("cells.toolbar.refresh", fallback: "Refresh cells"))
            Button(action: onCreate) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .help(localizer.string("cells.toolbar.create", fallback: "Create cell"))
            .accessibilityLabel(localizer.string("cells.toolbar.create", fallback: "Create cell"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct CellCard: View {
    let row: CellSidebarRowPresentation
    let onDestroy: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(row.provider.rawValue)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text(row.status.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !row.metadataSummary.isEmpty {
                    Text(row.metadataSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Button(action: onDestroy) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .help(localizer.string("cells.card.destroy", fallback: "Destroy cell"))
            .accessibilityLabel(String(
                format: localizer.string("cells.card.destroy.accessibility", fallback: "Destroy %@"),
                locale: localizer.locale,
                row.title
            ))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.accessibilityLabel)
    }

    private var statusColor: Color {
        switch row.status {
        case .creating:
            return .blue
        case .running:
            return .green
        case .stopped:
            return .secondary
        case .failed:
            return .red
        case .destroyed:
            return .gray
        }
    }
}

struct CellCreateSheet: View {
    @Binding var provider: String
    @Binding var profile: String
    @Binding var image: String
    @Binding var host: String
    let onCreate: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizer.string("cells.create.title", fallback: "Create Cell"))
                .font(.headline)
            Picker(localizer.string("cells.create.provider", fallback: "Provider"), selection: $provider) {
                ForEach(CellProviderKind.localFirstCases, id: \.rawValue) { kind in
                    Text(kind.rawValue).tag(kind.rawValue)
                }
            }
            TextField(localizer.string("cells.create.profile", fallback: "Profile"), text: $profile)
                .textFieldStyle(.roundedBorder)
            TextField(localizer.string("cells.create.image", fallback: "Image or template"), text: $image)
                .textFieldStyle(.roundedBorder)
            TextField(localizer.string("cells.create.host", fallback: "SSH host"), text: $host)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button(localizer.string("cells.create.launch", fallback: "Create"), action: onCreate)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 380)
    }
}
