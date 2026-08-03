// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectDirectoryTransaction.swift - Atomic descriptor-relative project publication.

import Darwin
import Foundation

struct ProjectDirectoryTransactionContext: Sendable {
    let rootURL: URL
    let stagingName: String
    let destinationName: String

    var stagingURL: URL {
        rootURL.appendingPathComponent(stagingName, isDirectory: true)
    }

    var destinationURL: URL {
        rootURL.appendingPathComponent(destinationName, isDirectory: true)
    }
}

struct ProjectDirectoryTransactionHooks: Sendable {
    typealias Hook = @Sendable (ProjectDirectoryTransactionContext) throws -> Void

    let afterRootOpen: (@Sendable (URL) throws -> Void)?
    let afterStagingOpen: Hook?
    let beforePublish: Hook?
    let afterPublish: Hook?
    let beforeCleanup: Hook?

    init(
        afterRootOpen: (@Sendable (URL) throws -> Void)? = nil,
        afterStagingOpen: Hook? = nil,
        beforePublish: Hook? = nil,
        afterPublish: Hook? = nil,
        beforeCleanup: Hook? = nil
    ) {
        self.afterRootOpen = afterRootOpen
        self.afterStagingOpen = afterStagingOpen
        self.beforePublish = beforePublish
        self.afterPublish = afterPublish
        self.beforeCleanup = beforeCleanup
    }

    static let none = ProjectDirectoryTransactionHooks()
}

struct ProjectDirectoryPublication: Sendable {
    private let root: ProjectDirectoryRoot
    private let destinationName: String
    private let identity: ProjectDirectoryFileIdentity

    init(
        root: ProjectDirectoryRoot,
        destinationName: String,
        identity: ProjectDirectoryFileIdentity
    ) {
        self.root = root
        self.destinationName = destinationName
        self.identity = identity
    }

    func verifiedURL() throws -> URL {
        try root.verifiedChildURL(named: destinationName, identity: identity)
    }
}

final class ProjectDirectoryTransaction {
    private static let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    private let root: ProjectDirectoryRoot
    private let destinationName: String
    private let stagingName: String
    private let stagingDescriptor: Int32
    private let stagingIdentity: ProjectDirectoryFileIdentity
    private let hooks: ProjectDirectoryTransactionHooks
    private var wasPublished = false
    private var cleanupWasAttempted = false

    private init(
        root: ProjectDirectoryRoot,
        destinationName: String,
        stagingName: String,
        stagingDescriptor: Int32,
        stagingIdentity: ProjectDirectoryFileIdentity,
        hooks: ProjectDirectoryTransactionHooks
    ) {
        self.root = root
        self.destinationName = destinationName
        self.stagingName = stagingName
        self.stagingDescriptor = stagingDescriptor
        self.stagingIdentity = stagingIdentity
        self.hooks = hooks
    }

    deinit {
        if !wasPublished, !cleanupWasAttempted {
            try? cleanup()
        }
        Darwin.close(stagingDescriptor)
    }

    static func begin(
        in root: ProjectDirectoryRoot,
        destinationName: String,
        hooks: ProjectDirectoryTransactionHooks = .none
    ) throws -> ProjectDirectoryTransaction {
        try validateName(destinationName)
        if try root.childIdentity(named: destinationName) != nil {
            throw ProjectDirectoryError.destinationExists(
                try root.displayPath(for: destinationName)
            )
        }

        let stagingName = ".cocxy-project-\(UUID().uuidString)"
        let creation = stagingName.withCString {
            Darwin.mkdirat(root.descriptor, $0, mode_t(0o700))
        }
        guard creation == 0 else {
            if errno == EEXIST {
                throw ProjectDirectoryError.destinationExists(
                    try root.displayPath(for: stagingName)
                )
            }
            throw ProjectDirectoryError.systemCallFailed(
                operation: "create project staging directory",
                code: errno
            )
        }

        let descriptor = stagingName.withCString {
            Darwin.openat(root.descriptor, $0, directoryOpenFlags)
        }
        guard descriptor >= 0 else {
            throw ProjectDirectoryError.cleanupUnverified(
                try root.displayPath(for: stagingName)
            )
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              metadata.st_uid == geteuid(),
              Darwin.fchmod(descriptor, mode_t(0o700)) == 0,
              Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(0o777) == mode_t(0o700) else {
            Darwin.close(descriptor)
            throw ProjectDirectoryError.cleanupUnverified(
                try root.displayPath(for: stagingName)
            )
        }

        let transaction = ProjectDirectoryTransaction(
            root: root,
            destinationName: destinationName,
            stagingName: stagingName,
            stagingDescriptor: descriptor,
            stagingIdentity: ProjectDirectoryFileIdentity(metadata),
            hooks: hooks
        )
        do {
            try hooks.afterStagingOpen?(transaction.context())
            return transaction
        } catch let originalError {
            do {
                try transaction.cleanup()
            } catch {
                throw error
            }
            throw originalError
        }
    }

    var workingDirectory: BoundedProcessWorkingDirectory {
        get throws {
            BoundedProcessWorkingDirectory.descriptor(
                displayURL: try context().stagingURL,
                rawValue: stagingDescriptor
            )
        }
    }

    func verifyRepositoryMetadata() throws {
        let descriptor = ".git".withCString {
            Darwin.openat(stagingDescriptor, $0, Self.directoryOpenFlags)
        }
        guard descriptor >= 0 else {
            throw ProjectDirectoryError.repositoryMetadataMissing(
                try repositoryMetadataPath()
            )
        }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw ProjectDirectoryError.repositoryMetadataMissing(
                try repositoryMetadataPath()
            )
        }
    }

    func publish() throws -> ProjectDirectoryPublication {
        guard !wasPublished else {
            throw ProjectDirectoryError.publicationChanged(
                try root.displayPath(for: destinationName)
            )
        }
        try hooks.beforePublish?(context())
        try verifyStagingLink()
        try verifyRepositoryMetadata()
        if try root.childIdentity(named: destinationName) != nil {
            throw ProjectDirectoryError.destinationExists(
                try root.displayPath(for: destinationName)
            )
        }
        let result = stagingName.withCString { source in
            destinationName.withCString { destination in
                Darwin.renameatx_np(
                    root.descriptor,
                    source,
                    root.descriptor,
                    destination,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            if errno == EEXIST || errno == ENOTEMPTY {
                throw ProjectDirectoryError.destinationExists(
                    try root.displayPath(for: destinationName)
                )
            }
            throw ProjectDirectoryError.systemCallFailed(
                operation: "publish project directory",
                code: errno
            )
        }
        wasPublished = true
        try hooks.afterPublish?(context())
        try verifyPublishedLink()
        try verifyRepositoryMetadata()
        try root.synchronize()
        try verifyPublishedLink()
        try verifyRepositoryMetadata()
        return ProjectDirectoryPublication(
            root: root,
            destinationName: destinationName,
            identity: stagingIdentity
        )
    }

    func cleanup() throws {
        guard !wasPublished, !cleanupWasAttempted else { return }
        cleanupWasAttempted = true
        try hooks.beforeCleanup?(context())
        try verifyStagingLink(cleanup: true)
        try Self.removeContents(of: stagingDescriptor)
        try verifyStagingLink(cleanup: true)
        let removal = stagingName.withCString {
            Darwin.unlinkat(root.descriptor, $0, AT_REMOVEDIR)
        }
        guard removal == 0 else {
            throw ProjectDirectoryError.cleanupUnverified(
                try root.displayPath(for: stagingName)
            )
        }
        try root.synchronize()
        guard try root.childIdentity(named: stagingName) == nil else {
            throw ProjectDirectoryError.cleanupUnverified(
                try root.displayPath(for: stagingName)
            )
        }
    }

    private func context() throws -> ProjectDirectoryTransactionContext {
        ProjectDirectoryTransactionContext(
            rootURL: try root.currentURL(),
            stagingName: stagingName,
            destinationName: destinationName
        )
    }

    private func repositoryMetadataPath() throws -> String {
        try root.displayPath(for: wasPublished ? destinationName : stagingName)
            .appending("/.git")
    }

    private func verifyStagingLink(cleanup: Bool = false) throws {
        guard try root.childIdentity(named: stagingName) == stagingIdentity else {
            let path = try root.displayPath(for: stagingName)
            if cleanup { throw ProjectDirectoryError.cleanupUnverified(path) }
            throw ProjectDirectoryError.publicationChanged(path)
        }
    }

    private func verifyPublishedLink() throws {
        guard try root.childIdentity(named: destinationName) == stagingIdentity else {
            throw ProjectDirectoryError.publicationChanged(
                try root.displayPath(for: destinationName)
            )
        }
    }

    private static func validateName(_ name: String) throws {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\0") else {
            throw ProjectDirectoryError.invalidDestinationName
        }
    }

    private static func removeContents(of descriptor: Int32) throws {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else {
            throw ProjectDirectoryError.systemCallFailed(
                operation: "duplicate project staging directory",
                code: errno
            )
        }
        guard let stream = Darwin.fdopendir(duplicate) else {
            let code = errno
            Darwin.close(duplicate)
            throw ProjectDirectoryError.systemCallFailed(
                operation: "enumerate project staging directory",
                code: code
            )
        }
        var names: [String] = []
        errno = 0
        while let entry = Darwin.readdir(stream) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(entry.pointee.d_namlen) + 1
                ) { String(cString: $0) }
            }
            if name != "." && name != ".." { names.append(name) }
        }
        let enumerationCode = errno
        Darwin.closedir(stream)
        guard enumerationCode == 0 else {
            throw ProjectDirectoryError.systemCallFailed(
                operation: "enumerate project staging directory",
                code: enumerationCode
            )
        }
        for name in names {
            try removeEntry(named: name, from: descriptor)
        }
    }

    private static func removeEntry(named name: String, from parent: Int32) throws {
        var metadata = stat()
        let inspection = name.withCString {
            Darwin.fstatat(parent, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if inspection != 0, errno == ENOENT { return }
        guard inspection == 0 else {
            throw ProjectDirectoryError.cleanupUnverified(name)
        }
        let identity = ProjectDirectoryFileIdentity(metadata)
        if identity.fileType == mode_t(S_IFDIR) {
            let child = name.withCString {
                Darwin.openat(parent, $0, directoryOpenFlags)
            }
            guard child >= 0 else {
                throw ProjectDirectoryError.cleanupUnverified(name)
            }
            defer { Darwin.close(child) }
            var openedMetadata = stat()
            guard Darwin.fstat(child, &openedMetadata) == 0,
                  ProjectDirectoryFileIdentity(openedMetadata) == identity else {
                throw ProjectDirectoryError.cleanupUnverified(name)
            }
            try removeContents(of: child)
            guard try linkedIdentity(named: name, parent: parent) == identity,
                  name.withCString({ Darwin.unlinkat(parent, $0, AT_REMOVEDIR) }) == 0 else {
                throw ProjectDirectoryError.cleanupUnverified(name)
            }
        } else {
            guard try linkedIdentity(named: name, parent: parent) == identity,
                  name.withCString({ Darwin.unlinkat(parent, $0, 0) }) == 0 else {
                throw ProjectDirectoryError.cleanupUnverified(name)
            }
        }
    }

    private static func linkedIdentity(
        named name: String,
        parent: Int32
    ) throws -> ProjectDirectoryFileIdentity? {
        var metadata = stat()
        let result = name.withCString {
            Darwin.fstatat(parent, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return ProjectDirectoryFileIdentity(metadata) }
        if errno == ENOENT { return nil }
        throw ProjectDirectoryError.cleanupUnverified(name)
    }
}
