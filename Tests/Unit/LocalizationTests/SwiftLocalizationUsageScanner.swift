// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SwiftLocalizationUsageScanner.swift - Token-based localization call discovery.

import Foundation

enum SwiftLocalizationUsageScanner {
    struct Location: Hashable {
        let path: String
        let line: Int
    }

    struct DynamicUsage: Hashable {
        let template: String
        let location: Location
    }

    struct Result {
        var staticUsages: [String: [Location]] = [:]
        var dynamicUsages: [DynamicUsage] = []

        mutating func merge(_ other: Result) {
            for (key, locations) in other.staticUsages {
                staticUsages[key, default: []].append(contentsOf: locations)
            }
            dynamicUsages.append(contentsOf: other.dynamicUsages)
        }
    }

    private enum TokenKind: Equatable {
        case identifier(String)
        case stringLiteral(String)
        case symbol(Character)
    }

    private struct Token: Equatable {
        let kind: TokenKind
        let line: Int
    }

    private enum ScopeKind {
        case declaration
        case container
        case nested
    }

    static func scan(directory: URL, relativeTo root: URL) throws -> Result {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return Result() }

        var result = Result()
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            result.merge(scan(source: source, path: relativePath(for: fileURL, from: root)))
        }
        return result
    }

    static func scan(source: String, path: String) -> Result {
        let tokens = tokenize(source)
        let appLocalizerExtension = tokens.indices.contains { index in
            guard case .identifier("extension") = tokens[index].kind,
                  index + 1 < tokens.count,
                  case .identifier("AppLocalizer") = tokens[index + 1].kind else {
                return false
            }
            return true
        }
        var result = Result()

        for index in tokens.indices {
            guard let keyRange = localizationKeyRange(
                tokens,
                functionAt: index,
                appLocalizerExtension: appLocalizerExtension
            ) else { continue }
            let location = Location(path: path, line: tokens[index].line)
            let keys = localizationKeys(
                in: keyRange,
                tokens: tokens,
                before: index
            )
            for key in keys {
                if key.contains(#"\("#) {
                    result.dynamicUsages.append(DynamicUsage(template: key, location: location))
                } else if key.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
                    result.staticUsages[key, default: []].append(location)
                }
            }
        }
        return result
    }

    private static func localizationKeyRange(
        _ tokens: [Token],
        functionAt index: Int,
        appLocalizerExtension: Bool
    ) -> Range<Int>? {
        guard case .identifier(let function) = tokens[index].kind else { return nil }
        if index > 0, tokens[index - 1].kind == .identifier("func") {
            return nil
        }

        if function == "String",
           index + 4 < tokens.count,
           tokens[index + 1].kind == .symbol("("),
           tokens[index + 2].kind == .identifier("localized"),
           tokens[index + 3].kind == .symbol(":") {
            return argumentRange(tokens, startingAt: index + 4)
        }

        guard index + 2 < tokens.count,
              tokens[index + 1].kind == .symbol("(") else { return nil }
        if function == "NSLocalizedString" {
            return argumentRange(tokens, startingAt: index + 2)
        }

        guard ["formattedProjectString", "localized", "localizedString", "string"].contains(function),
              callHasFallbackLabel(tokens, openingAt: index + 1) else {
            return nil
        }
        if function == "string",
           !isLocalizationStringCall(
               tokens,
               functionAt: index,
               appLocalizerExtension: appLocalizerExtension
           ) {
            return nil
        }
        return argumentRange(tokens, startingAt: index + 2)
    }

    private static func argumentRange(
        _ tokens: [Token],
        startingAt start: Int
    ) -> Range<Int>? {
        guard start < tokens.count else { return nil }
        var parenthesisDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        var index = start
        while index < tokens.count {
            switch tokens[index].kind {
            case .symbol("("):
                parenthesisDepth += 1
            case .symbol(")"):
                if parenthesisDepth == 0, bracketDepth == 0, braceDepth == 0 {
                    return start..<index
                }
                parenthesisDepth -= 1
            case .symbol("["):
                bracketDepth += 1
            case .symbol("]"):
                bracketDepth -= 1
            case .symbol("{"):
                braceDepth += 1
            case .symbol("}"):
                braceDepth -= 1
            case .symbol(",") where parenthesisDepth == 0 && bracketDepth == 0 && braceDepth == 0:
                return start..<index
            default:
                break
            }
            index += 1
        }
        return nil
    }

    private static func localizationKeys(
        in range: Range<Int>,
        tokens: [Token],
        before callIndex: Int
    ) -> Set<String> {
        let direct = Set(range.compactMap { index -> String? in
            guard case .stringLiteral(let key) = tokens[index].kind else { return nil }
            return key
        })
        if !direct.isEmpty { return direct }

        let identifiers = Set(range.compactMap { index -> String? in
            guard case .identifier(let identifier) = tokens[index].kind else { return nil }
            return identifier
        })
        var resolved: Set<String> = []
        for identifier in identifiers {
            let assigned = assignedStringLiterals(
                to: identifier,
                tokens: tokens,
                before: callIndex
            )
            if assigned.isEmpty {
                resolved.formUnion(computedPropertyReturnLiterals(
                    named: identifier,
                    tokens: tokens
                ))
            } else {
                resolved.formUnion(assigned)
            }
        }
        return resolved
    }

    private static func computedPropertyReturnLiterals(
        named identifier: String,
        tokens: [Token]
    ) -> Set<String> {
        var index = 0
        while index + 2 < tokens.count {
            guard tokens[index].kind == .identifier("var"),
                  tokens[index + 1].kind == .identifier(identifier),
                  let opening = tokens[(index + 2)..<tokens.count].firstIndex(where: {
                      $0.kind == .symbol("{")
                  }),
                  let closing = matchingBrace(tokens: tokens, openingAt: opening) else {
                index += 1
                continue
            }
            var values: Set<String> = []
            var cursor = opening + 1
            while cursor < closing {
                if tokens[cursor].kind == .identifier("return") {
                    let valueIndex = cursor + 1
                    if valueIndex < closing,
                       case .stringLiteral(let value) = tokens[valueIndex].kind {
                        values.insert(value)
                    }
                }
                cursor += 1
            }
            return values
        }
        return []
    }

    private static func matchingBrace(tokens: [Token], openingAt opening: Int) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            if tokens[index].kind == .symbol("{") {
                depth += 1
            } else if tokens[index].kind == .symbol("}") {
                depth -= 1
                if depth == 0 { return index }
            }
        }
        return nil
    }

    private static func assignedStringLiterals(
        to identifier: String,
        tokens: [Token],
        before callIndex: Int
    ) -> Set<String> {
        for scopeStart in containingScopeStarts(tokens: tokens, before: callIndex) {
            var values: Set<String> = []
            var index = scopeStart
            while index < callIndex {
                guard tokens[index].kind == .identifier(identifier),
                      let valueStart = assignmentValueStart(tokens: tokens, identifierAt: index),
                      valueStart < callIndex else {
                    index += 1
                    continue
                }
                let valueLine = tokens[valueStart].line
                var valueIndex = valueStart
                while valueIndex < callIndex, tokens[valueIndex].line == valueLine {
                    if case .stringLiteral(let value) = tokens[valueIndex].kind {
                        values.insert(value)
                    }
                    if tokens[valueIndex].kind == .symbol(";") { break }
                    valueIndex += 1
                }
                index = max(index + 1, valueIndex)
            }
            if !values.isEmpty { return values }
        }
        return []
    }

    private static func assignmentValueStart(
        tokens: [Token],
        identifierAt index: Int
    ) -> Int? {
        let declarationLine = tokens[index].line
        var cursor = index + 1
        while cursor < tokens.count, cursor <= index + 8,
              tokens[cursor].line == declarationLine {
            if tokens[cursor].kind == .symbol("=") {
                guard cursor + 1 < tokens.count,
                      tokens[cursor + 1].kind != .symbol("=") else { return nil }
                return cursor + 1
            }
            if tokens[cursor].kind == .symbol(",") || tokens[cursor].kind == .symbol(")") {
                return nil
            }
            cursor += 1
        }
        return nil
    }

    private static func containingScopeStarts(
        tokens: [Token],
        before index: Int
    ) -> [Int] {
        guard index > 0 else { return [0] }
        var depth = 0
        var starts: [Int] = []
        for cursor in stride(from: index - 1, through: 0, by: -1) {
            switch tokens[cursor].kind {
            case .symbol("}"):
                depth += 1
            case .symbol("{"):
                if depth == 0 {
                    switch scopeKind(tokens: tokens, openingAt: cursor) {
                    case .declaration:
                        starts.append(cursor + 1)
                        return starts
                    case .container:
                        return starts.isEmpty ? [cursor + 1] : starts
                    case .nested:
                        starts.append(cursor + 1)
                    }
                } else {
                    depth -= 1
                }
            default:
                break
            }
        }
        starts.append(0)
        return starts
    }

    private static func scopeKind(tokens: [Token], openingAt index: Int) -> ScopeKind {
        guard index > 0 else { return .container }
        let declarationKeywords: Set<String> = ["deinit", "func", "init", "subscript", "var"]
        let containerKeywords: Set<String> = ["actor", "class", "enum", "extension", "protocol", "struct"]
        var cursor = index - 1
        while true {
            switch tokens[cursor].kind {
            case .identifier(let identifier) where declarationKeywords.contains(identifier):
                return .declaration
            case .identifier(let identifier) where containerKeywords.contains(identifier):
                return .container
            case .symbol("{"), .symbol("}"):
                return .nested
            default:
                break
            }
            if cursor == 0 || index - cursor >= 80 { break }
            cursor -= 1
        }
        return .nested
    }

    private static func isLocalizationStringCall(
        _ tokens: [Token],
        functionAt index: Int,
        appLocalizerExtension: Bool
    ) -> Bool {
        guard index > 0, tokens[index - 1].kind == .symbol(".") else {
            return appLocalizerExtension
        }
        let lowerBound = max(0, index - 16)
        return tokens[lowerBound..<index].contains { token in
            guard case .identifier(let identifier) = token.kind else { return false }
            return identifier.localizedCaseInsensitiveContains("localizer")
        }
    }

    private static func callHasFallbackLabel(_ tokens: [Token], openingAt opening: Int) -> Bool {
        var depth = 0
        var index = opening
        while index < tokens.count {
            switch tokens[index].kind {
            case .symbol("("):
                depth += 1
            case .symbol(")"):
                depth -= 1
                if depth == 0 { return false }
            case .identifier("fallback") where depth == 1:
                if index + 1 < tokens.count, tokens[index + 1].kind == .symbol(":") {
                    return true
                }
            default:
                break
            }
            index += 1
        }
        return false
    }

    private static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        var index = source.startIndex
        var line = 1
        var blockCommentDepth = 0

        while index < source.endIndex {
            let character = source[index]
            let next = source.index(after: index)
            let nextCharacter = next < source.endIndex ? source[next] : nil

            if blockCommentDepth > 0 {
                if character == "/", nextCharacter == "*" {
                    blockCommentDepth += 1
                    index = source.index(after: next)
                } else if character == "*", nextCharacter == "/" {
                    blockCommentDepth -= 1
                    index = source.index(after: next)
                } else {
                    if character == "\n" { line += 1 }
                    index = next
                }
                continue
            }
            if character == "/", nextCharacter == "/" {
                while index < source.endIndex, source[index] != "\n" {
                    index = source.index(after: index)
                }
                continue
            }
            if character == "/", nextCharacter == "*" {
                blockCommentDepth = 1
                index = source.index(after: next)
                continue
            }
            if character == "\n" {
                line += 1
                index = next
                continue
            }
            if character.isWhitespace {
                index = next
                continue
            }
            if character == "\"" {
                let tokenLine = line
                var value = ""
                index = next
                var escaped = false
                while index < source.endIndex {
                    let current = source[index]
                    if current == "\n" { line += 1 }
                    if escaped {
                        value.append("\\")
                        value.append(current)
                        escaped = false
                    } else if current == "\\" {
                        escaped = true
                    } else if current == "\"" {
                        index = source.index(after: index)
                        break
                    } else {
                        value.append(current)
                    }
                    index = source.index(after: index)
                }
                tokens.append(Token(kind: .stringLiteral(value), line: tokenLine))
                continue
            }
            if isIdentifierStart(character) {
                let start = index
                index = next
                while index < source.endIndex, isIdentifierContinuation(source[index]) {
                    index = source.index(after: index)
                }
                tokens.append(Token(kind: .identifier(String(source[start..<index])), line: line))
                continue
            }

            tokens.append(Token(kind: .symbol(character), line: line))
            index = next
        }
        return tokens
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    private static func relativePath(for fileURL: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return filePath }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
