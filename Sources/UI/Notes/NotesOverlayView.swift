// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotesOverlayView.swift - Right-docked notes panel for per-workspace notes.

import SwiftUI

struct NotesOverlayView: View {

    enum ContentLayout: Equatable {
        case stacked
        case split
    }

    static let defaultPanelWidth: CGFloat = 560
    static let minimumPanelWidth: CGFloat = 420
    static let maximumPanelWidth: CGFloat = 760
    static let compactLayoutThreshold: CGFloat = 620
    static let countBadgeMinimumWidth: CGFloat = 22
    static let noteRowMinimumHitHeight: CGFloat = 52
    /// Corner radius applied to the leading edge of the right-docked
    /// panel. The trailing edge stays flat because the panel hugs the
    /// window's right border; rounding both sides would produce a
    /// visible gap between the glass surface and the chrome.
    static let leadingCornerRadius: CGFloat = Design.Radius.large.rawValue

    @ObservedObject var viewModel: NotesViewModel
    var panelWidth: CGFloat = NotesOverlayView.defaultPanelWidth
    /// Aurora theme used to resolve the glass tint and chrome accents.
    /// Defaults to `.aurora` so previews and tests render with the
    /// shipping dark palette without forcing every host to compute one.
    /// Production hosts pass the live identity (resolved from the
    /// active theme variant) so the overlay tracks light/dark mode.
    var themeIdentity: Design.ThemeIdentity = .aurora
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    var onDismiss: (() -> Void)?

    @State private var pendingDeleteNote: Note?

    static func contentLayout(forPanelWidth panelWidth: CGFloat) -> ContentLayout {
        panelWidth < compactLayoutThreshold ? .stacked : .split
    }

    /// Shape used as the glass surface. Leading edges round, trailing
    /// edges stay flat to hug the window border. Exposed `static` so
    /// snapshot or layout tests can assert geometry without instantiating
    /// the view.
    static var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: leadingCornerRadius,
            bottomLeadingRadius: leadingCornerRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        Design.GlassSurface(shape: Self.panelShape) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                toolbar
                Divider().opacity(0.35)
                if let error = viewModel.lastError {
                    errorBanner(error)
                }
                content
            }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .designThemePalette(Design.palette(for: themeIdentity))
        .confirmationDialog(
            deleteNoteCopy.messageText,
            isPresented: Binding(
                get: { pendingDeleteNote != nil },
                set: { if !$0 { pendingDeleteNote = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteNoteCopy.primaryButton, role: .destructive) {
                guard let note = pendingDeleteNote else { return }
                pendingDeleteNote = nil
                Task { await viewModel.deleteNote(note) }
            }
            Button(deleteNoteCopy.secondaryButton, role: .cancel) {
                pendingDeleteNote = nil
            }
        } message: {
            Text(deleteNoteCopy.informativeText)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localized("notes.panel.accessibility", fallback: "Notes panel"))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(localized("notes.title", fallback: "Notes"))
                    .font(.system(size: 14, weight: .semibold))
                Text(viewModel.workspace?.displayName ?? localized("notes.noWorkspace", fallback: "No workspace"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                Task { await viewModel.createNote() }
            } label: {
                Label(localized("notes.newNote", fallback: "New Note"), systemImage: "square.and.pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(localized("notes.newNote.help", fallback: "New note"))
            .accessibilityLabel(localized("notes.newNote.help", fallback: "New note"))
            .disabled(viewModel.workspace == nil)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(localized("notes.close", fallback: "Close notes"))
                .help(localized("notes.close", fallback: "Close notes"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(localized("notes.search.placeholder", fallback: "Search notes"), text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .accessibilityLabel(localized("notes.search.accessibility", fallback: "Search notes"))
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    Task { await viewModel.runSearch() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(localized("notes.search.clear", fallback: "Clear search"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.26))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.workspace == nil {
            emptyState(
                title: localized("notes.noWorkspace", fallback: "No workspace"),
                message: localized("notes.empty.noWorkspace", fallback: "Open a terminal tab before using notes.")
            )
        } else {
            GeometryReader { proxy in
                switch Self.contentLayout(forPanelWidth: panelWidth) {
                case .stacked:
                    VStack(spacing: 0) {
                        noteList
                            .frame(height: stackedListHeight(for: proxy.size.height))
                        Divider().opacity(0.35)
                        editor
                    }
                case .split:
                    HSplitView {
                        noteList
                            .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)
                        Divider().opacity(0.35)
                        editor
                            .frame(minWidth: 300)
                    }
                }
            }
        }
    }

    private var noteList: some View {
        let showingSearch = !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            listHeader(showingSearch: showingSearch)
            Divider().opacity(0.25)
            if showingSearch {
                if viewModel.searchResults.isEmpty {
                    emptyState(
                        title: localized("notes.empty.noMatches.title", fallback: "No matches"),
                        message: localized("notes.empty.noMatches.message", fallback: "Try a different search.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(viewModel.searchResults) { result in
                                searchResultRow(result)
                            }
                        }
                        .padding(10)
                    }
                }
            } else if viewModel.notes.isEmpty {
                emptyState(
                    title: localized("notes.empty.noNotes.title", fallback: "No notes"),
                    message: localized("notes.empty.noNotes.message", fallback: "Create a note for this workspace.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(viewModel.notes) { note in
                            noteRow(note)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.08))
    }

    private var editor: some View {
        VStack(spacing: 0) {
            if let selected = viewModel.selectedNote {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selected.localizedDerivedTitle(using: localizer))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Text(localizedEditedDate(selected.updatedAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { await viewModel.saveSelectedNote() }
                    } label: {
                        Label(localized("common.save", fallback: "Save"), systemImage: "square.and.arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(localized("notes.save", fallback: "Save note"))
                    .accessibilityLabel(localized("notes.save", fallback: "Save note"))

                    Button(role: .destructive) {
                        pendingDeleteNote = selected
                    } label: {
                        Label(localized("notes.delete", fallback: "Delete"), systemImage: "trash")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(localized("notes.deleteNote", fallback: "Delete note"))
                    .accessibilityLabel(localized("notes.deleteNote", fallback: "Delete note"))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                Divider().opacity(0.35)
                ZStack(alignment: .topLeading) {
                    if selected.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(localized(
                            "notes.editor.placeholder",
                            fallback: "Start writing. Use a Markdown heading for the title."
                        ))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: editorText)
                        .font(.system(size: 13, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                }
            } else {
                emptyState(
                    title: localized("notes.empty.select.title", fallback: "Select a note"),
                    message: localized(
                        "notes.empty.select.message",
                        fallback: "Pick one from the list or create a new note."
                    )
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.10))
    }

    private var editorText: Binding<String> {
        Binding(
            get: {
                viewModel.selectedNote?.body ?? ""
            },
            set: { newValue in
                guard var note = viewModel.selectedNote else { return }
                note.body = newValue
                Task { await viewModel.updateNote(note) }
            }
        )
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            viewModel.selectNote(note)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(viewModel.selectedNote?.id == note.id ? Color.accentColor : Color.secondary)
                    .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(note.localizedDerivedTitle(using: localizer))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(note.updatedAt.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    let excerpt = note.excerpt(maxLength: 90)
                    if !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Self.noteRowMinimumHitHeight)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.selectedNote?.id == note.id ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(note.localizedDerivedTitle(using: localizer))
    }

    private func searchResultRow(_ result: NoteSearchResult) -> some View {
        Button {
            if let note = viewModel.notes.first(where: { $0.id == result.noteID }) {
                viewModel.selectNote(note)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Note.localizedTitle(result.title, using: localizer))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(result.score * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(result.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: Self.noteRowMinimumHitHeight)
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityLabel(Note.localizedTitle(result.title, using: localizer))
    }

    private func emptyState(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(3)
            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.12))
        .overlay(Divider().opacity(0.35), alignment: .bottom)
    }

    private func listHeader(showingSearch: Bool) -> some View {
        HStack(spacing: 8) {
            Text(showingSearch
                ? localized("notes.results", fallback: "Results")
                : localized("notes.workspaceNotes", fallback: "Workspace Notes")
            )
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                countBadge(showingSearch ? viewModel.searchResults.count : viewModel.notes.count)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func countBadge(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(minWidth: Self.countBadgeMinimumWidth)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
            )
            .accessibilityLabel(localizedCountLabel(count))
    }

    private func stackedListHeight(for availableHeight: CGFloat) -> CGFloat {
        min(max(180, availableHeight * 0.36), 280)
    }

    private var deleteNoteCopy: AppAlertCopy {
        Self.localizedDeleteNoteCopy(localizer: localizer)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }

    private func localizedEditedDate(_ date: Date) -> String {
        String(
            format: localized("notes.edited", fallback: "Edited %@"),
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private func localizedCountLabel(_ count: Int) -> String {
        let key = count == 1 ? "notes.count.one" : "notes.count.many"
        let fallback = count == 1 ? "%d note" : "%d notes"
        return String(format: localized(key, fallback: fallback), count)
    }

    static func localizedDeleteNoteCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("notes.delete.confirm.title", fallback: "Delete note?"),
            informativeText: localizer.string(
                "notes.delete.confirm.message",
                fallback: "This removes the note from this workspace."
            ),
            primaryButton: localizer.string("notes.delete.confirm.button", fallback: "Delete Note"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }
}
