// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DB and cloud helper panel")
struct DBCloudHelperSwiftTestingTests {
    @Test("catalog exposes bundled database cloud and container helpers")
    func catalogExposesBundledHelpers() throws {
        let manifests = try bundledHelperManifests()
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

    @Test("database commands keep credentials and SQL out of argv")
    func databaseCommandsKeepSecretsOutOfArguments() throws {
        let builder = DBCloudHelperCommandBuilder()
        let password = "secret:marker"
        let query = "select 'query-marker' from users"

        let postgres = try builder.command(
            for: .postgresQuery(
                database: "postgres://user:secret%3Amarker@localhost:5433/app",
                sql: query
            )
        )
        let sqlite = try builder.command(
            for: .sqliteQuery(
                databasePath: "/Users/private/app.sqlite",
                sql: "select token from secrets"
            )
        )

        #expect(postgres.executable == "psql")
        #expect(postgres.arguments == [
            "--no-password", "--dbname", "postgres://user@localhost:5433/app",
            "--file", "-",
        ])
        #expect(String(decoding: try #require(postgres.standardInput), as: UTF8.self) == query)
        #expect(!postgres.arguments.joined().contains(password))
        #expect(!postgres.arguments.joined().contains("query-marker"))
        #expect(postgres.redactedPreview == "psql --no-password --dbname <database> --file -")

        guard case .postgreSQLPassfile(let passfile)? = postgres.credentialMaterial else {
            Issue.record("Expected protected PostgreSQL passfile material")
            return
        }
        #expect(String(decoding: passfile, as: UTF8.self) == "localhost:5433:app:user:secret\\:marker\n")

        #expect(sqlite.arguments == ["/Users/private/app.sqlite"])
        #expect(String(decoding: try #require(sqlite.standardInput), as: UTF8.self) == "select token from secrets")
        #expect(sqlite.redactedPreview == "sqlite3 <database>")
        #expect(!sqlite.arguments.joined().contains("token"))
    }

    @Test("PostgreSQL passfile fields decode and escape URI components")
    func postgresPassfileEscapesDecodedURIFields() throws {
        let command = try DBCloudHelperCommandBuilder().command(
            for: .postgresQuery(
                database: "postgresql://us%3Aer:p%40ss%3Aword@[::1]:5433/db%3Aname?sslmode=require",
                sql: "select 1"
            )
        )

        #expect(command.arguments == [
            "--no-password", "--dbname",
            "postgresql://us%3Aer@[::1]:5433/db%3Aname?sslmode=require",
            "--file", "-",
        ])
        guard case .postgreSQLPassfile(let passfile)? = command.credentialMaterial else {
            Issue.record("Expected protected PostgreSQL passfile material")
            return
        }
        #expect(String(decoding: passfile, as: UTF8.self) == "\\:\\:1:5433:db\\:name:us\\:er:p@ss\\:word\n")
    }

    @Test("PostgreSQL passfile resolves local and hostaddr connection targets")
    func postgresPassfileResolvesDefaultHosts() throws {
        let builder = DBCloudHelperCommandBuilder()
        let local = try builder.command(
            for: .postgresQuery(
                database: "postgresql://dev:local-secret@/app",
                sql: "select 1"
            )
        )
        let addressed = try builder.command(
            for: .postgresQuery(
                database: "postgresql://dev@/app?hostaddr=127.0.0.1&password=remote-secret",
                sql: "select 1"
            )
        )

        guard case .postgreSQLPassfile(let localPassfile)? = local.credentialMaterial,
              case .postgreSQLPassfile(let addressedPassfile)? = addressed.credentialMaterial else {
            Issue.record("Expected protected PostgreSQL passfile material")
            return
        }
        #expect(String(decoding: localPassfile, as: UTF8.self) == "localhost:5432:app:dev:local-secret\n")
        #expect(String(decoding: addressedPassfile, as: UTF8.self) == "127.0.0.1:5432:app:dev:remote-secret\n")
        #expect(!addressed.arguments.joined().contains("remote-secret"))
        #expect(addressed.arguments.contains("postgresql://dev@/app?hostaddr=127.0.0.1"))
    }

    @Test("unsupported password conninfo and oversized queries fail closed")
    func unsafeDatabaseInputsFailClosed() throws {
        let builder = DBCloudHelperCommandBuilder()

        #expect(throws: DBCloudHelperError.unsupportedPostgreSQLCredentialFormat) {
            try builder.command(
                for: .postgresQuery(
                    database: "host=localhost user=dev password=secret",
                    sql: "select 1"
                )
            )
        }
        #expect(throws: DBCloudHelperError.unsupportedPostgreSQLCredentialFormat) {
            try builder.command(
                for: .postgresQuery(
                    database: "postgresql://dev@localhost/app?sslpassword=private-key-secret",
                    sql: "select 1"
                )
            )
        }
        #expect(throws: DBCloudHelperError.unsupportedPostgreSQLCredentialFormat) {
            try builder.command(
                for: .postgresQuery(
                    database: "host=localhost user=dev oauth_client_secret=secret",
                    sql: "select 1"
                )
            )
        }

        let oversized = String(
            repeating: "x",
            count: DBCloudHelperCommand.maximumStandardInputBytes + 1
        )
        #expect(
            throws: DBCloudHelperError.queryTooLarge(
                limitBytes: DBCloudHelperCommand.maximumStandardInputBytes
            )
        ) {
            try builder.command(
                for: .sqliteQuery(databasePath: "/tmp/test.sqlite", sql: oversized)
            )
        }
    }

    @Test("runner drains pipe-sized stdout and stderr while bounding retained memory")
    func runnerDrainsLargeStreamsWithBoundedRetention() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = try makeExecutableScript(
            in: directory,
            named: "large-output",
            contents: """
            #!/bin/sh
            (/usr/bin/yes O | /usr/bin/head -c "$1") &
            stdout_pid=$!
            (/usr/bin/yes E | /usr/bin/head -c "$1" >&2) &
            stderr_pid=$!
            wait "$stdout_pid"
            stdout_status=$?
            wait "$stderr_pid"
            stderr_status=$?
            [ "$stdout_status" -eq 0 ] && [ "$stderr_status" -eq 0 ]
            """
        )
        let emittedBytes = 512 * 1_024
        let retainedBytes = 32 * 1_024
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 5,
                terminationGracePeriodSeconds: 0.5,
                maximumRetainedBytesPerStream: retainedBytes
            )
        )

        let result = try await runner.run(
            DBCloudHelperCommand(
                executable: script.path,
                arguments: [String(emittedBytes)],
                redactedArguments: [:]
            )
        )

        #expect(result.exitCode == 0)
        #expect(result.stdoutBytesRead == Int64(emittedBytes))
        #expect(result.stderrBytesRead == Int64(emittedBytes))
        #expect(result.stdout.utf8.count == retainedBytes)
        #expect(result.stderr.utf8.count == retainedBytes)
        #expect(result.stdoutTruncated)
        #expect(result.stderrTruncated)
    }

    @Test("runner transports PostgreSQL secrets through stdin and a temporary 0600 passfile")
    func runnerUsesProtectedPostgresTransportsAndCleansUp() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentialRoot = directory.appendingPathComponent("credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: credentialRoot, withIntermediateDirectories: false)
        let script = try makeExecutableScript(
            in: directory,
            named: "fake-psql",
            contents: """
            #!/bin/sh
            printf 'command='
            /bin/ps -p $$ -o command=
            printf 'mode='
            /usr/bin/stat -f '%OLp' "$PGPASSFILE"
            printf '\npath=%s\n' "$PGPASSFILE"
            printf 'passfile='
            /bin/cat "$PGPASSFILE"
            printf 'stdin='
            /bin/cat
            """
        )
        let passwordMarker = "URI_SECRET_MARKER"
        let queryMarker = "select 'QUERY_SECRET_MARKER'"
        let built = try DBCloudHelperCommandBuilder().command(
            for: .postgresQuery(
                database: "postgresql://probe:\(passwordMarker)@127.0.0.1/example",
                sql: queryMarker
            )
        )
        let command = DBCloudHelperCommand(
            executable: script.path,
            arguments: built.arguments,
            redactedArguments: built.redactedArguments,
            standardInput: built.standardInput,
            credentialMaterial: built.credentialMaterial
        )
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 3,
                terminationGracePeriodSeconds: 0.5,
                maximumRetainedBytesPerStream: 128 * 1_024,
                credentialTemporaryDirectory: credentialRoot
            )
        )

        let result = try await runner.run(command)
        let lines = result.stdout.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let processCommand = try #require(lines.first { $0.hasPrefix("command=") })
        let passfilePathLine = try #require(lines.first { $0.hasPrefix("path=") })
        let passfilePath = String(passfilePathLine.dropFirst("path=".count))

        #expect(result.exitCode == 0)
        #expect(!processCommand.contains(passwordMarker))
        #expect(!processCommand.contains("QUERY_SECRET_MARKER"))
        #expect(result.stdout.contains("mode=600"))
        #expect(result.stdout.contains("passfile=127.0.0.1:5432:example:probe:\(passwordMarker)"))
        #expect(result.stdout.contains("stdin=\(queryMarker)"))
        #expect(!FileManager.default.fileExists(atPath: passfilePath))
        #expect(try FileManager.default.contentsOfDirectory(atPath: credentialRoot.path).isEmpty)
    }

    @Test("timeout terminates and reaps the child")
    func timeoutTerminatesChild() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("timeout.pid")
        let script = try longRunningScript(in: directory)
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 1,
                terminationGracePeriodSeconds: 0.2,
                maximumRetainedBytesPerStream: 8 * 1_024
            )
        )

        let task = Task {
            try await runner.run(
                DBCloudHelperCommand(
                    executable: script.path,
                    arguments: [pidFile.path],
                    redactedArguments: [:]
                )
            )
        }
        try await waitForFile(pidFile)

        do {
            _ = try await task.value
            Issue.record("Expected helper timeout")
        } catch let error as DBCloudHelperExecutionError {
            #expect(error == .timedOut(seconds: 1))
        }

        let pid = try processID(from: pidFile)
        #expect(!processExists(pid))
    }

    @Test("continuous output cannot starve cancellation enforcement")
    func continuousOutputStillCancels() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("flood.pid")
        let script = try makeExecutableScript(
            in: directory,
            named: "continuous-output",
            contents: """
            #!/bin/sh
            printf '%s' "$$" > "$1"
            exec /usr/bin/yes flood
            """
        )
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 5,
                terminationGracePeriodSeconds: 0.2,
                maximumRetainedBytesPerStream: 8 * 1_024
            )
        )
        let task = Task {
            try await runner.run(
                DBCloudHelperCommand(
                    executable: script.path,
                    arguments: [pidFile.path],
                    redactedArguments: [:]
                )
            )
        }
        try await waitForFile(pidFile)
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected helper cancellation")
        } catch is CancellationError {
            // Expected after the flood process has been terminated and reaped.
        }

        let pid = try processID(from: pidFile)
        #expect(!processExists(pid))
    }

    @Test("task cancellation terminates the child and removes credential artifacts")
    func cancellationTerminatesChildAndRemovesCredentials() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentialRoot = directory.appendingPathComponent("credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: credentialRoot, withIntermediateDirectories: false)
        let pidFile = directory.appendingPathComponent("cancel.pid")
        let passfilePathFile = directory.appendingPathComponent("passfile-path")
        let script = try makeExecutableScript(
            in: directory,
            named: "cancel-helper",
            contents: """
            #!/bin/sh
            printf '%s' "$$" > "$1"
            printf '%s' "$PGPASSFILE" > "$2"
            exec /bin/sleep 30
            """
        )
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 5,
                terminationGracePeriodSeconds: 0.2,
                maximumRetainedBytesPerStream: 8 * 1_024,
                credentialTemporaryDirectory: credentialRoot
            )
        )
        let command = DBCloudHelperCommand(
            executable: script.path,
            arguments: [pidFile.path, passfilePathFile.path],
            redactedArguments: [:],
            credentialMaterial: .postgreSQLPassfile(Data("host:5432:db:user:secret\n".utf8))
        )

        let task = Task { try await runner.run(command) }
        try await waitForFile(pidFile)
        try await waitForFile(passfilePathFile)
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected after the runner has terminated and reaped the child.
        }

        let pid = try processID(from: pidFile)
        let passfilePath = try String(contentsOf: passfilePathFile, encoding: .utf8)
        #expect(!processExists(pid))
        #expect(!FileManager.default.fileExists(atPath: passfilePath))
        #expect(try FileManager.default.contentsOfDirectory(atPath: credentialRoot.path).isEmpty)
    }

    @Test("launch failure removes credential artifacts")
    func launchFailureRemovesCredentials() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentialRoot = directory.appendingPathComponent("credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: credentialRoot, withIntermediateDirectories: false)
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 1,
                credentialTemporaryDirectory: credentialRoot
            )
        )

        do {
            _ = try await runner.run(
                DBCloudHelperCommand(
                    executable: directory.appendingPathComponent("missing").path,
                    arguments: [],
                    redactedArguments: [:],
                    credentialMaterial: .postgreSQLPassfile(Data("host:5432:db:user:secret\n".utf8))
                )
            )
            Issue.record("Expected launch failure")
        } catch {
            #expect(!(error is CancellationError))
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: credentialRoot.path).isEmpty)
    }

    @Test("nonzero child exit removes credential artifacts")
    func nonzeroExitRemovesCredentials() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentialRoot = directory.appendingPathComponent("credentials", isDirectory: true)
        try FileManager.default.createDirectory(at: credentialRoot, withIntermediateDirectories: false)
        let passfilePathFile = directory.appendingPathComponent("nonzero-passfile-path")
        let script = try makeExecutableScript(
            in: directory,
            named: "nonzero-helper",
            contents: """
            #!/bin/sh
            printf '%s' "$PGPASSFILE" > "$1"
            exit 7
            """
        )
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 2,
                credentialTemporaryDirectory: credentialRoot
            )
        )

        let result = try await runner.run(
            DBCloudHelperCommand(
                executable: script.path,
                arguments: [passfilePathFile.path],
                redactedArguments: [:],
                credentialMaterial: .postgreSQLPassfile(Data("host:5432:db:user:secret\n".utf8))
            )
        )
        let passfilePath = try String(contentsOf: passfilePathFile, encoding: .utf8)

        #expect(result.exitCode == 7)
        #expect(!FileManager.default.fileExists(atPath: passfilePath))
        #expect(try FileManager.default.contentsOfDirectory(atPath: credentialRoot.path).isEmpty)
    }

    @Test("child closing stdin cannot signal or hang the parent")
    func closedChildStandardInputFailsSafely() async throws {
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 2,
                terminationGracePeriodSeconds: 0.2,
                maximumRetainedBytesPerStream: 8 * 1_024
            )
        )
        let input = Data(repeating: 0x78, count: 1 * 1_024 * 1_024)

        do {
            _ = try await runner.run(
                DBCloudHelperCommand(
                    executable: "/usr/bin/true",
                    arguments: [],
                    redactedArguments: [:],
                    standardInput: input
                )
            )
            Issue.record("Expected an incomplete stdin write")
        } catch let error as DBCloudHelperExecutionError {
            #expect(error == .standardInputWriteFailed)
        }
    }

    @Test("local runner keeps the main actor responsive")
    @MainActor
    func localRunnerKeepsMainActorResponsive() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedFile = directory.appendingPathComponent("started")
        let releaseFile = directory.appendingPathComponent("release")
        let script = try makeExecutableScript(
            in: directory,
            named: "main-actor-handshake",
            contents: """
            #!/bin/sh
            : > "$1"
            while [ ! -e "$2" ]; do
                /bin/sleep 0.01
            done
            printf 'completed'
            """
        )
        let runner = LocalDBCloudHelperRunner(
            configuration: DBCloudHelperRunnerConfiguration(
                timeoutSeconds: 2,
                terminationGracePeriodSeconds: 0.2,
                maximumRetainedBytesPerStream: 8 * 1_024
            )
        )

        let task = Task { @MainActor in
            try await runner.run(
                DBCloudHelperCommand(
                    executable: script.path,
                    arguments: [startedFile.path, releaseFile.path],
                    redactedArguments: [:]
                )
            )
        }
        try await waitForFile(startedFile)
        try Data().write(to: releaseFile, options: .atomic)

        let result = try await task.value
        #expect(result.stdout == "completed")
        #expect(result.exitCode == 0)
    }

    @Test("view model runs selected sqlite query asynchronously")
    @MainActor
    func viewModelRunsSelectedSQLiteQueryOnExplicitRequest() async throws {
        let recorder = DBCloudHelperCommandRecorder()
        let manifests = try bundledHelperManifests()
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { command in
                recorder.append(command)
                return DBCloudHelperRunResult(
                    exitCode: 0,
                    stdout: "answer\n1\n",
                    stderr: "",
                    stdoutTruncated: true
                )
            }
        )

        viewModel.selectedHelperID = "cocxy-db-sqlite"
        viewModel.sqliteDatabasePath = "/tmp/cocxy-cc2-smoke.sqlite"
        viewModel.sqlText = "select 1 as answer"

        let task = try #require(viewModel.runSelectedAction())
        #expect(viewModel.isRunning)
        await task.value

        let commands = recorder.commands
        #expect(commands.count == 1)
        #expect(commands[0].executable == "sqlite3")
        #expect(commands[0].arguments == ["/tmp/cocxy-cc2-smoke.sqlite"])
        #expect(String(decoding: try #require(commands[0].standardInput), as: UTF8.self) == "select 1 as answer")
        #expect(viewModel.outputText == "answer\n1\n")
        #expect(viewModel.outputWasTruncated)
        #expect(viewModel.statusText == "SQLite query finished.")
        #expect(!viewModel.isRunning)
    }

    @Test("view model exposes and completes cancellation state")
    @MainActor
    func viewModelExposesCancellationState() async throws {
        let manifests = try bundledHelperManifests()
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { _ in
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return DBCloudHelperRunResult(exitCode: 0, stdout: "", stderr: "")
            }
        )
        viewModel.selectedHelperID = "cocxy-db-sqlite"
        viewModel.sqliteDatabasePath = "/tmp/cocxy.sqlite"

        let task = try #require(viewModel.runSelectedAction())
        #expect(viewModel.isRunning)
        viewModel.cancelRunningAction()
        #expect(viewModel.isCancelling)
        await task.value

        #expect(!viewModel.isRunning)
        #expect(!viewModel.isCancelling)
        #expect(viewModel.statusText == "Cancelled")
    }

    @Test("switching to cloud selects AWS helper and builds S3 command")
    @MainActor
    func switchingToCloudSelectsAWSHelperAndBuildsS3Command() async throws {
        let recorder = DBCloudHelperCommandRecorder()
        let manifests = try bundledHelperManifests()
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { command in
                recorder.append(command)
                return DBCloudHelperRunResult(exitCode: 0, stdout: "{\"Buckets\":[]}\n", stderr: "")
            }
        )

        viewModel.selectedKind = .cloud
        viewModel.awsProfile = "dev"
        viewModel.awsRegion = "us-east-1"

        #expect(viewModel.selectedHelperID == "cocxy-aws-cli-helper")
        #expect(viewModel.commandPreview == "aws s3api list-buckets --output json --profile dev --region us-east-1")

        let task = try #require(viewModel.runSelectedAction())
        await task.value

        let commands = recorder.commands
        #expect(commands.count == 1)
        #expect(commands[0].executable == "aws")
        #expect(commands[0].arguments == [
            "s3api", "list-buckets", "--output", "json",
            "--profile", "dev", "--region", "us-east-1",
        ])
        #expect(viewModel.outputText == "{\"Buckets\":[]}\n")
        #expect(viewModel.statusText == "S3 bucket listing finished.")
    }

    @Test("Spanish localizer updates DB and cloud helper statuses")
    @MainActor
    func spanishLocalizerUpdatesDBCloudHelperStatuses() async throws {
        let manifests = try bundledHelperManifests()
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = DBCloudHelperPanelViewModel(
            manifestProvider: { manifests },
            runner: { _ in DBCloudHelperRunResult(exitCode: 0, stdout: "ok\n", stderr: "") },
            localizer: spanish
        )

        #expect(DBCloudHelperKind.database.localizedTitle(using: spanish) == "Base de datos")
        #expect(DBCloudHelperKind.cloud.localizedTitle(using: spanish) == "Nube")
        #expect(viewModel.statusText == "10 ayudantes cargados.")
        #expect(
            viewModel.selectedDescriptor.map { viewModel.localizedDescription(for: $0) }
                == "Agrega comprobaciones locales de SQLite CLI y comandos auxiliares."
        )

        viewModel.selectedHelperID = "cocxy-db-sqlite"
        viewModel.sqliteDatabasePath = "/tmp/cocxy.sqlite"
        viewModel.sqlText = "select 1"

        let task = try #require(viewModel.runSelectedAction())
        #expect(viewModel.statusText == "Ejecutando consulta SQLite...")
        await task.value
        #expect(viewModel.statusText == "Consulta SQLite finalizada.")

        viewModel.recordFailure(
            DBCloudHelperError.queryTooLarge(
                limitBytes: DBCloudHelperCommand.maximumStandardInputBytes
            )
        )
        #expect(viewModel.outputText.hasPrefix("La consulta supera el límite de entrada de "))

        viewModel.recordFailure(DBCloudHelperExecutionError.timedOut(seconds: 2.5))
        #expect(viewModel.statusText == "Tiempo de espera agotado")
        #expect(viewModel.outputText == "El ayudante agotó el tiempo de espera después de 2.5 segundos.")

        viewModel.updateLocalizer(AppLocalizer(languagePreference: .english, bundle: bundle))
        #expect(viewModel.statusText == "Timed out")
        #expect(viewModel.outputText == "The helper timed out after 2.5 seconds.")
    }
}

private final class DBCloudHelperCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DBCloudHelperCommand] = []

    var commands: [DBCloudHelperCommand] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ command: DBCloudHelperCommand) {
        lock.lock()
        storage.append(command)
        lock.unlock()
    }
}

private enum DBCloudHelperTestError: Error {
    case fileDidNotAppear(URL)
    case invalidProcessID
}

private func bundledHelperManifests() throws -> [PluginManifest] {
    try BundledPluginCatalog(
        pluginsDirectory: repositoryRoot().appendingPathComponent("Resources/Plugins", isDirectory: true)
    ).loadManifests()
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "cocxy-dbcloud-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return directory
}

private func makeExecutableScript(
    in directory: URL,
    named name: String,
    contents: String
) throws -> URL {
    let script = directory.appendingPathComponent(name, isDirectory: false)
    try contents.write(to: script, atomically: true, encoding: .utf8)
    guard chmod(script.path, 0o700) == 0 else {
        throw CocoaError(.fileWriteNoPermission)
    }
    return script
}

private func longRunningScript(in directory: URL) throws -> URL {
    try makeExecutableScript(
        in: directory,
        named: "long-running",
        contents: """
        #!/bin/sh
        printf '%s' "$$" > "$1"
        exec /bin/sleep 30
        """
    )
}

private func waitForFile(_ url: URL) async throws {
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw DBCloudHelperTestError.fileDidNotAppear(url)
}

private func processID(from file: URL) throws -> pid_t {
    let raw = try String(contentsOf: file, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let pid = pid_t(raw), pid > 0 else {
        throw DBCloudHelperTestError.invalidProcessID
    }
    return pid
}

private func processExists(_ pid: pid_t) -> Bool {
    errno = 0
    if Darwin.kill(pid, 0) == 0 { return true }
    return errno != ESRCH
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
