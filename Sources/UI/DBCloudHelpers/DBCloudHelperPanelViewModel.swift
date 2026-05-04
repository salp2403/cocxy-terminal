// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperPanelViewModel.swift - Local DB/cloud helper panel state.

import Foundation

typealias DBCloudHelperManifestProvider = () throws -> [PluginManifest]
typealias DBCloudHelperRunner = (DBCloudHelperCommand) throws -> DBCloudHelperRunResult

@MainActor
final class DBCloudHelperPanelViewModel: ObservableObject {
    private enum StatusState: Equatable {
        case ready
        case loaded(Int)
        case loadFailed(String)
        case action(DBCloudHelperAction, Bool)
        case actionFailed
    }

    @Published private(set) var descriptors: [DBCloudHelperDescriptor] = []
    @Published var selectedKind: DBCloudHelperKind = .database {
        didSet {
            guard oldValue != selectedKind else { return }
            selectDefaultHelperForSelectedKind()
        }
    }
    @Published var selectedHelperID: String?
    @Published var postgresDatabase: String = ""
    @Published var sqliteDatabasePath: String = ""
    @Published var sqlText: String = "select 1"
    @Published var awsProfile: String = ""
    @Published var awsRegion: String = ""
    @Published private(set) var statusText: String
    @Published private(set) var outputText: String = ""

    private let manifestProvider: DBCloudHelperManifestProvider
    private let runner: DBCloudHelperRunner
    private let commandBuilder: DBCloudHelperCommandBuilder
    private var localizer: AppLocalizer
    private var statusState: StatusState = .ready
    private var currentError: Error?

    init(
        manifestProvider: @escaping DBCloudHelperManifestProvider = {
            try BundledPluginCatalog().loadManifests()
        },
        runner: @escaping DBCloudHelperRunner = { command in
            try LocalDBCloudHelperRunner().run(command)
        },
        commandBuilder: DBCloudHelperCommandBuilder = DBCloudHelperCommandBuilder(),
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.manifestProvider = manifestProvider
        self.runner = runner
        self.commandBuilder = commandBuilder
        self.localizer = localizer
        self.statusText = Self.localizedStatusText(.ready, localizer: localizer)
        refresh()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        statusText = Self.localizedStatusText(statusState, localizer: localizer)
        if let currentError {
            outputText = Self.localizedErrorDescription(currentError, localizer: localizer)
        }
    }

    var filteredDescriptors: [DBCloudHelperDescriptor] {
        descriptors.filter { $0.kind == selectedKind }
    }

    var selectedDescriptor: DBCloudHelperDescriptor? {
        descriptors.first { $0.id == selectedHelperID }
    }

    var commandPreview: String {
        do {
            return try makeCommand().redactedPreview
        } catch {
            return localizer.string(
                "dbCloud.commandPreview.unavailable",
                fallback: "Select a supported helper and enter required fields."
            )
        }
    }

    func refresh() {
        do {
            descriptors = DBCloudHelperCatalog.descriptors(from: try manifestProvider())
            if selectedHelperID == nil || !descriptors.contains(where: { $0.id == selectedHelperID }) {
                selectedHelperID = descriptors.first(where: { $0.id == "cocxy-db-sqlite" })?.id
                    ?? descriptors.first?.id
            }
            if let selectedDescriptor {
                selectedKind = selectedDescriptor.kind
            }
            setStatus(.loaded(descriptors.count))
            currentError = nil
        } catch {
            descriptors = []
            selectedHelperID = nil
            currentError = error
            setStatus(.loadFailed(Self.localizedErrorDescription(error, localizer: localizer)))
        }
    }

    func select(_ descriptor: DBCloudHelperDescriptor) {
        selectedKind = descriptor.kind
        selectedHelperID = descriptor.id
    }

    func runSelectedAction() throws {
        let action = try makeAction()
        let command = try commandBuilder.command(for: action)
        let result = try runner(command)
        outputText = result.stdout + result.stderr
        setStatus(.action(action, result.succeeded))
        currentError = nil
    }

    func recordFailure(_ error: Error) {
        currentError = error
        outputText = Self.localizedErrorDescription(error, localizer: localizer)
        setStatus(.actionFailed)
    }

    private func makeCommand() throws -> DBCloudHelperCommand {
        try commandBuilder.command(for: makeAction())
    }

    private func selectDefaultHelperForSelectedKind() {
        guard selectedDescriptor?.kind != selectedKind else { return }
        selectedHelperID = descriptors.first { $0.kind == selectedKind }?.id
    }

    private func makeAction() throws -> DBCloudHelperAction {
        switch selectedHelperID {
        case "cocxy-db-postgres":
            return .postgresQuery(database: postgresDatabase, sql: sqlText)
        case "cocxy-db-sqlite":
            return .sqliteQuery(databasePath: sqliteDatabasePath, sql: sqlText)
        case "cocxy-aws-cli-helper":
            return .s3ListBuckets(profile: awsProfile, region: awsRegion)
        case .some(let id):
            throw DBCloudHelperError.unsupportedHelper(id)
        case .none:
            throw DBCloudHelperError.unsupportedHelper("none")
        }
    }

    private func setStatus(_ status: StatusState) {
        statusState = status
        statusText = Self.localizedStatusText(status, localizer: localizer)
    }

    private static func localizedStatusText(
        _ status: StatusState,
        localizer: AppLocalizer
    ) -> String {
        switch status {
        case .ready:
            return localizer.string("dbCloud.status.ready", fallback: "Ready")
        case .loaded(let count):
            return String(
                format: localizer.string(
                    count == 1 ? "dbCloud.status.loaded.one" : "dbCloud.status.loaded.many",
                    fallback: count == 1 ? "%d helper loaded." : "%d helpers loaded."
                ),
                count
            )
        case .loadFailed(let errorText):
            return String(
                format: localizer.string(
                    "dbCloud.status.loadFailed",
                    fallback: "Failed to load helpers: %@"
                ),
                errorText
            )
        case .action(let action, let succeeded):
            return localizedActionStatus(action, succeeded: succeeded, localizer: localizer)
        case .actionFailed:
            return localizer.string("dbCloud.status.actionFailed", fallback: "Helper action failed.")
        }
    }

    private static func localizedActionStatus(
        _ action: DBCloudHelperAction,
        succeeded: Bool,
        localizer: AppLocalizer
    ) -> String {
        let keySuffix = succeeded ? "finished" : "failed"
        switch action {
        case .postgresQuery:
            return localizer.string(
                "dbCloud.status.postgres.\(keySuffix)",
                fallback: succeeded ? "PostgreSQL query finished." : "PostgreSQL query failed."
            )
        case .sqliteQuery:
            return localizer.string(
                "dbCloud.status.sqlite.\(keySuffix)",
                fallback: succeeded ? "SQLite query finished." : "SQLite query failed."
            )
        case .s3ListBuckets:
            return localizer.string(
                "dbCloud.status.s3.\(keySuffix)",
                fallback: succeeded ? "S3 bucket listing finished." : "S3 bucket listing failed."
            )
        }
    }

    private static func localizedErrorDescription(
        _ error: Error,
        localizer: AppLocalizer
    ) -> String {
        if let helperError = error as? DBCloudHelperError {
            switch helperError {
            case .emptyDatabase:
                return localizer.string("dbCloud.error.emptyDatabase", fallback: "Enter a database target.")
            case .emptyQuery:
                return localizer.string("dbCloud.error.emptyQuery", fallback: "Enter a query.")
            case .unsupportedHelper(let id):
                return String(
                    format: localizer.string(
                        "dbCloud.error.unsupportedHelper",
                        fallback: "%@ does not have a local visual action yet."
                    ),
                    id
                )
            }
        }
        return error.localizedDescription
    }
}
