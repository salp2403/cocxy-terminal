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
            "macOS 26+\nRequires macOS 15+\n"
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
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            depends_on macos: \">= :sequoia\"
            """
        )

        let failures = try runVerifier(fixture: fixture)
        #expect(failures.contains { $0.hasPrefix("nightly workflow Sparkle minimum expected") })
        #expect(failures.contains { $0.hasPrefix("preview workflow cask minimum expected") })
    }

    @Test("the stale floor sweep discovers new files and honours its exclusions")
    func staleFloorSweepDiscoversNewFiles() throws {
        let fixture = try FloorFixture()
        defer { fixture.remove() }

        try fixture.write("web/public/download.html", "Requires macOS 15.0+ (Sequoia)\n")
        try fixture.write("web/preview/landing.html", "macOS 15+\n")
        try fixture.write("web/public/docs/install.html", "Requires macOS 15+\n")
        try fixture.write("CONTRIBUTING.md", "- macOS 15 Sequoia or later\n")
        try fixture.write("CHANGELOG.md", "- Dropped macOS 15 (Sequoia)\n")
        try fixture.write("docs/plan.md", "Requires macOS 15+\n")

        let failures = try runVerifier(fixture: fixture)
        for label in [
            "web/public/download.html",
            "web/preview/landing.html",
            "web/public/docs/install.html",
            "CONTRIBUTING.md",
        ] {
            #expect(failures.contains { $0.hasPrefix("\(label) contains stale floor") })
        }
        #expect(!failures.contains { $0.hasPrefix("CHANGELOG.md") || $0.hasPrefix("docs/") })
    }

    @Test("extra correct mentions pass while a stale README requirement fails")
    func extraCorrectMentionsPassAndReadmeIsGuarded() throws {
        let fixture = try FloorFixture()
        defer { fixture.remove() }

        try fixture.write("web/public/press.html", "macOS 26+\nAlso macOS 26+\n")
        #expect(try runVerifier(fixture: fixture).isEmpty)

        try fixture.write(
            "README.md",
            "[badge](https://img.shields.io/badge/macOS-15%2B-black.svg)\n- macOS 15.0 (Sequoia) or later\n"
        )
        let failures = try runVerifier(fixture: fixture)
        #expect(failures.contains { $0.hasPrefix("README system requirement expected at least 1") })
        #expect(failures.contains { $0.hasPrefix("README platform badge expected at least 1") })
    }

    @Test("the canonical test gate runs site verification before the Swift suites")
    func canonicalTestGateRunsSiteVerificationFirst() throws {
        let fixture = try FloorFixture()
        defer { fixture.remove() }
        let gate = try String(
            contentsOf: repositoryRoot().appendingPathComponent("scripts/run-tests.sh"),
            encoding: .utf8
        )
        try fixture.write("scripts/run-tests.sh", gate, executable: true)
        try fixture.write("web/scripts/build-site.mjs", markerScript("build-site"))
        try fixture.write(
            "web/scripts/verify-site.mjs",
            markerScript("verify-site") + "process.exit(Number(process.env.COCXY_STUB_STATUS ?? '0'));\n"
        )
        try fixture.write("bin/swift", "#!/bin/sh\ntouch swift.ran\n", executable: true)
        try fixture.write(
            "scripts/run-swift-testing-serial.sh",
            "#!/bin/sh\ntouch serial.ran\n",
            executable: true
        )

        let passing = try runGate(fixture: fixture, verifyStatus: "0")
        #expect(passing == 0)
        #expect(fixture.exists("verify-site.ran"))
        #expect(fixture.exists("swift.ran"))

        for marker in ["build-site.ran", "verify-site.ran", "swift.ran", "serial.ran"] {
            try? FileManager.default.removeItem(at: fixture.root.appendingPathComponent(marker))
        }
        let failing = try runGate(fixture: fixture, verifyStatus: "1")
        #expect(failing != 0)
        #expect(fixture.exists("verify-site.ran"))
        #expect(!fixture.exists("swift.ran"))
    }

    @Test("site verification reports macOS floor failures")
    func siteVerificationReportsFloorFailures() throws {
        let fixture = try FloorFixture()
        defer { fixture.remove() }
        for script in ["verify-site.mjs", "verify-macos-floor.mjs"] {
            let source = try String(
                contentsOf: repositoryRoot().appendingPathComponent("web/scripts/\(script)"),
                encoding: .utf8
            )
            try fixture.write("web/scripts/\(script)", source)
        }
        try fixture.write("web/public/press.html", "Requires macOS 15+\n")

        let result = try runProcess(["node", "web/scripts/verify-site.mjs"], in: fixture.root)

        #expect(result.status != 0)
        #expect(result.standardError.contains(
            "- web/public/press.html contains stale floor reference: macOS 15+"
        ))
    }

    private func markerScript(_ name: String) -> String {
        "import fs from 'node:fs';\nfs.writeFileSync('\(name).ran', '');\n"
    }

    private func runGate(fixture: FloorFixture, verifyStatus: String) throws -> Int32 {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = fixture.root.appendingPathComponent("bin").path
            + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["COCXY_STUB_STATUS"] = verifyStatus
        environment.removeValue(forKey: "NODE")
        return try runProcess(
            ["bash", "scripts/run-tests.sh"],
            in: fixture.root,
            environment: environment
        ).status
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

        let result = try runProcess(
            ["node", "--input-type=module", "--eval", script, verifierURL.path, fixture.root.path],
            in: fixture.root
        )
        guard result.status == 0 else {
            Issue.record(Comment(rawValue: result.standardError))
            return []
        }
        return try JSONDecoder().decode([String].self, from: Data(result.standardOutput.utf8))
    }

    private func runProcess(
        _ arguments: [String],
        in directory: URL,
        environment: [String: String]? = nil
    ) throws -> (status: Int32, standardOutput: String, standardError: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        if let environment { process.environment = environment }
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let error = standardError.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: output, as: UTF8.self),
            String(decoding: error, as: UTF8.self)
        )
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

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }

    func write(_ relativePath: String, _ content: String, executable: Bool = false) throws {
        let destination = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: destination, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: destination.path
            )
        }
    }

    private func populate() throws {
        try write("Package.swift", #"platforms: [.macOS("26.0")]"#)
        try write(
            "README.md",
            "[badge](https://img.shields.io/badge/macOS-26%2B-black.svg)\n- macOS 26.0 (Tahoe) or later\n"
        )
        try write(
            "Resources/Info.plist",
            "<key>LSMinimumSystemVersion</key>\n<string>26.0</string>\n"
        )
        try write(
            "project.yml",
            """
              deploymentTarget:
                macOS: "26.0"
                deploymentTarget: "26.0"
                    MACOSX_DEPLOYMENT_TARGET: 26.0
            """
        )
        try write(
            ".github/workflows/release.yml",
            """
            <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
            - macOS 26.0 (Tahoe) or later
            "operatingSystem": "macOS 26.0+"
            "operatingSystem": "macOS 26.0+"
            depends_on macos: ">= :tahoe"
            """
        )
        for channel in ["nightly", "preview"] {
            try write(
                ".github/workflows/\(channel).yml",
                """
                <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
                depends_on macos: ">= :tahoe"
                """
            )
        }
        let plist = "<key>LSMinimumSystemVersion</key>\n<string>26.0</string>\n"
        try write("Distribution/Info.plist", plist)
        try write(
            "Distribution/Makefile",
            "<key>LSMinimumSystemVersion</key>\\\n<string>26.0</string>\n"
        )
        try write("Distribution/cocxy-terminal.rb", "depends_on macos: \">= :tahoe\"\n")
        try write("scripts/embed-pty-daemon-helper.sh", plist)
        try write(
            "web/scripts/build-site.mjs",
            """
            macOS 26.0+
            macOS 26.0+
            macOS 26.0+
            macOS 26+
            stat('26+', 'macOS')
            stat('26+', 'macOS')
            """
        )
        try write(
            "web/scripts/generate-releases-page.mjs",
            """
            operatingSystem: 'macOS 26.0+'
            operatingSystem: 'macOS 26.0+'
            """
        )
        let statistic = "<strong>26+</strong><span>macOS</span>"
        try write("web/preview/components.html", statistic)
        let homepage = "macOS 26.0+\nmacOS 26.0+\n\(statistic)\n"
        try write("web/public/index.html", homepage)
        try write("web/public/es/index.html", homepage)
        try write("web/public/releases.html", "macOS 26.0+\nmacOS 26.0+\n")
        try write("web/public/es/releases.html", "macOS 26.0+\nmacOS 26.0+\n")
        try write("web/public/press.html", "macOS 26+\n")
        try write("web/public/es/press.html", "macOS 26+\n")
        try write("web/public/llms.txt", "Platform: macOS 26.0+\n")
    }
}
