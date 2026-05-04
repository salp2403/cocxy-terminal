// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperPanelViewModel.swift - Local DB/cloud helper panel state.

import Foundation

typealias DBCloudHelperManifestProvider = () throws -> [PluginManifest]
typealias DBCloudHelperRunner = (DBCloudHelperCommand) throws -> DBCloudHelperRunResult

@MainActor
final class DBCloudHelperPanelViewModel: ObservableObject {
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
    @Published private(set) var statusText: String = "Ready"
    @Published private(set) var outputText: String = ""

    private let manifestProvider: DBCloudHelperManifestProvider
    private let runner: DBCloudHelperRunner
    private let commandBuilder: DBCloudHelperCommandBuilder

    init(
        manifestProvider: @escaping DBCloudHelperManifestProvider = {
            try BundledPluginCatalog().loadManifests()
        },
        runner: @escaping DBCloudHelperRunner = { command in
            try LocalDBCloudHelperRunner().run(command)
        },
        commandBuilder: DBCloudHelperCommandBuilder = DBCloudHelperCommandBuilder()
    ) {
        self.manifestProvider = manifestProvider
        self.runner = runner
        self.commandBuilder = commandBuilder
        refresh()
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
            return "Select a supported helper and enter required fields."
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
            statusText = "Loaded \(descriptors.count) helpers."
        } catch {
            descriptors = []
            selectedHelperID = nil
            statusText = "Failed to load helpers: \(error.localizedDescription)"
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
        statusText = status(for: action, result: result)
    }

    func recordFailure(_ error: Error) {
        outputText = error.localizedDescription
        statusText = "Helper action failed."
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

    private func status(for action: DBCloudHelperAction, result: DBCloudHelperRunResult) -> String {
        let suffix = result.succeeded ? "finished" : "failed"
        switch action {
        case .postgresQuery:
            return "PostgreSQL query \(suffix)."
        case .sqliteQuery:
            return "SQLite query \(suffix)."
        case .s3ListBuckets:
            return "S3 bucket listing \(suffix)."
        }
    }
}
