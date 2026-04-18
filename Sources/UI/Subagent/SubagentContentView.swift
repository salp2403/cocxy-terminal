// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SubagentContentView.swift - AppKit host for SubagentPanelView in splits.

import AppKit
import SwiftUI

// MARK: - Subagent Content View

/// An AppKit NSView that hosts a `SubagentPanelView` inside a split.
///
/// Created by `MainWindowController+SplitActions` when a SubagentStart
/// hook event triggers auto-split creation. Manages the SwiftUI hosting
/// lifecycle and provides the close callback.
final class SubagentContentView: NSView {

    /// The subagent identifier this panel tracks.
    let subagentId: String

    /// The parent session identifier.
    let sessionId: String

    private var hostingView: NSHostingView<SubagentPanelView>?
    private weak var viewModel: AgentDashboardViewModel?

    /// Forced `NSAppearance` applied to the hosted `SubagentPanelView`.
    ///
    /// Retained so re-renders triggered by config hot-reload can rebuild
    /// the SwiftUI root view without losing the active override.
    private(set) var vibrancyAppearanceOverride: NSAppearance?

    /// Callback when the user closes this panel.
    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(
        viewModel: AgentDashboardViewModel,
        subagentId: String,
        sessionId: String,
        vibrancyAppearanceOverride: NSAppearance? = nil
    ) {
        self.subagentId = subagentId
        self.sessionId = sessionId
        self.viewModel = viewModel
        self.vibrancyAppearanceOverride = vibrancyAppearanceOverride
        super.init(frame: .zero)

        let hosting = NSHostingView(rootView: makePanelView(viewModel: viewModel))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        self.hostingView = hosting
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SubagentContentView does not support NSCoding")
    }

    // MARK: - Appearance Propagation

    /// Applies a new vibrancy `NSAppearance` override to the hosted panel.
    ///
    /// Called by `MainWindowController` when the user changes the
    /// `transparency-chrome-theme` setting so live subagent split panels
    /// repaint vibrancy with the forced appearance. A no-op when the
    /// hosting view or owning dashboard view-model are no longer live
    /// (for example during teardown).
    func setVibrancyAppearanceOverride(_ override: NSAppearance?) {
        vibrancyAppearanceOverride = override
        guard let hostingView, let viewModel else { return }
        hostingView.rootView = makePanelView(viewModel: viewModel)
    }

    private func makePanelView(viewModel: AgentDashboardViewModel) -> SubagentPanelView {
        var view = SubagentPanelView(
            viewModel: viewModel,
            subagentId: subagentId,
            sessionId: sessionId,
            onClose: { [weak self] in self?.onClose?() }
        )
        view.vibrancyAppearanceOverride = vibrancyAppearanceOverride
        return view
    }
}
