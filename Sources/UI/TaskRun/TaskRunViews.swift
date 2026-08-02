// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskRunViews.swift - Launch and read-only comparison surfaces for parallel tasks.

import Foundation
import SwiftUI

@MainActor
final class TaskRunLaunchSheetViewModel: ObservableObject {
    let availableProviders: [AgentTeamProvider]
    let availableBaseRefs: [String]

    @Published var prompt = ""
    @Published private(set) var selectedProviders: [AgentTeamProvider]
    @Published var candidateCount: Int
    @Published var baseRef: String
    @Published private(set) var isLaunching = false
    @Published private(set) var errorMessage: String?

    init(
        availableProviders: [AgentTeamProvider] = AgentTeamProvider.allCases,
        availableBaseRefs: [String],
        initialBaseRef: String
    ) {
        self.availableProviders = availableProviders
        let preferred = [AgentTeamProvider.claudeCode, .codex]
            .filter(availableProviders.contains)
        let selectedProviders = preferred.isEmpty
            ? Array(availableProviders.prefix(1))
            : preferred
        self.selectedProviders = selectedProviders
        self.candidateCount = max(
            TaskRunRequest.minimumCandidateCount,
            selectedProviders.count
        )
        self.availableBaseRefs = Self.uniqueBaseRefs(
            [initialBaseRef] + availableBaseRefs + ["HEAD"]
        )
        self.baseRef = Self.normalized(initialBaseRef) ?? "HEAD"
    }

    var canLaunch: Bool {
        !isLaunching && (try? makeRequest()) != nil
    }

    func isSelected(_ provider: AgentTeamProvider) -> Bool {
        selectedProviders.contains(provider)
    }

    func isSelectionDisabled(_ provider: AgentTeamProvider) -> Bool {
        !isSelected(provider)
            && selectedProviders.count >= TaskRunRequest.maximumCandidateCount
    }

    func setProvider(_ provider: AgentTeamProvider, selected: Bool) {
        if selected {
            guard !selectedProviders.contains(provider),
                  selectedProviders.count < TaskRunRequest.maximumCandidateCount else {
                return
            }
            selectedProviders.append(provider)
            selectedProviders.sort { lhs, rhs in
                let left = availableProviders.firstIndex(of: lhs) ?? .max
                let right = availableProviders.firstIndex(of: rhs) ?? .max
                return left < right
            }
            candidateCount = max(candidateCount, selectedProviders.count)
        } else {
            selectedProviders.removeAll { $0 == provider }
        }
        candidateCount = min(
            TaskRunRequest.maximumCandidateCount,
            max(TaskRunRequest.minimumCandidateCount, candidateCount)
        )
        errorMessage = nil
    }

    func makeRequest() throws -> TaskRunRequest {
        try TaskRunRequest.make(
            prompt: prompt,
            agents: selectedProviders.map(\.rawValue).joined(separator: ","),
            count: candidateCount,
            baseRef: baseRef
        )
    }

    func beginLaunch() {
        isLaunching = true
        errorMessage = nil
    }

    func finishLaunch(error: String?) {
        isLaunching = false
        errorMessage = error
    }

    private static func uniqueBaseRefs(_ refs: [String]) -> [String] {
        var seen = Set<String>()
        return refs.compactMap { raw in
            guard let value = normalized(raw), seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    private static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct TaskRunLaunchSheet: View {
    @ObservedObject var viewModel: TaskRunLaunchSheetViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onCancel: () -> Void
    let onLaunch: (TaskRunRequest) -> Void

    private let providerColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("taskRun.launch.title", fallback: "Fan Out Task"))
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("taskRun.launch.prompt", fallback: "Task prompt"))
                    .font(.headline)
                TextEditor(text: $viewModel.prompt)
                    .font(.system(size: 13))
                    .frame(height: 120)
                    .padding(6)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(localized("taskRun.launch.providers", fallback: "Providers"))
                    .font(.headline)
                ScrollView {
                    LazyVGrid(columns: providerColumns, alignment: .leading, spacing: 8) {
                        ForEach(viewModel.availableProviders, id: \.rawValue) { provider in
                            Toggle(
                                provider.displayName,
                                isOn: Binding(
                                    get: { viewModel.isSelected(provider) },
                                    set: { viewModel.setProvider(provider, selected: $0) }
                                )
                            )
                            .toggleStyle(.checkbox)
                            .disabled(viewModel.isSelectionDisabled(provider))
                        }
                    }
                }
                .frame(height: 150)
            }

            HStack(spacing: 20) {
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

                Picker(
                    localized("taskRun.launch.baseRef", fallback: "Base ref"),
                    selection: $viewModel.baseRef
                ) {
                    ForEach(viewModel.availableBaseRefs, id: \.self) { ref in
                        Text(ref).tag(ref)
                    }
                }
                .frame(maxWidth: 260)
            }

            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                if viewModel.isLaunching {
                    ProgressView()
                        .controlSize(.small)
                    Text(localized("taskRun.launch.progress", fallback: "Launching candidates..."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localized("common.cancel", fallback: "Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(viewModel.isLaunching)
                Button {
                    guard let request = try? viewModel.makeRequest() else { return }
                    onLaunch(request)
                } label: {
                    Label(
                        localized("taskRun.launch.action", fallback: "Launch"),
                        systemImage: "arrow.triangle.branch"
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canLaunch)
            }
        }
        .padding(20)
        .frame(width: 620)
        .glassPanelBackground()
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

@MainActor
final class TaskRunComparisonSheetViewModel: ObservableObject {
    @Published private(set) var run: TaskRun
    @Published private(set) var comparisons: [TaskRunCandidateComparison] = []
    @Published var selectedCandidateID: String?
    @Published var mode: DiffViewerMode = .unified
    @Published private(set) var isLoading = false
    @Published private(set) var isPromoting = false
    @Published private(set) var errorMessage: String?

    private var loadRevision = 0

    init(run: TaskRun) {
        self.run = run
        self.selectedCandidateID = Self.firstAvailableCandidate(in: run)?.id
    }

    var selectedComparison: TaskRunCandidateComparison? {
        guard let selectedCandidateID else { return comparisons.first }
        return comparisons.first { $0.id == selectedCandidateID }
    }

    var selectedCandidate: TaskRunCandidate? {
        guard let selectedCandidateID else { return Self.firstAvailableCandidate(in: run) }
        return run.candidates.first { $0.id == selectedCandidateID }
    }

    var canPromote: Bool {
        run.status == .running
            && selectedCandidate?.worktree != nil
            && selectedCandidate?.status != .orphaned
            && !isLoading
            && !isPromoting
    }

    @discardableResult
    func beginReload() -> Int {
        loadRevision += 1
        isLoading = true
        errorMessage = nil
        return loadRevision
    }

    func apply(
        run: TaskRun,
        comparisons: [TaskRunCandidateComparison],
        revision: Int
    ) {
        guard revision == loadRevision, !isPromoting else { return }
        self.run = run
        self.comparisons = comparisons
        if let selectedCandidateID,
           run.candidates.contains(where: {
               $0.id == selectedCandidateID && $0.status != .orphaned
           }) {
            self.selectedCandidateID = selectedCandidateID
        } else {
            selectedCandidateID = Self.firstAvailableCandidate(in: run)?.id
        }
        isLoading = false
        errorMessage = nil
    }

    func failReload(_ message: String, revision: Int) {
        guard revision == loadRevision, !isPromoting else { return }
        isLoading = false
        errorMessage = message
    }

    func beginPromotion() {
        isPromoting = true
        isLoading = false
        loadRevision += 1
        errorMessage = nil
    }

    func failPromotion(_ message: String) {
        isPromoting = false
        errorMessage = message
    }

    static func costLabel(micros: Int64, unavailable: String) -> String {
        guard micros > 0 else { return unavailable }
        return String(format: "$%.4f", Double(micros) / 1_000_000)
    }

    private static func firstAvailableCandidate(in run: TaskRun) -> TaskRunCandidate? {
        run.candidates.first { $0.status != .orphaned && $0.worktree != nil }
    }
}

struct TaskRunComparisonSheet: View {
    @ObservedObject var viewModel: TaskRunComparisonSheetViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    let onRefresh: () -> Void
    let onPromote: (String) -> Void
    let onDismiss: () -> Void

    @State private var showsPromotionConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                candidateList
                Divider()
                DiffViewerView(
                    diffs: viewModel.selectedComparison?.diffs ?? [],
                    mode: $viewModel.mode,
                    onStage: { _, _, _ in },
                    localizer: localizer,
                    showsStagingControls: false
                )
            }
            Divider()
            footer
        }
        .frame(width: 1_020, height: 680)
        .glassPanelBackground()
        .alert(
            promotionTitle,
            isPresented: $showsPromotionConfirmation
        ) {
            Button(localized("common.cancel", fallback: "Cancel"), role: .cancel) {}
            Button(
                localized("taskRun.compare.promote", fallback: "Promote"),
                role: .destructive
            ) {
                guard let candidateID = viewModel.selectedCandidateID else { return }
                onPromote(candidateID)
            }
        } message: {
            Text(promotionMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("taskRun.compare.title", fallback: "Compare Task Candidates"))
                    .font(.title3.weight(.semibold))
                Text("\(viewModel.run.originRepoPath.lastPathComponent) | \(viewModel.run.baseRef) | \(localizedStatus(viewModel.run.status.rawValue))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(localized("taskRun.compare.refresh", fallback: "Refresh comparisons"))
            .disabled(viewModel.isLoading || viewModel.isPromoting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var candidateList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(viewModel.run.candidates) { candidate in
                    Button {
                        viewModel.selectedCandidateID = candidate.id
                    } label: {
                        candidateRow(candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 260)
    }

    private func candidateRow(_ candidate: TaskRunCandidate) -> some View {
        let comparison = viewModel.comparisons.first { $0.id == candidate.id }
        let selected = candidate.id == viewModel.selectedCandidateID
        let fileCount = comparison?.changedFileCount ?? 0
        let fileCountLabel = String(
            format: localized(
                fileCount == 1
                    ? "taskRun.compare.file.one"
                    : "taskRun.compare.file.many",
                fallback: fileCount == 1 ? "%d file" : "%d files"
            ),
            fileCount
        )
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(statusColor(candidate.status))
                Text(candidate.provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(localizedStatus(candidate.status.rawValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(candidate.worktree?.branch ?? candidate.id)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(fileCountLabel)
                Spacer()
                Text("+\(comparison?.additions ?? 0) -\(comparison?.deletions ?? 0)")
                Spacer()
                Text(TaskRunComparisonSheetViewModel.costLabel(
                    micros: candidate.estimatedCostMicros,
                    unavailable: localized("taskRun.compare.costUnavailable", fallback: "N/A")
                ))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.14) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = viewModel.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else if viewModel.isPromoting {
                ProgressView()
                    .controlSize(.small)
                Text(localized("taskRun.compare.promoting", fallback: "Promoting candidate..."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(localized("common.done", fallback: "Done"), action: onDismiss)
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isPromoting)
            Button {
                showsPromotionConfirmation = true
            } label: {
                Label(
                    localized("taskRun.compare.promote", fallback: "Promote"),
                    systemImage: "checkmark.seal"
                )
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canPromote)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var promotionTitle: String {
        guard let candidate = viewModel.selectedCandidate else {
            return localized("taskRun.compare.promote", fallback: "Promote")
        }
        return String(
            format: localized(
                "taskRun.compare.confirmTitle",
                fallback: "Promote %@?"
            ),
            candidate.provider.displayName
        )
    }

    private var promotionMessage: String {
        guard let candidate = viewModel.selectedCandidate else { return "" }
        let branch = candidate.worktree?.branch ?? candidate.id
        let discardedCount = max(0, viewModel.run.candidates.count - 1)
        return String(
            format: localized(
                discardedCount == 1
                    ? "taskRun.compare.confirmMessage.one"
                    : "taskRun.compare.confirmMessage.many",
                fallback: discardedCount == 1
                    ? "Merge branch %@ into the origin checkout and remove %d other task worktree directory."
                    : "Merge branch %@ into the origin checkout and remove %d other task worktree directories."
            ),
            branch,
            discardedCount
        )
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    private func localizedStatus(_ rawValue: String) -> String {
        localizer.string(
            "taskRun.status.\(rawValue)",
            fallback: rawValue.capitalized
        )
    }

    private func statusColor(_ status: TaskRunCandidateStatus) -> Color {
        switch status {
        case .preparing:
            return .secondary
        case .running:
            return .blue
        case .finished, .promoted:
            return .green
        case .failed, .orphaned:
            return .red
        case .discarded:
            return .orange
        }
    }
}
