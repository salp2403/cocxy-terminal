// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraProjectRegistrySection.swift - Pinned and recent project navigation.

import SwiftUI

extension Design {
    struct AuroraProjectRegistrySection: View {
        let projects: [ProjectPresentationItem]
        let registryAvailable: Bool
        let onActivate: ((String) -> Void)?
        let onSetPinned: ((String, Bool) -> Void)?
        let localizer: AppLocalizer

        @Environment(\.designThemePalette) private var palette

        private var pinned: [ProjectPresentationItem] {
            projects.filter(\.isPinned)
        }

        private var recent: [ProjectPresentationItem] {
            Array(projects.lazy.filter { !$0.isPinned }.prefix(6))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if !registryAvailable {
                    unavailableRow
                } else {
                    projectGroup(
                        title: localizer.string("projectSidebar.pinned", fallback: "Pinned"),
                        projects: pinned
                    )
                    projectGroup(
                        title: localizer.string("projectSidebar.recent", fallback: "Recent"),
                        projects: recent
                    )
                }
            }
            .padding(.bottom, projects.isEmpty && registryAvailable ? 0 : Spacing.xSmall)
        }

        @ViewBuilder
        private func projectGroup(title: String, projects: [ProjectPresentationItem]) -> some View {
            if !projects.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .accessibilityAddTraits(.isHeader)

                ForEach(projects) { project in
                    projectRow(project)
                }
            }
        }

        private func projectRow(_ project: ProjectPresentationItem) -> some View {
            HStack(spacing: Spacing.xSmall) {
                if project.isAvailable, let onActivate {
                    Button(action: { onActivate(project.id) }) {
                        projectLabel(project)
                    }
                    .buttonStyle(.plain)
                    .help(project.id)
                } else {
                    projectLabel(project)
                }

                if let onSetPinned {
                    Button(action: { onSetPinned(project.id, !project.isPinned) }) {
                        Image(systemName: project.isPinned ? "pin.slash" : "pin")
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .help(project.isPinned
                        ? localizer.string("projectSidebar.unpin", fallback: "Unpin project")
                        : localizer.string("projectSidebar.pin", fallback: "Pin project"))
                }
            }
            .opacity(project.isAvailable ? (project.isLive ? 1 : 0.68) : 0.4)
            .accessibilityElement(children: .contain)
        }

        private func projectLabel(_ project: ProjectPresentationItem) -> some View {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: project.isLive ? "circle.fill" : "folder")
                    .font(.system(size: project.isLive ? 7 : 11, weight: .medium))
                    .foregroundStyle(project.isLive
                        ? palette.accent.resolvedColor()
                        : palette.textLow.resolvedColor())
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(project.parentPath)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(project.name)
            .accessibilityValue(project.parentPath)
        }

        private var unavailableRow: some View {
            HStack(spacing: Spacing.xSmall) {
                Image(systemName: "exclamationmark.triangle")
                Text(localizer.string(
                    "projectSidebar.unavailable",
                    fallback: "Project list unavailable"
                ))
                    .lineLimit(2)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.textMedium.resolvedColor())
            .accessibilityElement(children: .combine)
        }
    }
}
