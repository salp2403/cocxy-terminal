// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownViewMode.swift - Display mode for the markdown content panel.

import Foundation

/// Which view the markdown panel is showing.
///
/// The three modes share the same `MarkdownDocument` model, so switching is
/// cheap: no re-parse, no file read. Keyboard shortcuts are Cmd+1 (source),
/// Cmd+2 (preview), Cmd+3 (split).
public enum MarkdownViewMode: String, CaseIterable, Sendable, Equatable {
    /// Raw source with markdown syntax highlighting.
    case source

    /// Rendered preview (formatted NSAttributedString).
    case preview

    /// Source on the left, preview on the right, inside an NSSplitView.
    case split

    /// Human-readable label for UI affordances like segmented controls.
    public var label: String {
        switch self {
        case .source:  return "Source"
        case .preview: return "Preview"
        case .split:   return "Split"
        }
    }

    /// Keyboard shortcut key (used alongside ⌘ in menu items and tooltips).
    public var shortcutKey: String {
        switch self {
        case .source:  return "1"
        case .preview: return "2"
        case .split:   return "3"
        }
    }
}
