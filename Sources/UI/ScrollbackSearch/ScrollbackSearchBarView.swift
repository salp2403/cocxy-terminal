// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ScrollbackSearchBarView.swift - Inline search bar for terminal scrollback.

import AppKit
import SwiftUI
import Combine

// MARK: - Scrollback Search Bar View

/// Inline search bar displayed at the top or bottom of the terminal,
/// similar to a browser's Cmd+F search bar.
///
/// ## Layout
///
/// ```
/// +-- Search Bar -----------------------------------------------+
/// | [TextField: search query]  3 of 47 matches  [<] [>]  [aA] [.*] [x] |
/// +----------------------------------------------------------------+
/// ```
///
/// ## Keyboard
///
/// - Enter: Navigate to next match
/// - Shift+Enter: Navigate to previous match
/// - Escape: Close search bar
///
/// ## Behavior
///
/// - Live search: results update as the user types.
/// - Navigation wraps around at boundaries.
/// - Options (case sensitive, regex) toggle inline.
///
/// - SeeAlso: `ScrollbackSearchBarViewModel` (drives this view)
/// - SeeAlso: `ScrollbackSearchEngineImpl` (executes searches)
struct ScrollbackSearchBarView: View {

    /// The ViewModel driving this search bar.
    @ObservedObject var viewModel: ScrollbackSearchBarViewModel

    /// Callback invoked when the user requests to close the search bar.
    var onClose: (() -> Void)?

    /// Callback invoked when the current match changes (for scrolling to match).
    var onNavigateToResult: ((SearchResult) -> Void)?

    /// Forced `NSAppearance` for the translucent search-bar background.
    ///
    /// `nil` keeps the legacy behaviour (inherit from the window chain).
    /// `.aqua` / `.darkAqua` pin the vibrancy so the search bar matches
    /// the rest of the chrome when the user forces a transparency theme.
    var vibrancyAppearanceOverride: NSAppearance?

    // MARK: - Body

    var body: some View {
        HStack(spacing: 8) {
            searchField
            resultCountLabel
            navigationButtons
            optionToggles
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ZStack {
                // Solid Catppuccin Surface0 as reliable fallback.
                Color(nsColor: CocxyColors.surface0)
                VisualEffectBackground(
                    material: .titlebar,
                    blendingMode: .withinWindow,
                    appearanceOverride: vibrancyAppearanceOverride
                )
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scrollback search")
    }

    // MARK: - Search Field

    private var searchField: some View {
        TextField("Search scrollback...", text: $viewModel.query)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .frame(minWidth: 150, maxWidth: 300)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.textBackgroundColor))
            )
            .accessibilityLabel("Search query")
    }

    // MARK: - Result Count

    private var resultCountLabel: some View {
        Text(viewModel.resultCountDisplay)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .frame(minWidth: 80)
            .accessibilityLabel("Search results: \(viewModel.resultCountDisplay)")
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 2) {
            Button(action: {
                viewModel.navigatePrev()
                notifyNavigationChanged()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.totalMatches == 0)
            .accessibilityLabel("Previous match")

            Button(action: {
                viewModel.navigateNext()
                notifyNavigationChanged()
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.totalMatches == 0)
            .accessibilityLabel("Next match")
        }
    }

    // MARK: - Option Toggles

    private var optionToggles: some View {
        HStack(spacing: 4) {
            Toggle(isOn: $viewModel.caseSensitive) {
                Text("aA")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .accessibilityLabel("Case sensitive")

            Toggle(isOn: $viewModel.useRegex) {
                Text(".*")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .accessibilityLabel("Regular expression")
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button(action: {
            viewModel.close()
            onClose?()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close search")
    }

    // MARK: - Private Helpers

    private func notifyNavigationChanged() {
        if let result = viewModel.currentResult {
            onNavigateToResult?(result)
        }
    }
}
