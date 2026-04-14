// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewGit.swift - Shared git process helpers for code review services.

import Foundation

struct CodeReviewGitResult: Sendable {
    let stdout: String
    let stderr: String
    let terminationStatus: Int32
}

private final class CodeReviewGitDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func store(_ data: Data) {
        lock.lock()
        storage = data
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum CodeReviewGit {
    private static let fallbackGitPaths = [
        "/opt/homebrew/bin/git",
        "/usr/local/bin/git",
        "/usr/bin/git",
        "/bin/git",
    ]

    static func resolveGitExecutableURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates: [String] = []

        if let path = environment["PATH"], !path.isEmpty {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/git" })
        }
        candidates.append(contentsOf: fallbackGitPaths)

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            guard fileManager.isExecutableFile(atPath: candidate) else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    static func run(
        workingDirectory: URL,
        arguments: [String],
        stdin: Data? = nil,
        gitExecutableURLOverride: URL? = nil
    ) throws -> CodeReviewGitResult {
        guard let gitURL = gitExecutableURLOverride ?? resolveGitExecutableURL() else {
            throw HunkActionError.gitUnavailable
        }

        let process = Process()
        process.executableURL = gitURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBox = CodeReviewGitDataBox()
        let stderrBox = CodeReviewGitDataBox()
        let readGroup = DispatchGroup()
        let readQueue = DispatchQueue.global(qos: .userInitiated)

        readGroup.enter()
        readQueue.async {
            stdoutBox.store(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        readGroup.enter()
        readQueue.async {
            stderrBox.store(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            readGroup.leave()
        }

        let stdinPipe = stdin.map { _ in Pipe() }
        if let stdin {
            process.standardInput = stdinPipe
            do {
                try process.run()
            } catch {
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                try? stdinPipe?.fileHandleForWriting.close()
                readGroup.wait()
                throw error
            }
            if !stdin.isEmpty {
                stdinPipe?.fileHandleForWriting.write(stdin)
            }
            try? stdinPipe?.fileHandleForWriting.close()
        } else {
            do {
                try process.run()
            } catch {
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                readGroup.wait()
                throw error
            }
        }

        process.waitUntilExit()
        readGroup.wait()

        return CodeReviewGitResult(
            stdout: String(decoding: stdoutBox.data, as: UTF8.self),
            stderr: String(decoding: stderrBox.data, as: UTF8.self),
            terminationStatus: process.terminationStatus
        )
    }
}
