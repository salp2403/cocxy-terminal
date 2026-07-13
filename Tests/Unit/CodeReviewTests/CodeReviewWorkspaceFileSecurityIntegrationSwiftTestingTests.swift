// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Code Review workspace file security integration")
struct CodeReviewWorkspaceFileSecurityIntegrationSwiftTestingTests {
    @Test("editor open rejects an intermediate symlink")
    func editorOpenRejectsIntermediateSymlink() throws {
        let fixture = try makeReviewSecurityFixture(named: "editor-open")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let outsideTarget = fixture.outside.appendingPathComponent("Secret.swift")
        try "outside secret\n".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: fixture.root.appendingPathComponent("Sources").path,
            withDestinationPath: fixture.outside.path
        )

        let viewModel = makeReviewViewModel(root: fixture.root)
        viewModel.openFileInEditor("Sources/Secret.swift")

        #expect(viewModel.isEditorVisible == false)
        #expect(viewModel.editorContent.isEmpty)
        #expect(viewModel.editorFilePath == nil)
        #expect(viewModel.editorErrorMessage?.contains("symbolic link") == true)
    }

    @Test("editor save rejects a parent swapped to an outside symlink")
    func editorSaveRejectsSwappedParent() throws {
        let fixture = try makeReviewSecurityFixture(named: "editor-save")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let sources = fixture.root.appendingPathComponent("Sources", isDirectory: true)
        let retained = fixture.root.appendingPathComponent("Sources-retained", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let insideTarget = sources.appendingPathComponent("App.swift")
        let outsideTarget = fixture.outside.appendingPathComponent("App.swift")
        try "inside\n".write(to: insideTarget, atomically: true, encoding: .utf8)
        try "outside\n".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let viewModel = makeReviewViewModel(root: fixture.root)
        viewModel.openFileInEditor("Sources/App.swift")
        #expect(viewModel.editorContent == "inside\n")
        viewModel.editorContent = "editor replacement\n"

        try FileManager.default.moveItem(at: sources, to: retained)
        try FileManager.default.createSymbolicLink(
            atPath: sources.path,
            withDestinationPath: fixture.outside.path
        )
        viewModel.saveEditorContent()

        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "outside\n")
        #expect(
            try String(contentsOf: retained.appendingPathComponent("App.swift"), encoding: .utf8) == "inside\n"
        )
        #expect(viewModel.isEditorDirty)
        #expect(viewModel.editorErrorMessage?.contains("symbolic link") == true)
    }

    @Test("editor save rejects a concurrently replaced file with localized guidance")
    func editorSaveRejectsStaleFileInSpanish() throws {
        let bundle = try #require(reviewLocalizationBundle())
        let fixture = try makeReviewSecurityFixture(named: "editor-stale")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let target = fixture.root.appendingPathComponent("App.swift")
        try "original\n".write(to: target, atomically: true, encoding: .utf8)
        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            localizer: AppLocalizer(languagePreference: .spanish, bundle: bundle)
        )
        viewModel.activeTabCwdProvider = { fixture.root }
        viewModel.openFileInEditor("App.swift")
        viewModel.editorContent = "editor replacement\n"

        try "concurrent replacement\n".write(to: target, atomically: true, encoding: .utf8)
        viewModel.saveEditorContent()

        #expect(try String(contentsOf: target, encoding: .utf8) == "concurrent replacement\n")
        #expect(viewModel.isEditorDirty)
        #expect(
            viewModel.editorErrorMessage ==
                "El archivo cambió en el disco. Recárgalo antes de guardar o aplicar sugerencias."
        )
    }

    @Test("suggestions reject an intermediate symlink before planning")
    func suggestionsRejectExistingIntermediateSymlink() throws {
        let fixture = try makeReviewSecurityFixture(named: "suggestion-existing-link")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let outsideTarget = fixture.outside.appendingPathComponent("App.swift")
        try "let enabled = false\n".write(to: outsideTarget, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: fixture.root.appendingPathComponent("Sources").path,
            withDestinationPath: fixture.outside.path
        )

        let viewModel = makeReviewViewModel(root: fixture.root)
        addSuggestion(
            to: viewModel,
            filePath: "Sources/App.swift",
            replacement: "let enabled = true"
        )
        viewModel.applyPendingSuggestions()

        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "let enabled = false\n")
        #expect(viewModel.pendingSuggestionCount == 1)
        #expect(viewModel.pendingComments.count == 1)
        #expect(viewModel.lastErrorMessage?.contains("symbolic link") == true)
        #expect(viewModel.lastInfoMessage == nil)
    }

    @Test("multi-file suggestions roll back when a parent swaps after planning")
    func suggestionsRollbackAfterControlledParentSwap() throws {
        let fixture = try makeReviewSecurityFixture(named: "suggestion-swap")
        defer { try? FileManager.default.removeItem(at: fixture.container) }
        let firstTarget = fixture.root.appendingPathComponent("A.swift")
        let secondDirectory = fixture.root.appendingPathComponent("Second", isDirectory: true)
        let retainedDirectory = fixture.root.appendingPathComponent("Second-retained", isDirectory: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let secondTarget = secondDirectory.appendingPathComponent("B.swift")
        let outsideTarget = fixture.outside.appendingPathComponent("B.swift")
        try "let first = false\n".write(to: firstTarget, atomically: true, encoding: .utf8)
        try "let second = false\n".write(to: secondTarget, atomically: true, encoding: .utf8)
        try "let second = false\n".write(to: outsideTarget, atomically: true, encoding: .utf8)

        let viewModel = makeReviewViewModel(root: fixture.root)
        addSuggestion(to: viewModel, filePath: "A.swift", replacement: "let first = true")
        addSuggestion(to: viewModel, filePath: "Second/B.swift", replacement: "let second = true")
        viewModel.suggestionPlansPreparedTestHandler = {
            try? FileManager.default.moveItem(at: secondDirectory, to: retainedDirectory)
            try? FileManager.default.createSymbolicLink(
                atPath: secondDirectory.path,
                withDestinationPath: fixture.outside.path
            )
        }

        viewModel.applyPendingSuggestions()

        #expect(try String(contentsOf: firstTarget, encoding: .utf8) == "let first = false\n")
        #expect(try String(contentsOf: outsideTarget, encoding: .utf8) == "let second = false\n")
        #expect(
            try String(contentsOf: retainedDirectory.appendingPathComponent("B.swift"), encoding: .utf8) ==
                "let second = false\n"
        )
        #expect(viewModel.pendingSuggestionCount == 2)
        #expect(viewModel.pendingComments.count == 2)
        #expect(viewModel.lastErrorMessage?.contains("symbolic link") == true)
        #expect(viewModel.lastInfoMessage == nil)
    }
}

@MainActor
private func makeReviewViewModel(root: URL) -> CodeReviewPanelViewModel {
    let viewModel = CodeReviewPanelViewModel(
        tracker: SessionDiffTrackerImpl(),
        hookEventReceiver: nil
    )
    viewModel.activeTabCwdProvider = { root }
    return viewModel
}

@MainActor
private func addSuggestion(
    to viewModel: CodeReviewPanelViewModel,
    filePath: String,
    replacement: String
) {
    viewModel.addComment(
        filePath: filePath,
        line: 1,
        body: """
        ```suggestion
        \(replacement)
        ```
        """
    )
}

private func makeReviewSecurityFixture(
    named name: String
) throws -> (container: URL, root: URL, outside: URL) {
    let container = FileManager.default.temporaryDirectory
        .appendingPathComponent("code-review-security-\(name)-\(UUID().uuidString)", isDirectory: true)
    let root = container.appendingPathComponent("workspace", isDirectory: true)
    let outside = container.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    return (container, root, outside)
}

private func reviewLocalizationBundle() -> Bundle? {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
}
