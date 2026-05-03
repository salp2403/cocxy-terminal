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

    init(windowProvider: @escaping () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow }) {
        self.windowProvider = windowProvider
    }

    func destination(
        for format: ActivityDashboardExportFormat,
        defaultFilename: String,
        completion: @escaping (URL?) -> Void
    ) {
        let panel = NSSavePanel()
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

    func confirmDeleteAll(completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete all Activity data?"
        alert.informativeText = "This removes local Activity and token records from this Mac."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        let handle: (NSApplication.ModalResponse) -> Void = { response in
            completion(response == .alertFirstButtonReturn)
        }

        if let window = windowProvider() {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
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
}
