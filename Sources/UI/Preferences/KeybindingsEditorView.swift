// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// KeybindingsEditorView.swift - SwiftUI editor for keyboard shortcuts.

import SwiftUI
import AppKit

// MARK: - Keybindings Editor View

/// Scrollable, category-grouped editor for every rebindable shortcut.
///
/// Each row renders:
/// - the display name and summary from the catalog,
/// - the pretty macOS glyph label of the current shortcut (`⌘⇧D`),
/// - an **Edit** button that opens a modal capturing the next keystroke,
/// - a **Reset** button that restores the catalog default (enabled only when
///   the action has been customized).
///
/// Conflicts are highlighted inline: rows that share a shortcut are tinted
/// red and listed in a warning banner at the top. The global **Save** button
/// is disabled until all conflicts are resolved.
///
/// - SeeAlso: `KeybindingsEditorViewModel` for the editable state.
/// - SeeAlso: `KeybindingCaptureView` for the capture modal.
struct KeybindingsEditorView: View {

    /// Editable state exposed by the parent preferences window.
    @ObservedObject var viewModel: KeybindingsEditorViewModel

    /// Action whose capture modal is currently presented. `nil` when the
    /// modal is hidden.
    @State private var capturingAction: KeybindingAction?

    /// Temporary status banner text (save success or error message).
    @State private var saveStatus: String?

    var body: some View {
        Form {
            conflictsBanner

            ForEach(KeybindingActionCatalog.grouped, id: \.category.id) { section in
                Section(section.category.title) {
                    ForEach(section.actions) { action in
                        KeybindingRow(
                            action: action,
                            shortcutString: viewModel.rawShortcut(for: action.id),
                            isCustomized: viewModel.isCustomized(action.id),
                            isConflicting: !viewModel.conflictingActionIds(
                                for: viewModel.rawShortcut(for: action.id),
                                excluding: action.id
                            ).isEmpty,
                            onEdit: { capturingAction = action },
                            onReset: { viewModel.reset(action.id) }
                        )
                    }
                }
            }

            Section {
                HStack(spacing: 12) {
                    Button("Save") { performSave() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!viewModel.hasUnsavedChanges || viewModel.hasConflicts)

                    Button("Reset All") { viewModel.resetAll() }

                    Spacer()

                    if let status = saveStatus ?? viewModel.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Keybindings")
        .sheet(item: $capturingAction) { action in
            KeybindingCaptureSheet(
                action: action,
                currentShortcut: viewModel.rawShortcut(for: action.id),
                viewModel: viewModel,
                onDismiss: { capturingAction = nil }
            )
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var conflictsBanner: some View {
        let groups = viewModel.conflictGroups()
        if !groups.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Conflicts detected", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.headline)
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                        Text(groupDescription(for: group))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Resolve conflicts before saving.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func groupDescription(for ids: [String]) -> String {
        let names = ids.compactMap { KeybindingAction.catalogEntry(for: $0)?.displayName }
        return names.joined(separator: ", ")
    }

    private func performSave() {
        do {
            try viewModel.save()
            saveStatus = "Keybindings saved."
        } catch {
            saveStatus = error.localizedDescription
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            saveStatus = nil
        }
    }
}

// MARK: - Keybinding Row

/// Single row in the keybindings editor.
private struct KeybindingRow: View {

    let action: KeybindingAction
    let shortcutString: String
    let isCustomized: Bool
    let isConflicting: Bool
    let onEdit: () -> Void
    let onReset: () -> Void

    private var prettyLabel: String {
        guard let shortcut = KeybindingShortcut.parse(shortcutString) else {
            return shortcutString.isEmpty ? "—" : shortcutString
        }
        return shortcut.prettyLabel
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.displayName)
                    .font(.body)
                Text(action.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Text(prettyLabel)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(shortcutBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .foregroundStyle(isConflicting ? .red : .primary)
                .accessibilityLabel("Shortcut: \(prettyLabel)")

            Button("Edit", action: onEdit)
                .buttonStyle(.bordered)

            Button("Reset", action: onReset)
                .buttonStyle(.bordered)
                .disabled(!isCustomized)
        }
        .padding(.vertical, 2)
    }

    private var shortcutBackground: Color {
        if isConflicting {
            return Color.red.opacity(0.12)
        }
        if isCustomized {
            return Color.accentColor.opacity(0.18)
        }
        return Color.secondary.opacity(0.08)
    }
}

// MARK: - Capture Sheet

/// Modal presenting a keybinding capture field, Save/Cancel/Clear buttons,
/// and an inline conflict warning.
struct KeybindingCaptureSheet: View {

    let action: KeybindingAction
    let currentShortcut: String
    @ObservedObject var viewModel: KeybindingsEditorViewModel
    let onDismiss: () -> Void

    @State private var capturedShortcut: KeybindingShortcut?
    @State private var captureHint: String = "Press the new shortcut..."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(action.displayName)
                    .font(.headline)
                Text(action.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Text("Current:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(renderPretty(currentShortcut))
                    .font(.system(.body, design: .monospaced))
            }

            KeybindingCaptureField(capturedShortcut: $capturedShortcut, hint: $captureHint)
                .frame(height: 48)

            if let shortcut = capturedShortcut {
                let conflicts = viewModel.conflictingActionIds(
                    for: shortcut.canonical,
                    excluding: action.id
                )
                if !conflicts.isEmpty {
                    Label(conflictMessage(for: conflicts), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button("Clear") {
                    viewModel.clear(action.id)
                    onDismiss()
                }
                Spacer()
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.escape)
                Button("Save") {
                    if let captured = capturedShortcut,
                       viewModel.assign(captured, to: action.id) {
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }

    private var canSave: Bool {
        guard let captured = capturedShortcut else { return false }
        let conflicts = viewModel.conflictingActionIds(
            for: captured.canonical,
            excluding: action.id
        )
        return conflicts.isEmpty
    }

    private func renderPretty(_ raw: String) -> String {
        guard !raw.isEmpty else { return "—" }
        return KeybindingShortcut.parse(raw)?.prettyLabel ?? raw
    }

    private func conflictMessage(for ids: [String]) -> String {
        let names = ids.compactMap { KeybindingAction.catalogEntry(for: $0)?.displayName }
        let list = names.joined(separator: ", ")
        return "Also bound to: \(list). Save will be blocked until this is resolved."
    }
}

// MARK: - Capture Field

/// `NSView`-backed capture field. Becomes first responder while visible and
/// forwards `.keyDown` events to `KeybindingShortcut.fromEvent`.
struct KeybindingCaptureField: NSViewRepresentable {

    @Binding var capturedShortcut: KeybindingShortcut?
    @Binding var hint: String

    func makeNSView(context: Context) -> CaptureNSView {
        let view = CaptureNSView()
        view.onCaptured = { shortcut in
            DispatchQueue.main.async {
                capturedShortcut = shortcut
                hint = shortcut?.prettyLabel ?? "Press the new shortcut..."
            }
        }
        return view
    }

    func updateNSView(_ nsView: CaptureNSView, context: Context) {
        nsView.displayText = hint
    }

    // MARK: - NSView Implementation

    /// Owned NSView that consumes every `.keyDown` while focused and
    /// renders the pretty shortcut label in-place.
    final class CaptureNSView: NSView {

        /// Text currently drawn in the center of the field.
        var displayText: String = "Press the new shortcut..." {
            didSet { needsDisplay = true }
        }

        /// Callback invoked when a key-down event resolves to a shortcut.
        /// Modifier-only events pass `nil`.
        var onCaptured: ((KeybindingShortcut?) -> Void)?

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }
        override var needsPanelToBecomeKey: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.textBackgroundColor.withAlphaComponent(0.6).setFill()
            let path = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
            path.fill()

            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let textRect = NSRect(
                x: 0,
                y: (bounds.height - 20) / 2,
                width: bounds.width,
                height: 20
            )
            (displayText as NSString).draw(in: textRect, withAttributes: attrs)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        }

        override func keyDown(with event: NSEvent) {
            // Ignore pure Escape so the sheet's cancel button handles it.
            if event.keyCode == 0x35 { super.keyDown(with: event); return }
            let shortcut = KeybindingShortcut.fromEvent(event)
            onCaptured?(shortcut)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // Capture Cmd-based shortcuts so menu bar doesn't swallow them.
            if event.type == .keyDown,
               window?.firstResponder === self,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) {
                let shortcut = KeybindingShortcut.fromEvent(event)
                onCaptured?(shortcut)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
