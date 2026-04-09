// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TOMLParser.swift - Minimal TOML parser for configuration files.

import Foundation

// MARK: - TOML Value

/// Represents a parsed TOML value.
///
/// Supports the subset of TOML needed for configuration:
/// strings, integers, floats, booleans, arrays, and tables.
/// Does not support datetime, inline tables, or multiline strings.
enum TOMLValue: Equatable {
    case string(String)
    case integer(Int)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])
}

// MARK: - TOML Parser

/// Parses a TOML string into a dictionary of `TOMLValue` entries.
///
/// Supports:
/// - Key-value pairs with string, integer, float, and boolean values.
/// - Tables (sections delimited by `[table-name]`).
/// - Single-line comments starting with `#`.
/// - Basic arrays `[1, 2, 3]`.
/// - Windows CRLF line endings (the `\r` is stripped alongside whitespace).
///
/// Does not support:
/// - Datetime values.
/// - Inline tables `{ key = value }`.
/// - Array of tables `[[table]]`.
/// - Multiline strings (`"""` or `'''`).
/// - Dotted keys (`a.b.c = value`).
///
/// - SeeAlso: ADR-005 (TOML config format)
struct TOMLParser {

    /// Parses a TOML string and returns the top-level table.
    ///
    /// - Parameter input: The raw TOML content.
    /// - Returns: A dictionary mapping keys to their parsed values.
    ///   Tables become nested `.table` values.
    /// - Throws: `TOMLParserError` if the input contains syntax errors.
    func parse(_ input: String) throws -> [String: TOMLValue] {
        var rootTable: [String: TOMLValue] = [:]
        var currentTableName: String?
        var currentTable: [String: TOMLValue] = [:]
        let lines = input.components(separatedBy: "\n")

        for (lineIndex, rawLine) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            // Use .whitespacesAndNewlines to handle CRLF files where lines split
            // on "\n" leave a trailing "\r" that .whitespaces does not strip.
            let stripped = stripComment(from: rawLine)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if stripped.isEmpty {
                continue
            }

            // Table header: [table-name]
            if stripped.hasPrefix("[") {
                // Save current table before switching
                if let tableName = currentTableName {
                    rootTable[tableName] = .table(currentTable)
                }

                let tableName = try parseTableHeader(stripped, lineNumber: lineNumber)

                if rootTable[tableName] != nil {
                    throw TOMLParserError.duplicateKey(key: tableName, line: lineNumber)
                }

                currentTableName = tableName
                currentTable = [:]
                continue
            }

            // Key-value pair
            let (key, value) = try parseKeyValuePair(stripped, lineNumber: lineNumber)

            if currentTableName != nil {
                if currentTable[key] != nil {
                    throw TOMLParserError.duplicateKey(key: key, line: lineNumber)
                }
                currentTable[key] = value
            } else {
                if rootTable[key] != nil {
                    throw TOMLParserError.duplicateKey(key: key, line: lineNumber)
                }
                rootTable[key] = value
            }
        }

        // Save the last table
        if let tableName = currentTableName {
            rootTable[tableName] = .table(currentTable)
        }

        return rootTable
    }

    // MARK: - Private Parsing Helpers

    /// Strips inline comments from a line, respecting quoted strings.
    ///
    /// A `#` inside a quoted string (double or single) is not treated as
    /// a comment delimiter. Both basic strings (`"..."`) and literal
    /// strings (`'...'`) are tracked.
    private func stripComment(from line: String) -> String {
        var activeQuote: Character?
        var result = ""

        for character in line {
            if activeQuote == nil && (character == "\"" || character == "'") {
                activeQuote = character
                result.append(character)
            } else if character == activeQuote {
                activeQuote = nil
                result.append(character)
            } else if character == "#" && activeQuote == nil {
                break
            } else {
                result.append(character)
            }
        }

        return result
    }

    /// Parses a table header like `[table-name]` and returns the table name.
    ///
    /// - Throws: `TOMLParserError.invalidTableHeader` if the header is malformed.
    private func parseTableHeader(_ line: String, lineNumber: Int) throws -> String {
        guard line.hasPrefix("[") && line.hasSuffix("]") else {
            throw TOMLParserError.invalidTableHeader(
                line: lineNumber,
                detail: "Table header must be enclosed in brackets"
            )
        }

        let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)

        if name.isEmpty {
            throw TOMLParserError.invalidTableHeader(
                line: lineNumber,
                detail: "Table name cannot be empty"
            )
        }

        return name
    }

    /// Parses a `key = value` pair and returns the key and parsed value.
    ///
    /// - Throws: `TOMLParserError.invalidSyntax` if there is no `=` sign.
    /// - Throws: Various `TOMLParserError` variants for malformed values.
    private func parseKeyValuePair(
        _ line: String,
        lineNumber: Int
    ) throws -> (String, TOMLValue) {
        guard let equalsIndex = line.firstIndex(of: "=") else {
            throw TOMLParserError.invalidSyntax(
                line: lineNumber,
                detail: "Expected key = value pair"
            )
        }

        let key = String(line[line.startIndex..<equalsIndex])
            .trimmingCharacters(in: .whitespaces)
        let rawValue = String(line[line.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespaces)

        if key.isEmpty {
            throw TOMLParserError.invalidSyntax(
                line: lineNumber,
                detail: "Key cannot be empty"
            )
        }

        let value = try parseValue(rawValue, lineNumber: lineNumber)
        return (key, value)
    }

    /// Parses a raw string into a `TOMLValue`.
    ///
    /// Attempts to interpret the value as (in order):
    /// boolean, string, array, integer, float.
    private func parseValue(_ raw: String, lineNumber: Int) throws -> TOMLValue {
        if raw.isEmpty {
            throw TOMLParserError.invalidValue(
                line: lineNumber,
                detail: "Value cannot be empty"
            )
        }

        // Boolean
        if raw == "true" {
            return .boolean(true)
        }
        if raw == "false" {
            return .boolean(false)
        }

        // String (double-quoted basic or single-quoted literal)
        if raw.hasPrefix("\"") || raw.hasPrefix("'") {
            return try parseStringValue(raw, lineNumber: lineNumber)
        }

        // Array
        if raw.hasPrefix("[") {
            return try parseArrayValue(raw, lineNumber: lineNumber)
        }

        // Numeric (integer or float)
        return try parseNumericValue(raw, lineNumber: lineNumber)
    }

    /// Parses a quoted string value like `"hello world"`.
    ///
    /// - Throws: `TOMLParserError.unterminatedString` if the closing quote is missing.
    private func parseStringValue(_ raw: String, lineNumber: Int) throws -> TOMLValue {
        // Support both basic strings ("...") and literal strings ('...').
        // TOML literal strings (single-quoted) preserve backslashes verbatim,
        // which is essential for regex patterns like '^claude\b'.
        if raw.hasPrefix("\"") {
            return .string(try parseBasicStringValue(raw, lineNumber: lineNumber))
        } else if raw.hasPrefix("'") {
            return .string(try parseLiteralStringValue(raw, lineNumber: lineNumber))
        } else {
            throw TOMLParserError.invalidValue(
                line: lineNumber,
                detail: "String must start with a quote"
            )
        }
    }

    private func parseBasicStringValue(_ raw: String, lineNumber: Int) throws -> String {
        var content = ""
        var iterator = raw.dropFirst().makeIterator()
        var isEscaping = false

        while let character = iterator.next() {
            if isEscaping {
                switch character {
                case "\"", "\\":
                    content.append(character)
                case "n":
                    content.append("\n")
                case "r":
                    content.append("\r")
                case "t":
                    content.append("\t")
                default:
                    content.append(character)
                }
                isEscaping = false
                continue
            }

            switch character {
            case "\\":
                isEscaping = true
            case "\"":
                return content
            default:
                content.append(character)
            }
        }

        throw TOMLParserError.unterminatedString(line: lineNumber)
    }

    private func parseLiteralStringValue(_ raw: String, lineNumber: Int) throws -> String {
        let withoutOpeningQuote = String(raw.dropFirst())

        guard let closingQuoteIndex = withoutOpeningQuote.firstIndex(of: "'") else {
            throw TOMLParserError.unterminatedString(line: lineNumber)
        }

        return String(withoutOpeningQuote[withoutOpeningQuote.startIndex..<closingQuoteIndex])
    }

    /// Parses an array value like `[1, 2, 3]`.
    ///
    /// - Throws: `TOMLParserError.unterminatedArray` if the closing bracket is missing.
    private func parseArrayValue(_ raw: String, lineNumber: Int) throws -> TOMLValue {
        guard raw.hasPrefix("[") else {
            throw TOMLParserError.invalidValue(
                line: lineNumber,
                detail: "Array must start with ["
            )
        }

        guard raw.hasSuffix("]") else {
            throw TOMLParserError.unterminatedArray(line: lineNumber)
        }

        let inner = String(raw.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespaces)

        if inner.isEmpty {
            return .array([])
        }

        let elements = splitArrayElements(inner)
        var values: [TOMLValue] = []

        for element in elements {
            let trimmed = element.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let value = try parseValue(trimmed, lineNumber: lineNumber)
                values.append(value)
            }
        }

        return .array(values)
    }

    /// Splits array elements by commas, respecting quoted strings.
    ///
    /// Both basic strings (`"a, b"`) and literal strings (`'a, b'`)
    /// are handled correctly — commas inside quotes are not split points.
    private func splitArrayElements(_ input: String) -> [String] {
        var elements: [String] = []
        var current = ""
        var activeQuote: Character?

        for character in input {
            if activeQuote == nil && (character == "\"" || character == "'") {
                activeQuote = character
                current.append(character)
            } else if character == activeQuote {
                activeQuote = nil
                current.append(character)
            } else if character == "," && activeQuote == nil {
                elements.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            elements.append(current)
        }

        return elements
    }

    /// Parses a numeric value as either an integer or float.
    ///
    /// A value containing a decimal point is parsed as float;
    /// otherwise it is parsed as integer.
    ///
    /// - Throws: `TOMLParserError.invalidValue` if the value is not a valid number.
    private func parseNumericValue(_ raw: String, lineNumber: Int) throws -> TOMLValue {
        if raw.contains(".") {
            guard let doubleValue = Double(raw) else {
                throw TOMLParserError.invalidValue(
                    line: lineNumber,
                    detail: "Invalid float value: \(raw)"
                )
            }
            return .float(doubleValue)
        }

        guard let intValue = Int(raw) else {
            throw TOMLParserError.invalidValue(
                line: lineNumber,
                detail: "Invalid integer value: \(raw)"
            )
        }
        return .integer(intValue)
    }
}

// MARK: - TOML Parser Errors

/// Errors that can occur during TOML parsing.
enum TOMLParserError: Error, Equatable {
    /// A line could not be parsed as a valid TOML construct.
    case invalidSyntax(line: Int, detail: String)
    /// A table header is malformed (e.g., missing closing bracket).
    case invalidTableHeader(line: Int, detail: String)
    /// A value could not be interpreted as any supported TOML type.
    case invalidValue(line: Int, detail: String)
    /// A string literal is not properly terminated.
    case unterminatedString(line: Int)
    /// An array literal is not properly terminated.
    case unterminatedArray(line: Int)
    /// A duplicate key was found in the same table.
    case duplicateKey(key: String, line: Int)
}
