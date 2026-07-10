// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DBCloudHelperPanelViewModel.swift - Local DB/cloud helper panel state.

import Foundation

typealias DBCloudHelperManifestProvider = () throws -> [PluginManifest]
typealias DBCloudHelperRunner = @Sendable (DBCloudHelperCommand) async throws -> DBCloudHelperRunResult

@MainActor
final class DBCloudHelperPanelViewModel: ObservableObject {
    private enum Operation: Equatable {
        case postgresQuery
        case sqliteQuery
        case s3ListBuckets

        init(_ action: DBCloudHelperAction) {
            switch action {
            case .postgresQuery: self = .postgresQuery
            case .sqliteQuery: self = .sqliteQuery
            case .s3ListBuckets: self = .s3ListBuckets
            }
        }
    }

    private enum StatusState: Equatable {
        case ready
        case loaded(Int)
        case loadFailed(String)
        case running(Operation)
        case cancelling
        case cancelled
        case timedOut
        case action(Operation, Bool)
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
    @Published private(set) var outputWasTruncated = false
    @Published private(set) var isRunning = false
    @Published private(set) var isCancelling = false

    private let manifestProvider: DBCloudHelperManifestProvider
    private let runner: DBCloudHelperRunner
    private let commandBuilder: DBCloudHelperCommandBuilder
    private var localizer: AppLocalizer
    private var statusState: StatusState = .ready
    private var currentError: Error?
    private var runTask: Task<Void, Never>?

    init(
        manifestProvider: @escaping DBCloudHelperManifestProvider = {
            try BundledPluginCatalog().loadManifests()
        },
        runner: @escaping DBCloudHelperRunner = { command in
            try await LocalDBCloudHelperRunner().run(command)
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

    deinit {
        runTask?.cancel()
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

    func localizedDescription(for descriptor: DBCloudHelperDescriptor) -> String {
        localizer.string("dbCloud.helper.\(descriptor.id).description", fallback: descriptor.description)
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
        guard !isRunning else { return }
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
        guard !isRunning else { return }
        selectedKind = descriptor.kind
        selectedHelperID = descriptor.id
    }

    @discardableResult
    func runSelectedAction() -> Task<Void, Never>? {
        if let runTask { return runTask }

        let action: DBCloudHelperAction
        let command: DBCloudHelperCommand
        do {
            action = try makeAction()
            command = try commandBuilder.command(for: action)
        } catch {
            recordFailure(error)
            return nil
        }

        let operation = Operation(action)
        let runner = self.runner
        isRunning = true
        isCancelling = false
        outputText = ""
        outputWasTruncated = false
        currentError = nil
        setStatus(.running(operation))

        let task = Task { @MainActor [weak self] in
            do {
                let result = try await runner(command)
                guard let self else { return }
                if Task.isCancelled {
                    self.finishCancelled()
                } else {
                    self.finish(result, operation: operation)
                }
            } catch is CancellationError {
                self?.finishCancelled()
            } catch {
                self?.finishFailure(error)
            }
        }
        runTask = task
        return task
    }

    func cancelRunningAction() {
        guard let runTask, isRunning else { return }
        isCancelling = true
        setStatus(.cancelling)
        runTask.cancel()
    }

    func recordFailure(_ error: Error) {
        currentError = error
        outputText = Self.localizedErrorDescription(error, localizer: localizer)
        outputWasTruncated = false
        isRunning = false
        isCancelling = false
        if case DBCloudHelperExecutionError.timedOut = error {
            setStatus(.timedOut)
        } else {
            setStatus(.actionFailed)
        }
    }

    private func finish(_ result: DBCloudHelperRunResult, operation: Operation) {
        outputText = Self.joinedOutput(stdout: result.stdout, stderr: result.stderr)
        outputWasTruncated = result.outputWasTruncated
        currentError = nil
        isRunning = false
        isCancelling = false
        runTask = nil
        setStatus(.action(operation, result.succeeded))
    }

    private func finishFailure(_ error: Error) {
        runTask = nil
        recordFailure(error)
    }

    private func finishCancelled() {
        currentError = nil
        outputText = ""
        outputWasTruncated = false
        isRunning = false
        isCancelling = false
        runTask = nil
        setStatus(.cancelled)
    }

    private func makeCommand() throws -> DBCloudHelperCommand {
        try commandBuilder.command(for: makeAction())
    }

    private func selectDefaultHelperForSelectedKind() {
        guard !isRunning, selectedDescriptor?.kind != selectedKind else { return }
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

    private static func joinedOutput(stdout: String, stderr: String) -> String {
        guard !stdout.isEmpty else { return stderr }
        guard !stderr.isEmpty else { return stdout }
        return stdout.hasSuffix("\n") ? stdout + stderr : stdout + "\n" + stderr
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
        case .running:
            return localizer.string("agent.panel.status.running", fallback: "Running...")
        case .cancelling:
            return localizer.string("common.cancel", fallback: "Cancel") + "..."
        case .cancelled:
            return localizer.string("github.pane.check.conclusion.cancelled", fallback: "Cancelled")
        case .timedOut:
            return localizer.string("github.pane.check.conclusion.timedOut", fallback: "Timed out")
        case .action(let operation, let succeeded):
            return localizedActionStatus(operation, succeeded: succeeded, localizer: localizer)
        case .actionFailed:
            return localizer.string("dbCloud.status.actionFailed", fallback: "Helper action failed.")
        }
    }

    private static func localizedActionStatus(
        _ operation: Operation,
        succeeded: Bool,
        localizer: AppLocalizer
    ) -> String {
        let keySuffix = succeeded ? "finished" : "failed"
        switch operation {
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
            case .queryTooLarge(let limitBytes):
                let size = ByteCountFormatter.string(fromByteCount: Int64(limitBytes), countStyle: .file)
                return localizer.string(
                    "dbCloud.error.queryTooLarge",
                    fallback: "The query exceeds the \(size) input limit."
                )
            case .invalidPostgreSQLDatabaseTarget:
                return localizer.string(
                    "dbCloud.error.invalidPostgresTarget",
                    fallback: "Enter a valid PostgreSQL URL or service name."
                )
            case .unsupportedPostgreSQLCredentialFormat:
                return localizer.string(
                    "dbCloud.error.unsupportedPostgresCredential",
                    fallback: "Use a PostgreSQL URL for password-protected connections."
                )
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
