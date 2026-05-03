// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabControlBar.swift - Density and row-detail controls for the Aurora vertical sidebar.

import SwiftUI

extension Design {

    struct VerticalTabControlBar: View {
        let displayMode: AuroraSidebarDisplayMode
        let primaryInfo: AuroraSidebarPrimaryInfo
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
                        Text(mode.verticalTabShortLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 88)
                .help("Sidebar density")

                Menu {
                    ForEach(AuroraSidebarPrimaryInfo.allCases, id: \.self) { info in
                        Button(info.verticalTabMenuLabel) {
                            onPrimaryInfoChange?(info)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: primaryInfo.verticalTabSystemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(primaryInfo.verticalTabShortLabel)
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
                .help("Primary row detail")
            }
            .padding(.horizontal, 1)
        }
    }
}

extension AuroraSidebarDisplayMode {
    var verticalTabShortLabel: String {
        switch self {
        case .detailed: return "D"
        case .summary: return "S"
        case .compact: return "C"
        }
    }
}

extension AuroraSidebarPrimaryInfo {
    var verticalTabShortLabel: String {
        switch self {
        case .state: return "State"
        case .directory: return "Dir"
        case .process: return "Proc"
        case .command: return "Cmd"
        }
    }

    var verticalTabMenuLabel: String {
        switch self {
        case .state: return "State and panes"
        case .directory: return "Directory"
        case .process: return "Foreground process"
        case .command: return "Last command"
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
