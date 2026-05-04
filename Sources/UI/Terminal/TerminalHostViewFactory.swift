// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalHostViewFactory.swift - Selects the renderer for the active engine.

import Foundation

@MainActor
enum TerminalHostViewFactory {
    static func make(
        viewModel: TerminalViewModel,
        engine: (any TerminalEngine)?,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) -> TerminalHostView {
        if engine is PTYDaemonClient {
            return PTYDaemonHostView(viewModel: viewModel)
        }
        return CocxyCoreView(viewModel: viewModel, localizer: localizer)
    }
}
