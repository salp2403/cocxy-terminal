// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityDashboardFileActions.swift - Manual export and deletion helpers for local Activity data.

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
protocol ActivityDashboardFilePresenting: AnyObject {
    func destination(
        for format: ActivityDashboardExportFormat,
        defaultFilename: String,
        completion: @escaping (URL?) -> Void
    )

    func confirmDeleteAll(completion: @escaping (Bool) -> Void)
}

@MainActor
final class ActivityDashboardFileActions: ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastExportedURL: URL?

    private let viewModel: ActivityDashboardViewModel
    private let presenter: ActivityDashboardFilePresenting

    init(
        viewModel: ActivityDashboardViewModel,
        presenter: ActivityDashboardFilePresenting = SystemActivityDashboardFilePresenter()
    ) {
        self.viewModel = viewModel
        self.presenter = presenter
    }

    func export(_ format: ActivityDashboardExportFormat) {
        presenter.destination(
            for: format,
            defaultFilename: Self.defaultFilename(for: format)
        ) { [weak self] destination in
            guard let self, let destination else { return }
            do {
                let data = try viewModel.exportData(format: format)
                try data.write(to: destination, options: .atomic)
                lastExportedURL = destination
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func confirmAndDeleteAllLocalData() {
        presenter.confirmDeleteAll { [weak self] confirmed in
            guard let self, confirmed else { return }
            do {
                try viewModel.deleteAllLocalData()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    static func defaultFilename(for format: ActivityDashboardExportFormat) -> String {
        switch format {
        case .json:
            return "cocxy-activity.json"
        case .eventsCSV:
            return "cocxy-activity-events.csv"
        case .tokenUsageCSV:
            return "cocxy-activity-token-usage.csv"
        }
    }
}

@MainActor
final class SystemActivityDashboardFilePresenter: ActivityDashboardFilePresenting {
    private let windowProvider: () -> NSWindow?
    private let localizer: AppLocalizer

    init(
        windowProvider: @escaping () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow },
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.windowProvider = windowProvider
        self.localizer = localizer
    }

    func destination(
        for format: ActivityDashboardExportFormat,
        defaultFilename: String,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        let copy = Self.localizedDestinationPanelCopy(for: format, localizer: localizer)
        panel.title = copy.title
        panel.message = copy.message
        panel.prompt = copy.prompt
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = defaultFilename

        if let window = windowProvider() {
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            let response = panel.runModal()
            completion(response == .OK ? panel.url : nil)
        }
    }

    static func localizedDestinationPanelCopy(
        for format: ActivityDashboardExportFormat,
        localizer: AppLocalizer
    ) -> AppFilePanelCopy {
        AppFilePanelCopy(
            title: localizer.string("activity.exportPanel.title", fallback: "Export Activity"),
            message: String(
                format: localizer.string(
                    "activity.exportPanel.message",
                    fallback: "Choose where to save %@."
                ),
                format.localizedMenuTitle(using: localizer)
            ),
            prompt: localizer.string("common.export", fallback: "Export")
        )
    }

    func confirmDeleteAll(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let copy = Self.localizedDeleteAllCopy(localizer: localizer)
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .alertFirstButtonReturn)
        }

        if let window = windowProvider() {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    static func localizedDeleteAllCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("activity.deleteAll.title", fallback: "Delete all Activity data?"),
            informativeText: localizer.string(
                "activity.deleteAll.message",
                fallback: "This removes local Activity and token records from this Mac."
            ),
            primaryButton: localizer.string("activity.deleteAll.button", fallback: "Delete"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }
}

extension ActivityDashboardExportFormat {
    var contentType: UTType {
        switch self {
        case .json:
            return .json
        case .eventsCSV, .tokenUsageCSV:
            return .commaSeparatedText
        }
    }

    var menuTitle: String {
        switch self {
        case .json:
            return "JSON"
        case .eventsCSV:
            return "Events CSV"
        case .tokenUsageCSV:
            return "Token Usage CSV"
        }
    }

    func localizedMenuTitle(using localizer: AppLocalizer) -> String {
        switch self {
        case .json:
            return localizer.string("activity.export.json", fallback: menuTitle)
        case .eventsCSV:
            return localizer.string("activity.export.eventsCSV", fallback: menuTitle)
        case .tokenUsageCSV:
            return localizer.string("activity.export.tokenUsageCSV", fallback: menuTitle)
        }
    }
}
