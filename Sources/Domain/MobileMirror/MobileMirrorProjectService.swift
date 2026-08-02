// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorProjectService.swift - Constrained local project creation.

import Darwin
import Foundation

protocol MobileMirrorProjectCreating: Sendable {
    func createProject(named name: String, in authorizedRoot: URL) async throws -> URL
}

struct MobileMirrorProjectService: MobileMirrorProjectCreating, Sendable {
    static let maximumNameUTF8Bytes = 160

    private let fileManager: FileManager
    private let gitExecutable: URL

    init(
        fileManager: FileManager = .default,
        gitExecutable: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        self.fileManager = fileManager
        self.gitExecutable = gitExecutable
    }

    func createProject(named rawName: String, in authorizedRoot: URL) async throws -> URL {
        let name = try normalizedProjectName(rawName)
        let root = authorizedRoot.standardizedFileURL
        try validateAuthorizedRoot(root)
        let destination = root.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        guard destination.deletingLastPathComponent() == root else {
            throw MobileMirrorError.invalidProjectName
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw MobileMirrorError.projectAlreadyExists
        }

        let staging = root
            .appendingPathComponent(".cocxy-project-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var stagingOwned = true
        defer {
            if stagingOwned {
                try? fileManager.removeItem(at: staging)
            }
        }

        let result = try await runGitInit(in: staging)
        guard result.exitCode == 0 else {
            let message = result.standardError
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MobileMirrorError.projectCreationFailed(
                message.isEmpty ? "git init exited with status \(result.exitCode)" : message
            )
        }
        var gitDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: staging.appendingPathComponent(".git", isDirectory: true).path,
            isDirectory: &gitDirectory
        ), gitDirectory.boolValue else {
            throw MobileMirrorError.projectCreationFailed("git did not create repository metadata")
        }
        do {
            try fileManager.moveItem(at: staging, to: destination)
            stagingOwned = false
            return destination
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                throw MobileMirrorError.projectAlreadyExists
            }
            throw MobileMirrorError.projectCreationFailed(error.localizedDescription)
        }
    }

    func normalizedProjectName(_ rawName: String) throws -> String {
        let name = rawName
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name.utf8.count <= Self.maximumNameUTF8Bytes,
              name != ".",
              name != "..",
              !name.hasPrefix("."),
              !name.hasSuffix("."),
              !name.contains("/"),
              !name.contains(":"),
              !name.contains("\0"),
              name.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .format, .lineSeparator, .paragraphSeparator:
                      return false
                  default:
                      return true
                  }
              }) else {
            throw MobileMirrorError.invalidProjectName
        }
        return name
    }

    private func validateAuthorizedRoot(_ root: URL) throws {
        var metadata = stat()
        let status = root.path.withCString { Darwin.lstat($0, &metadata) }
        guard status == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw MobileMirrorError.projectCreationUnavailable
        }
        let resolved = root.resolvingSymlinksInPath().standardizedFileURL
        guard resolved == root else {
            throw MobileMirrorError.projectCreationUnavailable
        }
    }

    private func runGitInit(in directory: URL) async throws -> GitResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let standardError = Pipe()
                process.executableURL = gitExecutable
                process.arguments = ["init", "--quiet", "--initial-branch=main", "--"]
                process.currentDirectoryURL = directory
                process.standardOutput = FileHandle.nullDevice
                process.standardError = standardError
                do {
                    try process.run()
                    process.waitUntilExit()
                    let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
                    let boundedError = Data(errorData.suffix(8 * 1_024))
                    continuation.resume(returning: GitResult(
                        exitCode: process.terminationStatus,
                        standardError: String(decoding: boundedError, as: UTF8.self)
                    ))
                } catch {
                    continuation.resume(throwing: MobileMirrorError.projectCreationFailed(
                        error.localizedDescription
                    ))
                }
            }
        }
    }
}

private struct GitResult: Sendable {
    let exitCode: Int32
    let standardError: String
}
