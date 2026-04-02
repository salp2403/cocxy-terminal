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

    /// Callback when the user closes this panel.
    var onClose: (() -> Void)?

    // MARK: - Initialization

    init(viewModel: AgentDashboardViewModel, subagentId: String, sessionId: String) {
        self.subagentId = subagentId
        self.sessionId = sessionId
        super.init(frame: .zero)

        let panelView = SubagentPanelView(
            viewModel: viewModel,
            subagentId: subagentId,
            sessionId: sessionId,
            onClose: { [weak self] in self?.onClose?() }
        )
        let hosting = NSHostingView(rootView: panelView)
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
}
