// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectHomePanelView.swift - Dense project context with a unified task inbox.

import SwiftUI

struct ProjectHomePanelView: View {
    @StateObject private var viewModel: ProjectHomePanelViewModel
    @StateObject private var fanOutViewModel: ProjectFanOutFlowViewModel
    @ObservedObject private var inboxStore: TaskInboxStore
    @ObservedObject private var fanOutCoordinator: ProjectFanOutCoordinator
    let localizer: AppLocalizer

    @Environment(\.designThemePalette) private var palette

    init(
        viewModel: ProjectHomePanelViewModel,
        fanOutViewModel: ProjectFanOutFlowViewModel,
        inboxStore: TaskInboxStore,
        fanOutCoordinator: ProjectFanOutCoordinator,
        localizer: AppLocalizer
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _fanOutViewModel = StateObject(wrappedValue: fanOutViewModel)
        self.inboxStore = inboxStore
        self.fanOutCoordinator = fanOutCoordinator
        self.localizer = localizer
    }

    private var entries: [TaskInboxEntry] {
        inboxStore.entries(for: viewModel.projectID)
    }

    var body: some View {
        VStack(spacing: 0) {
            projectHeader
            Divider().overlay(palette.divider.resolvedColor())
            if fanOutViewModel.mode == .inbox {
                GeometryReader { proxy in
                    if proxy.size.width >= 760 {
                        HStack(spacing: 0) {
                            taskInbox(scrolls: true)
                                .frame(minWidth: 430, maxWidth: .infinity)
                            Divider().overlay(palette.divider.resolvedColor())
                            projectContext
                                .frame(width: min(310, max(250, proxy.size.width * 0.31)))
                        }
                    } else {
                        ScrollView {
                            VStack(spacing: 0) {
                                taskInbox(scrolls: false)
                                Divider().overlay(palette.divider.resolvedColor())
                                projectContext
                            }
                        }
                    }
                }
            } else {
                ProjectFanOutFlowView(viewModel: fanOutViewModel, localizer: localizer)
            }
        }
        .glassPanelBackground()
        .task {
            viewModel.loadContext()
            await consumePendingFanOutRequest()
        }
        .onReceive(fanOutCoordinator.$request.compactMap { $0 }) { request in
            Task { @MainActor in
                await Task.yield()
                await consumeFanOutRequest(request)
            }
        }
        .sheet(isPresented: $viewModel.isTeamSheetPresented) {
            ProjectHomeTeamLaunchSheet(
                projectName: viewModel.displayName,
                localizer: localizer,
                isLaunching: viewModel.isLaunchingTeam,
                onCancel: { viewModel.isTeamSheetPresented = false },
                onLaunch: { request in
                    Task { await viewModel.launchTeam(request) }
                }
            )
        }
        .alert(
            localizer.string("projectHome.action.error.title", fallback: "Action Failed"),
            isPresented: Binding(
                get: { viewModel.actionErrorMessage != nil },
                set: { if !$0 { viewModel.actionErrorMessage = nil } }
            )
        ) {
            Button(localizer.string("common.ok", fallback: "OK")) {
                viewModel.actionErrorMessage = nil
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
    }

    private var projectHeader: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 2)
                .fill(projectAccent)
                .frame(width: 4, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(viewModel.displayName)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        projectMetadata(includeRemote: true, includeStatus: true)
                        projectMetadata(includeRemote: false, includeStatus: true)
                        projectMetadata(includeRemote: false, includeStatus: false)
                    }
                }
            }

            Spacer(minLength: 12)
            quickActions
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(palette.backgroundSecondary.resolvedColor())
    }

    private var quickActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                quickActionButtons(compact: false)
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 6) {
                quickActionButtons(compact: true)
            }
            .fixedSize(horizontal: true, vertical: false)
            quickActionsMenu
        }
    }

    @ViewBuilder
    private func quickActionButtons(compact: Bool) -> some View {
        projectAction(
            title: localizer.string("projectHome.action.newSession", fallback: "New Session"),
            icon: "plus.square",
            compact: compact,
            action: viewModel.actions.createSession
        )
        if let createWorktree = viewModel.actions.createWorktree {
            projectAction(
                title: localizer.string("projectHome.action.newWorktree", fallback: "New Worktree"),
                icon: "arrow.triangle.branch",
                compact: compact,
                action: createWorktree
            )
        }
        projectAction(
            title: localizer.string("projectHome.action.launchTeam", fallback: "Launch Team"),
            icon: "person.3",
            compact: compact,
            action: { viewModel.isTeamSheetPresented = true }
        )
        if viewModel.worktreeConfig.enabled {
            projectAction(
                title: localizer.string("projectHome.action.fanOut", fallback: "Fan Out"),
                icon: "square.stack.3d.up",
                compact: compact,
                action: { fanOutViewModel.showLaunch() }
            )
        }
        projectAction(
            title: localizer.string("projectHome.action.codeReview", fallback: "Code Review"),
            icon: "doc.text.magnifyingglass",
            compact: compact,
            action: viewModel.actions.openCodeReview
        )
    }

    @ViewBuilder
    private func projectAction(
        title: String,
        icon: String,
        compact: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if compact {
            Button(action: action) {
                Image(systemName: icon).frame(width: 24, height: 22)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(title)
            .accessibilityLabel(title)
        } else {
            actionButton(title: title, icon: icon, action: action)
        }
    }

    private var quickActionsMenu: some View {
        Menu {
            Button(
                localizer.string("projectHome.action.newSession", fallback: "New Session"),
                action: viewModel.actions.createSession
            )
            if let createWorktree = viewModel.actions.createWorktree {
                Button(
                    localizer.string("projectHome.action.newWorktree", fallback: "New Worktree"),
                    action: createWorktree
                )
            }
            Button(localizer.string("projectHome.action.launchTeam", fallback: "Launch Team")) {
                viewModel.isTeamSheetPresented = true
            }
            if viewModel.worktreeConfig.enabled {
                Button(localizer.string("projectHome.action.fanOut", fallback: "Fan Out")) {
                    fanOutViewModel.showLaunch()
                }
            }
            Button(
                localizer.string("projectHome.action.codeReview", fallback: "Code Review"),
                action: viewModel.actions.openCodeReview
            )
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 24, height: 22)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(localizer.string("projectHome.action.menu", fallback: "Project Actions"))
        .accessibilityLabel(localizer.string("projectHome.action.menu", fallback: "Project Actions"))
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
    }

    private func metadataLabel(icon: String, text: String) -> some View {
        Label {
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(palette.textMedium.resolvedColor())
    }

    private func projectMetadata(includeRemote: Bool, includeStatus: Bool) -> some View {
        HStack(spacing: 12) {
            metadataLabel(
                icon: "arrow.triangle.branch",
                text: viewModel.gitMetadata?.branch
                    ?? localizer.string("projectHome.git.loading", fallback: "Git status pending")
            )
            if includeStatus, let summary = viewModel.gitMetadata?.statusSummary {
                metadataLabel(icon: "circle.lefthalf.filled", text: summary)
            }
            if includeRemote, let remote = viewModel.gitMetadata?.remoteOrigin {
                metadataLabel(icon: "network", text: remote)
            }
        }
    }

    @ViewBuilder
    private func taskInbox(scrolls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                localizer.string("projectHome.inbox.title", fallback: "Task Inbox"),
                count: entries.count
            )
            inboxAvailability
            if scrolls {
                ScrollView { taskRows }
            } else {
                taskRows
            }
        }
    }

    @ViewBuilder
    private var inboxAvailability: some View {
        switch inboxStore.snapshot.availability {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(localizer.string("projectHome.inbox.loading", fallback: "Loading project tasks"))
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.textMedium.resolvedColor())
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        case .partial:
            availabilityBanner(
                localizer.string(
                    "projectHome.inbox.partial",
                    fallback: "Some project activity is temporarily unavailable."
                )
            )
        case .failed:
            availabilityBanner(
                localizer.string("projectHome.inbox.failed", fallback: "Project activity is unavailable.")
            )
        case .ready:
            EmptyView()
        }
    }

    private func availabilityBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(palette.textMedium.resolvedColor())
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
    }

    @ViewBuilder
    private var taskRows: some View {
        LazyVStack(spacing: 0) {
            if entries.isEmpty, inboxStore.snapshot.availability == .ready {
                Text(localizer.string("projectHome.inbox.empty", fallback: "No project tasks"))
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(entries) { entry in
                    taskRow(entry)
                    Divider().overlay(palette.divider.resolvedColor()).padding(.leading, 48)
                }
            }
        }
    }

    @ViewBuilder
    private func taskRow(_ entry: TaskInboxEntry) -> some View {
        if let navigation = entry.navigation,
           entry.kind != .fanOut || viewModel.worktreeConfig.enabled {
            Button { activate(entry, navigation: navigation) } label: {
                taskRowContent(entry)
            }
            .buttonStyle(.plain)
        } else {
            taskRowContent(entry)
        }
    }

    private func activate(_ entry: TaskInboxEntry, navigation: TaskInboxNavigation) {
        if entry.kind == .fanOut,
           viewModel.worktreeConfig.enabled,
           let runID = navigation.sessionID {
            Task { await fanOutViewModel.showComparison(runID: runID) }
            return
        }
        viewModel.actions.activateEntry(navigation)
    }

    private func consumePendingFanOutRequest() async {
        guard let destination = fanOutCoordinator.consume(for: viewModel.projectID) else { return }
        await fanOutViewModel.handle(destination)
    }

    private func consumeFanOutRequest(_ request: ProjectFanOutRequest) async {
        guard let destination = fanOutCoordinator.consume(
            request,
            for: viewModel.projectID
        ) else { return }
        await fanOutViewModel.handle(destination)
    }

    private func taskRowContent(_ entry: TaskInboxEntry) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: entryIcon(entry.kind))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(statusColor(entry.status))
                .frame(width: 18, height: 20)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Text(entry.status)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(statusColor(entry.status))
                        .lineLimit(1)
                }
                if !entry.agents.isEmpty {
                    detailLine(icon: "person.2", text: entry.agents.joined(separator: ", "))
                }
                if let path = entry.worktreePaths.first {
                    detailLine(icon: "arrow.triangle.branch", text: path, monospaced: true)
                } else if let file = entry.touchedFiles.first {
                    detailLine(icon: "doc", text: file, monospaced: true)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func detailLine(icon: String, text: String, monospaced: Bool = false) -> some View {
        Label {
            Text(text)
                .font(.system(size: 10, design: monospaced ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: icon).font(.system(size: 9))
        }
        .foregroundStyle(palette.textLow.resolvedColor())
    }

    private var projectContext: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(localizer.string("projectHome.context.title", fallback: "Project Context"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                Spacer()
                Button { viewModel.loadContext() } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(localizer.string("common.refresh", fallback: "Refresh"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            detailLine(icon: "folder", text: viewModel.projectRoot.path, monospaced: true)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            if viewModel.worktreeConfig.enabled {
                Divider().overlay(palette.divider.resolvedColor())
                worktreeSection
            }
            if let sessionID = viewModel.recentDiffSessionID,
               let openRecentDiff = viewModel.actions.openRecentDiff {
                Divider().overlay(palette.divider.resolvedColor())
                Button { openRecentDiff(sessionID) } label: {
                    Label(
                        localizer.string("projectHome.diff.recent", fallback: "Open Recent Diff"),
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
        }
        .background(palette.backgroundSecondary.resolvedColor())
    }

    private var worktreeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                localizer.string("projectHome.worktrees.title", fallback: "Worktrees"),
                count: viewModel.worktrees.count,
                horizontalPadding: 16
            )
            if viewModel.isLoadingContext {
                ProgressView().controlSize(.small).padding(.horizontal, 16).padding(.bottom, 12)
            } else if viewModel.worktreeContextFailed {
                Text(localizer.string(
                    "projectHome.worktrees.failed",
                    fallback: "Worktree data is unavailable."
                ))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textMedium.resolvedColor())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else if viewModel.worktrees.isEmpty {
                Text(localizer.string("projectHome.worktrees.empty", fallback: "No managed worktrees"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textLow.resolvedColor())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                ForEach(viewModel.worktrees) { worktree in
                    Button {
                        Task { await viewModel.focusWorktree(worktree.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(worktree.branch)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.textHigh.resolvedColor())
                                .lineLimit(1)
                            Text(worktree.path.path)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(palette.textLow.resolvedColor())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionHeader(
        _ title: String,
        count: Int,
        horizontalPadding: CGFloat = 18
    ) -> some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textLow.resolvedColor())
        }
        .foregroundStyle(palette.textMedium.resolvedColor())
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 13)
    }

    private func entryIcon(_ kind: TaskInboxEntryKind) -> String {
        switch kind {
        case .fanOut: return "square.stack.3d.up"
        case .queuedTask: return "calendar.badge.clock"
        case .liveAgent: return "terminal"
        case .handoff: return "arrow.right.arrow.left"
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "failed", "error", "blocked": return Color(nsColor: .systemRed)
        case "waiting", "waitingForInput", "waitingInput": return Color(nsColor: .systemOrange)
        case "completed", "finished", "succeeded", "promoted": return Color(nsColor: .systemGreen)
        default: return palette.accent.resolvedColor()
        }
    }

    private var projectAccent: Color {
        guard let accent = viewModel.accent else { return palette.accent.resolvedColor() }
        let hex = accent.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard [6, 8].contains(hex.count),
              hex.unicodeScalars.allSatisfy({ hexDigits.contains($0) }) else {
            return palette.accent.resolvedColor()
        }
        return Color(nsColor: CodableColor(hex: "#\(hex)").nsColor)
    }
}
