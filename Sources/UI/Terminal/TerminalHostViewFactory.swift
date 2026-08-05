// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalHostViewFactory.swift - Selects the renderer for the active engine.

import AppKit

@MainActor
enum TerminalHostViewFactory {
    static func make(
        viewModel: TerminalViewModel,
        engine: (any TerminalEngine)?,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) -> TerminalHostView {
        let view: TerminalHostView = if engine is PTYDaemonClient {
            PTYDaemonHostView(viewModel: viewModel, localizer: localizer)
        } else {
            CocxyCoreView(viewModel: viewModel, localizer: localizer)
        }
        view.userInterfaceLayoutDirection = .leftToRight
        return view
    }
}
