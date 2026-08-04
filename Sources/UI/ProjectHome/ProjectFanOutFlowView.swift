// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectFanOutFlowView.swift - Embedded fan-out launch, comparison, and promotion.

import SwiftUI

struct ProjectFanOutFlowView: View {
    @ObservedObject var viewModel: ProjectFanOutFlowViewModel
    let localizer: AppLocalizer

    @Environment(\.designThemePalette) private var palette
    @State private var diffMode: DiffViewerMode = .unified

    var body: some View {
        VStack(spacing: 0) {
            flowHeader
            Divider().overlay(palette.divider.resolvedColor())
            switch viewModel.mode {
            case .inbox:
                EmptyView()
            case .launch:
                launchEditor
            case .comparison:
                comparisonSurface
            case .promotion:
                promotionPreview
            }
        }
        .background(palette.backgroundPrimary.resolvedColor())
    }

    private var flowHeader: some View {
        HStack(spacing: 12) {
            Button { viewModel.showInbox() } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(localized("projectHome.fanOut.back", fallback: "Back to Task Inbox"))
            .accessibilityLabel(localized("projectHome.fanOut.back", fallback: "Back to Task Inbox"))

            VStack(alignment: .leading, spacing: 3) {
                Text(flowTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                if let subtitle = flowSubtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.textLow.resolvedColor())
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if viewModel.isBusy {
                ProgressView().controlSize(.small)
            }
            if viewModel.mode == .comparison {
                TaskRunLifecycleControls(
                    canCancel: viewModel.canCancelRun,
                    canForget: viewModel.canForgetRun,
                    isBusy: viewModel.isBusy,
                    localizer: localizer,
                    cancel: { Task { await viewModel.cancelRun() } },
                    forget: { Task { await viewModel.forgetRun() } }
                )
                Button { Task { await viewModel.refreshComparison() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isBusy)
                .help(localized("taskRun.compare.refresh", fallback: "Refresh comparisons"))
                .accessibilityLabel(localized("taskRun.compare.refresh", fallback: "Refresh comparisons"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(palette.backgroundSecondary.resolvedColor())
    }

    private var launchEditor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                launchPrompt
                launchProviders
                launchOptions
                automaticFileRadar
                collisionBanner(viewModel.launchCollisionReport)
                messageBanner
                HStack {
                    Spacer()
                    Button { Task { await viewModel.launch() } } label: {
                        Label(
                            localized("taskRun.launch.action", fallback: "Launch"),
                            systemImage: "arrow.triangle.branch"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!viewModel.canLaunch)
                }
            }
            .padding(18)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var launchPrompt: some View {
        VStack(alignment: .leading, spacing: 7) {
            fieldLabel(localized("taskRun.launch.prompt", fallback: "Task prompt"))
            TextEditor(text: $viewModel.prompt)
                .font(.system(size: 12.5))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 110, maxHeight: 160)
                .background(palette.backgroundSecondary.resolvedColor())
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.divider.resolvedColor())
                )
                .onChange(of: viewModel.prompt) {
                    viewModel.scheduleLaunchCollisionRefresh()
                }
        }
    }

    private var launchProviders: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(localized("taskRun.launch.providers", fallback: "Providers"))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 145), spacing: 10)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(viewModel.availableProviders, id: \.rawValue) { provider in
                    Toggle(
                        provider.displayName,
                        isOn: Binding(
                            get: { viewModel.isSelected(provider) },
                            set: { viewModel.setProvider(provider, selected: $0) }
                        )
                    )
                    .toggleStyle(.checkbox)
                    .disabled(viewModel.isSelectionDisabled(provider) || viewModel.isBusy)
                }
            }
        }
    }

    private var launchOptions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                candidateStepper
                baseRefPicker
            }
            VStack(alignment: .leading, spacing: 14) {
                candidateStepper
                baseRefPicker
            }
        }
    }

    private var candidateStepper: some View {
        Stepper(
            value: $viewModel.candidateCount,
            in: max(
                TaskRunRequest.minimumCandidateCount,
                viewModel.selectedProviders.count
            )...TaskRunRequest.maximumCandidateCount
        ) {
            LabeledContent(
                localized("taskRun.launch.candidates", fallback: "Candidates"),
                value: "\(viewModel.candidateCount)"
            )
        }
        .disabled(viewModel.isBusy)
        .frame(maxWidth: 310)
    }

    private var baseRefPicker: some View {
        Picker(
            localized("taskRun.launch.baseRef", fallback: "Base ref"),
            selection: $viewModel.baseRef
        ) {
            ForEach(viewModel.availableBaseRefs, id: \.self) { ref in
                Text(ref).tag(ref)
            }
        }
        .disabled(viewModel.isBusy)
        .frame(maxWidth: 320)
    }

    @ViewBuilder
    private var automaticFileRadar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                fieldLabel(localized(
                    "projectHome.fanOut.inferredPaths",
                    fallback: "Detected file targets"
                ))
                if viewModel.isAnalyzingCollisions {
                    ProgressView().controlSize(.mini)
                }
            }
            if !viewModel.isAnalyzingCollisions && viewModel.inferredPaths.isEmpty {
                Text(localized(
                    "projectHome.fanOut.noInferredPaths",
                    fallback: "No file targets detected"
                ))
                .font(.system(size: 10.5))
                .foregroundStyle(palette.textLow.resolvedColor())
            }
            ForEach(viewModel.inferredPaths.prefix(8), id: \.self) { path in
                HStack(spacing: 8) {
                    Image(systemName: "scope")
                        .foregroundStyle(palette.textLow.resolvedColor())
                    Text(path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(palette.backgroundSecondary.resolvedColor())
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if viewModel.inferredPaths.count > 8 {
                Text(verbatim: "+\(viewModel.inferredPaths.count - 8)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
        }
    }

    private var comparisonSurface: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 760 {
                HStack(spacing: 0) {
                    comparisonSidebar
                        .frame(width: min(285, max(235, proxy.size.width * 0.28)))
                    Divider().overlay(palette.divider.resolvedColor())
                    comparisonDetail
                }
            } else {
                VStack(spacing: 0) {
                    comparisonSidebar
                        .frame(height: min(230, max(170, proxy.size.height * 0.34)))
                    Divider().overlay(palette.divider.resolvedColor())
                    comparisonDetail
                }
            }
        }
    }

    private var comparisonSidebar: some View {
        VStack(spacing: 0) {
            collisionBanner(viewModel.candidateCollisionReport)
                .padding(.horizontal, 10)
                .padding(.top, 10)
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.run?.candidates ?? []) { candidate in
                        Button { viewModel.selectedCandidateID = candidate.id } label: {
                            candidateRow(candidate)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
        .background(palette.backgroundSecondary.resolvedColor())
    }

    private func candidateRow(_ candidate: TaskRunCandidate) -> some View {
        let comparison = viewModel.comparisons.first { $0.id == candidate.id }
        let selected = viewModel.selectedCandidateID == candidate.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(candidate.status))
                    .frame(width: 7, height: 7)
                Text(candidate.provider.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(localizedStatus(candidate.status.rawValue))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
            Text(candidate.worktree?.branch ?? candidate.id)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.textMedium.resolvedColor())
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(fileCountLabel(comparison?.changedFileCount ?? 0))
                Spacer()
                Text("+\(comparison?.additions ?? 0) -\(comparison?.deletions ?? 0)")
                Spacer()
                Text(costLabel(candidate.estimatedCostMicros))
            }
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(palette.textLow.resolvedColor())
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? palette.accent.resolvedColor().opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private var comparisonDetail: some View {
        VStack(spacing: 0) {
            DiffViewerView(
                diffs: viewModel.selectedComparison?.diffs ?? [],
                mode: $diffMode,
                onStage: { _, _, _ in },
                localizer: localizer,
                showsStagingControls: false
            )
            Divider().overlay(palette.divider.resolvedColor())
            HStack(spacing: 9) {
                messageBanner
                Spacer(minLength: 8)
                if viewModel.canRecycleSelectedCandidate {
                    Button { Task { await viewModel.recycleSelectedCandidate() } } label: {
                        Label(
                            localized("projectHome.fanOut.recycle", fallback: "Recycle"),
                            systemImage: "arrow.clockwise.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                }
                Button { Task { await viewModel.preparePromotion() } } label: {
                    Label(
                        localized("taskRun.compare.promote", fallback: "Promote"),
                        systemImage: "checkmark.seal"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canPreparePromotion)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
        }
    }

    private var promotionPreview: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    collisionBanner(viewModel.promotionPreview?.collisionReport ?? .empty)
                    fieldLabel(localized("projectHome.fanOut.cleanupPlan", fallback: "Confirmed cleanup plan"))
                    ForEach(viewModel.promotionPreview?.cleanupEntries ?? []) { entry in
                        cleanupRow(entry)
                    }
                    if viewModel.promotionPreview?.cleanupEntries.isEmpty == true {
                        Text(localized(
                            "projectHome.fanOut.cleanupEmpty",
                            fallback: "No managed task worktree is eligible for cleanup."
                        ))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textMedium.resolvedColor())
                    }
                    if let preview = viewModel.promotionPreview {
                        cleanupPlanExceptions(preview)
                    }
                    messageBanner
                }
                .padding(18)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            Divider().overlay(palette.divider.resolvedColor())
            HStack {
                Button(localized("common.cancel", fallback: "Cancel")) {
                    viewModel.cancelPromotion()
                }
                .disabled(viewModel.isBusy)
                Spacer()
                Button { Task { await viewModel.confirmPromotion() } } label: {
                    Label(
                        localized("projectHome.fanOut.confirmPromotion", fallback: "Merge and Clean Up"),
                        systemImage: "checkmark.seal.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy || viewModel.promotionPreview == nil)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
        }
    }

    private func cleanupRow(_ entry: TaskRunCleanupPreviewEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: cleanupIcon(entry.disposition))
                .foregroundStyle(cleanupColor(entry.disposition))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.worktree.branch)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Text(entry.worktree.path.path)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(cleanupLabel(entry.disposition))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(palette.textMedium.resolvedColor())
        }
        .padding(10)
        .background(palette.backgroundSecondary.resolvedColor())
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func cleanupPlanExceptions(_ preview: TaskRunPromotionPreview) -> some View {
        let model = WorktreeBatchCleanupSheetViewModel(
            plan: preview.mergedCleanupPlan,
            baseRef: preview.selectedComparison.candidate.worktree?.branch ?? preview.run.baseRef
        )
        let blocked = model.localizedBlockedDetails(using: localizer)
        let skipped = model.localizedSkippedDetails(using: localizer)
        if !blocked.isEmpty {
            fieldLabel(WorktreeBatchCleanupSheet.localizedBlockedSectionTitle(using: localizer))
            ForEach(blocked, id: \.self) { cleanupExceptionRow($0, icon: "exclamationmark.octagon") }
        }
        if !skipped.isEmpty {
            fieldLabel(WorktreeBatchCleanupSheet.localizedSkippedSectionTitle(using: localizer))
            ForEach(skipped, id: \.self) { cleanupExceptionRow($0, icon: "forward") }
        }
    }

    private func cleanupExceptionRow(_ detail: String, icon: String) -> some View {
        Label(detail, systemImage: icon)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(palette.textMedium.resolvedColor())
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.backgroundSecondary.resolvedColor())
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func collisionBanner(_ report: TaskCollisionReport) -> some View {
        if !report.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Label(
                    localized("projectHome.fanOut.collision", fallback: "Potential file collision"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .semibold))
                ForEach(report.collisions.prefix(8)) { collision in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(collision.path)
                            .font(.system(size: 9.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(collision.participants.map(\.label).joined(separator: " | "))
                            .font(.system(size: 9.5))
                            .foregroundStyle(palette.textMedium.resolvedColor())
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(Color(nsColor: .systemOrange))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .systemOrange).opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder
    private var messageBanner: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.octagon.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: .systemRed))
                .lineLimit(3)
                .textSelection(.enabled)
        } else if let issue = viewModel.durabilityNotice {
            Label(issue, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: .systemOrange))
                .lineLimit(5)
                .textSelection(.enabled)
        } else if let success = viewModel.successMessage {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.system(size: 10.5))
                .foregroundStyle(Color(nsColor: .systemGreen))
                .lineLimit(10)
                .textSelection(.enabled)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(palette.textMedium.resolvedColor())
    }

    private var flowTitle: String {
        switch viewModel.mode {
        case .inbox: return ""
        case .launch: return localized("taskRun.launch.title", fallback: "Fan Out Task")
        case .comparison: return localized("taskRun.compare.title", fallback: "Compare Task Candidates")
        case .promotion: return localized("projectHome.fanOut.promotion", fallback: "Promotion Preview")
        }
    }

    private var flowSubtitle: String? {
        switch viewModel.mode {
        case .comparison, .promotion:
            guard let run = viewModel.run else { return nil }
            return "\(run.baseRef) | \(localizedStatus(run.status.rawValue)) | \(run.id)"
        case .launch:
            return viewModel.projectRoot.path
        case .inbox:
            return nil
        }
    }

    private func fileCountLabel(_ count: Int) -> String {
        String(
            format: localized(
                count == 1 ? "taskRun.compare.file.one" : "taskRun.compare.file.many",
                fallback: count == 1 ? "%d file" : "%d files"
            ),
            count
        )
    }

    private func costLabel(_ micros: Int64) -> String {
        guard micros > 0 else {
            return localized("taskRun.compare.costUnavailable", fallback: "N/A")
        }
        return ProjectActivityMetricsFormatter.cost(micros, locale: localizer.locale)
    }

    private func localizedStatus(_ rawValue: String) -> String {
        localized("taskRun.status.\(rawValue)", fallback: rawValue.capitalized)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    private func statusColor(_ status: TaskRunCandidateStatus) -> Color {
        switch status {
        case .preparing: return palette.textLow.resolvedColor()
        case .running: return palette.accent.resolvedColor()
        case .finished, .promoted: return Color(nsColor: .systemGreen)
        case .failed, .orphaned: return Color(nsColor: .systemRed)
        case .discarded: return Color(nsColor: .systemOrange)
        }
    }

    private func cleanupIcon(_ disposition: TaskRunCleanupDisposition) -> String {
        switch disposition {
        case .removeMerged: return "trash"
        case .discardCandidate: return "trash.slash"
        case .retainWinner: return "pin"
        }
    }

    private func cleanupColor(_ disposition: TaskRunCleanupDisposition) -> Color {
        switch disposition {
        case .retainWinner: return Color(nsColor: .systemGreen)
        case .removeMerged, .discardCandidate: return Color(nsColor: .systemOrange)
        }
    }

    private func cleanupLabel(_ disposition: TaskRunCleanupDisposition) -> String {
        switch disposition {
        case .removeMerged:
            return localized("projectHome.fanOut.cleanup.remove", fallback: "Remove after merge")
        case .discardCandidate:
            return localized("projectHome.fanOut.cleanup.discard", fallback: "Discard candidate")
        case .retainWinner:
            return localized("projectHome.fanOut.cleanup.retain", fallback: "Retain winner")
        }
    }
}
