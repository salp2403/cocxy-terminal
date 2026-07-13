// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewWorkspaceFileAccess.swift - Descriptor-bound review file reads and writes.

import Darwin
import Foundation

struct CodeReviewWorkspaceFileVersion: Equatable, Sendable {
    fileprivate let device: UInt64
    fileprivate let inode: UInt64
    fileprivate let size: Int64
    fileprivate let mode: UInt32
    fileprivate let modifiedSeconds: Int64
    fileprivate let modifiedNanoseconds: Int64
    fileprivate let changedSeconds: Int64
    fileprivate let changedNanoseconds: Int64

    fileprivate init(_ metadata: stat) {
        device = UInt64(truncatingIfNeeded: metadata.st_dev)
        inode = UInt64(truncatingIfNeeded: metadata.st_ino)
        size = Int64(metadata.st_size)
        mode = UInt32(metadata.st_mode)
        modifiedSeconds = Int64(metadata.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
        changedSeconds = Int64(metadata.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
    }

    fileprivate var identity: CodeReviewWorkspaceFileIdentity {
        CodeReviewWorkspaceFileIdentity(device: device, inode: inode)
    }

    fileprivate func hasSameContentState(as other: Self) -> Bool {
        identity == other.identity
            && size == other.size
            && mode == other.mode
            && modifiedSeconds == other.modifiedSeconds
            && modifiedNanoseconds == other.modifiedNanoseconds
    }
}

fileprivate struct CodeReviewWorkspaceFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct CodeReviewWorkspaceFileSnapshot: Equatable, Sendable {
    let content: String
    let version: CodeReviewWorkspaceFileVersion
}

enum CodeReviewWorkspaceFileError: Error, Equatable, LocalizedError, Sendable {
    case invalidPath(String)
    case unsafePath(String)
    case fileChanged(String)
    case fileTooLarge(String)
    case invalidUTF8(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPath(let path), .unsafePath(let path):
            return "The review file path is unsafe or uses a symbolic link: \(path)"
        case .fileChanged(let path):
            return "The review file changed on disk. Reload it before saving: \(path)"
        case .fileTooLarge(let path):
            return "The review file is too large to open safely: \(path)"
        case .invalidUTF8(let path):
            return "The review file is not valid UTF-8 text: \(path)"
        case .writeFailed(let path):
            return "The review file could not be saved safely: \(path)"
        }
    }
}

final class CodeReviewWorkspaceFileAccess: Equatable, @unchecked Sendable {
    private static let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    private static let maxFileBytes = 64 * 1_024 * 1_024

    let rootURL: URL
    private let rootDescriptor: OwnedDescriptor
    private let rootIdentity: CodeReviewWorkspaceFileIdentity

    init(rootURL: URL) throws {
        let host = rootURL.host
        let hasLocalHost = host == nil || host?.isEmpty == true || host == "localhost"
        guard rootURL.isFileURL, hasLocalHost else {
            throw CodeReviewWorkspaceFileError.invalidPath(rootURL.path)
        }

        let canonicalRoot = try Self.canonicalRootURL(rootURL)
        let components = try Self.validatedAbsoluteComponents(canonicalRoot.path)
        let descriptor = try Self.openAbsoluteDirectory(
            components: components,
            unsafePath: canonicalRoot.path
        )
        var metadata = stat()
        guard Darwin.fstat(descriptor.value, &metadata) == 0,
              Self.isDirectory(metadata) else {
            throw CodeReviewWorkspaceFileError.unsafePath(canonicalRoot.path)
        }

        self.rootURL = canonicalRoot
        self.rootDescriptor = descriptor
        self.rootIdentity = CodeReviewWorkspaceFileVersion(metadata).identity
    }

    static func == (lhs: CodeReviewWorkspaceFileAccess, rhs: CodeReviewWorkspaceFileAccess) -> Bool {
        lhs.rootIdentity == rhs.rootIdentity
    }

    func read(relativePath: String) throws -> CodeReviewWorkspaceFileSnapshot {
        let components = try Self.validatedRelativeComponents(relativePath)
        let parent = try openParent(
            components: Array(components.dropLast()),
            relativePath: relativePath
        )
        let finalName = components[components.count - 1]
        let descriptor = finalName.withCString {
            Darwin.openat(parent.value, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }
        let file = OwnedDescriptor(descriptor)

        var initialMetadata = stat()
        guard Darwin.fstat(file.value, &initialMetadata) == 0,
              Self.isRegularFile(initialMetadata),
              initialMetadata.st_size >= 0 else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }
        guard initialMetadata.st_size <= off_t(Self.maxFileBytes) else {
            throw CodeReviewWorkspaceFileError.fileTooLarge(relativePath)
        }
        let initialVersion = CodeReviewWorkspaceFileVersion(initialMetadata)

        var data = Data()
        data.reserveCapacity(Int(initialMetadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(file.value, $0.baseAddress, $0.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else {
                throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
            }
            if count == 0 { break }
            guard count <= Self.maxFileBytes - data.count else {
                throw CodeReviewWorkspaceFileError.fileTooLarge(relativePath)
            }
            data.append(contentsOf: buffer.prefix(count))
        }

        var finalMetadata = stat()
        guard Darwin.fstat(file.value, &finalMetadata) == 0,
              CodeReviewWorkspaceFileVersion(finalMetadata) == initialVersion,
              data.count == initialVersion.size else {
            throw CodeReviewWorkspaceFileError.fileChanged(relativePath)
        }
        guard let content = String(data: data, encoding: .utf8) else {
            throw CodeReviewWorkspaceFileError.invalidUTF8(relativePath)
        }
        return CodeReviewWorkspaceFileSnapshot(content: content, version: initialVersion)
    }

    func write(
        _ content: String,
        relativePath: String,
        expectedVersion: CodeReviewWorkspaceFileVersion
    ) throws -> CodeReviewWorkspaceFileVersion {
        let data = Data(content.utf8)
        guard data.count <= Self.maxFileBytes else {
            throw CodeReviewWorkspaceFileError.fileTooLarge(relativePath)
        }

        let components = try Self.validatedRelativeComponents(relativePath)
        let parent = try openParent(
            components: Array(components.dropLast()),
            relativePath: relativePath
        )
        let finalName = components[components.count - 1]
        let targetDescriptor = finalName.withCString {
            Darwin.openat(parent.value, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard targetDescriptor >= 0 else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }
        let target = OwnedDescriptor(targetDescriptor)

        var targetMetadata = stat()
        guard Darwin.fstat(target.value, &targetMetadata) == 0,
              Self.isRegularFile(targetMetadata) else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }
        guard CodeReviewWorkspaceFileVersion(targetMetadata) == expectedVersion else {
            throw CodeReviewWorkspaceFileError.fileChanged(relativePath)
        }

        let temporaryFile = try Self.createTemporaryFile(
            data,
            targetMode: targetMetadata.st_mode,
            relativePath: relativePath,
            parentDescriptor: parent.value
        )
        defer {
            if temporaryFile.shouldCleanup {
                temporaryFile.name.withCString {
                    _ = Darwin.unlinkat(parent.value, $0, 0)
                }
            }
        }

        var refreshedTargetMetadata = stat()
        guard Darwin.fstat(target.value, &refreshedTargetMetadata) == 0,
              CodeReviewWorkspaceFileVersion(refreshedTargetMetadata) == expectedVersion,
              try Self.outputNode(
                named: finalName,
                relativePath: relativePath,
                parentDescriptor: parent.value
              ) == .regular(expectedVersion),
              try Self.outputNode(
                named: temporaryFile.name,
                relativePath: relativePath,
                parentDescriptor: parent.value
              ) == .regular(temporaryFile.version) else {
            throw CodeReviewWorkspaceFileError.fileChanged(relativePath)
        }

        let swapResult = Self.renameEntry(
            temporaryFile.name,
            to: finalName,
            relativeTo: parent.value,
            flags: UInt32(RENAME_SWAP)
        )
        guard swapResult == 0 else {
            throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
        }

        let publishedVersion: CodeReviewWorkspaceFileVersion
        do {
            guard case .regular(let previousVersion) = try Self.outputNode(
                named: temporaryFile.name,
                relativePath: relativePath,
                parentDescriptor: parent.value
            ),
            case .regular(let currentPublishedVersion) = try Self.outputNode(
                named: finalName,
                relativePath: relativePath,
                parentDescriptor: parent.value
            ),
            previousVersion.hasSameContentState(as: expectedVersion),
            currentPublishedVersion.hasSameContentState(as: temporaryFile.version) else {
                throw CodeReviewWorkspaceFileError.fileChanged(relativePath)
            }

            let cleanupResult = temporaryFile.name.withCString {
                Darwin.unlinkat(parent.value, $0, 0)
            }
            guard cleanupResult == 0 else {
                throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
            }
            temporaryFile.shouldCleanup = false
            publishedVersion = currentPublishedVersion
        } catch {
            let rollbackResult = Self.renameEntry(
                temporaryFile.name,
                to: finalName,
                relativeTo: parent.value,
                flags: UInt32(RENAME_SWAP)
            )
            if rollbackResult != 0 {
                temporaryFile.shouldCleanup = false
            }
            throw error
        }

        _ = Darwin.fsync(parent.value)
        return publishedVersion
    }

    private func openParent(
        components: [String],
        relativePath: String
    ) throws -> OwnedDescriptor {
        let duplicate = ".".withCString {
            Darwin.openat(rootDescriptor.value, $0, Self.directoryOpenFlags)
        }
        guard duplicate >= 0 else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }
        var current = OwnedDescriptor(duplicate)
        var rootMetadata = stat()
        guard Darwin.fstat(current.value, &rootMetadata) == 0,
              Self.isDirectory(rootMetadata),
              CodeReviewWorkspaceFileVersion(rootMetadata).identity == rootIdentity else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }

        for component in components {
            let nextDescriptor = component.withCString {
                Darwin.openat(current.value, $0, Self.directoryOpenFlags)
            }
            guard nextDescriptor >= 0 else {
                throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
            }
            current = OwnedDescriptor(nextDescriptor)
        }
        return current
    }

    private static func openAbsoluteDirectory(
        components: [String],
        unsafePath: String
    ) throws -> OwnedDescriptor {
        let rootDescriptor = "/".withCString {
            Darwin.open($0, directoryOpenFlags)
        }
        guard rootDescriptor >= 0 else {
            throw CodeReviewWorkspaceFileError.unsafePath(unsafePath)
        }

        var current = OwnedDescriptor(rootDescriptor)
        for component in components {
            let nextDescriptor = component.withCString {
                Darwin.openat(current.value, $0, directoryOpenFlags)
            }
            guard nextDescriptor >= 0 else {
                throw CodeReviewWorkspaceFileError.unsafePath(unsafePath)
            }
            current = OwnedDescriptor(nextDescriptor)
        }
        return current
    }

    private static func canonicalRootURL(_ rootURL: URL) throws -> URL {
        var storage = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolvedPath: String? = rootURL.path.withCString { sourcePath in
            storage.withUnsafeMutableBufferPointer { buffer in
                guard Darwin.realpath(sourcePath, buffer.baseAddress) != nil,
                      let baseAddress = buffer.baseAddress else {
                    return nil
                }
                return String(cString: baseAddress)
            }
        }
        guard let resolvedPath else {
            throw CodeReviewWorkspaceFileError.unsafePath(rootURL.path)
        }
        return URL(fileURLWithPath: resolvedPath, isDirectory: true)
    }

    private static func validatedAbsoluteComponents(_ path: String) throws -> [String] {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw CodeReviewWorkspaceFileError.invalidPath(path)
        }
        if path == "/" { return [] }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first?.isEmpty == true else {
            throw CodeReviewWorkspaceFileError.invalidPath(path)
        }
        let result = components.dropFirst().map(String.init)
        guard result.allSatisfy(Self.isSafeComponent) else {
            throw CodeReviewWorkspaceFileError.invalidPath(path)
        }
        return result
    }

    private static func validatedRelativeComponents(_ path: String) throws -> [String] {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\0") else {
            throw CodeReviewWorkspaceFileError.invalidPath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
            .map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(Self.isSafeComponent) else {
            throw CodeReviewWorkspaceFileError.invalidPath(path)
        }
        return components
    }

    private static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func createTemporaryFile(
        _ data: Data,
        targetMode: mode_t,
        relativePath: String,
        parentDescriptor: Int32
    ) throws -> TemporaryFile {
        for _ in 0..<16 {
            let name = ".cocxy-review-\(UUID().uuidString).tmp"
            let descriptor = name.withCString {
                Darwin.openat(
                    parentDescriptor,
                    $0,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                    mode_t(0o600)
                )
            }
            if descriptor < 0 {
                if errno == EEXIST { continue }
                throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
            }

            var descriptorIsOpen = true
            do {
                guard Darwin.fchmod(descriptor, targetMode & mode_t(0o777)) == 0 else {
                    throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
                }
                try writeAll(data, to: descriptor, relativePath: relativePath)
                guard Darwin.fsync(descriptor) == 0 else {
                    throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
                }

                var metadata = stat()
                guard Darwin.fstat(descriptor, &metadata) == 0,
                      isRegularFile(metadata) else {
                    throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
                }
                let version = CodeReviewWorkspaceFileVersion(metadata)
                let closeResult = Darwin.close(descriptor)
                descriptorIsOpen = false
                guard closeResult == 0 else {
                    throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
                }
                return TemporaryFile(name: name, version: version)
            } catch {
                if descriptorIsOpen { Darwin.close(descriptor) }
                name.withCString {
                    _ = Darwin.unlinkat(parentDescriptor, $0, 0)
                }
                throw error
            }
        }
        throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
    }

    private static func writeAll(
        _ data: Data,
        to descriptor: Int32,
        relativePath: String
    ) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw CodeReviewWorkspaceFileError.writeFailed(relativePath)
                }
                offset += count
            }
        }
    }

    private static func outputNode(
        named name: String,
        relativePath: String,
        parentDescriptor: Int32
    ) throws -> OutputNode {
        var metadata = stat()
        let result = name.withCString {
            Darwin.fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if result == 0 {
            if isSymbolicLink(metadata) { return .symbolicLink }
            if isRegularFile(metadata) {
                return .regular(CodeReviewWorkspaceFileVersion(metadata))
            }
            return .other
        }
        guard errno == ENOENT else {
            throw CodeReviewWorkspaceFileError.unsafePath(relativePath)
        }
        return .absent
    }

    private static func renameEntry(
        _ source: String,
        to destination: String,
        relativeTo parentDescriptor: Int32,
        flags: UInt32
    ) -> Int32 {
        source.withCString { sourcePath in
            destination.withCString { destinationPath in
                Darwin.renameatx_np(
                    parentDescriptor,
                    sourcePath,
                    parentDescriptor,
                    destinationPath,
                    flags
                )
            }
        }
    }

    private static func isRegularFile(_ metadata: stat) -> Bool {
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    private static func isDirectory(_ metadata: stat) -> Bool {
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    private static func isSymbolicLink(_ metadata: stat) -> Bool {
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private enum OutputNode: Equatable {
        case absent
        case regular(CodeReviewWorkspaceFileVersion)
        case symbolicLink
        case other
    }

    private final class TemporaryFile {
        let name: String
        let version: CodeReviewWorkspaceFileVersion
        var shouldCleanup = true

        init(name: String, version: CodeReviewWorkspaceFileVersion) {
            self.name = name
            self.version = version
        }
    }

    private final class OwnedDescriptor {
        let value: Int32

        init(_ value: Int32) {
            self.value = value
        }

        deinit {
            Darwin.close(value)
        }
    }
}
