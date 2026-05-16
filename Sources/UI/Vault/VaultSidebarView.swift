// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSidebarView.swift - Right-docked visual Vault sidebar.

import AppKit
import SwiftUI
import CocxyVault

struct VaultSidebarView: View {
    static let minimumPanelWidth = VaultSidebarWidthMode.iconOnly.panelWidth
    static let compactPanelWidth = VaultSidebarWidthMode.compact.panelWidth
    static let defaultPanelWidth = VaultSidebarWidthMode.expanded.panelWidth
    static let maximumPanelWidth: CGFloat = 520

    @ObservedObject var viewModel: VaultSidebarViewModel
    var onDismiss: (() -> Void)?
    var onNewSession: (() -> Void)?
    var onResume: ((VaultSession) -> Void)?
    var onResumeInNewTab: ((VaultSession) -> Void)?
    var onExport: (([VaultSession], VaultSessionExportFormat) -> Void)?
    var onCompare: ((VaultSession) -> Void)?
    var onWidthModeChanged: (() -> Void)?
    var panelWidth: CGFloat = VaultSidebarView.defaultPanelWidth
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    var vibrancyAppearanceOverride: NSAppearance?

    @FocusState private var isSearchFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            VaultSidebarHeader(
                widthMode: viewModel.widthMode,
                onCycleWidth: viewModel.cycleWidthMode,
                onNewSession: onNewSession,
                onDismiss: onDismiss,
                localizer: localizer
            )
            Divider().opacity(0.5)

            if viewModel.widthMode != .iconOnly {
                VaultSearchBar(
                    text: $viewModel.searchQuery,
                    isFocused: $isSearchFocused,
                    localizer: localizer
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                VaultAgentFilterStrip(
                    agents: VaultAgentRegistry.builtIn.agents,
                    selectedAgents: viewModel.selectedAgents,
                    onToggle: viewModel.toggleAgentFilter,
                    onClear: viewModel.clearAgentFilters,
                    localizer: localizer
                )
                .padding(.bottom, 8)

                VaultSidebarToolbar(
                    sortOrder: $viewModel.sortOrder,
                    groupBy: $viewModel.groupBy,
                    localizer: localizer
                )
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            content
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .glassPanelBackground(vibrancyAppearanceOverride: vibrancyAppearanceOverride)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("vault.sidebar.accessibility", fallback: "Vault sidebar"))
        .task { await viewModel.loadSessions() }
        .onChange(of: viewModel.searchQuery) { _, query in
            scheduleSearch(query)
        }
        .onChange(of: viewModel.widthMode) { _, _ in
            onWidthModeChanged?()
        }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
        }
        .focusable()
        .onKeyPress(.return) {
            guard let session = viewModel.selectedSessions.first ?? viewModel.filteredSessions.first else {
                return .ignored
            }
            onResume?(session)
            return .handled
        }
        .onKeyPress(.escape) {
            if !viewModel.selectedSessionIDs.isEmpty {
                viewModel.clearSelection()
                return .handled
            }
            onDismiss?()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let digit = Int(press.characters), digit >= 1, digit <= 9 else {
                return .ignored
            }
            let agents = VaultAgentRegistry.builtIn.agents
            guard digit <= agents.count else { return .ignored }
            viewModel.toggleAgentFilter(agents[digit - 1].id)
            return .handled
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            VaultLoadingState(localizer: localizer)
        } else if let error = viewModel.errorMessage {
            VaultErrorState(
                message: error,
                onRetry: viewModel.retryLoad,
                localizer: localizer
            )
        } else if viewModel.cards.isEmpty {
            VaultEmptyState(localizer: localizer)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if viewModel.isOnboardingVisible, viewModel.widthMode == .expanded {
                        VaultOnboardingTip(
                            onDismiss: viewModel.dismissOnboarding,
                            localizer: localizer
                        )
                    }

                    if let suggestion = viewModel.workspaceSuggestion,
                       viewModel.widthMode == .expanded {
                        VaultWorkspaceSuggestionView(
                            suggestion: suggestion,
                            localizer: localizer
                        )
                    }

                    if !viewModel.selectedSessionIDs.isEmpty,
                       viewModel.widthMode != .iconOnly {
                        VaultBulkActionBar(
                            count: viewModel.selectedSessionIDs.count,
                            selectedSessions: viewModel.selectedSessions,
                            onPin: viewModel.pinSelected,
                            onUnpin: viewModel.unpinSelected,
                            onExportJSON: {
                                onExport?(viewModel.selectedSessions, .json)
                            },
                            onDelete: {
                                Task { try? await viewModel.deleteSelected() }
                            },
                            localizer: localizer
                        )
                    }

                    ForEach(viewModel.groupSections) { section in
                        VaultSessionGroupSection(
                            section: section,
                            widthMode: viewModel.widthMode,
                            selectedSessionIDs: viewModel.selectedSessionIDs,
                            onSelect: { sessionID, modifiers in
                                if modifiers.contains(.shift) {
                                    viewModel.selectRange(to: sessionID)
                                } else if modifiers.contains(.command) {
                                    viewModel.toggleSelection(sessionID)
                                } else {
                                    viewModel.clearSelection()
                                    viewModel.toggleSelection(sessionID)
                                }
                            },
                            onResume: { session in onResume?(session) },
                            onResumeInNewTab: { session in onResumeInNewTab?(session) },
                            onPin: viewModel.pin,
                            onUnpin: viewModel.unpin,
                            onDelete: { session in
                                Task { try? await viewModel.delete(session: session) }
                            },
                            onExport: { session, format in onExport?([session], format) },
                            onCompare: { session in onCompare?(session) },
                            localizer: localizer
                        )
                    }
                }
                .padding(.horizontal, viewModel.widthMode == .iconOnly ? 6 : 10)
                .padding(.vertical, 10)
            }
        }
    }

    private func scheduleSearch(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.search(query: query)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultSidebarHeader: View {
    let widthMode: VaultSidebarWidthMode
    let onCycleWidth: () -> Void
    let onNewSession: (() -> Void)?
    let onDismiss: (() -> Void)?
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            if widthMode != .iconOnly {
                Text(localized("vault.sidebar.title", fallback: "Vault"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
            }

            Button(action: onCycleWidth) {
                Image(systemName: widthMode == .iconOnly ? "sidebar.right" : "arrow.left.and.right")
            }
            .buttonStyle(.borderless)
            .help(localized("vault.action.widthMode", fallback: "Change width"))

            if widthMode != .iconOnly {
                Button(action: { onNewSession?() }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(localized("vault.action.new", fallback: "New session"))
            }

            Button(action: { onDismiss?() }) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(localized("vault.action.close", fallback: "Close Vault"))
            .help(localized("vault.action.close", fallback: "Close Vault"))
        }
        .padding(.horizontal, widthMode == .iconOnly ? 8 : 12)
        .padding(.vertical, 10)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(localized("vault.search.placeholder", fallback: "Search sessions..."), text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(localized("vault.search.clear", fallback: "Clear search"))
            } else {
                Text(localized("vault.search.shortcutHint", fallback: "⌘F"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused.wrappedValue ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultAgentFilterStrip: View {
    let agents: [VaultAgent]
    let selectedAgents: Set<VaultAgentID>
    let onToggle: (VaultAgentID) -> Void
    let onClear: () -> Void
    let localizer: AppLocalizer

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                VaultFilterChip(
                    title: localized("vault.filter.allAgents", fallback: "All"),
                    systemImage: "square.grid.2x2",
                    isSelected: selectedAgents.isEmpty,
                    action: onClear
                )
                ForEach(agents, id: \.id) { agent in
                    VaultFilterChip(
                        title: agent.displayName,
                        systemImage: symbol(for: agent.id),
                        isSelected: selectedAgents.contains(agent.id),
                        action: { onToggle(agent.id) }
                    )
                }
            }
            .padding(.horizontal, 10)
        }
    }

    private func symbol(for agentID: VaultAgentID) -> String {
        switch agentID.rawValue {
        case "claude": return "sparkles"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "diamond"
        case "cursor": return "cursorarrow"
        default: return "cpu"
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct VaultSidebarToolbar: View {
    @Binding var sortOrder: VaultSortOrder
    @Binding var groupBy: VaultGroupBy
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(VaultSortOrder.allCases, id: \.self) { order in
                    Button(sortTitle(order)) { sortOrder = order }
                }
            } label: {
                Label(sortTitle(sortOrder), systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)

            Menu {
                ForEach(VaultGroupBy.allCases, id: \.self) { group in
                    Button(groupTitle(group)) { groupBy = group }
                }
            } label: {
                Label(groupTitle(groupBy), systemImage: "rectangle.3.group")
            }
            .menuStyle(.borderlessButton)

            Spacer()
        }
        .font(.system(size: 11))
    }

    private func sortTitle(_ order: VaultSortOrder) -> String {
        switch order {
        case .mostRecent: return localized("vault.sort.mostRecent", fallback: "Recent")
        case .oldest: return localized("vault.sort.oldest", fallback: "Oldest")
        case .alphabetical: return localized("vault.sort.alphabetical", fallback: "A-Z")
        case .agentThenRecent: return localized("vault.sort.agentThenRecent", fallback: "Agent")
        case .workspaceThenRecent: return localized("vault.sort.workspaceThenRecent", fallback: "Workspace")
        }
    }

    private func groupTitle(_ group: VaultGroupBy) -> String {
        switch group {
        case .none: return localized("vault.group.none", fallback: "None")
        case .agent: return localized("vault.group.agent", fallback: "Agent")
        case .workspace: return localized("vault.group.workspace", fallback: "Workspace")
        case .date: return localized("vault.group.date", fallback: "Date")
        case .pinFirst: return localized("vault.group.pinFirst", fallback: "Pins first")
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultSessionGroupSection: View {
    let section: VaultSidebarSection
    let widthMode: VaultSidebarWidthMode
    let selectedSessionIDs: Set<String>
    let onSelect: (String, NSEvent.ModifierFlags) -> Void
    let onResume: (VaultSession) -> Void
    let onResumeInNewTab: (VaultSession) -> Void
    let onPin: (VaultSession) -> Void
    let onUnpin: (VaultSession) -> Void
    let onDelete: (VaultSession) -> Void
    let onExport: (VaultSession, VaultSessionExportFormat) -> Void
    let onCompare: (VaultSession) -> Void
    let localizer: AppLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if widthMode != .iconOnly {
                HStack(spacing: 6) {
                    Image(systemName: symbol(for: section.kind))
                        .foregroundStyle(.secondary)
                    Text(sectionTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(section.cards.count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
            }

            ForEach(section.cards) { card in
                VaultSessionCard(
                    card: card,
                    widthMode: widthMode,
                    isSelected: selectedSessionIDs.contains(card.session.id),
                    onSelect: {
                        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
                        onSelect(card.session.id, modifiers)
                    },
                    onResume: { onResume(card.session) },
                    onResumeInNewTab: { onResumeInNewTab(card.session) },
                    onPin: { onPin(card.session) },
                    onUnpin: { onUnpin(card.session) },
                    onDelete: { onDelete(card.session) },
                    onExport: { format in onExport(card.session, format) },
                    onCompare: { onCompare(card.session) },
                    localizer: localizer
                )
            }
        }
    }

    private func symbol(for kind: VaultSidebarSectionKind) -> String {
        switch kind {
        case .pinned: return "pin.fill"
        case .recent: return "clock"
        case .older: return "archivebox"
        case .agent: return "cpu"
        case .workspace: return "folder"
        case .date: return "calendar"
        case .all: return "tray.full"
        }
    }

    private var sectionTitle: String {
        switch section.kind {
        case .all:
            return localized("vault.section.all", fallback: section.title)
        case .pinned:
            return localized("vault.section.pinned", fallback: section.title)
        case .recent:
            return localized("vault.section.recent", fallback: section.title)
        case .older:
            return localized("vault.section.older", fallback: section.title)
        case .date(let value):
            switch value {
            case "Today": return localized("vault.date.today", fallback: value)
            case "Yesterday": return localized("vault.date.yesterday", fallback: value)
            case "Last 7 days": return localized("vault.date.last7Days", fallback: value)
            case "Older": return localized("vault.date.older", fallback: value)
            default: return value
            }
        case .agent, .workspace:
            return section.title
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultSessionCard: View {
    let card: VaultSidebarCard
    let widthMode: VaultSidebarWidthMode
    let isSelected: Bool
    let onSelect: () -> Void
    let onResume: () -> Void
    let onResumeInNewTab: () -> Void
    let onPin: () -> Void
    let onUnpin: () -> Void
    let onDelete: () -> Void
    let onExport: (VaultSessionExportFormat) -> Void
    let onCompare: () -> Void
    let localizer: AppLocalizer

    @State private var isHovered = false
    @State private var isPreviewPresented = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: widthMode == .iconOnly ? 0 : 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(card.isPinned ? 0.28 : 0.16))
                    Image(systemName: symbol(for: card.session.agentID))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

                if widthMode != .iconOnly {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(card.title)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            if card.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(card.ageText)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(card.preview)
                            .font(.system(size: widthMode == .compact ? 10 : 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(widthMode == .compact ? 1 : 2)

                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 9))
                            Text(card.workspaceDisplay)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            VaultSparkline(values: card.activitySparkline)
                                .frame(width: 34, height: 12)
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(widthMode == .iconOnly ? 5 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            previewTask?.cancel()
            if hovering, widthMode == .expanded {
                previewTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        if isHovered, widthMode == .expanded {
                            isPreviewPresented = true
                        }
                    }
                }
            } else {
                isPreviewPresented = false
            }
        }
        .onDrag {
            VaultSessionDragPayload.itemProvider(for: card.session)
        } preview: {
            HStack {
                Image(systemName: symbol(for: card.session.agentID))
                Text(card.title)
                    .lineLimit(1)
            }
            .padding(8)
        }
        .contextMenu {
            Button(localized("vault.action.resume", fallback: "Resume"), action: onResume)
            Button(localized("vault.action.resumeNewTab", fallback: "Resume in New Tab"), action: onResumeInNewTab)
            Divider()
            if card.isPinned {
                Button(localized("vault.action.unpin", fallback: "Unpin"), action: onUnpin)
            } else {
                Button(localized("vault.action.pin", fallback: "Pin"), action: onPin)
            }
            Button(localized("vault.action.compare", fallback: "Compare..."), action: onCompare)
            Menu(localized("vault.action.export", fallback: "Export...")) {
                Button(localized("vault.export.json", fallback: "JSON"), action: { onExport(.json) })
                Button(localized("vault.export.markdown", fallback: "Markdown"), action: { onExport(.markdown) })
                Button(localized("vault.export.text", fallback: "Plain Text"), action: { onExport(.text) })
            }
            Divider()
            Button(localized("vault.action.delete", fallback: "Delete"), role: .destructive, action: onDelete)
        }
        .popover(isPresented: Binding(
            get: { isPreviewPresented && widthMode == .expanded },
            set: { if !$0 { isPreviewPresented = false } }
        )) {
            VaultQuickPreview(card: card, localizer: localizer)
        }
        .onDisappear {
            previewTask?.cancel()
            previewTask = nil
        }
        .accessibilityLabel(card.accessibilityLabel)
        .accessibilityHint(card.accessibilityHint)
    }

    private var backgroundColor: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovered { return Color.primary.opacity(0.08) }
        return Color.primary.opacity(0.045)
    }

    private func symbol(for agentID: VaultAgentID) -> String {
        switch agentID.rawValue {
        case "claude": return "sparkles"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "diamond"
        case "cursor": return "cursorarrow"
        default: return "cpu"
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultBulkActionBar: View {
    let count: Int
    let selectedSessions: [VaultSession]
    let onPin: () -> Void
    let onUnpin: () -> Void
    let onExportJSON: () -> Void
    let onDelete: () -> Void
    let localizer: AppLocalizer

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: localized("vault.bulk.selected", fallback: "%d selected"), count))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button(action: onPin) {
                Image(systemName: "pin")
            }
            .buttonStyle(.borderless)
            .help(localized("vault.action.pin", fallback: "Pin"))

            Button(action: onUnpin) {
                Image(systemName: "pin.slash")
            }
            .buttonStyle(.borderless)
            .help(localized("vault.action.unpin", fallback: "Unpin"))

            Button(action: onExportJSON) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .help(localized("vault.action.export", fallback: "Export..."))
            .disabled(selectedSessions.isEmpty)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(localized("vault.action.delete", fallback: "Delete"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultWorkspaceSuggestionView: View {
    let suggestion: VaultWorkspaceSuggestion
    let localizer: AppLocalizer

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(localized("vault.suggestion.title", fallback: "Workspace sessions found"))
                    .font(.system(size: 11, weight: .semibold))
                Text(
                    String(
                        format: localized(
                            "vault.suggestion.workspace",
                            fallback: "%d previous sessions in %@"
                        ),
                        suggestion.matchingSessionCount,
                        suggestion.workspaceDisplay
                    )
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else { return }
                for (index, value) in values.enumerated() {
                    let x = proxy.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = proxy.size.height * (1 - CGFloat(max(0, min(1, value))))
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(Color.accentColor.opacity(0.75), lineWidth: 1.2)
        }
    }
}

private struct VaultQuickPreview: View {
    let card: VaultSidebarCard
    let localizer: AppLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.headline)
            Text(card.preview)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Label(card.workspaceDisplay, systemImage: "folder")
            Label(card.ageText, systemImage: "clock")
            Label(card.session.sessionID, systemImage: "number")
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
    }
}

private struct VaultOnboardingTip: View {
    let onDismiss: () -> Void
    let localizer: AppLocalizer

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "hand.draw")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("vault.onboarding.title", fallback: "Drag sessions into any terminal"))
                    .font(.system(size: 11, weight: .semibold))
                Text(localized("vault.onboarding.body", fallback: "Search locally, filter by agent, then drop a card to resume."))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1))
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultLoadingState: View {
    let localizer: AppLocalizer

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(localized("vault.loading.title", fallback: "Loading sessions..."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultEmptyState: View {
    let localizer: AppLocalizer

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text(localized("vault.empty.title", fallback: "No sessions yet"))
                .font(.system(size: 13, weight: .semibold))
            Text(localized("vault.empty.subtitle", fallback: "Start a supported agent session in any tab to see it here."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

private struct VaultErrorState: View {
    let message: String
    let onRetry: () -> Void
    let localizer: AppLocalizer

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(localized("vault.error.loadFailed", fallback: "Could not load Vault"))
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Button(localized("vault.action.retry", fallback: "Retry"), action: onRetry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
