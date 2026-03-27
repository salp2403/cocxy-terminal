// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabViewModel.swift - Presentation logic for a single tab in the tab bar.

import Foundation
import Combine

// MARK: - Tab View Model

/// Presentation logic for a single tab item in the tab bar.
///
/// Transforms a `Tab` domain model into display-ready properties:
/// - Truncated title for limited tab bar width.
/// - Status color name based on agent state.
/// - Badge text for active agent states.
/// - Subtitle combining git branch and process name.
///
/// Does NOT import AppKit (per ADR-002). Colors are exposed as
/// semantic string names; the view layer maps them to `NSColor`.
///
/// - SeeAlso: ADR-002 (MVVM pattern)
/// - SeeAlso: `Tab` (the domain model this presents)
@MainActor
final class TabViewModel: ObservableObject {

    // MARK: - Constants

    /// Maximum number of characters before truncation.
    static let maxTitleLength = 20

    // MARK: - Published State

    /// The underlying tab model.
    @Published private(set) var tab: Tab

    // MARK: - Initialization

    /// Creates a TabViewModel for the given tab.
    ///
    /// - Parameter tab: The domain tab model to present.
    init(tab: Tab) {
        self.tab = tab
    }

    // MARK: - Display Properties

    /// Title truncated to `maxTitleLength` characters with ellipsis suffix.
    ///
    /// Short titles are returned unchanged. Titles exceeding the limit
    /// are cut at `maxTitleLength` characters with "..." appended.
    var displayTitle: String {
        let title = tab.title
        guard title.count > Self.maxTitleLength else {
            return title
        }
        let truncated = String(title.prefix(Self.maxTitleLength))
        return truncated + "..."
    }

    /// Semantic color name for the agent state indicator.
    ///
    /// The view layer maps these names to actual `NSColor` values:
    /// - "gray" for idle
    /// - "blue" for working and launched
    /// - "yellow" for waiting input
    /// - "green" for finished
    /// - "red" for error
    var statusColorName: String {
        switch tab.agentState {
        case .idle:
            return "gray"
        case .launched, .working:
            return "blue"
        case .waitingInput:
            return "yellow"
        case .finished:
            return "green"
        case .error:
            return "red"
        }
    }

    /// Badge text shown next to the tab. Nil when idle (no badge shown).
    var badgeText: String? {
        switch tab.agentState {
        case .idle:
            return nil
        case .launched:
            return "Launched"
        case .working:
            return "Working"
        case .waitingInput:
            return "Input"
        case .finished:
            return "Done"
        case .error:
            return "Error"
        }
    }

    /// Subtitle combining git branch and process name.
    ///
    /// Format depends on available data:
    /// - Both: "branch . process"
    /// - Only branch: "branch"
    /// - Only process: "process"
    /// - Neither: nil
    var subtitle: String? {
        switch (tab.gitBranch, tab.processName) {
        case let (.some(branch), .some(process)):
            return "\(branch) \u{2022} \(process)"
        case let (.some(branch), .none):
            return branch
        case let (.none, .some(process)):
            return process
        case (.none, .none):
            return nil
        }
    }

    // MARK: - Update

    /// Replaces the underlying tab model and triggers UI updates.
    ///
    /// - Parameter newTab: The updated tab model.
    func update(with newTab: Tab) {
        tab = newTab
    }
}
