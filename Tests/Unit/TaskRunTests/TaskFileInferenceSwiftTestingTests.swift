// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task file inference")
struct TaskFileInferenceSwiftTestingTests {
    private let root = URL(fileURLWithPath: "/tmp/cocxy-inference", isDirectory: true)
    private let files = [
        "Sources/Auth/LoginService.swift",
        "Sources/Billing/LoginService.swift",
        "Sources/ProjectRegistryStore.swift",
        "Tests/ProjectRegistryStoreTests.swift",
        "README.md",
    ]

    @Test("explicit paths, quoted future files, and unique names are inferred")
    func infersDeterministicFileReferences() {
        let inferred = TaskFileInference.infer(
            prompt: "Update Sources/Auth/LoginService.swift and ProjectRegistryStore.swift, then create `Tests/NewFlowTests.swift`.",
            projectFiles: files,
            projectRoot: root
        )

        #expect(inferred == [
            "Sources/Auth/LoginService.swift",
            "Sources/ProjectRegistryStore.swift",
            "Tests/NewFlowTests.swift",
        ])
    }

    @Test("ambiguous basenames require a path-qualified reference")
    func rejectsAmbiguousBasenames() {
        let ambiguous = TaskFileInference.infer(
            prompt: "Update LoginService.swift",
            projectFiles: files,
            projectRoot: root
        )
        let qualified = TaskFileInference.infer(
            prompt: "Update Sources/Billing/LoginService.swift",
            projectFiles: files,
            projectRoot: root
        )

        #expect(ambiguous.isEmpty)
        #expect(qualified == ["Sources/Billing/LoginService.swift"])
    }

    @Test("directory references expand only to the bounded project catalog")
    func expandsReferencedDirectory() {
        let inferred = TaskFileInference.infer(
            prompt: "Audit Sources/Auth/",
            projectFiles: files,
            projectRoot: root
        )

        #expect(inferred == ["Sources/Auth/LoginService.swift"])
    }

    @Test("seed paths preserve known files without manual prompt hints")
    func preservesKnownSeedPaths() {
        let inferred = TaskFileInference.infer(
            prompt: "Continue the previous task",
            projectFiles: files,
            projectRoot: root,
            seedPaths: ["Tests/ProjectRegistryStoreTests.swift"]
        )

        #expect(inferred == ["Tests/ProjectRegistryStoreTests.swift"])
    }
}
