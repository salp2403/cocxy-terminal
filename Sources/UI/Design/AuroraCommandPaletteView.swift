// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraCommandPaletteView.swift - Redesigned command palette overlay.
//
// Floating palette that composes itself on top of `Design.GlassSurface`
// so the existing Liquid Glass / visual-effect / opaque accessibility
// pipeline drives its background. The view is decoupled from
// `CommandPaletteEngine` on purpose: the host passes the resolved
// `AuroraPaletteAction` list in, keeping this module self-contained
// and testable while the integration layer bridges to production.

import SwiftUI

extension Design {

    // MARK: - Action model

    /// Flat, presentation-only description of a palette entry.
    ///
    /// Callers build this struct from whatever live command registry
    /// they use; the view never calls back into the domain layer
    /// directly. `shortcut` is rendered verbatim so the caller can
    /// pre-format it with `MenuKeybindingsBinder.prettyShortcut(...)`
    /// (or leave it `nil` for actions without a keyboard binding).
    ///
    /// `subtitle` is optional free-form text that appears beneath the
    /// label when present — used by the tweaks panel for long
    /// descriptions and ignored otherwise.
    struct AuroraPaletteAction: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let category: String
        let subtitle: String?
        let shortcut: String?

        init(
            id: String,
            label: String,
            category: String,
            subtitle: String? = nil,
            shortcut: String? = nil
        ) {
            self.id = id
            self.label = label
            self.category = category
            self.subtitle = subtitle
            self.shortcut = shortcut
        }
    }

    // MARK: - Filter

    /// Pure filter that powers the palette's live search. Extracted so
    /// the SwiftUI view can stay declarative and the matching rules are
    /// testable without booting the overlay.
    ///
    /// Matching is case-insensitive and checks `label`, `category`, and
    /// `subtitle` (when set). Empty queries return every action in the
    /// order the caller supplied them, which keeps a stable "all
    /// actions" view for the empty state.
    enum AuroraPaletteFilter {
        static func filter(
            _ actions: [AuroraPaletteAction],
            by query: String
        ) -> [AuroraPaletteAction] {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return actions }
            let needle = trimmed.lowercased()
            return actions.filter { action in
                if action.label.lowercased().contains(needle) { return true }
                if action.category.lowercased().contains(needle) { return true }
                if let subtitle = action.subtitle,
                   subtitle.lowercased().contains(needle) { return true }
                return false
            }
        }
    }

    // MARK: - Command palette view

    /// Aurora-styled command palette overlay.
    ///
    /// The view is intentionally dumb: it owns a search query and a
    /// selection index, and delegates every side-effect (executing the
    /// chosen action, dismissing the overlay) to closures supplied by
    /// the host. The host (integration layer or the demo inspector)
    /// refreshes `actions` whenever the underlying command registry
    /// changes and drives `isVisible` through a `@State` or @Binding.
    ///
    /// Composition:
    ///
    ///     Dimmed backdrop (dismiss on tap)
    ///     └── GlassSurface (rounded rect, Radius.large)
    ///         └── VStack
    ///             ├── searchField
    ///             ├── results ScrollView
    ///             └── footerHint
    ///
    /// Keyboard navigation (`↑` / `↓` / `Enter` / `Esc`) is handled in
    /// the view so the host only has to mount the `NSHostingView` as
    /// first responder and provide the action/dismiss closures.
    struct AuroraCommandPaletteView: View {

        @Binding var isVisible: Bool
        @Binding var query: String
        @Binding var selectedIndex: Int

        let actions: [AuroraPaletteAction]
        let onSelect: (AuroraPaletteAction) -> Void
        let onDismiss: () -> Void

        @Environment(\.designThemePalette) private var palette
        @FocusState private var searchFieldFocused: Bool

        private static let maxWidth: CGFloat = 560
        private static let maxHeight: CGFloat = 420

        var body: some View {
            if isVisible {
                ZStack(alignment: .top) {
                    backdrop
                    content
                        .padding(.top, 80)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Command palette")
                // Swallow arrow navigation and Escape so keystrokes
                // never reach the terminal surface while the palette
                // is up, and so the palette has first-class keyboard
                // navigation without requiring the host to wire up an
                // NSEvent monitor.
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    submitCurrentSelection()
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }
                .onAppear {
                    // Autofocus the search field so the user can type
                    // immediately, matching the classic palette.
                    searchFieldFocused = true
                }
                .onChange(of: isVisible) { _, newValue in
                    if newValue {
                        searchFieldFocused = true
                    }
                }
                .onChange(of: query) { _, _ in
                    // Re-clamp the selection when the filter list
                    // shrinks; keeps the highlight inside the
                    // currently visible rows.
                    selectedIndex = clampedSelection(for: filteredActions)
                }
            }
        }

        // MARK: - Pieces

        private var backdrop: some View {
            Color.black
                .opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
        }

        private var content: some View {
            GlassSurface(cornerRadius: .large) {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    searchField
                    Divider()
                        .opacity(0.5)
                    resultsList
                    Divider()
                        .opacity(0.4)
                    footerHint
                }
                .padding(Spacing.small)
            }
            .frame(maxWidth: Self.maxWidth)
            .frame(maxHeight: Self.maxHeight)
        }

        private var searchField: some View {
            HStack(spacing: Spacing.xSmall) {
                Text("⌕")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())

                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                    .accessibilityLabel("Command palette search")
                    .focused($searchFieldFocused)
                    .onSubmit { submitCurrentSelection() }
            }
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, 8)
        }

        // MARK: - Keyboard navigation helpers

        private func moveSelection(by delta: Int) {
            let visible = filteredActions
            guard !visible.isEmpty else { return }
            let current = clampedSelection(for: visible)
            let next = current + delta
            if next < 0 {
                selectedIndex = visible.count - 1
            } else if next >= visible.count {
                selectedIndex = 0
            } else {
                selectedIndex = next
            }
        }

        private func submitCurrentSelection() {
            let visible = filteredActions
            guard !visible.isEmpty else { return }
            let index = clampedSelection(for: visible)
            onSelect(visible[index])
        }

        private var filteredActions: [AuroraPaletteAction] {
            AuroraPaletteFilter.filter(actions, by: query)
        }

        private var resultsList: some View {
            let visible = filteredActions
            return ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if visible.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, action in
                            AuroraPaletteRow(
                                action: action,
                                isSelected: index == clampedSelection(for: visible)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedIndex = index
                                onSelect(action)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var emptyState: some View {
            HStack {
                Spacer()
                Text("No matches")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
                Spacer()
            }
            .padding(.vertical, Spacing.small)
        }

        private var footerHint: some View {
            HStack(spacing: Spacing.xSmall) {
                hintChip("↑↓", "Navigate")
                hintChip("⏎", "Select")
                hintChip("⎋", "Close")
                Spacer()
                Text("\(filteredActions.count) action\(filteredActions.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
            .padding(.horizontal, Spacing.xxSmall)
            .padding(.top, Spacing.xxSmall)
        }

        private func hintChip(_ glyph: String, _ caption: String) -> some View {
            HStack(spacing: 4) {
                Text(glyph)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.textHigh.resolvedColor())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.glassHighlight.resolvedColor())
                    )
                Text(caption)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.textLow.resolvedColor())
            }
        }

        /// Clamps `selectedIndex` so rendering stays valid after the
        /// filtered set shrinks below the previously-selected row. The
        /// host can rely on the view to always highlight a valid entry.
        private func clampedSelection(for visible: [AuroraPaletteAction]) -> Int {
            guard !visible.isEmpty else { return 0 }
            return min(max(selectedIndex, 0), visible.count - 1)
        }
    }

    // MARK: - Palette row

    /// Single row rendered inside the palette results list. Exposed as
    /// its own view so tests can snapshot the row shape without
    /// allocating the whole palette, and so the tweaks panel can reuse
    /// the same visual when previewing an action set.
    struct AuroraPaletteRow: View {
        let action: AuroraPaletteAction
        let isSelected: Bool

        @Environment(\.designThemePalette) private var palette

        var body: some View {
            HStack(spacing: Spacing.small) {
                categoryChip
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textHigh.resolvedColor())
                        .lineLimit(1)
                    if let subtitle = action.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textLow.resolvedColor())
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let shortcut = action.shortcut, !shortcut.isEmpty {
                    shortcutLabel(shortcut)
                }
            }
            .padding(.horizontal, Spacing.xSmall)
            .padding(.vertical, 7)
            .background(backgroundFill)
            .overlay(selectionBorder)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(action.label)
            .accessibilityValue(action.shortcut ?? "")
            .accessibilityHint(action.category)
        }

        private var categoryChip: some View {
            Text(action.category.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(palette.textLow.resolvedColor())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.glassHighlight.resolvedColor())
                )
        }

        private func shortcutLabel(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textHigh.resolvedColor())
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(palette.glassHighlight.resolvedColor())
                )
        }

        @ViewBuilder
        private var backgroundFill: some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.accent.withAlpha(0.12).resolvedColor())
            } else {
                Color.clear
            }
        }

        @ViewBuilder
        private var selectionBorder: some View {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(palette.accent.withAlpha(0.45).resolvedColor(), lineWidth: 1)
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Sample data

extension Design {

    /// Canonical sample action catalog used by previews, the demo
    /// inspector, and unit tests. Mirrors the categories listed in the
    /// palette reference (`Tabs`, `Splits`, `Window`, `Theme`) so the
    /// snapshot stays close to what the integration layer will emit.
    static let samplePaletteActions: [AuroraPaletteAction] = [
        AuroraPaletteAction(id: "tab.new", label: "New tab", category: "Tabs", shortcut: "⌘T"),
        AuroraPaletteAction(id: "tab.close", label: "Close tab", category: "Tabs", shortcut: "⌘W"),
        AuroraPaletteAction(id: "tab.next", label: "Next tab", category: "Tabs", shortcut: "⌘⇧]"),
        AuroraPaletteAction(id: "tab.prev", label: "Previous tab", category: "Tabs", shortcut: "⌘⇧["),
        AuroraPaletteAction(id: "split.horizontal", label: "Split horizontal", category: "Splits", shortcut: "⌘D"),
        AuroraPaletteAction(id: "split.vertical", label: "Split vertical", category: "Splits", shortcut: "⌘⇧D"),
        AuroraPaletteAction(id: "split.close", label: "Close split", category: "Splits", shortcut: "⌘⇧W"),
        AuroraPaletteAction(id: "window.palette", label: "Toggle command palette", category: "Window", shortcut: "⌘⇧P"),
        AuroraPaletteAction(
            id: "theme.cycle",
            label: "Cycle theme",
            category: "Theme",
            subtitle: "aurora → paper → nocturne",
            shortcut: "⌘⌥T"
        ),
    ]
}
