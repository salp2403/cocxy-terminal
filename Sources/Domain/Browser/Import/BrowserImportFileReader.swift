// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserImportFileReader.swift - Bounded, identity-stable browser data reads.

import Darwin
import Foundation

enum BrowserImportFileReader {
    private static let directoryOpenFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: time_t
        let modifiedNanoseconds: Int
        let changedSeconds: time_t
        let changedNanoseconds: Int

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
            size = metadata.st_size
            modifiedSeconds = metadata.st_mtimespec.tv_sec
            modifiedNanoseconds = metadata.st_mtimespec.tv_nsec
            changedSeconds = metadata.st_ctimespec.tv_sec
            changedNanoseconds = metadata.st_ctimespec.tv_nsec
        }
    }

    static func readData(from url: URL, maximumByteCount: Int) throws -> Data {
        guard maximumByteCount > 0 else {
            throw BrowserImportError.invalidSourceFile(url.path)
        }

        guard let data = try withRegularFileDescriptor(at: url, allowMissing: false, body: { descriptor in
            var initialMetadata = stat()
            guard Darwin.fstat(descriptor, &initialMetadata) == 0,
                  initialMetadata.st_size >= 0,
                  initialMetadata.st_size <= off_t(maximumByteCount) else {
                throw BrowserImportError.invalidSourceFile(url.path)
            }
            let initialIdentity = Identity(initialMetadata)

            var data = Data()
            data.reserveCapacity(Int(initialMetadata.st_size))
            var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
            while true {
                try Task.checkCancellation()
                let count = buffer.withUnsafeMutableBytes {
                    Darwin.read(descriptor, $0.baseAddress, $0.count)
                }
                if count < 0, errno == EINTR { continue }
                guard count >= 0 else {
                    throw BrowserImportError.invalidSourceFile(url.path)
                }
                if count == 0 { break }
                guard count <= maximumByteCount - data.count else {
                    throw BrowserImportError.invalidSourceFile(url.path)
                }
                data.append(contentsOf: buffer.prefix(count))
            }

            var finalMetadata = stat()
            guard Darwin.fstat(descriptor, &finalMetadata) == 0,
                  Identity(finalMetadata) == initialIdentity,
                  data.count == Int(initialMetadata.st_size) else {
                throw BrowserImportError.sourceChangedDuringRead(url.path)
            }
            return data
        }) else {
            throw BrowserImportError.invalidSourceFile(url.path)
        }
        return data
    }

    static func isRegularFile(at url: URL) -> Bool {
        do {
            return try withRegularFileDescriptor(at: url, allowMissing: true) { _ in true } ?? false
        } catch {
            return false
        }
    }

    /// Opens an absolute path one directory component at a time. This keeps
    /// symbolic-link swaps in any parent component from redirecting an
    /// approved browser-data read after authorization.
    static func withRegularFileDescriptor<T>(
        at url: URL,
        allowMissing: Bool,
        body: (Int32) throws -> T
    ) throws -> T? {
        let path = url.path
        let pathToOpen = normalizedMacOSRootAlias(in: path)
        guard url.isFileURL,
              path.hasPrefix("/"),
              !path.contains("\0") else {
            throw BrowserImportError.invalidSourceFile(path)
        }
        let components = pathToOpen.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy(isSafePathComponent) else {
            throw BrowserImportError.invalidSourceFile(path)
        }

        var parentDescriptor = "/".withCString {
            Darwin.open($0, directoryOpenFlags)
        }
        guard parentDescriptor >= 0 else {
            throw BrowserImportError.invalidSourceFile(path)
        }

        for component in components.dropLast() {
            let nextDescriptor = component.withCString {
                Darwin.openat(parentDescriptor, $0, directoryOpenFlags)
            }
            if nextDescriptor < 0 {
                let openError = errno
                Darwin.close(parentDescriptor)
                if allowMissing, openError == ENOENT { return nil }
                throw BrowserImportError.invalidSourceFile(path)
            }
            Darwin.close(parentDescriptor)
            parentDescriptor = nextDescriptor
        }

        let finalDescriptor = components[components.count - 1].withCString {
            Darwin.openat(parentDescriptor, $0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        let openError = errno
        Darwin.close(parentDescriptor)
        if finalDescriptor < 0 {
            if allowMissing, openError == ENOENT { return nil }
            throw BrowserImportError.invalidSourceFile(path)
        }
        defer { Darwin.close(finalDescriptor) }

        var metadata = stat()
        guard Darwin.fstat(finalDescriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw BrowserImportError.invalidSourceFile(path)
        }
        return try body(finalDescriptor)
    }

    private static func isSafePathComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func normalizedMacOSRootAlias(in path: String) -> String {
        for (alias, destination) in [
            ("/var", "/private/var"),
            ("/tmp", "/private/tmp"),
            ("/etc", "/private/etc"),
        ] {
            if path == alias { return destination }
            if path.hasPrefix(alias + "/") {
                return destination + path.dropFirst(alias.count)
            }
        }
        return path
    }
}
