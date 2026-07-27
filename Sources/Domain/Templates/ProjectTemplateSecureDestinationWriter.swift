// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTemplateSecureDestinationWriter.swift - Descriptor-relative scaffold output writer.

import Darwin
import Foundation

struct ProjectTemplateSecureDestinationWriter {
    struct Policy: Sendable {
        let createdDirectoryMode: mode_t
        let enforcedDestinationMode: mode_t?
        let outputFileMode: mode_t?

        static let projectTemplate = Policy(
            createdDirectoryMode: 0o755,
            enforcedDestinationMode: nil,
            outputFileMode: nil
        )

        static let ownerOnlyPrivateFiles = Policy(
            createdDirectoryMode: 0o700,
            enforcedDestinationMode: 0o700,
            outputFileMode: 0o600
        )
    }

    private static let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    let destinationURL: URL
    private let destinationDescriptor: OwnedDescriptor
    private let policy: Policy

    init(destinationURL: URL, policy: Policy = .projectTemplate) throws {
        let components = try Self.validatedDestinationComponents(destinationURL)
        let destinationDescriptor = try Self.openDestination(
            components: components,
            unsafePath: destinationURL.path,
            createdDirectoryMode: policy.createdDirectoryMode
        )
        if let destinationMode = policy.enforcedDestinationMode {
            try Self.enforceOwnerOnlyDestination(
                destinationDescriptor.value,
                mode: destinationMode,
                unsafePath: destinationURL.path
            )
        }
        self.destinationURL = destinationURL.standardizedFileURL
        self.destinationDescriptor = destinationDescriptor
        self.policy = policy
    }

    func write(
        _ data: Data,
        relativePath: String,
        overwrite: Bool
    ) throws {
        let components = try Self.validatedOutputComponents(relativePath)
        let parentDescriptor = try Self.openOutputParent(
            components: Array(components.dropLast()),
            destinationDescriptor: destinationDescriptor.value,
            createdDirectoryMode: policy.createdDirectoryMode,
            unsafePath: relativePath
        )
        try Self.writeRenderedContent(
            data,
            finalName: components[components.count - 1],
            relativePath: relativePath,
            parentDescriptor: parentDescriptor.value,
            overwrite: overwrite,
            outputFileMode: policy.outputFileMode
        )
    }

    private static func validatedDestinationComponents(_ destinationURL: URL) throws -> [String] {
        let host = destinationURL.host
        let hasLocalHost = host == nil || host?.isEmpty == true || host == "localhost"
        let path = destinationURL.path
        guard destinationURL.isFileURL,
              hasLocalHost,
              path.hasPrefix("/"),
              !path.contains("\0") else {
            throw ProjectTemplateError.unsafeOutputPath(path)
        }
        guard path != "/" else { return [] }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first?.isEmpty == true else {
            throw ProjectTemplateError.unsafeOutputPath(path)
        }
        let pathComponents = components.dropFirst().map(String.init)
        guard pathComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProjectTemplateError.unsafeOutputPath(path)
        }
        return pathComponents
    }

    private static func validatedOutputComponents(_ relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0") else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }
        return components.map(String.init)
    }

    private static func openDestination(
        components: [String],
        unsafePath: String,
        createdDirectoryMode: mode_t
    ) throws -> OwnedDescriptor {
        let rootDescriptor = "/".withCString {
            Darwin.open($0, directoryOpenFlags)
        }
        guard rootDescriptor >= 0 else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }

        var current = OwnedDescriptor(rootDescriptor)
        for (index, component) in components.enumerated() {
            let next = try openOrCreateDirectory(
                named: component,
                relativeTo: current.value,
                allowTrustedSystemRootSymlink: index == 0 && index < components.count - 1,
                createdDirectoryMode: createdDirectoryMode,
                unsafePath: unsafePath
            )
            current = OwnedDescriptor(next)
        }
        return current
    }

    private static func openOutputParent(
        components: [String],
        destinationDescriptor: Int32,
        createdDirectoryMode: mode_t,
        unsafePath: String
    ) throws -> OwnedDescriptor {
        let duplicate = ".".withCString {
            Darwin.openat(destinationDescriptor, $0, directoryOpenFlags)
        }
        guard duplicate >= 0 else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }

        var current = OwnedDescriptor(duplicate)
        for component in components {
            let next = try openOrCreateDirectory(
                named: component,
                relativeTo: current.value,
                allowTrustedSystemRootSymlink: false,
                createdDirectoryMode: createdDirectoryMode,
                unsafePath: unsafePath
            )
            current = OwnedDescriptor(next)
        }
        return current
    }

    private static func openOrCreateDirectory(
        named name: String,
        relativeTo parentDescriptor: Int32,
        allowTrustedSystemRootSymlink: Bool,
        createdDirectoryMode: mode_t,
        unsafePath: String
    ) throws -> Int32 {
        let descriptor = name.withCString {
            Darwin.openat(parentDescriptor, $0, directoryOpenFlags)
        }
        if descriptor >= 0 {
            return try validatedDirectoryDescriptor(descriptor, unsafePath: unsafePath)
        }

        var metadata = stat()
        let inspectionResult = name.withCString {
            Darwin.fstatat(parentDescriptor, $0, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if inspectionResult == 0 {
            if isSymbolicLink(metadata), allowTrustedSystemRootSymlink {
                // macOS exposes /var and /tmp as immutable root-owned aliases.
                return try openTrustedSystemRootSymlink(
                    named: name,
                    metadata: metadata,
                    relativeTo: parentDescriptor,
                    unsafePath: unsafePath
                )
            }
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }
        guard errno == ENOENT else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }

        let creationResult = name.withCString {
            Darwin.mkdirat(parentDescriptor, $0, createdDirectoryMode)
        }
        guard creationResult == 0 || errno == EEXIST else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }

        let createdDescriptor = name.withCString {
            Darwin.openat(parentDescriptor, $0, directoryOpenFlags)
        }
        guard createdDescriptor >= 0 else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }
        return try validatedDirectoryDescriptor(createdDescriptor, unsafePath: unsafePath)
    }

    private static func openTrustedSystemRootSymlink(
        named name: String,
        metadata: stat,
        relativeTo rootDescriptor: Int32,
        unsafePath: String
    ) throws -> Int32 {
        var rootMetadata = stat()
        guard Darwin.fstat(rootDescriptor, &rootMetadata) == 0,
              isSecureSystemRoot(rootMetadata),
              metadata.st_uid == 0 else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }

        let descriptor = name.withCString {
            Darwin.openat(
                rootDescriptor,
                $0,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }
        return try validatedDirectoryDescriptor(descriptor, unsafePath: unsafePath)
    }

    private static func validatedDirectoryDescriptor(
        _ descriptor: Int32,
        unsafePath: String
    ) throws -> Int32 {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              isDirectory(metadata) else {
            Darwin.close(descriptor)
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }
        return descriptor
    }

    private static func enforceOwnerOnlyDestination(
        _ descriptor: Int32,
        mode: mode_t,
        unsafePath: String
    ) throws {
        guard mode & ~mode_t(0o777) == 0 else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              isDirectory(metadata),
              metadata.st_uid == geteuid(),
              Darwin.fchmod(descriptor, mode) == 0,
              Darwin.fstat(descriptor, &metadata) == 0,
              metadata.st_uid == geteuid(),
              metadata.st_mode & mode_t(0o777) == mode else {
            throw ProjectTemplateError.unsafeOutputPath(unsafePath)
        }
    }

    private static func writeRenderedContent(
        _ data: Data,
        finalName: String,
        relativePath: String,
        parentDescriptor: Int32,
        overwrite: Bool,
        outputFileMode: mode_t?
    ) throws {
        try validateExistingOutput(
            named: finalName,
            relativePath: relativePath,
            parentDescriptor: parentDescriptor,
            overwrite: overwrite
        )
        let temporaryFile = try createTemporaryFile(
            data,
            relativePath: relativePath,
            parentDescriptor: parentDescriptor,
            outputFileMode: outputFileMode
        )
        defer {
            if temporaryFile.shouldCleanup {
                temporaryFile.name.withCString {
                    _ = Darwin.unlinkat(parentDescriptor, $0, 0)
                }
            }
        }

        if overwrite {
            try publishAllowingOverwrite(
                temporaryFile,
                finalName: finalName,
                relativePath: relativePath,
                parentDescriptor: parentDescriptor
            )
        } else {
            try publishWithoutOverwrite(
                temporaryFile,
                finalName: finalName,
                relativePath: relativePath,
                parentDescriptor: parentDescriptor
            )
        }
    }

    private static func validateExistingOutput(
        named name: String,
        relativePath: String,
        parentDescriptor: Int32,
        overwrite: Bool
    ) throws {
        switch try outputNode(
            named: name,
            relativePath: relativePath,
            parentDescriptor: parentDescriptor
        ) {
        case .absent:
            return
        case .regular:
            if !overwrite {
                throw ProjectTemplateError.destinationExists(relativePath)
            }
        case .symbolicLink:
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        case .other:
            if overwrite {
                throw ProjectTemplateError.unsafeOutputPath(relativePath)
            }
            throw ProjectTemplateError.destinationExists(relativePath)
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
            if isSymbolicLink(metadata) {
                return .symbolicLink
            }
            if isRegularFile(metadata) {
                return .regular(FileIdentity(metadata))
            }
            return .other
        }
        guard errno == ENOENT else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }
        return .absent
    }

    private static func createTemporaryFile(
        _ data: Data,
        relativePath: String,
        parentDescriptor: Int32,
        outputFileMode: mode_t?
    ) throws -> TemporaryFile {
        for _ in 0..<16 {
            let name = ".cocxy-scaffold-\(UUID().uuidString).tmp"
            let descriptor = name.withCString {
                Darwin.openat(
                    parentDescriptor,
                    $0,
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                    mode_t(0o666)
                )
            }
            if descriptor < 0 {
                if errno == EEXIST { continue }
                throw ProjectTemplateError.unsafeOutputPath(relativePath)
            }

            var descriptorIsOpen = true
            do {
                try writeAll(data, to: descriptor, relativePath: relativePath)
                if let outputFileMode {
                    guard Darwin.fchmod(descriptor, outputFileMode) == 0 else {
                        throw ProjectTemplateError.unsafeOutputPath(relativePath)
                    }
                }
                var metadata = stat()
                guard Darwin.fstat(descriptor, &metadata) == 0,
                      isRegularFile(metadata) else {
                    throw ProjectTemplateError.unsafeOutputPath(relativePath)
                }
                if let outputFileMode,
                   metadata.st_mode & mode_t(0o777) != outputFileMode {
                    throw ProjectTemplateError.unsafeOutputPath(relativePath)
                }
                let closeResult = Darwin.close(descriptor)
                descriptorIsOpen = false
                guard closeResult == 0 else {
                    throw ProjectTemplateError.unsafeOutputPath(relativePath)
                }
                return TemporaryFile(name: name, identity: FileIdentity(metadata))
            } catch {
                if descriptorIsOpen { Darwin.close(descriptor) }
                name.withCString {
                    _ = Darwin.unlinkat(parentDescriptor, $0, 0)
                }
                throw error
            }
        }
        throw ProjectTemplateError.unsafeOutputPath(relativePath)
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
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    buffer.count - offset
                )
                if written < 0, errno == EINTR { continue }
                guard written > 0 else {
                    throw ProjectTemplateError.unsafeOutputPath(relativePath)
                }
                offset += written
            }
        }
    }

    private static func publishWithoutOverwrite(
        _ temporaryFile: TemporaryFile,
        finalName: String,
        relativePath: String,
        parentDescriptor: Int32
    ) throws {
        let renameResult = renameEntry(
            temporaryFile.name,
            to: finalName,
            relativeTo: parentDescriptor,
            flags: UInt32(RENAME_EXCL)
        )
        if renameResult == 0 {
            temporaryFile.shouldCleanup = false
            try verifyPublishedFile(
                named: finalName,
                identity: temporaryFile.identity,
                relativePath: relativePath,
                parentDescriptor: parentDescriptor
            )
            return
        }

        switch try outputNode(
            named: finalName,
            relativePath: relativePath,
            parentDescriptor: parentDescriptor
        ) {
        case .symbolicLink:
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        case .regular, .other:
            throw ProjectTemplateError.destinationExists(relativePath)
        case .absent:
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }
    }

    private static func publishAllowingOverwrite(
        _ temporaryFile: TemporaryFile,
        finalName: String,
        relativePath: String,
        parentDescriptor: Int32
    ) throws {
        for _ in 0..<4 {
            switch try outputNode(
                named: finalName,
                relativePath: relativePath,
                parentDescriptor: parentDescriptor
            ) {
            case .absent:
                do {
                    try publishWithoutOverwrite(
                        temporaryFile,
                        finalName: finalName,
                        relativePath: relativePath,
                        parentDescriptor: parentDescriptor
                    )
                    return
                } catch ProjectTemplateError.destinationExists {
                    continue
                }

            case .regular(let existingIdentity):
                let result = renameEntry(
                    temporaryFile.name,
                    to: finalName,
                    relativeTo: parentDescriptor,
                    flags: UInt32(RENAME_SWAP)
                )
                if result < 0, errno == ENOENT { continue }
                guard result == 0 else {
                    throw ProjectTemplateError.unsafeOutputPath(relativePath)
                }

                do {
                    let previousNode = try outputNode(
                        named: temporaryFile.name,
                        relativePath: relativePath,
                        parentDescriptor: parentDescriptor
                    )
                    let publishedNode = try outputNode(
                        named: finalName,
                        relativePath: relativePath,
                        parentDescriptor: parentDescriptor
                    )
                    guard previousNode == .regular(existingIdentity),
                          publishedNode == .regular(temporaryFile.identity) else {
                        throw ProjectTemplateError.unsafeOutputPath(relativePath)
                    }
                } catch {
                    let rollbackResult = renameEntry(
                        temporaryFile.name,
                        to: finalName,
                        relativeTo: parentDescriptor,
                        flags: UInt32(RENAME_SWAP)
                    )
                    if rollbackResult != 0 {
                        temporaryFile.shouldCleanup = false
                    }
                    throw error
                }

                let cleanupResult = temporaryFile.name.withCString {
                    Darwin.unlinkat(parentDescriptor, $0, 0)
                }
                guard cleanupResult == 0 else {
                    throw ProjectTemplateError.unsafeOutputPath(relativePath)
                }
                temporaryFile.shouldCleanup = false
                return

            case .symbolicLink, .other:
                throw ProjectTemplateError.unsafeOutputPath(relativePath)
            }
        }
        throw ProjectTemplateError.unsafeOutputPath(relativePath)
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

    private static func verifyPublishedFile(
        named name: String,
        identity: FileIdentity,
        relativePath: String,
        parentDescriptor: Int32
    ) throws {
        guard try outputNode(
            named: name,
            relativePath: relativePath,
            parentDescriptor: parentDescriptor
        ) == .regular(identity) else {
            throw ProjectTemplateError.unsafeOutputPath(relativePath)
        }
    }

    private static func isDirectory(_ metadata: stat) -> Bool {
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR)
    }

    private static func isRegularFile(_ metadata: stat) -> Bool {
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
    }

    private static func isSymbolicLink(_ metadata: stat) -> Bool {
        (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private static func isSecureSystemRoot(_ metadata: stat) -> Bool {
        isDirectory(metadata)
            && metadata.st_uid == 0
            && (metadata.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t

        init(_ metadata: stat) {
            self.device = metadata.st_dev
            self.inode = metadata.st_ino
        }
    }

    private enum OutputNode: Equatable {
        case absent
        case regular(FileIdentity)
        case symbolicLink
        case other
    }

    private final class TemporaryFile {
        let name: String
        let identity: FileIdentity
        var shouldCleanup = true

        init(name: String, identity: FileIdentity) {
            self.name = name
            self.identity = identity
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
