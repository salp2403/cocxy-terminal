// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserFindBar.swift - Find-in-page bar for the in-app browser.

import SwiftUI

// MARK: - Browser Find Bar

/// A find-in-page bar that appears at the top of the browser content area.
///
/// ## Layout
///
/// ```
/// +------------------------------------------------------+
/// | [magnifyingglass] [search text...] 3 of 15 [<][>]  X |
/// +------------------------------------------------------+
/// ```
///
/// ## Features
///
/// - Text field with live search updates.
/// - Match count display (current / total).
/// - Previous / Next navigation buttons.
/// - Escape key or close button to dismiss.
/// - Delegates actual find operations to the parent via callbacks,
///   which should invoke WKWebView's find or JavaScript highlighting.
///
/// ## Keyboard Shortcuts
///
/// - Cmd+F: Show (handled by parent).
/// - Escape: Dismiss.
/// - Enter: Next match.
/// - Shift+Enter: Previous match.
///
/// - SeeAlso: ``BrowserPanelView``
/// - SeeAlso: ``BrowserContentView``
struct BrowserFindBar: View {

    /// The search query text, bound to the parent.
    @Binding var searchText: String

    /// The index of the currently highlighted match (1-based).
    let currentMatch: Int

    /// The total number of matches found.
    let totalMatches: Int

    /// Called when the search text changes (debounced by the parent).
    let onSearch: (String) -> Void

    /// Called when the user requests the next match.
    let onNextMatch: () -> Void

    /// Called when the user requests the previous match.
    let onPreviousMatch: () -> Void

    /// Called when the user dismisses the find bar.
    let onDismiss: () -> Void

    /// Whether the text field should receive focus on appear.
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Body

    var body: some View {
        HStack(spacing: 6) {
            searchField
            matchCountLabel
            navigationButtons
            closeButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: CocxyColors.surface0))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(nsColor: CocxyColors.surface1)),
            alignment: .bottom
        )
        .onAppear { isSearchFieldFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find in page")
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))

            TextField("Find in page...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .focused($isSearchFieldFocused)
                .onSubmit { onNextMatch() }
                .onChange(of: searchText) { onSearch(searchText) }
                .accessibilityLabel("Search text")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: CocxyColors.base))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(nsColor: CocxyColors.surface1), lineWidth: 1)
        )
    }

    // MARK: - Match Count

    private var matchCountLabel: some View {
        Group {
            if searchText.isEmpty {
                EmptyView()
            } else {
                Text(matchCountText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(matchCountColor)
                    .frame(minWidth: 50)
                    .accessibilityLabel(matchCountAccessibilityLabel)
            }
        }
    }

    private var matchCountText: String {
        if totalMatches == 0 {
            return "0 results"
        }
        return "\(currentMatch) of \(totalMatches)"
    }

    private var matchCountColor: Color {
        if totalMatches == 0 && !searchText.isEmpty {
            return Color(nsColor: CocxyColors.red)
        }
        return Color(nsColor: CocxyColors.subtext0)
    }

    private var matchCountAccessibilityLabel: String {
        if totalMatches == 0 {
            return "No matches found"
        }
        return "Match \(currentMatch) of \(totalMatches)"
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button(action: onPreviousMatch) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(navigationButtonColor)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .disabled(totalMatches == 0)
            .accessibilityLabel("Previous match")

            Button(action: onNextMatch) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(navigationButtonColor)
            }
            .buttonStyle(.plain)
            .frame(width: 22, height: 22)
            .disabled(totalMatches == 0)
            .accessibilityLabel("Next match")
        }
    }

    private var navigationButtonColor: Color {
        totalMatches > 0
            ? Color(nsColor: CocxyColors.text)
            : Color(nsColor: CocxyColors.surface2)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .accessibilityLabel("Close find bar")
    }
}
