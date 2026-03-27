// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SmartCopyMenuBuilderTests.swift - Tests for intelligent content detection.

import XCTest
@testable import CocxyTerminal

@MainActor
final class SmartCopyMenuBuilderTests: XCTestCase {

    // MARK: - URL Detection

    func testDetectsHTTPURL() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Visit https://example.com today")
        XCTAssertTrue(results.contains { $0.type == .url && $0.value == "https://example.com" })
    }

    func testDetectsHTTPSURLWithPath() {
        let results = SmartCopyMenuBuilder.detectContent(in: "See https://github.com/user/repo/issues/42")
        XCTAssertTrue(results.contains { $0.type == .url && $0.value == "https://github.com/user/repo/issues/42" })
    }

    func testDetectsHTTPURLWithQueryString() {
        let results = SmartCopyMenuBuilder.detectContent(in: "http://localhost:3000/api?key=value&other=123")
        XCTAssertTrue(results.contains { $0.type == .url })
    }

    func testIgnoresNonHTTPProtocols() {
        let results = SmartCopyMenuBuilder.detectContent(in: "ftp://files.example.com")
        XCTAssertFalse(results.contains { $0.type == .url })
    }

    // MARK: - File Path Detection

    func testDetectsAbsolutePath() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Edit /usr/local/bin/script.sh")
        XCTAssertTrue(results.contains { $0.type == .filePath && $0.value == "/usr/local/bin/script.sh" })
    }

    func testDetectsHomeRelativePath() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Config at ~/Documents/settings.json")
        XCTAssertTrue(results.contains { $0.type == .filePath && $0.value == "~/Documents/settings.json" })
    }

    func testFilePathSkipsURLFragments() {
        // The path /example.com should not be detected separately from the URL
        let results = SmartCopyMenuBuilder.detectContent(in: "https://example.com/path/to/file")
        let pathResults = results.filter { $0.type == .filePath }
        // Should not extract /example.com/path/to/file as a separate file path
        for path in pathResults {
            XCTAssertFalse(path.value.contains("example.com"), "File path should not contain URL host: \(path.value)")
        }
    }

    func testFilePathSkipsShortPaths() {
        // Paths shorter than 3 chars should be ignored
        let results = SmartCopyMenuBuilder.detectContent(in: "/ is root")
        let pathResults = results.filter { $0.type == .filePath }
        XCTAssertTrue(pathResults.isEmpty || pathResults.allSatisfy { $0.value.count > 2 })
    }

    // MARK: - IPv4 Detection

    func testDetectsIPv4Address() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Server at 192.168.1.100")
        XCTAssertTrue(results.contains { $0.type == .ipAddress && $0.value == "192.168.1.100" })
    }

    func testDetectsLocalhostIP() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Listening on 127.0.0.1:8080")
        XCTAssertTrue(results.contains { $0.type == .ipAddress && $0.value == "127.0.0.1" })
    }

    // MARK: - Git Hash Detection

    func testDetectsShortGitHash() {
        let results = SmartCopyMenuBuilder.detectContent(in: "commit abc1234 merged")
        XCTAssertTrue(results.contains { $0.type == .gitHash && $0.value == "abc1234" })
    }

    func testDetectsFullGitHash() {
        let hash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let results = SmartCopyMenuBuilder.detectContent(in: "commit \(hash)")
        XCTAssertTrue(results.contains { $0.type == .gitHash && $0.value == hash })
    }

    func testIgnoresTooShortHash() {
        // 6 chars is below the 7-char minimum
        let results = SmartCopyMenuBuilder.detectContent(in: "value abc123 here")
        XCTAssertFalse(results.contains { $0.type == .gitHash && $0.value == "abc123" })
    }

    // MARK: - Email Detection

    func testDetectsEmail() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Contact user@example.com")
        XCTAssertTrue(results.contains { $0.type == .email && $0.value == "user@example.com" })
    }

    func testDetectsEmailWithSubdomain() {
        let results = SmartCopyMenuBuilder.detectContent(in: "admin@mail.company.org")
        XCTAssertTrue(results.contains { $0.type == .email && $0.value == "admin@mail.company.org" })
    }

    // MARK: - Multiple Patterns

    func testDetectsMultiplePatternsInSameText() {
        let text = "See https://github.com and contact admin@dev.com from 192.168.1.1"
        let results = SmartCopyMenuBuilder.detectContent(in: text)
        XCTAssertTrue(results.contains { $0.type == .url })
        XCTAssertTrue(results.contains { $0.type == .email })
        XCTAssertTrue(results.contains { $0.type == .ipAddress })
    }

    // MARK: - Edge Cases

    func testEmptyTextReturnsEmpty() {
        let results = SmartCopyMenuBuilder.detectContent(in: "")
        XCTAssertTrue(results.isEmpty)
    }

    func testPlainTextReturnsEmpty() {
        let results = SmartCopyMenuBuilder.detectContent(in: "Hello world this is plain text")
        XCTAssertTrue(results.isEmpty)
    }

    func testURLsOrderedFirst() {
        let text = "admin@dev.com https://example.com"
        let results = SmartCopyMenuBuilder.detectContent(in: text)
        guard let firstURL = results.firstIndex(where: { $0.type == .url }),
              let firstEmail = results.firstIndex(where: { $0.type == .email }) else {
            XCTFail("Expected both URL and email")
            return
        }
        XCTAssertLessThan(firstURL, firstEmail, "URLs should appear before emails in results")
    }
}
