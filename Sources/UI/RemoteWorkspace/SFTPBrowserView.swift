// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPBrowserView.swift - Remote file browser via SFTP.

import AppKit
import SwiftUI

private enum SFTPDirectoryLoadResult: Sendable {
    case success([RemoteFileEntry])
    case failure(SFTPBrowserFailure)
}

private enum SFTPOperationResult: Sendable {
    case success
    case successWithWarning(SFTPBrowserFailure)
    case failure(SFTPBrowserFailure)
}

private enum SFTPRemoteReviewResult: Sendable {
    case success(SFTPReviewedRemoteEntry)
    case failure(SFTPBrowserFailure)
}

enum SFTPBrowserOperation: Sendable {
    case listing
    case download
    case upload
    case createDirectory
    case remove
}

private enum SFTPBrowserFailure: Sendable {
    case client(SFTPClientError, operation: SFTPBrowserOperation)
    case unsafeDownloadName
    case invalidFolderName
    case downloadPublishedWithIssues(SFTPDownloadRecoveryState)
    case uploadNotCommittedWithIssues(SFTPUploadRecoveryState)
    case uploadCommittedWithIssues(SFTPUploadRecoveryState)
    case uploadCommitIndeterminate(SFTPUploadRecoveryState)
    case mutationNotCommittedWithIssues(SFTPRemoteMutationRecoveryState)
    case mutationCommittedWithIssues(SFTPRemoteMutationRecoveryState)
    case mutationCommitIndeterminate(SFTPRemoteMutationRecoveryState)
    case unexpected

    init(_ error: any Error, operation: SFTPBrowserOperation) {
        if let clientError = error as? SFTPClientError {
            self = .client(clientError, operation: operation)
        } else {
            self = .unexpected
        }
    }
}

struct SFTPReviewedLocalUpload: Sendable, Equatable {
    let localURL: URL
    let identity: SFTPLocalFileIdentity
}

private struct SFTPPendingUploadReplacement {
    let reviewedUpload: SFTPReviewedLocalUpload
    let remoteReview: SFTPReviewedRemoteEntry
}

private struct SFTPBrowserMutationSnapshot {
    let revision: UInt
    let isRunning: Bool
    let pendingResults: [SFTPOperationResult]
    let shouldRefresh: Bool
}

@MainActor
private final class SFTPBrowserMutationObserver {
    weak var viewModel: SFTPBrowserViewModel?

    init(viewModel: SFTPBrowserViewModel) {
        self.viewModel = viewModel
    }
}

@MainActor
private final class SFTPBrowserMutationCoordinator {
    private var snapshot = SFTPBrowserMutationSnapshot(
        revision: 0,
        isRunning: false,
        pendingResults: [],
        shouldRefresh: false
    )
    private var task: Task<Void, Never>?
    private var observers: [ObjectIdentifier: SFTPBrowserMutationObserver] = [:]

    var isRunning: Bool { snapshot.isRunning }

    func observe(_ viewModel: SFTPBrowserViewModel) {
        observers[ObjectIdentifier(viewModel)] = SFTPBrowserMutationObserver(
            viewModel: viewModel
        )
        viewModel.applyMutationSnapshot(snapshot)
    }

    @discardableResult
    func start(
        _ operation: @escaping @Sendable () -> SFTPOperationResult
    ) -> Bool {
        guard task == nil else { return false }
        publish(
            isRunning: true,
            pendingResults: snapshot.pendingResults,
            shouldRefresh: false
        )
        let worker = Task.detached(priority: .userInitiated) { operation() }
        task = Task { [weak self] in
            let result = await worker.value
            guard let self else { return }
            self.task = nil
            var pendingResults = self.snapshot.pendingResults
            let shouldRefresh: Bool
            switch result {
            case .success:
                shouldRefresh = true
            case .successWithWarning:
                pendingResults.append(result)
                shouldRefresh = true
            case .failure:
                pendingResults.append(result)
                shouldRefresh = false
            }
            self.publish(
                isRunning: false,
                pendingResults: pendingResults,
                shouldRefresh: shouldRefresh
            )
        }
        return true
    }

    func dismissResult() {
        guard !snapshot.pendingResults.isEmpty else { return }
        var pendingResults = snapshot.pendingResults
        pendingResults.removeFirst()
        publish(
            isRunning: snapshot.isRunning,
            pendingResults: pendingResults,
            shouldRefresh: false
        )
    }

    private func publish(
        isRunning: Bool,
        pendingResults: [SFTPOperationResult],
        shouldRefresh: Bool
    ) {
        snapshot = SFTPBrowserMutationSnapshot(
            revision: snapshot.revision &+ 1,
            isRunning: isRunning,
            pendingResults: pendingResults,
            shouldRefresh: shouldRefresh
        )
        observers = observers.filter { $0.value.viewModel != nil }
        for observer in observers.values {
            observer.viewModel?.applyMutationSnapshot(snapshot)
        }
    }
}

@MainActor
private enum SFTPBrowserMutationRegistry {
    private static var coordinators: [
        SFTPConnectionScope: SFTPBrowserMutationCoordinator
    ] = [:]

    static func coordinator(
        for scope: SFTPConnectionScope
    ) -> SFTPBrowserMutationCoordinator {
        coordinators = coordinators.filter { key, coordinator in
            key == scope || key.profileID != scope.profileID || coordinator.isRunning
        }
        if let coordinator = coordinators[scope] {
            return coordinator
        }
        let coordinator = SFTPBrowserMutationCoordinator()
        coordinators[scope] = coordinator
        return coordinator
    }
}

// MARK: - SFTP Browser View Model

@MainActor
final class SFTPBrowserViewModel: ObservableObject {
    @Published private(set) var currentPath: String = "."
    @Published private(set) var entries: [RemoteFileEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var downloadingEntryIDs: Set<String> = []
    @Published private(set) var isMutating = false
    @Published private var listingFailure: SFTPBrowserFailure?
    @Published private var operationFailure: SFTPBrowserFailure?
    @Published private var mutationFailure: SFTPBrowserFailure?
    @Published private var transientRecoveryFailures: [SFTPBrowserFailure] = []

    private let sftpClient: SFTPClient
    private let mutationCoordinator: SFTPBrowserMutationCoordinator
    private let downloadsDirectory: URL
    private let fileManager: FileManager
    private var localizer: AppLocalizer
    private var directoryRequestID = UUID()
    private var directoryTask: Task<Void, Never>?
    private var operationTasks: [String: Task<Void, Never>] = [:]
    private var lastMutationRevision: UInt?
    private var operationGeneration: UInt = 0
    private var hasStarted = false

    init(
        sftpClient: SFTPClient,
        downloadsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true),
        fileManager: FileManager = .default,
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    ) {
        self.sftpClient = sftpClient
        self.mutationCoordinator = SFTPBrowserMutationRegistry.coordinator(
            for: sftpClient.connectionScope
        )
        self.downloadsDirectory = downloadsDirectory
        self.fileManager = fileManager
        self.localizer = localizer
        self.mutationCoordinator.observe(self)
    }

    var listingErrorMessage: String? {
        listingFailure.map(message(for:))
    }

    var operationErrorMessage: String? {
        activeOperationFailure.map(message(for:))
    }

    var operationRecoveryPath: String? {
        guard let activeOperationFailure else { return nil }
        switch activeOperationFailure {
        case .uploadNotCommittedWithIssues(let state),
             .uploadCommittedWithIssues(let state),
             .uploadCommitIndeterminate(let state):
            return state.remoteBackupPath ?? state.stagedPayloadPath
        case .mutationNotCommittedWithIssues(let state),
             .mutationCommittedWithIssues(let state),
             .mutationCommitIndeterminate(let state):
            return state.recoveryPath
        default:
            return nil
        }
    }

    var operationLocalRecoveryURL: URL? {
        guard let activeOperationFailure else { return nil }
        switch activeOperationFailure {
        case .downloadPublishedWithIssues(let state):
            return state.stagingDirectoryURL ?? state.destinationURL
        case .uploadNotCommittedWithIssues(let state),
             .uploadCommittedWithIssues(let state),
             .uploadCommitIndeterminate(let state):
            return state.localSnapshotURL
        default:
            return nil
        }
    }

    private var activeOperationFailure: SFTPBrowserFailure? {
        operationFailure ?? mutationFailure ?? transientRecoveryFailures.first
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        loadDirectory()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        if listingFailure != nil || activeOperationFailure != nil {
            objectWillChange.send()
        }
        self.localizer = localizer
    }

    func loadDirectory(at path: String? = nil) {
        let targetPath = path ?? currentPath
        let requestID = UUID()
        directoryRequestID = requestID
        isLoading = true
        listingFailure = nil
        directoryTask?.cancel()
        let client = sftpClient
        let worker = Task.detached(priority: .userInitiated) {
            do {
                return SFTPDirectoryLoadResult.success(
                    try client.listDirectory(path: targetPath)
                )
            } catch {
                return SFTPDirectoryLoadResult.failure(
                    SFTPBrowserFailure(error, operation: .listing)
                )
            }
        }
        directoryTask = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.directoryRequestID == requestID else { return }
            self.directoryTask = nil
            switch result {
            case .success(let values):
                self.entries = self.sortEntries(values)
                self.currentPath = targetPath
            case .failure(let failure):
                self.entries = []
                self.listingFailure = failure
            }
            self.isLoading = false
        }
    }

    func navigateToDirectory(_ entry: RemoteFileEntry) {
        guard entry.isDirectory, !entry.isSymbolicLink else { return }
        loadDirectory(at: entry.id)
    }

    func navigateUp() {
        let parent = Self.parentPath(of: currentPath)
        guard parent != currentPath else { return }
        loadDirectory(at: parent)
    }

    func refresh() {
        loadDirectory()
    }

    func downloadFile(_ entry: RemoteFileEntry) {
        guard !isMutating,
              entry.isRegularFile,
              !downloadingEntryIDs.contains(entry.id) else { return }
        operationFailure = nil
        guard RemoteFileEntry.isSafePathComponent(entry.name) else {
            operationFailure = .unsafeDownloadName
            return
        }
        let destination: URL
        do {
            destination = try downloadDestination(for: entry.name)
        } catch {
            operationFailure = SFTPBrowserFailure(error, operation: .download)
            return
        }

        downloadingEntryIDs.insert(entry.id)
        let client = sftpClient
        startTransientOperation(id: "download:\(entry.id)") {
            do {
                switch try client.download(entry: entry, to: destination) {
                case .completed:
                    return SFTPOperationResult.success
                case .publishedWithIssues(let state):
                    return SFTPOperationResult.successWithWarning(
                        .downloadPublishedWithIssues(state)
                    )
                }
            } catch {
                return SFTPOperationResult.failure(
                    SFTPBrowserFailure(error, operation: .download)
                )
            }
        } completion: { [weak self] result in
            self?.downloadingEntryIDs.remove(entry.id)
            switch result {
            case .success:
                break
            case .successWithWarning(let failure):
                self?.transientRecoveryFailures.append(failure)
            case .failure(let failure):
                self?.operationFailure = failure
            }
        }
    }

    func reviewUploadFile(at localURL: URL) -> SFTPReviewedLocalUpload? {
        guard !isMutating, downloadingEntryIDs.isEmpty else { return nil }
        guard localURL.isFileURL,
              RemoteFileEntry.isSafePathComponent(localURL.lastPathComponent) else {
            operationFailure = .client(.unsafeLocalSource, operation: .upload)
            return nil
        }
        do {
            let identity = try SFTPLocalFileIdentity.capture(path: localURL.path)
            operationFailure = nil
            return SFTPReviewedLocalUpload(localURL: localURL, identity: identity)
        } catch {
            operationFailure = .client(.unsafeLocalSource, operation: .upload)
            return nil
        }
    }

    func prepareRemoteReview(
        _ entry: RemoteFileEntry,
        operation: SFTPBrowserOperation = .remove,
        completion: @escaping @MainActor (SFTPReviewedRemoteEntry) -> Void
    ) {
        guard !isMutating, downloadingEntryIDs.isEmpty else { return }
        let operationID = "review:\(entry.id)"
        guard operationTasks[operationID] == nil else { return }
        operationFailure = nil
        isMutating = true
        let generation = operationGeneration
        let client = sftpClient
        let worker = Task.detached(priority: .userInitiated) {
            do {
                return SFTPRemoteReviewResult.success(
                    try client.prepareReview(entry: entry)
                )
            } catch {
                return SFTPRemoteReviewResult.failure(
                    SFTPBrowserFailure(error, operation: operation)
                )
            }
        }
        operationTasks[operationID] = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.operationGeneration == generation else { return }
            self.operationTasks.removeValue(forKey: operationID)
            self.isMutating = false
            switch result {
            case .success(let review):
                completion(review)
            case .failure(let failure):
                self.operationFailure = failure
            }
        }
    }

    func uploadFile(
        _ reviewedUpload: SFTPReviewedLocalUpload,
        replacing remoteReview: SFTPReviewedRemoteEntry? = nil
    ) {
        guard !isMutating, downloadingEntryIDs.isEmpty else { return }
        let localURL = reviewedUpload.localURL
        guard localURL.isFileURL,
              RemoteFileEntry.isSafePathComponent(localURL.lastPathComponent) else {
            operationFailure = .client(.unsafeLocalSource, operation: .upload)
            return
        }
        if remoteReview == nil, hasEntry(named: localURL.lastPathComponent) {
            operationFailure = .client(.remoteDestinationExists, operation: .upload)
            return
        }
        if let expectedEntry = remoteReview?.entry,
           expectedEntry.name != localURL.lastPathComponent || !expectedEntry.isRegularFile {
            operationFailure = .client(.unsafeRemoteDestination, operation: .upload)
            return
        }
        let remotePath: String
        do {
            remotePath = try SFTPClient.appendingRemotePath(
                localURL.lastPathComponent,
                to: currentPath
            )
        } catch {
            operationFailure = SFTPBrowserFailure(error, operation: .upload)
            return
        }
        operationFailure = nil
        let client = sftpClient
        startMutation {
            do {
                let outcome = try client.upload(
                    localPath: localURL.path,
                    remotePath: remotePath,
                    expectedLocalIdentity: reviewedUpload.identity,
                    destinationPolicy: remoteReview.map(SFTPUploadDestinationPolicy.replace)
                        ?? .create
                )
                switch outcome {
                case .completed:
                    return SFTPOperationResult.success
                case .notCommittedWithIssues(let state):
                    return SFTPOperationResult.successWithWarning(
                        .uploadNotCommittedWithIssues(state)
                    )
                case .committedWithIssues(let state):
                    return SFTPOperationResult.successWithWarning(
                        .uploadCommittedWithIssues(state)
                    )
                case .commitIndeterminate(let state):
                    return SFTPOperationResult.successWithWarning(
                        .uploadCommitIndeterminate(state)
                    )
                }
            } catch {
                return SFTPOperationResult.failure(
                    SFTPBrowserFailure(error, operation: .upload)
                )
            }
        }
    }

    func createDirectory(named name: String) {
        guard !isMutating, downloadingEntryIDs.isEmpty else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let remotePath: String
        do {
            remotePath = try SFTPClient.appendingRemotePath(trimmedName, to: currentPath)
        } catch {
            operationFailure = .invalidFolderName
            return
        }
        operationFailure = nil
        let client = sftpClient
        startMutation {
            do {
                return Self.operationResult(
                    try client.mkdir(path: remotePath)
                )
            } catch {
                return SFTPOperationResult.failure(
                    SFTPBrowserFailure(error, operation: .createDirectory)
                )
            }
        }
    }

    func removeEntry(_ review: SFTPReviewedRemoteEntry) {
        guard !isMutating, downloadingEntryIDs.isEmpty else { return }
        operationFailure = nil
        let client = sftpClient
        startMutation {
            do {
                return Self.operationResult(
                    try client.remove(reviewedEntry: review)
                )
            } catch {
                return SFTPOperationResult.failure(
                    SFTPBrowserFailure(error, operation: .remove)
                )
            }
        }
    }

    func isDownloading(_ entry: RemoteFileEntry) -> Bool {
        downloadingEntryIDs.contains(entry.id)
    }

    func hasEntry(named name: String) -> Bool {
        entry(named: name) != nil
    }

    func entry(named name: String) -> RemoteFileEntry? {
        entries.first { $0.name == name }
    }

    func dismissListingError() {
        listingFailure = nil
    }

    func dismissOperationError() {
        if operationFailure != nil {
            operationFailure = nil
        } else if mutationFailure != nil {
            mutationCoordinator.dismissResult()
        } else if !transientRecoveryFailures.isEmpty {
            transientRecoveryFailures.removeFirst()
        }
    }

    func revealLocalRecoveryItem() {
        guard let localURL = operationLocalRecoveryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([localURL])
    }

    func inspectRemoteRecoveryPath() {
        guard let recoveryPath = operationRecoveryPath else { return }
        loadDirectory(at: Self.parentPath(of: recoveryPath))
    }

    func cancelPendingWork() {
        hasStarted = false
        directoryRequestID = UUID()
        directoryTask?.cancel()
        directoryTask = nil
        operationGeneration &+= 1
        for task in operationTasks.values { task.cancel() }
        operationTasks.removeAll()
        isLoading = false
        isMutating = mutationCoordinator.isRunning
        downloadingEntryIDs.removeAll()
    }

    nonisolated static func parentPath(of path: String) -> String {
        var components = path.split(separator: "/", omittingEmptySubsequences: true)
        if path.hasPrefix("/") {
            guard components.count > 1 else { return "/" }
            return "/" + components.dropLast().joined(separator: "/")
        }
        while components.first == "." { components.removeFirst() }
        guard components.count > 1 else { return "." }
        let parent = components.dropLast().joined(separator: "/")
        return path.hasPrefix("./") ? "./\(parent)" : parent
    }

    private func sortEntries(_ values: [RemoteFileEntry]) -> [RemoteFileEntry] {
        values.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func operationResult(
        _ outcome: SFTPRemoteMutationOutcome
    ) -> SFTPOperationResult {
        switch outcome {
        case .completed:
            return .success
        case .notCommittedWithIssues(let state):
            return .successWithWarning(.mutationNotCommittedWithIssues(state))
        case .committedWithIssues(let state):
            return .successWithWarning(.mutationCommittedWithIssues(state))
        case .commitIndeterminate(let state):
            return .successWithWarning(.mutationCommitIndeterminate(state))
        }
    }

    private func downloadDestination(for filename: String) throws -> URL {
        let root = downloadsDirectory.standardizedFileURL
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let candidate = root.appendingPathComponent(filename).standardizedFileURL
        guard candidate != root,
              candidate.deletingLastPathComponent() == root else {
            throw SFTPClientError.unsafeLocalDestination
        }
        return candidate
    }

    private func message(for failure: SFTPBrowserFailure) -> String {
        switch failure {
        case .client(let error, let operation):
            return message(for: error, operation: operation)
        case .unsafeDownloadName:
            return localizer.string(
                "remoteWorkspace.sftp.download.unsafeName",
                fallback: "The remote file name cannot be downloaded safely."
            )
        case .invalidFolderName:
            return localizer.string(
                "remoteWorkspace.sftp.mkdir.invalidName",
                fallback: "Enter a valid folder name."
            )
        case .downloadPublishedWithIssues(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.download.publishedWithIssues",
                    fallback: "The file was saved to %@, but final verification or cleanup at %@ could not be confirmed. Inspect it before downloading again."
                ),
                state.destinationURL.path,
                state.stagingDirectoryURL?.path ?? state.destinationURL.path
            )
        case .uploadNotCommittedWithIssues(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.upload.notCommittedRecovery",
                    fallback: "The upload did not replace %@, but cleanup of %@ could not be confirmed. Inspect the recovery item before retrying."
                ),
                state.destinationPath,
                uploadRecoveryDescription(state)
            )
        case .uploadCommittedWithIssues(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.upload.cleanupUnconfirmed",
                    fallback: "The upload to %@ completed, but cleanup of %@ could not be confirmed. Inspect the recovery item before retrying."
                ),
                state.destinationPath,
                uploadRecoveryDescription(state)
            )
        case .uploadCommitIndeterminate(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.upload.commitIndeterminate",
                    fallback: "The upload result for %@ is uncertain. Inspect %@ and refresh before retrying."
                ),
                state.destinationPath,
                uploadRecoveryDescription(state)
            )
        case .mutationNotCommittedWithIssues(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.mutation.notCommittedRecovery",
                    fallback: "The remote change to %@ was not completed. Inspect the recovery item %@ before retrying."
                ),
                state.targetPath,
                state.recoveryPath ?? state.targetPath
            )
        case .mutationCommittedWithIssues(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.mutation.committedRecovery",
                    fallback: "The remote change to %@ completed, but its final state needs review at %@."
                ),
                state.targetPath,
                state.recoveryPath ?? state.targetPath
            )
        case .mutationCommitIndeterminate(let state):
            return String(
                format: localizer.string(
                    "remoteWorkspace.sftp.mutation.commitIndeterminate",
                    fallback: "The remote change to %@ could not be confirmed. Inspect %@ before retrying."
                ),
                state.targetPath,
                state.recoveryPath ?? state.targetPath
            )
        case .unexpected:
            return localizer.string(
                "remoteWorkspace.sftp.error.generic",
                fallback: "The SFTP operation could not be completed."
            )
        }
    }

    private func message(
        for error: SFTPClientError,
        operation: SFTPBrowserOperation
    ) -> String {
        switch error {
        case .commandFailed:
            return localizer.string(
                "remoteWorkspace.sftp.error.commandFailed",
                fallback: "The SFTP command failed. Check the connection and try again."
            )
        case .parseFailed:
            return localizer.string(
                "remoteWorkspace.sftp.error.parseFailed",
                fallback: "The remote directory response could not be read safely."
            )
        case .transferFailed:
            return localizer.string(
                "remoteWorkspace.sftp.error.transferFailed",
                fallback: "The file transfer could not be completed."
            )
        case .notConnected:
            return localizer.string(
                "remoteWorkspace.sftp.connectionUnavailable",
                fallback: "Reconnect this profile before using SFTP."
            )
        case .invalidDestination:
            return localizer.string(
                "remoteWorkspace.sftp.error.invalidDestination",
                fallback: "The SFTP connection destination is invalid."
            )
        case .invalidPort:
            return localizer.string(
                "remoteWorkspace.sftp.error.invalidPort",
                fallback: "The SFTP connection port is invalid."
            )
        case .invalidPath:
            return localizer.string(
                "remoteWorkspace.sftp.error.invalidPath",
                fallback: "The selected remote path is invalid."
            )
        case .invalidCommand:
            return localizer.string(
                "remoteWorkspace.sftp.error.invalidCommand",
                fallback: "The SFTP operation could not be prepared safely."
            )
        case .unsafeLocalDestination:
            return localizer.string(
                "remoteWorkspace.sftp.download.unsafeDestination",
                fallback: "The download destination is outside Downloads."
            )
        case .destinationExists:
            return localizer.string(
                "remoteWorkspace.sftp.download.destinationExists",
                fallback: "A file with this name already exists in Downloads."
            )
        case .localPublishFailed:
            return localizer.string(
                "remoteWorkspace.sftp.error.localPublishFailed",
                fallback: "The downloaded file could not be saved safely."
            )
        case .unsafeLocalSource:
            return localizer.string(
                "remoteWorkspace.sftp.upload.invalidFile",
                fallback: "Select a regular local file to upload."
            )
        case .remoteDestinationExists:
            return localizer.string(
                "remoteWorkspace.sftp.upload.destinationExists",
                fallback: "An item with this name already exists on the remote host."
            )
        case .remoteDestinationChanged:
            switch operation {
            case .download:
                return localizer.string(
                    "remoteWorkspace.sftp.download.remoteChanged",
                    fallback: "The remote file changed after review. Refresh before downloading it."
                )
            case .remove:
                return localizer.string(
                    "remoteWorkspace.sftp.remove.remoteChanged",
                    fallback: "The remote item changed after review. Refresh before removing it."
                )
            default:
                return localizer.string(
                    "remoteWorkspace.sftp.upload.destinationChanged",
                    fallback: "The remote file changed after review. Refresh and try again."
                )
            }
        case .remoteDirectoryNotEmpty:
            return localizer.string(
                "remoteWorkspace.sftp.remove.directoryNotEmpty",
                fallback: "Only an empty remote directory can be removed safely."
            )
        case .unsafeRemoteDestination:
            switch operation {
            case .download:
                return localizer.string(
                    "remoteWorkspace.sftp.download.unsafeRemoteFile",
                    fallback: "The reviewed remote file is no longer safe to download. Refresh and try again."
                )
            case .remove:
                return localizer.string(
                    "remoteWorkspace.sftp.remove.unsafeRemoteItem",
                    fallback: "The reviewed remote item is no longer safe to remove. Refresh and try again."
                )
            default:
                return localizer.string(
                    "remoteWorkspace.sftp.upload.unsafeDestination",
                    fallback: "Only a regular remote file can be replaced."
                )
            }
        }
    }

    private func startTransientOperation(
        id: String,
        operation: @escaping @Sendable () -> SFTPOperationResult,
        completion: @escaping @MainActor (SFTPOperationResult) -> Void
    ) {
        guard operationTasks[id] == nil else { return }
        let generation = operationGeneration
        let worker = Task.detached(priority: .userInitiated) { operation() }
        operationTasks[id] = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, self.operationGeneration == generation else { return }
            self.operationTasks.removeValue(forKey: id)
            completion(result)
        }
    }

    private func startMutation(
        operation: @escaping @Sendable () -> SFTPOperationResult
    ) {
        _ = mutationCoordinator.start(operation)
    }

    fileprivate func applyMutationSnapshot(
        _ snapshot: SFTPBrowserMutationSnapshot
    ) {
        guard lastMutationRevision != snapshot.revision else { return }
        lastMutationRevision = snapshot.revision
        isMutating = snapshot.isRunning
        mutationFailure = snapshot.pendingResults.first.flatMap { result in
            switch result {
            case .failure(let failure), .successWithWarning(let failure):
                return failure
            case .success:
                return nil
            }
        }
        if snapshot.shouldRefresh, hasStarted {
            loadDirectory()
        }
    }

    private func uploadRecoveryDescription(
        _ state: SFTPUploadRecoveryState
    ) -> String {
        let remotePath = state.remoteBackupPath ?? state.stagedPayloadPath
        if let localPath = state.localSnapshotURL?.path, let remotePath {
            return "\(localPath); \(remotePath)"
        }
        return state.localSnapshotURL?.path ?? remotePath ?? state.destinationPath
    }
}

// MARK: - SFTP Browser View

enum SFTPRowSelectionMove: Sendable {
    case previous
    case next
    case first
    case last
}

/// Sub-panel providing a file browser for remote filesystems via SFTP.
///
/// ## Layout
///
/// ```
/// +-- /home/deploy/project ---------- [up] [R] --+
/// |                                               |
/// | [folder] src/            4.2 KB     Mar 25    |
/// | [folder] tests/          1.1 KB     Mar 24    |
/// | [doc]    README.md        892 B     Mar 26    |
/// | [doc]    package.json    1.2 KB     Mar 25    |
/// +-----------------------------------------------+
/// ```
///
/// - SeeAlso: `SFTPBrowserViewModel`
/// - SeeAlso: `SFTPClient`
struct SFTPBrowserView: View {

    @ObservedObject var viewModel: SFTPBrowserViewModel
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
    @State private var selectedEntryID: String?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var pendingDeletion: SFTPReviewedRemoteEntry?
    @State private var pendingUploadReplacement: SFTPPendingUploadReplacement?
    @FocusState private var isFileListFocused: Bool

    /// Formatter for file modification dates.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        uploadConfirmationContent
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            Divider()
            operationErrorContent
            listingErrorContent
            fileListContent
        }
    }

    @ViewBuilder
    private var operationErrorContent: some View {
        if let message = viewModel.operationErrorMessage {
            inlineError(
                message,
                localRecoveryAction: viewModel.operationLocalRecoveryURL == nil
                    ? nil
                    : { viewModel.revealLocalRecoveryItem() },
                remoteRecoveryAction: viewModel.operationRecoveryPath == nil
                    ? nil
                    : { viewModel.inspectRemoteRecoveryPath() },
                dismiss: { viewModel.dismissOperationError() }
            )
            Divider()
        }
    }

    @ViewBuilder
    private var listingErrorContent: some View {
        if let message = viewModel.listingErrorMessage,
           !viewModel.entries.isEmpty {
            inlineError(message, dismiss: { viewModel.dismissListingError() })
            Divider()
        }
    }

    private var keyboardContent: some View {
        panelContent
        .focusable(true)
        .focused($isFileListFocused)
        .onKeyPress(.upArrow) {
            moveSelection(.previous) ? .handled : .ignored
        }
        .onKeyPress(.downArrow) {
            moveSelection(.next) ? .handled : .ignored
        }
        .onKeyPress(.home) {
            moveSelection(.first) ? .handled : .ignored
        }
        .onKeyPress(.end) {
            moveSelection(.last) ? .handled : .ignored
        }
        .onKeyPress(.return) {
            guard selectedEntry != nil else { return .ignored }
            activateSelectedEntry()
            return .handled
        }
        .onKeyPress(.delete) {
            guard canDeleteSelectedEntry else { return .ignored }
            requestSelectedEntryDeletion()
            return .handled
        }
    }

    private var lifecycleContent: some View {
        keyboardContent
        .onAppear {
            viewModel.updateLocalizer(localizer)
            viewModel.start()
            isFileListFocused = true
        }
        .onChange(of: localizer.resolvedLanguage) { _, _ in
            viewModel.updateLocalizer(localizer)
        }
        .onChange(of: viewModel.entries.map(\.id)) { _, entryIDs in
            guard let selectedEntryID,
                  !entryIDs.contains(selectedEntryID) else { return }
            self.selectedEntryID = nil
        }
        .onDisappear { viewModel.cancelPendingWork() }
    }

    private var sheetContent: some View {
        lifecycleContent
        .sheet(isPresented: $isCreatingFolder) {
            createFolderSheet
        }
    }

    private var removalConfirmationContent: some View {
        sheetContent
        .confirmationDialog(
            localized("remoteWorkspace.sftp.remove.title", fallback: "Remove remote item?"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button(localized("common.delete", fallback: "Delete"), role: .destructive) {
                pendingDeletion = nil
                selectedEntryID = nil
                viewModel.removeEntry(entry)
            }
            Button(localized("common.cancel", fallback: "Cancel"), role: .cancel) {
                pendingDeletion = nil
            }
        } message: { review in
            Text(String(
                format: localized(
                    "remoteWorkspace.sftp.remove.detail",
                    fallback: "This removes %@ from the remote host."
                ),
                review.entry.name
            ))
        }
    }

    private var uploadConfirmationContent: some View {
        removalConfirmationContent
        .confirmationDialog(
            localized("remoteWorkspace.sftp.upload.replace.title", fallback: "Replace remote item?"),
            isPresented: Binding(
                get: { pendingUploadReplacement != nil },
                set: { if !$0 { pendingUploadReplacement = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingUploadReplacement
        ) { pendingUpload in
            Button(localized("common.replace", fallback: "Replace"), role: .destructive) {
                pendingUploadReplacement = nil
                viewModel.uploadFile(
                    pendingUpload.reviewedUpload,
                    replacing: pendingUpload.remoteReview
                )
            }
            Button(localized("common.cancel", fallback: "Cancel"), role: .cancel) {
                pendingUploadReplacement = nil
            }
        } message: { pendingUpload in
            Text(String(
                format: localized(
                    "remoteWorkspace.sftp.upload.replace.detail",
                    fallback: "A remote item named %@ already exists. Continue with the upload?"
                ),
                pendingUpload.reviewedUpload.localURL.lastPathComponent
            ))
        }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                pathBreadcrumb
                Spacer()
                navigationButtons
            }
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var pathBreadcrumb: some View {
        Text(viewModel.currentPath)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: CocxyColors.text))
            .lineLimit(1)
            .truncationMode(.head)
            .accessibilityLabel(
                String(
                    format: localized("remoteWorkspace.sftp.currentPath.accessibility", fallback: "Current path: %@"),
                    viewModel.currentPath
                )
            )
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.navigateUp() }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel(localized("remoteWorkspace.sftp.navigateParent.accessibility", fallback: "Navigate to parent directory"))
            .help(localized("remoteWorkspace.sftp.navigateParent.accessibility", fallback: "Navigate to parent directory"))

            Button(action: { viewModel.refresh() }) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .disabled(viewModel.isLoading)
            .accessibilityLabel(
                viewModel.isLoading
                    ? localized("remoteWorkspace.sftp.loading", fallback: "Loading...")
                    : localized("remoteWorkspace.sftp.refresh.accessibility", fallback: "Refresh directory listing")
            )
            .help(localized("remoteWorkspace.sftp.refresh.accessibility", fallback: "Refresh directory listing"))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            iconButton(
                symbol: "square.and.arrow.up",
                label: localized("remoteWorkspace.sftp.upload", fallback: "Upload file"),
                disabled: viewModel.isMutating || !viewModel.downloadingEntryIDs.isEmpty,
                action: chooseUploadFile
            )
            iconButton(
                symbol: "folder.badge.plus",
                label: localized("remoteWorkspace.sftp.mkdir", fallback: "New folder"),
                disabled: viewModel.isMutating || !viewModel.downloadingEntryIDs.isEmpty,
                action: { isCreatingFolder = true }
            )
            Spacer()
            iconButton(
                symbol: "arrow.down.to.line",
                label: localized("remoteWorkspace.sftp.download", fallback: "Download selected file"),
                disabled: selectedEntry.map {
                    viewModel.isMutating || !$0.isRegularFile || viewModel.isDownloading($0)
                } ?? true,
                action: downloadSelectedEntry
            )
            iconButton(
                symbol: "trash",
                label: localized("remoteWorkspace.sftp.remove", fallback: "Remove selected item"),
                disabled: !canDeleteSelectedEntry,
                role: .destructive,
                action: requestSelectedEntryDeletion
            )
        }
        .frame(height: 26)
    }

    // MARK: - File List

    private var fileListContent: some View {
        Group {
            if let error = viewModel.listingErrorMessage,
               viewModel.entries.isEmpty {
                errorStateView(error)
            } else if viewModel.isLoading && viewModel.entries.isEmpty {
                loadingStateView
            } else if viewModel.entries.isEmpty {
                emptyStateView
            } else {
                fileList
            }
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.entries) { entry in
                        if (entry.isDirectory && !entry.isSymbolicLink) || entry.isRegularFile {
                            entryRow(entry)
                                .accessibilityAction(named: entry.isDirectory
                                    ? localized("remoteWorkspace.sftp.open", fallback: "Open folder")
                                    : localized("remoteWorkspace.sftp.download", fallback: "Download selected file")) {
                                        activate(entry)
                                    }
                                .id(entry.id)
                        } else {
                            entryRow(entry)
                                .id(entry.id)
                        }
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
            .onChange(of: selectedEntryID) { _, entryID in
                guard let entryID else { return }
                proxy.scrollTo(entryID, anchor: .center)
            }
        }
    }

    // MARK: - State Views

    private var loadingStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(localized("remoteWorkspace.sftp.loading", fallback: "Loading..."))
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text(localized("remoteWorkspace.sftp.emptyDirectory", fallback: "Empty directory"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.red))
            Text(localized("remoteWorkspace.sftp.failedToList", fallback: "Failed to list directory"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button(localized("common.retry", fallback: "Retry")) { viewModel.refresh() }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: CocxyColors.blue))
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func inlineError(
        _ message: String,
        localRecoveryAction: (() -> Void)? = nil,
        remoteRecoveryAction: (() -> Void)? = nil,
        dismiss: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(nsColor: CocxyColors.red))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(Color(nsColor: CocxyColors.subtext0))
                .lineLimit(2)
            Spacer(minLength: 4)
            if let localRecoveryAction {
                Button(action: localRecoveryAction) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help(localized(
                    "remoteWorkspace.sftp.recovery.revealLocal",
                    fallback: "Reveal local recovery item"
                ))
                .accessibilityLabel(localized(
                    "remoteWorkspace.sftp.recovery.revealLocal",
                    fallback: "Reveal local recovery item"
                ))
            }
            if let remoteRecoveryAction {
                Button(action: remoteRecoveryAction) {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .help(localized(
                    "remoteWorkspace.sftp.recovery.inspectRemote",
                    fallback: "Inspect remote recovery item"
                ))
                .accessibilityLabel(localized(
                    "remoteWorkspace.sftp.recovery.inspectRemote",
                    fallback: "Inspect remote recovery item"
                ))
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("common.dismiss", fallback: "Dismiss"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var createFolderSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("remoteWorkspace.sftp.mkdir.title", fallback: "New Remote Folder"))
                .font(.system(size: 15, weight: .semibold))
            TextField(
                localized("remoteWorkspace.sftp.mkdir.placeholder", fallback: "Folder name"),
                text: $newFolderName
            )
            HStack {
                Spacer()
                Button(localized("common.cancel", fallback: "Cancel"), role: .cancel) {
                    newFolderName = ""
                    isCreatingFolder = false
                }
                Button(localized("common.create", fallback: "Create")) {
                    let name = newFolderName
                    newFolderName = ""
                    isCreatingFolder = false
                    viewModel.createDirectory(named: name)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var selectedEntry: RemoteFileEntry? {
        guard let selectedEntryID else { return nil }
        return viewModel.entries.first { $0.id == selectedEntryID }
    }

    private var canDeleteSelectedEntry: Bool {
        guard !viewModel.isMutating,
              viewModel.downloadingEntryIDs.isEmpty,
              let selectedEntry,
              Self.isDeleteEligible(selectedEntry) else { return false }
        return !viewModel.isDownloading(selectedEntry)
    }

    nonisolated static func isDeleteEligible(_ entry: RemoteFileEntry) -> Bool {
        !entry.isSymbolicLink && (entry.isDirectory || entry.isRegularFile)
    }

    private func entryRow(_ entry: RemoteFileEntry) -> some View {
        FileEntryRow(
            entry: entry,
            dateFormatter: Self.dateFormatter,
            isDownloading: viewModel.isDownloading(entry),
            isSelected: selectedEntryID == entry.id,
            localizer: localizer
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedEntryID = entry.id
            isFileListFocused = true
        }
        .onTapGesture(count: 2) {
            selectedEntryID = entry.id
            activate(entry)
        }
    }

    private func iconButton(
        symbol: String,
        label: String,
        disabled: Bool,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private func activateSelectedEntry() {
        guard let selectedEntry else { return }
        activate(selectedEntry)
    }

    @discardableResult
    private func moveSelection(_ move: SFTPRowSelectionMove) -> Bool {
        let entryIDs = viewModel.entries.map(\.id)
        guard let nextID = Self.selectionID(
            current: selectedEntryID,
            entryIDs: entryIDs,
            moving: move
        ) else {
            return false
        }
        selectedEntryID = nextID
        isFileListFocused = true
        return true
    }

    nonisolated static func selectionID(
        current: String?,
        entryIDs: [String],
        moving move: SFTPRowSelectionMove
    ) -> String? {
        guard !entryIDs.isEmpty else { return nil }
        switch move {
        case .first:
            return entryIDs.first
        case .last:
            return entryIDs.last
        case .previous:
            guard let current,
                  let index = entryIDs.firstIndex(of: current) else {
                return entryIDs.last
            }
            return entryIDs[max(entryIDs.startIndex, index - 1)]
        case .next:
            guard let current,
                  let index = entryIDs.firstIndex(of: current) else {
                return entryIDs.first
            }
            return entryIDs[min(entryIDs.index(before: entryIDs.endIndex), index + 1)]
        }
    }

    private func activate(_ entry: RemoteFileEntry) {
        if entry.isDirectory, !entry.isSymbolicLink {
            viewModel.navigateToDirectory(entry)
            selectedEntryID = nil
        } else if entry.isRegularFile {
            viewModel.downloadFile(entry)
        }
    }

    private func downloadSelectedEntry() {
        guard let selectedEntry,
              selectedEntry.isRegularFile else { return }
        viewModel.downloadFile(selectedEntry)
    }

    private func requestSelectedEntryDeletion() {
        guard canDeleteSelectedEntry,
              let selectedEntry else { return }
        viewModel.prepareRemoteReview(selectedEntry) { review in
            pendingDeletion = review
        }
    }

    private func chooseUploadFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let reviewedUpload = viewModel.reviewUploadFile(at: url) else { return }
        if let existingEntry = viewModel.entry(named: url.lastPathComponent) {
            guard existingEntry.isRegularFile else {
                viewModel.uploadFile(reviewedUpload)
                return
            }
            viewModel.prepareRemoteReview(existingEntry, operation: .upload) { review in
                pendingUploadReplacement = SFTPPendingUploadReplacement(
                    reviewedUpload: reviewedUpload,
                    remoteReview: review
                )
            }
        } else {
            viewModel.uploadFile(reviewedUpload)
        }
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}

// MARK: - File Entry Row

/// A single row displaying a remote file or directory with metadata.
struct FileEntryRow: View {

    let entry: RemoteFileEntry
    let dateFormatter: DateFormatter
    var isDownloading = false
    var isSelected = false
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)

    var body: some View {
        HStack(spacing: 8) {
            entryIcon
                .frame(width: 24, height: 24)

            Text(entry.name)
                .font(.system(size: 12, weight: entry.isDirectory ? .medium : .regular))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(formattedSize)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .frame(width: 60, alignment: .trailing)

            Text(dateFormatter.string(from: entry.modifiedDate))
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .frame(width: 48, alignment: .trailing)

            Group {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                        .accessibilityLabel(
                            localized(
                                "remoteWorkspace.sftp.download.inProgress",
                                fallback: "Downloading..."
                            )
                        )
                } else {
                    Color.clear
                }
            }
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            isSelected
                ? Color(nsColor: CocxyColors.surface1).opacity(0.8)
                : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(
            String(
                format: localized("remoteWorkspace.sftp.entry.accessibility", fallback: "%@: %@, %@"),
                entry.isDirectory
                    ? localized("remoteWorkspace.sftp.entry.folder", fallback: "Folder")
                    : (entry.isSymbolicLink
                        ? localized("remoteWorkspace.sftp.entry.link", fallback: "Symbolic link")
                        : localized("remoteWorkspace.sftp.entry.file", fallback: "File")),
                entry.name,
                formattedSize
            )
        )
    }

    // MARK: - Icon

    private var entryIcon: some View {
        Image(systemName: entry.isSymbolicLink
            ? "link"
            : (entry.isDirectory ? "folder.fill" : "doc.fill"))
            .font(.system(size: 12))
            .foregroundColor(
                entry.isDirectory
                    ? Color(nsColor: CocxyColors.blue)
                    : Color(nsColor: CocxyColors.overlay1)
            )
    }

    // MARK: - Size Formatting

    private var formattedSize: String {
        let bytes = entry.size
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kilobytes = Double(bytes) / 1024.0
        if kilobytes < 1024.0 {
            return String(format: "%.1f KB", kilobytes)
        }
        let megabytes = kilobytes / 1024.0
        return String(format: "%.1f MB", megabytes)
    }

    private func localized(_ key: String, fallback: String) -> String {
        localizer.string(key, fallback: fallback)
    }
}
