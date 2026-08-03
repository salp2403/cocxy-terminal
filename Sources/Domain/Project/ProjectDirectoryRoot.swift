// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectDirectoryRoot.swift - Descriptor-bound project directory authority.

import Darwin
import Foundation

enum ProjectDirectoryError: Error, Equatable, LocalizedError, Sendable {
    case invalidRoot(String)
    case symbolicLinkRejected(String)
    case invalidDestinationName
    case destinationExists(String)
    case repositoryMetadataMissing(String)
    case publicationChanged(String)
    case cleanupUnverified(String)
    case systemCallFailed(operation: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case .invalidRoot(let path):
            return "The project destination is not a valid directory: \(path)"
        case .symbolicLinkRejected(let path):
            return "The project destination cannot contain symbolic links: \(path)"
        case .invalidDestinationName:
            return "The project name is not a safe directory name."
        case .destinationExists(let path):
            return "A file or folder already exists at \(path)."
        case .repositoryMetadataMissing(let path):
            return "Git completed without creating repository metadata at \(path)."
        case .publicationChanged(let path):
            return "The project destination changed while it was being created: \(path)"
        case .cleanupUnverified(let path):
            return "Cocxy could not safely verify project cleanup at \(path)."
        case .systemCallFailed(let operation, let code):
            let detail = strerror(code).map { String(cString: $0) } ?? "POSIX error \(code)"
            return "Project directory operation \(operation) failed: \(detail)."
        }
    }
}

struct ProjectDirectoryFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let fileType: mode_t

    init(_ metadata: stat) {
        device = UInt64(truncatingIfNeeded: metadata.st_dev)
        inode = UInt64(truncatingIfNeeded: metadata.st_ino)
        fileType = metadata.st_mode & mode_t(S_IFMT)
    }
}

final class ProjectDirectoryRoot: @unchecked Sendable {
    private static let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    let displayURL: URL
    let identity: ProjectDirectoryFileIdentity
    let descriptor: Int32

    private init(
        displayURL: URL,
        identity: ProjectDirectoryFileIdentity,
        descriptor: Int32
    ) {
        self.displayURL = displayURL
        self.identity = identity
        self.descriptor = descriptor
    }

    deinit {
        Darwin.close(descriptor)
    }

    static func open(
        _ directory: URL,
        afterOpen: (@Sendable (URL) throws -> Void)? = nil
    ) throws -> ProjectDirectoryRoot {
        let components = try validatedComponents(directory)
        let rootDescriptor = "/".withCString {
            Darwin.open($0, directoryOpenFlags)
        }
        guard rootDescriptor >= 0 else {
            throw ProjectDirectoryError.systemCallFailed(
                operation: "open filesystem root",
                code: errno
            )
        }

        var currentDescriptor = rootDescriptor
        do {
            var traversal = components
            if let first = traversal.first,
               let replacement = try trustedRootAlias(
                   named: first,
                   rootDescriptor: rootDescriptor,
                   unsafePath: directory.path
               ) {
                traversal.removeFirst()
                traversal.insert(contentsOf: replacement, at: 0)
            }

            for component in traversal {
                let nextDescriptor = component.withCString {
                    Darwin.openat(currentDescriptor, $0, directoryOpenFlags)
                }
                guard nextDescriptor >= 0 else {
                    let code = errno
                    var metadata = stat()
                    let inspection = component.withCString {
                        Darwin.fstatat(
                            currentDescriptor,
                            $0,
                            &metadata,
                            AT_SYMLINK_NOFOLLOW
                        )
                    }
                    if inspection == 0,
                       metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) {
                        throw ProjectDirectoryError.symbolicLinkRejected(directory.path)
                    }
                    if code == ENOENT || code == ENOTDIR {
                        throw ProjectDirectoryError.invalidRoot(directory.path)
                    }
                    throw ProjectDirectoryError.systemCallFailed(
                        operation: "open project directory",
                        code: code
                    )
                }
                Darwin.close(currentDescriptor)
                currentDescriptor = nextDescriptor
            }

            var metadata = stat()
            guard Darwin.fstat(currentDescriptor, &metadata) == 0,
                  metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                throw ProjectDirectoryError.invalidRoot(directory.path)
            }
            let result = ProjectDirectoryRoot(
                displayURL: directory.standardizedFileURL,
                identity: ProjectDirectoryFileIdentity(metadata),
                descriptor: currentDescriptor
            )
            currentDescriptor = -1
            try afterOpen?(result.displayURL)
            return result
        } catch {
            if currentDescriptor >= 0 { Darwin.close(currentDescriptor) }
            throw error
        }
    }

    func currentURL() throws -> URL {
        if let reopened = try? ProjectDirectoryRoot.open(displayURL),
           reopened.identity == identity {
            return displayURL
        }
        return try descriptorBoundURL()
    }

    func descriptorBoundURL() throws -> URL {
        var information = vnode_fdinfowithpath()
        let expectedBytes = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            proc_pidfdinfo(
                getpid(),
                descriptor,
                PROC_PIDFDVNODEPATHINFO,
                pointer,
                expectedBytes
            )
        }
        guard result == expectedBytes else {
            throw ProjectDirectoryError.systemCallFailed(
                operation: "resolve project directory",
                code: errno
            )
        }
        let path = withUnsafePointer(to: &information.pvip.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        guard path.hasPrefix("/") else {
            throw ProjectDirectoryError.invalidRoot(displayURL.path)
        }
        return URL(
            fileURLWithPath: path,
            isDirectory: true
        ).standardizedFileURL
    }

    func verifiedChildURL(
        named name: String,
        identity expectedIdentity: ProjectDirectoryFileIdentity
    ) throws -> URL {
        try openVerifiedChild(named: name, identity: expectedIdentity).currentURL()
    }

    func openVerifiedChild(
        named name: String,
        identity expectedIdentity: ProjectDirectoryFileIdentity
    ) throws -> ProjectDirectoryRoot {
        let childDescriptor = name.withCString {
            Darwin.openat(descriptor, $0, Self.directoryOpenFlags)
        }
        guard childDescriptor >= 0 else {
            throw ProjectDirectoryError.publicationChanged(
                try displayPath(for: name)
            )
        }
        var transfersDescriptorOwnership = false
        defer {
            if !transfersDescriptorOwnership {
                Darwin.close(childDescriptor)
            }
        }
        var metadata = stat()
        guard Darwin.fstat(childDescriptor, &metadata) == 0,
              ProjectDirectoryFileIdentity(metadata) == expectedIdentity else {
            throw ProjectDirectoryError.publicationChanged(
                try displayPath(for: name)
            )
        }
        let rootURL = try currentURL()
        guard try childIdentity(named: name) == expectedIdentity else {
            throw ProjectDirectoryError.publicationChanged(
                rootURL.appendingPathComponent(name, isDirectory: true).path
            )
        }
        let child = ProjectDirectoryRoot(
            displayURL: rootURL.appendingPathComponent(name, isDirectory: true),
            identity: expectedIdentity,
            descriptor: childDescriptor
        )
        transfersDescriptorOwnership = true
        return child
    }

    func childIdentity(named name: String) throws -> ProjectDirectoryFileIdentity? {
        var metadata = stat()
        let result = name.withCString {
            Darwin.fstatat(descriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 { return ProjectDirectoryFileIdentity(metadata) }
        if errno == ENOENT { return nil }
        throw ProjectDirectoryError.systemCallFailed(
            operation: "inspect project directory entry",
            code: errno
        )
    }

    func displayPath(for name: String) throws -> String {
        try currentURL().appendingPathComponent(name).path
    }

    func synchronize() throws {
        guard Darwin.fsync(descriptor) == 0 else {
            throw ProjectDirectoryError.systemCallFailed(
                operation: "synchronize project directory",
                code: errno
            )
        }
    }

    private static func validatedComponents(_ directory: URL) throws -> [String] {
        let host = directory.host
        let localHost = host == nil || host?.isEmpty == true || host == "localhost"
        let path = directory.path
        guard directory.isFileURL,
              localHost,
              path.hasPrefix("/"),
              !path.contains("\0") else {
            throw ProjectDirectoryError.invalidRoot(path)
        }
        if path == "/" { return [] }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.first?.isEmpty == true else {
            throw ProjectDirectoryError.invalidRoot(path)
        }
        let components = pieces.dropFirst().map(String.init)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProjectDirectoryError.invalidRoot(path)
        }
        return components
    }

    private static func trustedRootAlias(
        named name: String,
        rootDescriptor: Int32,
        unsafePath: String
    ) throws -> [String]? {
        guard name == "var" || name == "tmp" else { return nil }
        var aliasMetadata = stat()
        let status = name.withCString {
            Darwin.fstatat(rootDescriptor, $0, &aliasMetadata, AT_SYMLINK_NOFOLLOW)
        }
        guard status == 0 else { return nil }
        guard aliasMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK) else {
            return nil
        }
        var rootMetadata = stat()
        guard Darwin.fstat(rootDescriptor, &rootMetadata) == 0,
              rootMetadata.st_uid == 0,
              rootMetadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              rootMetadata.st_mode & mode_t(S_IWGRP | S_IWOTH) == 0,
              aliasMetadata.st_uid == 0 else {
            throw ProjectDirectoryError.symbolicLinkRejected(unsafePath)
        }
        var buffer = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let count = name.withCString { component in
            buffer.withUnsafeMutableBytes { storage in
                Darwin.readlinkat(
                    rootDescriptor,
                    component,
                    storage.baseAddress?.assumingMemoryBound(to: CChar.self),
                    storage.count
                )
            }
        }
        guard count > 0 else {
            throw ProjectDirectoryError.symbolicLinkRejected(unsafePath)
        }
        let target = String(decoding: buffer.prefix(Int(count)), as: UTF8.self)
        guard target == "private/\(name)" else {
            throw ProjectDirectoryError.symbolicLinkRejected(unsafePath)
        }
        return ["private", name]
    }
}
