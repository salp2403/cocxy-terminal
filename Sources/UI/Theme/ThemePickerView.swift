// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ThemePickerView.swift - Searchable theme browser and live preview UI.

import Combine
import SwiftUI

@MainActor
final class ThemeBrowserViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filter: ThemeBrowserFilter = .all
    @Published var selectedItem: ThemeBrowserItem?
    @Published private(set) var items: [ThemeBrowserItem]
    @Published private(set) var statusMessage: String?

    private let themeEngine: ThemeEngineImpl
    private let importer: ThemeImporter
    private let applyTheme: (String) -> Void
    private var restoreThemeName: String
    private var shouldRestorePreview = false

    init(
        themeEngine: ThemeEngineImpl,
        importer: ThemeImporter,
        applyTheme: @escaping (String) -> Void
    ) {
        self.themeEngine = themeEngine
        self.importer = importer
        self.applyTheme = applyTheme
        self.restoreThemeName = themeEngine.activeTheme.metadata.name
        self.items = ThemeBrowserCatalog(themeEngine: themeEngine).items
        self.selectedItem = items.first { $0.name == themeEngine.activeTheme.metadata.name }
            ?? items.first
    }

    var filteredItems: [ThemeBrowserItem] {
        ThemeBrowserCatalog(themeEngine: themeEngine)
            .filteredItems(query: searchText, filter: filter)
    }

    var activeThemeName: String {
        themeEngine.activeTheme.metadata.name
    }

    func preview(_ item: ThemeBrowserItem) {
        selectedItem = item
        shouldRestorePreview = true
        applyTheme(item.name)
        statusMessage = "Previewing \(item.name)"
    }

    func applySelectedTheme() {
        guard let selectedItem else { return }
        applyTheme(selectedItem.name)
        restoreThemeName = selectedItem.name
        shouldRestorePreview = false
        statusMessage = "Applied \(selectedItem.name)"
    }

    func restorePreviewIfNeeded() {
        guard shouldRestorePreview else { return }
        applyTheme(restoreThemeName)
        shouldRestorePreview = false
    }

    func importTheme(from url: URL) throws {
        let imported = try importer.importExternalTheme(from: url)
        themeEngine.registerImportedTheme(imported.theme)
        reload(selecting: imported.theme.metadata.name)
        statusMessage = "Imported \(imported.theme.metadata.name)"
    }

    private func reload(selecting themeName: String? = nil) {
        items = ThemeBrowserCatalog(themeEngine: themeEngine).items
        if let themeName,
           let item = items.first(where: { $0.name == themeName }) {
            selectedItem = item
        } else if let selected = selectedItem,
                  let refreshed = items.first(where: { $0.name == selected.name }) {
            selectedItem = refreshed
        } else {
            selectedItem = items.first
        }
    }
}

struct ThemePickerView: View {
    @ObservedObject var viewModel: ThemeBrowserViewModel
    var onImportRequested: () -> Void
    var onClose: () -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            controls
            Divider().opacity(0.35)
            content
            Divider().opacity(0.35)
            footer
        }
        .frame(minWidth: 780, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "paintpalette")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(localized("theme.browser.title", fallback: "Themes"))
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(localized("common.close", fallback: "Close"))
            .accessibilityLabel(localized("common.close", fallback: "Close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            TextField(localized("theme.browser.search", fallback: "Search themes"), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 240)

            ForEach(ThemeBrowserFilter.allCases) { filter in
                Button(localizedFilterTitle(filter)) {
                    viewModel.filter = filter
                }
                .buttonStyle(ThemeFilterChipStyle(isSelected: viewModel.filter == filter))
            }

            Spacer()

            Button {
                onImportRequested()
            } label: {
                Label(localized("theme.browser.import", fallback: "Import"), systemImage: "square.and.arrow.down")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var content: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.filteredItems) { item in
                        ThemeRowView(
                            item: item,
                            isSelected: viewModel.selectedItem?.id == item.id,
                            isActive: viewModel.activeThemeName == item.name,
                            localizer: localizer
                        ) {
                            viewModel.preview(item)
                        }
                    }
                }
                .padding(10)
            }
            .frame(minWidth: 320, idealWidth: 360, maxWidth: 420)

            Divider().opacity(0.35)

            ThemePreviewPaneView(item: viewModel.selectedItem, localizer: localizer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(16)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(localized("common.cancel", fallback: "Cancel")) {
                viewModel.restorePreviewIfNeeded()
                onClose()
            }
            Button(localized("theme.browser.apply", fallback: "Apply")) {
                viewModel.applySelectedTheme()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedItem == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func localizedFilterTitle(_ filter: ThemeBrowserFilter) -> String {
        switch filter {
        case .all:
            return localized("theme.browser.filter.all", fallback: filter.displayName)
        case .dark:
            return localized("theme.browser.filter.dark", fallback: filter.displayName)
        case .light:
            return localized("theme.browser.filter.light", fallback: filter.displayName)
        case .builtIn:
            return localized("theme.browser.filter.builtIn", fallback: filter.displayName)
        case .custom:
            return localized("theme.browser.filter.custom", fallback: filter.displayName)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct ThemeRowView: View {
    let item: ThemeBrowserItem
    let isSelected: Bool
    let isActive: Bool
    let localizer: AppLocalizer
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                ThemeMiniPaletteView(palette: item.palette)
                    .frame(width: 58, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if isActive {
                            Text(localizer.string("theme.browser.active", fallback: "Active"))
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.20))
                                .clipShape(Capsule())
                        }
                    }
                    Text("\(item.variant.rawValue.capitalized) · \(item.sourceKind.displayName)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.35),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(item.name)
        .accessibilityLabel(item.name)
    }
}

private struct ThemePreviewPaneView: View {
    let item: ThemeBrowserItem?
    let localizer: AppLocalizer

    var body: some View {
        if let item {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.system(size: 18, weight: .semibold))
                            .lineLimit(1)
                        Text("\(item.variant.rawValue.capitalized) · \(item.sourceKind.displayName)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    ThemeMiniPaletteView(palette: item.palette)
                        .frame(width: 120, height: 36)
                }

                terminalPreview(item.palette)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(Array(item.palette.ansiColors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(swiftUIColor(color))
                            .frame(height: 22)
                    }
                }

                Spacer()
            }
        } else {
            ContentUnavailableView(
                localizer.string("theme.browser.noTheme", fallback: "No Theme"),
                systemImage: "paintpalette"
            )
        }
    }

    private func terminalPreview(_ palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(localizer.string("theme.browser.preview.title", fallback: "cocxy theme preview"))
                .foregroundColor(swiftUIColor(palette.foreground))
            HStack(spacing: 6) {
                Text(localizer.string("theme.browser.preview.local", fallback: "local"))
                    .foregroundColor(swiftUIColor(palette.ansiColors[safe: 2] ?? palette.foreground))
                Text(localizer.string("theme.browser.preview.main", fallback: "main"))
                    .foregroundColor(swiftUIColor(palette.ansiColors[safe: 4] ?? palette.foreground))
                Text("$")
                    .foregroundColor(swiftUIColor(palette.foreground))
            }
            Text(
                localizer.string(
                    "theme.browser.preview.selection",
                    fallback: "selection and cursor colors stay readable"
                )
            )
                .foregroundColor(swiftUIColor(palette.selectionForeground))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(swiftUIColor(palette.selectionBackground))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .font(.system(size: 13, design: .monospaced))
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(swiftUIColor(palette.background))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }
}

private struct ThemeMiniPaletteView: View {
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(sampleColors.enumerated()), id: \.offset) { _, color in
                swiftUIColor(color)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
    }

    private var sampleColors: [String] {
        [
            palette.background,
            palette.foreground,
            palette.ansiColors[safe: 1] ?? palette.foreground,
            palette.ansiColors[safe: 2] ?? palette.foreground,
            palette.ansiColors[safe: 4] ?? palette.foreground
        ]
    }
}

private struct ThemeFilterChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.20) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.35),
                        lineWidth: 1
                    )
            )
    }
}

private func swiftUIColor(_ hex: String) -> Color {
    Color(nsColor: CodableColor(hex: hex).nsColor)
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
