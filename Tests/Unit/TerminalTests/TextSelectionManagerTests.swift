// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TextSelectionManagerTests.swift - Tests for Cmd+click path and URL detection.

import XCTest
@testable import CocxyTerminal

@MainActor
final class TextSelectionRelativePathTests: XCTestCase {

    // MARK: - Content Detection via SmartCopyMenuBuilder

    // TextSelectionManager.detectFilePath is private, so we validate detection
    // patterns through SmartCopyMenuBuilder.detectContent which uses the same
    // regex family (Patterns.filePath, Patterns.url).

    // MARK: - Absolute Path Detection

    func testDetectsAbsolutePath() {
        let results = SmartCopyMenuBuilder.detectContent(in: "/usr/local/bin/script")
        XCTAssertTrue(results.contains { $0.type == .filePath })
    }

    func testDetectsAbsolutePathWithExtension() {
        let results = SmartCopyMenuBuilder.detectContent(in: "/home/user/project/main.swift")
        XCTAssertTrue(
            results.contains { $0.type == .filePath && $0.value == "/home/user/project/main.swift" }
        )
    }

    // MARK: - Home-Relative Path Detection

    func testDetectsHomeRelativePath() {
        let results = SmartCopyMenuBuilder.detectContent(in: "~/Documents/file.txt")
        XCTAssertTrue(results.contains { $0.type == .filePath })
    }

    func testDetectsNestedHomeRelativePath() {
        let results = SmartCopyMenuBuilder.detectContent(
            in: "Config at ~/.config/cocxy/config.toml"
        )
        XCTAssertTrue(
            results.contains { $0.type == .filePath && $0.value == "~/.config/cocxy/config.toml" }
        )
    }

    // MARK: - URL Detection

    func testDetectsHTTPSURL() {
        let results = SmartCopyMenuBuilder.detectContent(in: "https://github.com/user/repo")
        XCTAssertTrue(results.contains { $0.type == .url })
    }

    func testDetectsHTTPURL() {
        let results = SmartCopyMenuBuilder.detectContent(in: "http://localhost:3000")
        XCTAssertTrue(results.contains { $0.type == .url })
    }

    // MARK: - Plain Text (No False Positives)

    func testPlainTextReturnsEmpty() {
        let results = SmartCopyMenuBuilder.detectContent(in: "hello world")
        XCTAssertTrue(results.isEmpty)
    }

    func testSingleWordReturnsEmpty() {
        let results = SmartCopyMenuBuilder.detectContent(in: "README")
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Relative Path Regex

    func testRelativePathPatternMatchesDotSlash() {
        // swiftlint:disable:next force_try
        let pattern = try! NSRegularExpression(
            pattern: #"(?<!\w)\.{0,2}/[\w.\-@/]+"#,
            options: []
        )
        let text = "./README.md"
        let range = NSRange(text.startIndex..., in: text)
        let match = pattern.firstMatch(in: text, range: range)
        XCTAssertNotNil(match, "Pattern should match ./README.md")
    }

    func testRelativePathPatternMatchesDotDotSlash() {
        // swiftlint:disable:next force_try
        let pattern = try! NSRegularExpression(
            pattern: #"(?<!\w)\.{0,2}/[\w.\-@/]+"#,
            options: []
        )
        let text = "../docs/guide.md"
        let range = NSRange(text.startIndex..., in: text)
        let match = pattern.firstMatch(in: text, range: range)
        XCTAssertNotNil(match, "Pattern should match ../docs/guide.md")
    }

    func testRelativePathPatternRejectsBarePath() {
        // swiftlint:disable:next force_try
        let pattern = try! NSRegularExpression(
            pattern: #"(?<!\w)\.{0,2}/[\w.\-@/]+"#,
            options: []
        )
        let text = "src/main.swift"
        let range = NSRange(text.startIndex..., in: text)
        // "src/main.swift" has word chars before the "/" so the lookbehind
        // (?<!\w) prevents matching. Bare paths without ./ prefix are not
        // detected by this regex — they're handled by the CWD fallback in
        // detectFilePath when the full text is tried against the working directory.
        let match = pattern.firstMatch(in: text, range: range)
        XCTAssertNil(match, "Bare paths like src/file are not matched by the relative regex")
    }

    func testRelativePathPatternDoesNotMatchPlainWord() {
        // swiftlint:disable:next force_try
        let pattern = try! NSRegularExpression(
            pattern: #"(?<!\w)\.{0,2}/[\w.\-@/]+"#,
            options: []
        )
        let text = "hello"
        let range = NSRange(text.startIndex..., in: text)
        let match = pattern.firstMatch(in: text, range: range)
        XCTAssertNil(match, "Pattern should not match plain word without path separators")
    }

    // MARK: - WorkingDirectoryProvider Integration

    func testWorkingDirectoryProviderDefaultsToNil() {
        let manager = TextSelectionManager(hostView: NSView())
        XCTAssertNil(manager.workingDirectoryProvider)
    }

    func testWorkingDirectoryProviderCanBeSet() {
        let manager = TextSelectionManager(hostView: NSView())
        let testURL = URL(fileURLWithPath: "/tmp/test-project")
        manager.workingDirectoryProvider = { testURL }
        XCTAssertNotNil(manager.workingDirectoryProvider)
        XCTAssertEqual(
            manager.workingDirectoryProvider?(),
            testURL
        )
    }
}
