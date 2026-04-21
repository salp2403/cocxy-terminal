// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CodeReview Git workflow")
struct CodeReviewGitWorkflowSwiftTestingTests {

    @Test("parsePorcelainStatus counts staged, unstaged, untracked, ahead and behind")
    func parsePorcelainStatusCountsEverything() {
        let parsed = CodeReviewGitWorkflowService.parsePorcelainStatus(
            """
            ## main...origin/main [ahead 2, behind 1]
             M unstaged.swift
            M  staged.swift
            ?? new.swift
            """
        )

        #expect(parsed.staged == 1)
        #expect(parsed.unstaged == 1)
        #expect(parsed.untracked == 1)
        #expect(parsed.ahead == 2)
        #expect(parsed.behind == 1)
    }

    @Test("sanitizedBranchName rejects unsafe branch names")
    func sanitizedBranchNameRejectsUnsafeNames() throws {
        #expect(throws: HunkActionError.self) {
            try CodeReviewGitWorkflowService.sanitizedBranchName("../bad")
        }
        #expect(throws: HunkActionError.self) {
            try CodeReviewGitWorkflowService.sanitizedBranchName("bad branch")
        }
        let sanitized = try CodeReviewGitWorkflowService.sanitizedBranchName("feature/review-panel")
        #expect(sanitized == "feature/review-panel")
    }

    @Test("workflow creates branches and commits all changes")
    func workflowCreatesBranchesAndCommits() throws {
        let repo = try makeGitWorkflowRepo()
        let workflow = CodeReviewGitWorkflowService()

        try workflow.createBranch(named: "feature/review-panel", workingDirectory: repo)
        try "changed\n".write(
            to: repo.appendingPathComponent("file.swift"),
            atomically: true,
            encoding: .utf8
        )

        let before = try workflow.status(workingDirectory: repo)
        #expect(before.branch == "feature/review-panel")
        #expect(before.changedCount == 1)

        _ = try workflow.commitAll(message: "Update file", workingDirectory: repo)
        let after = try workflow.status(workingDirectory: repo)
        #expect(after.changedCount == 0)
    }
}

@MainActor
@Suite("CodeReview inline editor")
struct CodeReviewInlineEditorSwiftTestingTests {

    @Test("languageName detects common programming languages")
    func languageNameDetectsExtensions() {
        #expect(CodeReviewPanelViewModel.languageName(for: "Sources/App.swift") == "Swift")
        #expect(CodeReviewPanelViewModel.languageName(for: "src/main.zig") == "Zig")
        #expect(CodeReviewPanelViewModel.languageName(for: "README.md") == "Markdown")
        #expect(CodeReviewPanelViewModel.languageName(for: "unknown.nope") == "Plain Text")
    }

    @Test("syntax highlighter colors language tokens")
    func syntaxHighlighterColorsLanguageTokens() {
        let highlighted = CodeReviewSyntaxHighlighter.highlighted(
            "public function index(Request $request) { return true; }\n",
            language: "PHP",
            fontSize: 13
        )

        let text = highlighted.string as NSString
        let functionRange = text.range(of: "function")
        let variableRange = text.range(of: "$request")

        #expect(highlighted.attribute(.foregroundColor, at: functionRange.location, effectiveRange: nil) as? NSColor == CocxyColors.mauve)
        #expect(highlighted.attribute(.foregroundColor, at: variableRange.location, effectiveRange: nil) as? NSColor == CocxyColors.blue)
    }

    @Test("editor sizing and Git workflow visibility are controlled by the view model")
    func editorSizingAndGitWorkflowVisibilityAreControlledByViewModel() {
        let viewModel = CodeReviewPanelViewModel(tracker: SessionDiffTrackerImpl(), hookEventReceiver: nil)

        #expect(viewModel.isGitWorkflowVisible == false)
        viewModel.toggleGitWorkflowVisibility()
        #expect(viewModel.isGitWorkflowVisible == true)

        viewModel.adjustEditorHeight(by: 10_000)
        #expect(viewModel.editorHeight == 900)
        viewModel.adjustEditorHeight(by: -10_000)
        #expect(viewModel.editorHeight == 240)

        viewModel.adjustEditorFontSize(by: 100)
        #expect(viewModel.editorFontSize == 22)
        viewModel.adjustEditorFontSize(by: -100)
        #expect(viewModel.editorFontSize == 10)

        #expect(viewModel.isEditorExpanded == false)
        viewModel.toggleEditorExpanded()
        #expect(viewModel.isEditorExpanded == true)

        #expect(viewModel.editorSplitLayout == .stacked)
        viewModel.editorSplitLayout = .sideBySide
        #expect(viewModel.editorSplitLayout == .sideBySide)

        viewModel.setEditorSplitFraction(0.95)
        #expect(viewModel.editorSplitFraction == 0.72)
        viewModel.setEditorSplitFraction(0.05)
        #expect(viewModel.editorSplitFraction == 0.28)

        viewModel.requestEditorUndo()
        let undo = viewModel.editorCommandToken
        #expect(undo?.kind == .undo)
        viewModel.requestEditorRedo()
        #expect(viewModel.editorCommandToken?.kind == .redo)
        #expect(viewModel.editorCommandToken?.id != undo?.id)
    }

    @Test("openSelectedFileInEditor loads, tracks dirty state and saves")
    func editorLoadsAndSavesSelectedFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeReviewEditor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("Example.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                [FileDiff(filePath: "Example.swift", status: .modified, hunks: [])]
            }
        )
        viewModel.activeTabCwdProvider = { root }
        viewModel.refreshDiffs()
        try await waitForEditorCondition {
            viewModel.selectedFileDiff?.filePath == "Example.swift"
        }

        viewModel.openSelectedFileInEditor()
        #expect(viewModel.editorLanguage == "Swift")
        #expect(viewModel.editorContent == "let value = 1\n")
        #expect(viewModel.isEditorDirty == false)

        viewModel.editorContent = "let value = 2\n"
        #expect(viewModel.isEditorDirty)

        viewModel.saveEditorContent()
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "let value = 2\n")
        #expect(viewModel.isEditorDirty == false)
    }

    @Test("dirty editor prompts before switching files and can save or discard")
    func dirtyEditorPromptsBeforeSwitchingFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodeReviewEditorSwitch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstURL = root.appendingPathComponent("First.swift")
        let secondURL = root.appendingPathComponent("Second.swift")
        try "let first = 1\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "let second = 2\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                [
                    FileDiff(filePath: "First.swift", status: .modified, hunks: []),
                    FileDiff(filePath: "Second.swift", status: .modified, hunks: []),
                ]
            }
        )
        viewModel.activeTabCwdProvider = { root }
        viewModel.refreshDiffs()
        try await waitForEditorCondition {
            viewModel.currentDiffs.count == 2
        }

        viewModel.selectFile("First.swift")
        viewModel.openSelectedFileInEditor()
        viewModel.editorContent = "let first = 10\n"
        viewModel.selectFile("Second.swift")

        #expect(viewModel.pendingEditorSwitch?.targetFilePath == "Second.swift")
        #expect(viewModel.editorFilePath == "First.swift")

        viewModel.cancelEditorFileSwitch()
        #expect(viewModel.pendingEditorSwitch == nil)
        #expect(viewModel.editorFilePath == "First.swift")

        viewModel.selectFile("Second.swift")
        viewModel.saveAndSwitchEditorFile()
        #expect(try String(contentsOf: firstURL, encoding: .utf8) == "let first = 10\n")
        #expect(viewModel.selectedFilePath == "Second.swift")
        #expect(viewModel.editorFilePath == "Second.swift")
        #expect(viewModel.editorContent == "let second = 2\n")

        viewModel.editorContent = "let second = 20\n"
        viewModel.selectFile("First.swift")
        viewModel.discardAndSwitchEditorFile()
        #expect(try String(contentsOf: secondURL, encoding: .utf8) == "let second = 2\n")
        #expect(viewModel.selectedFilePath == "First.swift")
        #expect(viewModel.editorFilePath == "First.swift")
    }
}

private func makeGitWorkflowRepo() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CodeReviewGitWorkflow-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try "initial\n".write(to: root.appendingPathComponent("file.swift"), atomically: true, encoding: .utf8)
    _ = try runWorkflowGit(["init"], in: root)
    _ = try runWorkflowGit(["config", "user.name", "Code Review Tests"], in: root)
    _ = try runWorkflowGit(["config", "user.email", "tests@cocxy.dev"], in: root)
    _ = try runWorkflowGit(["add", "."], in: root)
    _ = try runWorkflowGit(["commit", "-m", "Initial"], in: root)
    return root
}

private func runWorkflowGit(_ arguments: [String], in directory: URL) throws -> String {
    let result = try CodeReviewGit.run(workingDirectory: directory, arguments: arguments)
    guard result.terminationStatus == 0 else {
        throw HunkActionError.commandFailed(result.stderr)
    }
    return result.stdout
}

@MainActor
private func waitForEditorCondition(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while condition() == false {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Timed out waiting for editor state")
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}
