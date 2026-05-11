// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing

@Suite("Update channel workflows")
struct ChannelWorkflowSwiftTestingTests {

    @Test("stable release workflow does not consume preview tags")
    func stableReleaseWorkflowDoesNotConsumePreviewTags() throws {
        let workflow = try workflowContents("release.yml")

        #expect(workflow.contains("if: ${{ !contains(github.ref_name, '-preview.') }}"))
        #expect(workflow.contains("./scripts/build-app.sh release --version \"$VERSION\""))
        #expect(!workflow.contains("--channel preview"))
    }

    @Test("preview workflow builds preview app and publishes preview appcast")
    func previewWorkflowBuildsPreviewAppAndPublishesPreviewAppcast() throws {
        let workflow = try workflowContents("preview.yml")

        #expect(workflow.contains("tags:"))
        #expect(workflow.contains("'v*-preview.*'"))
        #expect(workflow.contains("./scripts/build-app.sh release --version \"$VERSION\" --channel preview"))
        #expect(workflow.contains("mv build/CocxyTerminalPreview.app \"$APP_DIR\""))
        #expect(workflow.contains("https://cocxy.dev/appcast-preview.xml"))
        #expect(workflow.contains("build/appcast-preview.xml"))
        #expect(workflow.contains("prerelease: true"))
    }

    @Test("nightly workflow builds nightly app and publishes nightly appcast")
    func nightlyWorkflowBuildsNightlyAppAndPublishesNightlyAppcast() throws {
        let workflow = try workflowContents("nightly.yml")

        #expect(workflow.contains("./scripts/build-app.sh release --version \"$VERSION\" --channel nightly"))
        #expect(workflow.contains("mv build/CocxyTerminalNightly.app \"$APP_DIR\""))
        #expect(workflow.contains("https://cocxy.dev/appcast-nightly.xml"))
        #expect(workflow.contains("build/appcast-nightly.xml"))
    }

    @Test("build script validates channel-specific versions")
    func buildScriptValidatesChannelSpecificVersions() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )

        #expect(script.contains("EXPECTED_VERSION=\"X.Y.Z-preview.N\""))
        #expect(script.contains("EXPECTED_VERSION=\"X.Y.Z-nightly.YYYYMMDD\""))
        #expect(script.contains("Invalid --version '${VERSION_OVERRIDE}' for ${CHANNEL} channel"))
    }

    private func workflowContents(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try String(
            contentsOf: root.appendingPathComponent(".github/workflows/\(name)"),
            encoding: .utf8
        )
    }
}
