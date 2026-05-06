// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("NoteSpotlightScopePolicy")
struct NoteSpotlightScopePolicySwiftTestingTests {

    private final class PathBox: @unchecked Sendable {
        var value: String?
    }

    @Test(".cocxy-spotlight-ignore disables Spotlight search for that workspace root")
    func ignoreMarkerDisablesSearch() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(
                "cocxy-spotlight-policy-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let policy = NoteSpotlightScopePolicy()

        #expect(policy.allowsSpotlightSearch(in: root) == true)

        try Data().write(to: root.appendingPathComponent(NoteSpotlightScopePolicy.ignoreFileName))

        #expect(policy.allowsSpotlightSearch(in: root) == false)
    }

    @Test("policy checks the marker path after standardizing the workspace root")
    func markerPathUsesStandardizedWorkspaceRoot() {
        let box = PathBox()
        let policy = NoteSpotlightScopePolicy { url in
            box.value = url.path
            return false
        }
        let root = URL(fileURLWithPath: "/tmp/example/../workspace/")

        _ = policy.allowsSpotlightSearch(in: root)

        #expect(box.value?.hasSuffix("/workspace/\(NoteSpotlightScopePolicy.ignoreFileName)") == true)
        #expect(box.value?.contains("..") == false)
    }
}
