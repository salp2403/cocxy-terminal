// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TOMLParserTests.swift - Tests for the minimal TOML parser.

import XCTest
@testable import CocxyTerminal

// MARK: - TOML Parser Tests

/// Tests for `TOMLParser` covering all supported value types and edge cases.
///
/// Covers:
/// - String parsing (basic quoted strings).
/// - Integer parsing (positive, negative, zero).
/// - Float parsing (positive, negative, decimal).
/// - Boolean parsing (true, false).
/// - Table/section parsing.
/// - Array parsing.
/// - Comment handling.
/// - Empty input.
/// - Malformed input error handling.
///
/// - SeeAlso: ADR-005 (TOML config format)
final class TOMLParserTests: XCTestCase {

    private var parser: TOMLParser!

    override func setUp() {
        super.setUp()
        parser = TOMLParser()
    }

    // MARK: - Empty & Whitespace

    func testEmptyInputReturnsEmptyTable() throws {
        let result = try parser.parse("")
        XCTAssertTrue(result.isEmpty)
    }

    func testWhitespaceOnlyInputReturnsEmptyTable() throws {
        let result = try parser.parse("   \n\n   \n")
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Comments

    func testCommentOnlyLinesAreIgnored() throws {
        let toml = """
        # This is a comment
        # Another comment
        """
        let result = try parser.parse(toml)
        XCTAssertTrue(result.isEmpty)
    }

    func testInlineCommentsAreStripped() throws {
        let toml = """
        name = "hello" # inline comment
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["name"], .string("hello"))
    }

    // MARK: - String Values

    func testBasicStringValue() throws {
        let toml = """
        title = "TOML Example"
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["title"], .string("TOML Example"))
    }

    func testStringWithSpecialCharacters() throws {
        let toml = """
        path = "/usr/local/bin"
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["path"], .string("/usr/local/bin"))
    }

    func testEmptyStringValue() throws {
        let toml = """
        empty = ""
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["empty"], .string(""))
    }

    func testBasicStringPreservesEscapedQuotes() throws {
        let toml = #"""
        message = "He said \"hello\""
        """#
        let result = try parser.parse(toml)
        XCTAssertEqual(result["message"], .string(#"He said "hello""#))
    }

    // MARK: - Integer Values

    func testPositiveInteger() throws {
        let toml = """
        port = 8080
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["port"], .integer(8080))
    }

    func testNegativeInteger() throws {
        let toml = """
        offset = -10
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["offset"], .integer(-10))
    }

    func testZeroInteger() throws {
        let toml = """
        count = 0
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["count"], .integer(0))
    }

    // MARK: - Float Values

    func testPositiveFloat() throws {
        let toml = """
        size = 14.5
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["size"], .float(14.5))
    }

    func testNegativeFloat() throws {
        let toml = """
        temperature = -3.14
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["temperature"], .float(-3.14))
    }

    func testFloatWithLeadingZero() throws {
        let toml = """
        opacity = 0.8
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["opacity"], .float(0.8))
    }

    // MARK: - Boolean Values

    func testBooleanTrue() throws {
        let toml = """
        enabled = true
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["enabled"], .boolean(true))
    }

    func testBooleanFalse() throws {
        let toml = """
        disabled = false
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["disabled"], .boolean(false))
    }

    // MARK: - Table Sections

    func testSimpleTableSection() throws {
        let toml = """
        [server]
        host = "localhost"
        port = 8080
        """
        let result = try parser.parse(toml)
        guard case .table(let serverTable) = result["server"] else {
            XCTFail("Expected 'server' to be a table")
            return
        }
        XCTAssertEqual(serverTable["host"], .string("localhost"))
        XCTAssertEqual(serverTable["port"], .integer(8080))
    }

    func testMultipleTableSections() throws {
        let toml = """
        [font]
        family = "Menlo"
        size = 12.0

        [window]
        width = 800
        height = 600
        """
        let result = try parser.parse(toml)

        guard case .table(let fontTable) = result["font"] else {
            XCTFail("Expected 'font' to be a table")
            return
        }
        XCTAssertEqual(fontTable["family"], .string("Menlo"))
        XCTAssertEqual(fontTable["size"], .float(12.0))

        guard case .table(let windowTable) = result["window"] else {
            XCTFail("Expected 'window' to be a table")
            return
        }
        XCTAssertEqual(windowTable["width"], .integer(800))
        XCTAssertEqual(windowTable["height"], .integer(600))
    }

    func testTopLevelKeysAndTableSectionsCoexist() throws {
        let toml = """
        title = "My App"

        [database]
        host = "localhost"
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["title"], .string("My App"))
        guard case .table(let dbTable) = result["database"] else {
            XCTFail("Expected 'database' to be a table")
            return
        }
        XCTAssertEqual(dbTable["host"], .string("localhost"))
    }

    // MARK: - Array Values

    func testIntegerArray() throws {
        let toml = """
        ports = [80, 443, 8080]
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["ports"], .array([.integer(80), .integer(443), .integer(8080)]))
    }

    func testStringArray() throws {
        let toml = """
        colors = ["red", "green", "blue"]
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["colors"], .array([.string("red"), .string("green"), .string("blue")]))
    }

    func testEmptyArray() throws {
        let toml = """
        items = []
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["items"], .array([]))
    }

    // MARK: - Hyphenated Keys

    func testHyphenatedKeyName() throws {
        let toml = """
        font-size = 14
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["font-size"], .integer(14))
    }

    func testHyphenatedTableName() throws {
        let toml = """
        [agent-detection]
        enabled = true
        """
        let result = try parser.parse(toml)
        guard case .table(let agentTable) = result["agent-detection"] else {
            XCTFail("Expected 'agent-detection' to be a table")
            return
        }
        XCTAssertEqual(agentTable["enabled"], .boolean(true))
    }

    // MARK: - Full Config Example

    func testFullConfigFileParsesCorrectly() throws {
        let toml = """
        # Cocxy Terminal Configuration

        [general]
        shell = "/bin/zsh"
        working-directory = "~"
        confirm-close-process = true

        [appearance]
        theme = "catppuccin-mocha"
        font-family = "JetBrainsMono Nerd Font"
        font-size = 14.0
        tab-position = "left"
        window-padding = 8.0

        [agent-detection]
        enabled = true
        osc-notifications = true
        pattern-matching = true
        timing-heuristics = true
        idle-timeout-seconds = 5

        [notifications]
        macos-notifications = true
        sound = true
        badge-on-tab = true
        flash-tab = true

        [quick-terminal]
        hotkey = "cmd+grave"
        position = "top"
        height-percentage = 40

        [keybindings]
        new-tab = "cmd+t"
        close-tab = "cmd+w"
        next-tab = "cmd+shift+]"
        prev-tab = "cmd+shift+["
        split-vertical = "cmd+shift+d"
        split-horizontal = "cmd+d"
        goto-attention = "cmd+shift+u"
        toggle-quick-terminal = "cmd+grave"

        [sessions]
        auto-save = true
        auto-save-interval = 30
        restore-on-launch = true
        """
        let result = try parser.parse(toml)

        // Verify all 7 sections parsed
        XCTAssertEqual(result.count, 7)

        guard case .table(let generalTable) = result["general"] else {
            XCTFail("Expected 'general' table")
            return
        }
        XCTAssertEqual(generalTable["shell"], .string("/bin/zsh"))
        XCTAssertEqual(generalTable["confirm-close-process"], .boolean(true))

        guard case .table(let appearanceTable) = result["appearance"] else {
            XCTFail("Expected 'appearance' table")
            return
        }
        XCTAssertEqual(appearanceTable["font-size"], .float(14.0))
        XCTAssertEqual(appearanceTable["tab-position"], .string("left"))
    }

    // MARK: - Error Cases

    func testUnterminatedStringThrowsError() {
        let toml = """
        name = "hello
        """
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.unterminatedString = error else {
                XCTFail("Expected unterminatedString error, got \(error)")
                return
            }
        }
    }

    func testInvalidTableHeaderThrowsError() {
        let toml = """
        [missing-bracket
        key = "value"
        """
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.invalidTableHeader = error else {
                XCTFail("Expected invalidTableHeader error, got \(error)")
                return
            }
        }
    }

    func testLineWithoutEqualsSignThrowsError() {
        let toml = """
        this is not valid toml
        """
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.invalidSyntax = error else {
                XCTFail("Expected invalidSyntax error, got \(error)")
                return
            }
        }
    }

    func testDuplicateKeyInSameTableThrowsError() {
        let toml = """
        name = "first"
        name = "second"
        """
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.duplicateKey = error else {
                XCTFail("Expected duplicateKey error, got \(error)")
                return
            }
        }
    }

    func testUnterminatedArrayThrowsError() {
        let toml = """
        items = [1, 2, 3
        """
        XCTAssertThrowsError(try parser.parse(toml)) { error in
            guard case TOMLParserError.unterminatedArray = error else {
                XCTFail("Expected unterminatedArray error, got \(error)")
                return
            }
        }
    }

    // MARK: - Whitespace Handling

    func testExtraWhitespaceAroundEqualsSign() throws {
        let toml = """
        name   =   "hello"
        """
        let result = try parser.parse(toml)
        XCTAssertEqual(result["name"], .string("hello"))
    }

    func testTrailingWhitespaceOnLines() throws {
        let toml = "name = \"hello\"   \ncount = 42   "
        let result = try parser.parse(toml)
        XCTAssertEqual(result["name"], .string("hello"))
        XCTAssertEqual(result["count"], .integer(42))
    }
}
