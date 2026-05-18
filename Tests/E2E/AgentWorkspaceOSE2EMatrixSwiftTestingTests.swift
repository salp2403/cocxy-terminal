// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentWorkspaceOSE2EMatrixSwiftTestingTests.swift - Plan-level E2E matrix guardrails.

import Foundation
import Testing

@Suite("Agent Workspace OS E2E matrices")
struct AgentWorkspaceOSE2EMatrixSwiftTestingTests {
    @Test("matrix runner exposes nine required matrices and reports aggregate completion honestly")
    func matrixRunnerReportsAggregateCompletionHonestly() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-agent-workspace-e2e-matrices.sh")

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let list = try runProcess(scriptURL, arguments: ["--list"])
        #expect(list.terminationStatus == 0)
        let rows = list.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .map(String.init)
        #expect(rows.count == 9)

        for requiredMatrix in [
            "browser-automation",
            "remote-ssh-browser",
            "agent-team-launcher",
            "socket-security",
            "privacy-audit",
            "bundle-local-cli-smoke",
            "visual-screenshot",
            "performance-regressions",
            "config-import",
        ] {
            #expect(rows.contains { $0.hasPrefix("\(requiredMatrix)\t") })
        }

        let audit = try runProcess(scriptURL, arguments: ["--audit"])
        #expect(audit.stdout.contains("matrix-count=9"))
        #expect(audit.stdout.contains("matrix=browser-automation\tstatus=ok"))
        #expect(audit.stdout.contains("scenarios=95; target=80"))
        #expect(audit.stdout.contains("matrix=remote-ssh-browser\t"))
        #expect(audit.stdout.contains("matrix=agent-team-launcher\t"))
        #expect(audit.stdout.contains("matrix=visual-screenshot\tstatus=ok"))
        #expect(audit.stdout.contains("approved-golden-screenshots=20"))

        let lines = audit.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        if let remoteLine = lines.first(where: { $0.hasPrefix("matrix=remote-ssh-browser\t") }),
           remoteLine.contains("status=blocked"),
           remoteLine.contains("docker=daemon-unavailable"),
           let latestDockerSummary = latestFile(
            under: root.appendingPathComponent("build/remote-browser-docker-ssh"),
            named: "summary.txt"
           ) {
            let relativePath = latestDockerSummary.path
                .replacingOccurrences(of: root.path + "/", with: "")
            #expect(remoteLine.contains("evidence=\(relativePath)"))
        }

        let blockedCountLine = try #require(lines.first { $0.hasPrefix("blocked-count=") })
        let blockedCount = try #require(Int(blockedCountLine.replacingOccurrences(of: "blocked-count=", with: "")))

        if blockedCount == 0 {
            #expect(audit.terminationStatus == 0)
            #expect(lines.contains("status=complete"))
            #expect(!lines.contains("status=not-complete"))
        } else {
            #expect(audit.terminationStatus == 1)
            #expect(lines.contains("status=not-complete"))
            #expect(!lines.contains("status=complete"))
        }
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let package = url.appendingPathComponent("Package.swift")
            let scripts = url.appendingPathComponent("scripts")
            if FileManager.default.fileExists(atPath: package.path),
               FileManager.default.fileExists(atPath: scripts.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private func latestFile(under directory: URL, named fileName: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var matches: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == fileName {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                matches.append(fileURL)
            }
        }
        return matches.sorted { $0.path > $1.path }.first
    }

    private struct ProcessResult {
        let terminationStatus: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(_ executableURL: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            terminationStatus: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
