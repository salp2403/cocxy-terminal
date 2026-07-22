// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CellCloudInitFileBroker.swift - Approval-bound staging for cloud provider user data.

import Darwin
import Foundation

enum CellCloudInitFileBrokerError: Error, Equatable, LocalizedError, Sendable {
    case authorizationUnavailable
    case sourceUnavailable
    case sourceChanged
    case stagingUnavailable

    var errorDescription: String? {
        switch self {
        case .authorizationUnavailable:
            return "Approved cloud-init authorization is unavailable."
        case .sourceUnavailable:
            return "Approved cloud-init file is unavailable or exceeds the 65536-byte limit."
        case .sourceChanged:
            return "Cloud-init content changed after approval."
        case .stagingUnavailable:
            return "Cloud-init content could not be staged securely."
        }
    }
}

struct CellCloudInitFileBroker {
    let stager: CellCloudInitFileStager

    init(stager: CellCloudInitFileStager = CellCloudInitFileStager()) {
        self.stager = stager
    }

    func withStagedApprovedCloudInit<Result>(
        kind: String,
        params: [String: String],
        approvedContext: SocketPrivilegedCommandContext,
        operation: ([String: String]) throws -> Result
    ) throws -> Result {
        guard kind == "create",
              approvedContext.scope != .internalTrusted,
              let reference = CellCLICommandService.cloudInitLocalResourceReference(in: params) else {
            return try operation(params)
        }
        guard approvedContext.scope == .computeCell,
              let approvedPath = approvedContext.localResourcePaths["cloud-init"],
              let approvedDigest = approvedContext.localResourceDigests["cloud-init"] else {
            throw CellCloudInitFileBrokerError.authorizationUnavailable
        }
        guard let data = SocketPrivilegedCommandSecurity.boundedFileData(
            at: URL(fileURLWithPath: approvedPath),
            maximumBytes: CellCLICommandService.maxCloudInitBytes
        ) else {
            throw CellCloudInitFileBrokerError.sourceUnavailable
        }
        guard SocketPrivilegedCommandSecurity.digest(data: data) == approvedDigest else {
            throw CellCloudInitFileBrokerError.sourceChanged
        }

        let staged: CellCloudInitStagedFile
        do {
            staged = try stager.stage(data)
        } catch {
            throw CellCloudInitFileBrokerError.stagingUnavailable
        }
        defer { staged.remove() }

        var boundParams = params
        boundParams["cloud-init"] = reference.binding(to: staged.fileURL.path)
        return try operation(boundParams)
    }
}

struct CellCloudInitStagedFile {
    let fileURL: URL
    let directoryURL: URL
    let fileManager: FileManager

    func remove() {
        try? fileManager.removeItem(at: directoryURL)
    }
}

struct CellCloudInitFileStager {
    private enum StagingError: Error {
        case unsafeRoot
        case createFailed
        case writeFailed
    }

    static let rootDirectoryName = "CloudInitStaging"
    static let stagedFileName = "user-data"
    private static let processDirectoryName = "process-\(Darwin.getpid())-\(UUID().uuidString)"

    let rootDirectory: URL
    let fileManager: FileManager

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
    }

    static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        defaultParentDirectory(fileManager: fileManager)
            .appendingPathComponent(processDirectoryName, isDirectory: true)
    }

    static func removeAbandonedDefaultStaging(fileManager: FileManager = .default) throws {
        try removeAbandonedProcessStaging(
            in: defaultParentDirectory(fileManager: fileManager),
            currentProcessID: Darwin.getpid(),
            processIsRunning: isProcessRunning,
            fileManager: fileManager
        )
    }

    static func removeAbandonedProcessStaging(
        in parentDirectory: URL,
        currentProcessID: Int32,
        processIsRunning: (Int32) -> Bool,
        fileManager: FileManager = .default
    ) throws {
        var metadata = stat()
        let status = parentDirectory.path.withCString { Darwin.lstat($0, &metadata) }
        if status != 0 {
            if errno == ENOENT { return }
            throw StagingError.unsafeRoot
        }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw StagingError.unsafeRoot
        }

        for candidate in try fileManager.contentsOfDirectory(
            at: parentDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            guard let processID = processID(from: candidate.lastPathComponent),
                  processID != currentProcessID,
                  !processIsRunning(processID) else {
                continue
            }
            try? fileManager.removeItem(at: candidate)
        }
    }

    private static func defaultParentDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Cocxy", isDirectory: true)
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    private static func processID(from directoryName: String) -> Int32? {
        let components = directoryName.split(separator: "-", maxSplits: 2)
        guard components.count == 3,
              components[0] == "process",
              let processID = Int32(components[1]),
              processID > 0 else {
            return nil
        }
        return processID
    }

    private static func isProcessRunning(_ processID: Int32) -> Bool {
        if Darwin.kill(processID, 0) == 0 { return true }
        return errno == EPERM
    }

    func stage(_ data: Data) throws -> CellCloudInitStagedFile {
        guard data.count <= CellCLICommandService.maxCloudInitBytes else {
            throw StagingError.writeFailed
        }

        try fileManager.createDirectory(
            at: rootDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let rootDescriptor = try openRootDirectory()
        defer { Darwin.close(rootDescriptor) }

        let operationName = try createOperationDirectory(in: rootDescriptor)
        let operationURL = rootDirectory.appendingPathComponent(operationName, isDirectory: true)
        var operationDescriptor: Int32 = -1
        var fileDescriptor: Int32 = -1
        var keepOperationDirectory = false

        defer {
            if fileDescriptor >= 0 { Darwin.close(fileDescriptor) }
            if operationDescriptor >= 0 { Darwin.close(operationDescriptor) }
            if !keepOperationDirectory {
                try? fileManager.removeItem(at: operationURL)
            }
        }

        operationDescriptor = operationName.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard operationDescriptor >= 0,
              Darwin.fchmod(operationDescriptor, mode_t(0o700)) == 0 else {
            throw StagingError.createFailed
        }

        fileDescriptor = Self.stagedFileName.withCString {
            Darwin.openat(
                operationDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                mode_t(0o600)
            )
        }
        guard fileDescriptor >= 0,
              Darwin.fchmod(fileDescriptor, mode_t(0o600)) == 0 else {
            throw StagingError.createFailed
        }

        try writeAll(data, to: fileDescriptor)
        guard Darwin.fsync(fileDescriptor) == 0 else {
            throw StagingError.writeFailed
        }
        let closeResult = Darwin.close(fileDescriptor)
        fileDescriptor = -1
        guard closeResult == 0 else {
            throw StagingError.writeFailed
        }

        keepOperationDirectory = true
        return CellCloudInitStagedFile(
            fileURL: operationURL.appendingPathComponent(Self.stagedFileName),
            directoryURL: operationURL,
            fileManager: fileManager
        )
    }

    func removeAbandonedStaging() throws {
        var metadata = stat()
        let status = rootDirectory.path.withCString { Darwin.lstat($0, &metadata) }
        if status != 0 {
            if errno == ENOENT { return }
            throw StagingError.unsafeRoot
        }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw StagingError.unsafeRoot
        }
        try fileManager.removeItem(at: rootDirectory)
    }

    private func openRootDirectory() throws -> Int32 {
        let createStatus = rootDirectory.path.withCString {
            Darwin.mkdir($0, mode_t(0o700))
        }
        guard createStatus == 0 || errno == EEXIST else {
            throw StagingError.createFailed
        }

        let descriptor = rootDirectory.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw StagingError.unsafeRoot
        }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              Darwin.fchmod(descriptor, mode_t(0o700)) == 0 else {
            Darwin.close(descriptor)
            throw StagingError.unsafeRoot
        }
        return descriptor
    }

    private func createOperationDirectory(in rootDescriptor: Int32) throws -> String {
        for _ in 0..<16 {
            let name = "request-\(UUID().uuidString)"
            let status = name.withCString {
                Darwin.mkdirat(rootDescriptor, $0, mode_t(0o700))
            }
            if status == 0 { return name }
            if errno != EEXIST { throw StagingError.createFailed }
        }
        throw StagingError.createFailed
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw StagingError.writeFailed }
                offset += written
            }
        }
    }
}
