// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DB and cloud helper panel")
struct DBCloudHelperSwiftTestingTests {
    @Test("catalog exposes bundled database cloud and container helpers")
    func catalogExposesBundledHelpers() throws {
        let manifests = try BundledPluginCatalog(
            pluginsDirectory: repositoryRoot().appendingPathComponent("Resources/Plugins", isDirectory: true)
        ).loadManifests()

        let descriptors = DBCloudHelperCatalog.descriptors(from: manifests)
        let ids = Set(descriptors.map(\.id))

        #expect(descriptors.count == 10)
        #expect(ids.contains("cocxy-db-postgres"))
        #expect(ids.contains("cocxy-db-sqlite"))
        #expect(ids.contains("cocxy-aws-cli-helper"))
        #expect(ids.contains("cocxy-kubernetes"))
        #expect(descriptors.filter { $0.kind == .database }.count == 4)
        #expect(descriptors.filter { $0.kind == .cloud }.count == 4)
        #expect(descriptors.filter { $0.kind == .container }.count == 2)
    }

    @Test("command previews redact database paths and query text")
    func commandPreviewsRedactSensitiveInputs() throws {
        let builder = DBCloudHelperCommandBuilder()

        let postgres = try builder.command(
            for: .postgresQuery(database: "postgres://user:secret@localhost/app", sql: "select * from users")
        )
        let sqlite = try builder.command(
            for: .sqliteQuery(databasePath: "/Users/private/app.sqlite", sql: "select token from secrets")
        )

        #expect(postgres.executable == "psql")
        #expect(postgres.arguments == [
            "--dbname", "postgres://user:secret@localhost/app",
            "--command", "select * from users",
        ])
        #expect(postgres.redactedPreview == "psql --dbname <database> --command <query>")
        #expect(!postgres.redactedPreview.contains("secret"))
        #expect(sqlite.redactedPreview == "sqlite3 <database> <query>")
        #expect(!sqlite.redactedPreview.contains("/Users/private"))
        #expect(!sqlite.redactedPreview.contains("token"))
    }

    @Test("view model runs selected sqlite query on explicit request")
    @MainActor
    func viewModelRunsSelectedSQLiteQueryOnExplicitRequest() throws {
        var executedCommands: [DBCloudHelperCommand] = []
        let manifests = try BundledPluginCatalog(
            pluginsDirectory: repositoryRoot().appendingPathComponent("Resources/Plugins", isDirectory: true)
        ).loadManifests()
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { command in
                executedCommands.append(command)
                return DBCloudHelperRunResult(exitCode: 0, stdout: "answer\n1\n", stderr: "")
            }
        )

        viewModel.selectedHelperID = "cocxy-db-sqlite"
        viewModel.sqliteDatabasePath = "/tmp/cocxy-cc2-smoke.sqlite"
        viewModel.sqlText = "select 1 as answer"

        try viewModel.runSelectedAction()

        #expect(executedCommands.count == 1)
        #expect(executedCommands[0].executable == "sqlite3")
        #expect(executedCommands[0].arguments == ["/tmp/cocxy-cc2-smoke.sqlite", "select 1 as answer"])
        #expect(viewModel.outputText == "answer\n1\n")
        #expect(viewModel.statusText == "SQLite query finished.")
    }

    @Test("switching to cloud selects AWS helper and builds S3 command")
    @MainActor
    func switchingToCloudSelectsAWSHelperAndBuildsS3Command() throws {
        var executedCommands: [DBCloudHelperCommand] = []
        let manifests = try BundledPluginCatalog(
            pluginsDirectory: repositoryRoot().appendingPathComponent("Resources/Plugins", isDirectory: true)
        ).loadManifests()
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { command in
                executedCommands.append(command)
                return DBCloudHelperRunResult(exitCode: 0, stdout: "{\"Buckets\":[]}\n", stderr: "")
            }
        )

        viewModel.selectedKind = .cloud
        viewModel.awsProfile = "dev"
        viewModel.awsRegion = "us-east-1"

        #expect(viewModel.selectedHelperID == "cocxy-aws-cli-helper")
        #expect(viewModel.commandPreview == "aws s3api list-buckets --output json --profile dev --region us-east-1")

        try viewModel.runSelectedAction()

        #expect(executedCommands.count == 1)
        #expect(executedCommands[0].executable == "aws")
        #expect(executedCommands[0].arguments == [
            "s3api", "list-buckets", "--output", "json",
            "--profile", "dev", "--region", "us-east-1",
        ])
        #expect(viewModel.outputText == "{\"Buckets\":[]}\n")
        #expect(viewModel.statusText == "S3 bucket listing finished.")
    }

    @Test("Spanish localizer updates DB and cloud helper statuses")
    @MainActor
    func spanishLocalizerUpdatesDBCloudHelperStatuses() throws {
        let manifests = try BundledPluginCatalog(
            pluginsDirectory: repositoryRoot().appendingPathComponent("Resources/Plugins", isDirectory: true)
        ).loadManifests()
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { _ in DBCloudHelperRunResult(exitCode: 0, stdout: "ok\n", stderr: "") },
            localizer: spanish
        )

        #expect(DBCloudHelperKind.database.localizedTitle(using: spanish) == "Base de datos")
        #expect(viewModel.statusText == "10 ayudantes cargados.")

        viewModel.selectedHelperID = "cocxy-db-sqlite"
        viewModel.sqliteDatabasePath = "/tmp/cocxy.sqlite"
        viewModel.sqlText = "select 1"

        try viewModel.runSelectedAction()

        #expect(viewModel.statusText == "Consulta SQLite finalizada.")

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))

        #expect(viewModel.statusText == "SQLite query finished.")
    }
}

private func repositoryRoot() -> URL {
    var current = URL(fileURLWithPath: #filePath)
    while current.path != "/" {
        let candidate = current.appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return current
        }
        current.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

private func localizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
