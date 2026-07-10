// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginPackageSignaturePayload.swift - Canonical full-package plugin signature payload.

import Darwin
import Foundation

public enum PluginPackageSignaturePayloadError: Error, Equatable, Sendable {
    case invalidManifestName(String)
    case missingManifest(String)
    case directoryEnumerationFailed(String)
    case unsupportedEntry(String)
    case unreadableFile(String)
    case invalidManifestEncoding
    case tooManyFiles(Int)
    case payloadTooLarge(Int)
}

extension PluginPackageSignaturePayloadError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidManifestName(let name):
            return "Invalid plugin manifest name: \(name)."
        case .missingManifest(let name):
            return "Plugin package is missing \(name)."
        case .directoryEnumerationFailed(let reason):
            return "Could not enumerate plugin package: \(reason)."
        case .unsupportedEntry(let path):
            return "Plugin package contains an unsupported entry: \(path)."
        case .unreadableFile(let path):
            return "Plugin package file could not be read safely: \(path)."
        case .invalidManifestEncoding:
            return "Plugin manifest must use UTF-8 encoding."
        case .tooManyFiles(let limit):
            return "Plugin package exceeds the \(limit)-file signature limit."
        case .payloadTooLarge(let limit):
            return "Plugin package exceeds the \(limit)-byte signature limit."
        }
    }
}

/// Builds a deterministic payload over every regular file that can ship with
/// a plugin. The embedded signature fields and generic sidecar are excluded to
/// avoid signing the signature itself; executable event scripts remain covered.
public enum PluginPackageSignaturePayload {
    public static let maxFileCount = 10_000
    public static let maxPayloadBytes = 64 * 1_024 * 1_024

    private static let sidecarFileName = ".cocxy-signature.json"
    private static let signatureKeys: Set<String> = [
        "signature",
        "signature-algorithm",
        "signature-key-id",
        "signature-author",
        "signature-timestamp",
        "signature-payload-sha256",
    ]

    public static func payload(
        at directoryURL: URL,
        manifestFileName: String = "cocxy-plugin.toml",
        fileManager: FileManager = .default
    ) throws -> Data {
        guard !manifestFileName.isEmpty,
              !manifestFileName.contains("/"),
              manifestFileName != ".",
              manifestFileName != ".."
        else {
            throw PluginPackageSignaturePayloadError.invalidManifestName(manifestFileName)
        }

        let root = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw PluginPackageSignaturePayloadError.directoryEnumerationFailed(
                "package root is not a directory"
            )
        }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        var enumerationFailure: String?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { url, error in
                enumerationFailure = "\(url.lastPathComponent): \(error.localizedDescription)"
                return false
            }
        ) else {
            throw PluginPackageSignaturePayloadError.directoryEnumerationFailed(
                "could not create directory enumerator"
            )
        }

        var entries: [(path: String, url: URL)] = []
        var sawManifest = false
        while let entryURL = enumerator.nextObject() as? URL {
            let relativePath = try relativePath(for: entryURL, under: root)
            if relativePath == ".git" {
                enumerator.skipDescendants()
                continue
            }
            if relativePath.hasPrefix(".git/") || relativePath == sidecarFileName {
                continue
            }

            let values: URLResourceValues
            do {
                values = try entryURL.resourceValues(forKeys: keys)
            } catch {
                throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                throw PluginPackageSignaturePayloadError.unsupportedEntry(relativePath)
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw PluginPackageSignaturePayloadError.unsupportedEntry(relativePath)
            }

            entries.append((relativePath, entryURL))
            if entries.count > maxFileCount {
                throw PluginPackageSignaturePayloadError.tooManyFiles(maxFileCount)
            }
            if relativePath == manifestFileName {
                sawManifest = true
            }
        }

        if let enumerationFailure {
            throw PluginPackageSignaturePayloadError.directoryEnumerationFailed(
                enumerationFailure
            )
        }

        guard sawManifest else {
            throw PluginPackageSignaturePayloadError.missingManifest(manifestFileName)
        }

        entries.sort {
            $0.path.utf8.lexicographicallyPrecedes($1.path.utf8)
        }

        var result = Data("cocxy-plugin-package-v1\0".utf8)
        for entry in entries {
            let remainingBudget = maxPayloadBytes - result.count
            guard remainingBudget > 0 else {
                throw PluginPackageSignaturePayloadError.payloadTooLarge(maxPayloadBytes)
            }
            var contents = try readRegularFile(
                at: entry.url,
                relativePath: entry.path,
                maxBytes: remainingBudget
            )
            if entry.path == manifestFileName {
                guard let manifest = String(data: contents, encoding: .utf8) else {
                    throw PluginPackageSignaturePayloadError.invalidManifestEncoding
                }
                contents = canonicalManifestPayload(from: manifest)
            }

            let pathBytes = Data(entry.path.utf8)
            let recordSize = MemoryLayout<UInt32>.size
                + pathBytes.count
                + MemoryLayout<UInt64>.size
                + contents.count
            guard recordSize <= maxPayloadBytes - result.count else {
                throw PluginPackageSignaturePayloadError.payloadTooLarge(maxPayloadBytes)
            }

            appendBigEndian(UInt32(pathBytes.count), to: &result)
            result.append(pathBytes)
            appendBigEndian(UInt64(contents.count), to: &result)
            result.append(contents)
        }
        return result
    }

    public static func canonicalManifestPayload(from content: String) -> Data {
        var lines = content.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let separator = trimmed.firstIndex(of: "=") else { return true }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            return !signatureKeys.contains(key)
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func relativePath(for url: URL, under root: URL) throws -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else {
            throw PluginPackageSignaturePayloadError.unsupportedEntry(path)
        }
        let relative = String(path.dropFirst(rootPath.count))
        guard !relative.isEmpty,
              !relative.hasPrefix("/"),
              !relative.split(separator: "/").contains("..")
        else {
            throw PluginPackageSignaturePayloadError.unsupportedEntry(relative)
        }
        return relative
    }

    private static func readRegularFile(
        at url: URL,
        relativePath: String,
        maxBytes: Int
    ) throws -> Data {
        let descriptor = url.path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
        }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_size >= 0
        else {
            throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
        }
        guard metadata.st_size <= off_t(maxBytes) else {
            throw PluginPackageSignaturePayloadError.payloadTooLarge(maxPayloadBytes)
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0, errno == EINTR {
                continue
            }
            guard count >= 0 else {
                throw PluginPackageSignaturePayloadError.unreadableFile(relativePath)
            }
            if count == 0 {
                break
            }
            guard count <= maxBytes - data.count else {
                throw PluginPackageSignaturePayloadError.payloadTooLarge(maxPayloadBytes)
            }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
