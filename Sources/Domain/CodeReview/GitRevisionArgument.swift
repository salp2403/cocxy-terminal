// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitRevisionArgument.swift - Typed Git revision operands and range construction.

import Foundation

enum GitRevisionArgumentError: Error, Equatable, LocalizedError, Sendable {
    case invalidRevision

    var errorDescription: String? {
        "Git reference is not valid."
    }
}

struct GitRevisionArgument: Equatable, Sendable {
    enum RangeKind: Sendable {
        case twoDot
        case threeDot

        fileprivate var separator: String {
            switch self {
            case .twoDot: ".."
            case .threeDot: "..."
            }
        }
    }

    let value: String

    init(_ rawValue: String) throws {
        let containsWhitespaceOrControl = rawValue.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
        }
        guard !rawValue.isEmpty,
              !rawValue.hasPrefix("-"),
              !containsWhitespaceOrControl,
              !rawValue.contains("..") else {
            throw GitRevisionArgumentError.invalidRevision
        }
        value = rawValue
    }

    static func range(
        base: GitRevisionArgument,
        head: GitRevisionArgument,
        kind: RangeKind
    ) -> String {
        base.value + kind.separator + head.value
    }
}
