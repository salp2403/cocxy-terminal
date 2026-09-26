// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraProjectRegistrySection.swift - Pinned and recent project navigation.

import SwiftUI

extension Design {
    struct AuroraProjectRegistrySection: View {
        static let taskBadgeMinimumWidth: CGFloat = 18
        static let taskBadgeHeight: CGFloat = 16

        let projects: [ProjectPresentationItem]
        let projectTaskCounts: [String: Int]
        let registryAvailable: Bool
        let recoveryMessage: String?
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
                    if let recoveryMessage {
                        recoveryRow(recoveryMessage)
                    }
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
            let taskCount = projectTaskCounts[project.id] ?? 0
            return HStack(spacing: Spacing.xSmall) {
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
                if let badgeText = Self.taskBadgeText(for: taskCount) {
                    taskBadge(badgeText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityLabel(Self.localizedProjectAccessibilityLabel(
                project.name,
                taskCount: taskCount,
                using: localizer
            ))
            .accessibilityValue(project.parentPath)
        }

        private func taskBadge(_ text: String) -> some View {
            Text(verbatim: text)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textHigh.resolvedColor())
                .lineLimit(1)
                .frame(minWidth: Self.taskBadgeMinimumWidth, minHeight: Self.taskBadgeHeight)
                .padding(.horizontal, 4)
                .background(Capsule(style: .continuous).fill(palette.accentSoft.resolvedColor()))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(palette.accent.resolvedColor().opacity(0.35), lineWidth: 0.7)
                )
                .accessibilityHidden(true)
        }

        static func taskBadgeText(for count: Int) -> String? {
            guard count > 0 else { return nil }
            return count > 99 ? "99+" : String(count)
        }

        static func localizedProjectAccessibilityLabel(
            _ projectName: String,
            taskCount: Int,
            using localizer: AppLocalizer
        ) -> String {
            guard taskCount > 0 else { return projectName }
            let key = taskCount == 1
                ? "projectSidebar.taskBadge.accessibility.one"
                : "projectSidebar.taskBadge.accessibility.many"
            let fallback = taskCount == 1 ? "%@, %d task" : "%@, %d tasks"
            return String(format: localizer.string(key, fallback: fallback), projectName, taskCount)
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

        private func recoveryRow(_ message: String) -> some View {
            HStack(alignment: .top, spacing: Spacing.xSmall) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
            .accessibilityIdentifier("project-registry-recovery")
        }

        static func localizedRecoveryMessage(
            for diagnostic: ProjectRegistryRecoveryDiagnostic,
            using localizer: AppLocalizer
        ) -> String {
            guard diagnostic.recoveredWholeDocument else {
                return localizedRecoveryMessage(
                    count: diagnostic.discardedRecordCount,
                    using: localizer
                )
            }
            return localizer.string(
                "project.registry.recovery.document",
                fallback: "The project list could not be read. Cocxy saved it in a private recovery file and started a new list."
            )
        }

        static func localizedRecoveryMessage(
            count: Int,
            using localizer: AppLocalizer
        ) -> String {
            String(
                format: localizer.string(
                    "project.registry.recovery.message",
                    fallback: "Some project metadata could not be read. Cocxy saved the rejected records (%d) in a private recovery file."
                ),
                count
            )
        }
    }
}
