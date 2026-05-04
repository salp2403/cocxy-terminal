// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabControlBar.swift - Density and row-detail controls for the Aurora vertical sidebar.

import SwiftUI

extension Design {

    struct VerticalTabControlBar: View {
        let displayMode: AuroraSidebarDisplayMode
        let primaryInfo: AuroraSidebarPrimaryInfo
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        var onDisplayModeChange: ((AuroraSidebarDisplayMode) -> Void)? = nil
        var onPrimaryInfoChange: ((AuroraSidebarPrimaryInfo) -> Void)? = nil

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: Spacing.xSmall) {
                Picker(
                    "",
                    selection: Binding(
                        get: { displayMode },
                        set: { onDisplayModeChange?($0) }
                    )
                ) {
                    ForEach(AuroraSidebarDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.verticalTabShortLabel(using: localizer)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 88)
                .help(Self.localizedSidebarDensityHelp(using: localizer))

                Menu {
                    ForEach(AuroraSidebarPrimaryInfo.allCases, id: \.self) { info in
                        Button(info.verticalTabMenuLabel(using: localizer)) {
                            onPrimaryInfoChange?(info)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: primaryInfo.verticalTabSystemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(primaryInfo.verticalTabShortLabel(using: localizer))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundStyle(palette.textMedium.resolvedColor())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(palette.glassHighlight.resolvedColor())
                    )
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: .infinity)
                .help(Self.localizedPrimaryDetailHelp(using: localizer))
            }
            .padding(.horizontal, 1)
        }

        static func localizedSidebarDensityHelp(using localizer: AppLocalizer) -> String {
            localizer.string("verticalTab.controls.sidebarDensity", fallback: "Sidebar density")
        }

        static func localizedPrimaryDetailHelp(using localizer: AppLocalizer) -> String {
            localizer.string("verticalTab.controls.primaryRowDetail", fallback: "Primary row detail")
        }
    }
}

extension AuroraSidebarDisplayMode {
    var verticalTabShortLabel: String {
        verticalTabShortLabel(using: AppLocalizer(languagePreference: .english))
    }

    func verticalTabShortLabel(using localizer: AppLocalizer) -> String {
        switch self {
        case .detailed: return localizer.string("verticalTab.density.detailed.short", fallback: "D")
        case .summary: return localizer.string("verticalTab.density.summary.short", fallback: "S")
        case .compact: return localizer.string("verticalTab.density.compact.short", fallback: "C")
        }
    }
}

extension AuroraSidebarPrimaryInfo {
    var verticalTabShortLabel: String {
        verticalTabShortLabel(using: AppLocalizer(languagePreference: .english))
    }

    var verticalTabMenuLabel: String {
        verticalTabMenuLabel(using: AppLocalizer(languagePreference: .english))
    }

    func verticalTabShortLabel(using localizer: AppLocalizer) -> String {
        switch self {
        case .state: return localizer.string("verticalTab.primary.state.short", fallback: "State")
        case .directory: return localizer.string("verticalTab.primary.directory.short", fallback: "Dir")
        case .process: return localizer.string("verticalTab.primary.process.short", fallback: "Proc")
        case .command: return localizer.string("verticalTab.primary.command.short", fallback: "Cmd")
        }
    }

    func verticalTabMenuLabel(using localizer: AppLocalizer) -> String {
        switch self {
        case .state: return localizer.string("verticalTab.primary.state.menu", fallback: "State and panes")
        case .directory: return localizer.string("verticalTab.primary.directory.menu", fallback: "Directory")
        case .process: return localizer.string("verticalTab.primary.process.menu", fallback: "Foreground process")
        case .command: return localizer.string("verticalTab.primary.command.menu", fallback: "Last command")
        }
    }

    var verticalTabSystemImage: String {
        switch self {
        case .state: return "circle.hexagongrid"
        case .directory: return "folder"
        case .process: return "cpu"
        case .command: return "terminal"
        }
    }
}
