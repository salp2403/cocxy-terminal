// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing

@Suite("macOS floor verifier")
struct MacOSFloorVerifierSwiftTestingTests {
    @Test("a coordinated future floor passes and stale published text fails")
    func coordinatedFutureFloorPassesAndStalePublishedTextFails() throws {
        let fixture = try FloorFixture()
        defer { fixture.remove() }

        #expect(try runVerifier(fixture: fixture).isEmpty)

        try fixture.write(
            "web/public/press.html",
            "macOS 16+\nRequires macOS 15+\n"
        )
        let failures = try runVerifier(fixture: fixture)
        #expect(failures.contains {
            $0.contains("web/public/press.html contains stale floor reference: macOS 15+")
        })
    }

    @Test("pre-release update channels reject floor drift")
    func preReleaseUpdateChannelsRejectFloorDrift() throws {
        let fixture = try FloorFixture()
        defer { fixture.remove() }

        try fixture.write(
            ".github/workflows/nightly.yml",
            """
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            depends_on macos: \">= :tahoe\"
            """
        )
        try fixture.write(
            ".github/workflows/preview.yml",
            """
            <sparkle:minimumSystemVersion>16.0</sparkle:minimumSystemVersion>
            depends_on macos: \">= :sequoia\"
            """
        )

        let failures = try runVerifier(fixture: fixture)
        #expect(failures.contains { $0.hasPrefix("nightly workflow Sparkle minimum expected") })
        #expect(failures.contains { $0.hasPrefix("preview workflow cask minimum expected") })
    }

    @Test("public site verification invokes the macOS floor guard")
    func publicSiteVerificationInvokesMacOSFloorGuard() throws {
        let root = repositoryRoot()
        let testGate = try String(
            contentsOf: root.appendingPathComponent("scripts/run-tests.sh"),
            encoding: .utf8
        )
        let verifySite = try String(
            contentsOf: root.appendingPathComponent("web/scripts/verify-site.mjs"),
            encoding: .utf8
        )

        #expect(testGate.contains("web/scripts/verify-site.mjs"))
        #expect(verifySite.contains("for (const failure of verifyMacOSFloor({"))
        #expect(verifySite.contains("const swiftAgents = readUTF8("))
        #expect(verifySite.contains("const server = readUTF8("))
    }

    private func runVerifier(fixture: FloorFixture) throws -> [String] {
        let verifierURL = repositoryRoot()
            .appendingPathComponent("web/scripts/verify-macos-floor.mjs")
        let script = """
        import fs from 'node:fs';
        import path from 'node:path';
        import { pathToFileURL } from 'node:url';
        const verifierURL = process.argv[1];
        const repoRoot = process.argv[2];
        const webRoot = path.join(repoRoot, 'web');
        const { verifyMacOSFloor } = await import(pathToFileURL(verifierURL).href);
        const failures = verifyMacOSFloor({
          repoRoot,
          webRoot,
          homeContent: fs.readFileSync(path.join(webRoot, 'public/index.html'), 'utf8'),
          spanishHomeContent: fs.readFileSync(path.join(webRoot, 'public/es/index.html'), 'utf8'),
        });
        process.stdout.write(JSON.stringify(failures));
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "node",
            "--input-type=module",
            "--eval",
            script,
            verifierURL.path,
            fixture.root.path,
        ]
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: error, encoding: .utf8) ?? "Node verifier failed"
            Issue.record(Comment(rawValue: detail))
            return []
        }
        return try JSONDecoder().decode([String].self, from: output)
    }

    private func repositoryRoot() -> URL {
        var candidate = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while candidate.path != "/" {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("Package.swift").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        Issue.record("Unable to locate repository root")
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private struct FloorFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-macos-floor-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        try populate()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ relativePath: String, _ content: String) throws {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func populate() throws {
        try write("Package.swift", #"platforms: [.macOS("16.0")]"#)
        try write(
            "Resources/Info.plist",
            "<key>LSMinimumSystemVersion</key>\n<string>16.0</string>\n"
        )
        try write(
            "project.yml",
            """
              deploymentTarget:
                macOS: "16.0"
                deploymentTarget: "16.0"
                    MACOSX_DEPLOYMENT_TARGET: 16.0
            """
        )
        try write(
            ".github/workflows/release.yml",
            """
            <sparkle:minimumSystemVersion>16.0</sparkle:minimumSystemVersion>
            - macOS 16.0 (Tahoe) or later
            "operatingSystem": "macOS 16.0+"
            "operatingSystem": "macOS 16.0+"
            depends_on macos: ">= :tahoe"
            "macos 16"
            """
        )
        for channel in ["nightly", "preview"] {
            try write(
                ".github/workflows/\(channel).yml",
                """
                <sparkle:minimumSystemVersion>16.0</sparkle:minimumSystemVersion>
                depends_on macos: ">= :tahoe"
                """
            )
        }
        let plist = "<key>LSMinimumSystemVersion</key>\n<string>16.0</string>\n"
        try write("Distribution/Info.plist", plist)
        try write(
            "Distribution/Makefile",
            "<key>LSMinimumSystemVersion</key>\\\n<string>16.0</string>\n"
        )
        try write("Distribution/cocxy-terminal.rb", "depends_on macos: \">= :tahoe\"\n")
        try write("scripts/embed-pty-daemon-helper.sh", plist)
        try write(
            "web/scripts/build-site.mjs",
            """
            macOS 16.0+
            macOS 16.0+
            macOS 16.0+
            macOS 16+
            stat('16+', 'macOS')
            stat('16+', 'macOS')
            """
        )
        try write(
            "web/scripts/generate-releases-page.mjs",
            """
            operatingSystem: 'macOS 16.0+'
            operatingSystem: 'macOS 16.0+'
            """
        )
        let statistic = "<strong>16+</strong><span>macOS</span>"
        try write("web/preview/components.html", statistic)
        let homepage = "macOS 16.0+\nmacOS 16.0+\n\(statistic)\n"
        try write("web/public/index.html", homepage)
        try write("web/public/es/index.html", homepage)
        try write("web/public/releases.html", "macOS 16.0+\nmacOS 16.0+\n")
        try write("web/public/es/releases.html", "macOS 16.0+\nmacOS 16.0+\n")
        try write("web/public/press.html", "macOS 16+\n")
        try write("web/public/es/press.html", "macOS 16+\n")
        try write("web/public/llms.txt", "Platform: macOS 16.0+\n")
    }
}
