// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MergePullRequestActionSheet.swift - Confirmation alert that lets the
// user pick a merge strategy and toggle "Delete branch after merge"
// before invoking gh pr merge.
//
// The sheet is intentionally a pure function: callers receive a
// `Decision` value and forward it to the view model. Splitting the
// AppKit invocation from the result interpretation keeps the decision
// logic (button index → method) testable without spawning an NSAlert.

import AppKit
import Foundation

// MARK: - MergePullRequestActionSheet

enum MergePullRequestActionSheet {

    /// Outcome of presenting the alert. `nil` means the user
    /// cancelled (Esc, Cancel button, or the window closed before a
    /// choice was made).
    struct Decision: Equatable, Sendable {
        let method: GitHubMergeMethod
        let deleteBranch: Bool
    }

    /// UserDefaults key the sheet uses to remember the user's last
    /// "Delete branch" choice. Persisting per-process matches GitHub
    /// web UX (it remembers the toggle within the session).
    static let deleteBranchPreferenceKey = "dev.cocxy.codeReview.mergeDeleteBranch"

    // MARK: - Pure decision logic

    /// Maps an `NSAlert.Modal*Response` to a `Decision`. The button
    /// order is fixed (Squash, Merge, Rebase, Cancel) so the mapping
    /// is a simple lookup. Anything outside that range collapses to
    /// `.cancel`.
    ///
    /// Marked `static` so the test suite can exercise the mapping
    /// without instantiating an `NSAlert` — the actual UI presentation
    /// is delegated to `present(...)` below.
    static func decode(
        response: NSApplication.ModalResponse,
        deleteBranch: Bool
    ) -> Decision? {
        switch response {
        case .alertFirstButtonReturn:
            return Decision(method: .squash, deleteBranch: deleteBranch)
        case .alertSecondButtonReturn:
            return Decision(method: .merge, deleteBranch: deleteBranch)
        case .alertThirdButtonReturn:
            return Decision(method: .rebase, deleteBranch: deleteBranch)
        default:
            // Any other response (Cancel button = .alertFourthButtonReturn,
            // Esc, programmatic close) is treated as cancel.
            return nil
        }
    }

    // MARK: - Persistence helpers

    /// Returns the persisted "Delete branch" preference, defaulting to
    /// `true` when the user has never toggled it. `true` aligns with
    /// modern GitHub repository settings ("Auto-delete head branches"
    /// is the recommended default and is enabled by default for new
    /// repos in the GitHub web UI).
    static func storedDeleteBranchPreference(
        in defaults: UserDefaults = .standard
    ) -> Bool {
        if defaults.object(forKey: deleteBranchPreferenceKey) == nil {
            return true
        }
        return defaults.bool(forKey: deleteBranchPreferenceKey)
    }

    /// Persists the user's most recent "Delete branch" toggle so the
    /// next merge starts with the same choice.
    static func storeDeleteBranchPreference(
        _ value: Bool,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(value, forKey: deleteBranchPreferenceKey)
    }

    // MARK: - Presentation

    /// Presents the alert as an application-modal window and returns
    /// the user's decision synchronously. The caller blocks the main
    /// thread for the duration of the alert; that matches GitHub web
    /// where the merge dialog also blocks until dismissed and lets the
    /// caller `if let decision = ... { viewModel.requestMerge(...) }`
    /// inline without continuations.
    ///
    /// Application-modal (rather than window-modal sheet) keeps the
    /// surface simple — Cocxy's review panel is overlay-positioned
    /// and a sheet anchored to the panel itself does not visually
    /// belong with the surrounding window chrome anyway.
    @MainActor
    @discardableResult
    static func present(
        pullRequestNumber: Int,
        defaultsDeleteBranch: Bool? = nil,
        defaults: UserDefaults = .standard
    ) -> Decision? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Merge pull request #\(pullRequestNumber)?"
        alert.informativeText = """
        Choose how to merge this pull request. Once started, this action cannot be undone from Cocxy.
        """

        // Order matters: NSAlert maps the first button to
        // `.alertFirstButtonReturn`, so Squash & Merge stays the
        // default (it is the most common strategy on GitHub today and
        // pressing Return triggers it without scrolling).
        alert.addButton(withTitle: "Squash & Merge")
        alert.addButton(withTitle: "Merge Commit")
        alert.addButton(withTitle: "Rebase & Merge")
        alert.addButton(withTitle: "Cancel")

        // Cancel binding so Esc dismisses the sheet without firing a
        // strategy. The fourth button receives `.alertFourthButtonReturn`
        // which `decode(...)` treats as nil already; setting Esc lets
        // keyboard users reach it without tabbing.
        alert.buttons.last?.keyEquivalent = "\u{1b}"  // Escape

        let initialDeleteBranch = defaultsDeleteBranch
            ?? storedDeleteBranchPreference(in: defaults)
        let checkbox = NSButton(
            checkboxWithTitle: "Delete branch after merge",
            target: nil,
            action: nil
        )
        checkbox.state = initialDeleteBranch ? .on : .off
        checkbox.toolTip = "Removes the local and remote branch once the merge succeeds."
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        // Wrap the checkbox in a fixed-width container so the alert
        // does not resize unpredictably across locales with longer
        // translations of the label.
        let accessoryWidth: CGFloat = 320
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: accessoryWidth, height: 24))
        accessory.addSubview(checkbox)
        NSLayoutConstraint.activate([
            checkbox.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
            checkbox.trailingAnchor.constraint(lessThanOrEqualTo: accessory.trailingAnchor),
            checkbox.centerYAnchor.constraint(equalTo: accessory.centerYAnchor),
        ])
        alert.accessoryView = accessory

        let response = alert.runModal()
        let deleteBranch = checkbox.state == .on
        let decision = decode(response: response, deleteBranch: deleteBranch)
        // Persist the user's checkbox choice regardless of which
        // button was pressed. Even if they cancel, remembering the
        // toggle matches the GitHub web behaviour.
        storeDeleteBranchPreference(deleteBranch, in: defaults)
        return decision
    }
}
