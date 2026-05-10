// Copyright (c) 2026 Said Arturo Lopez. MIT License.

/// Classifies a terminal input line before execution.
///
/// Implementations must stay local-only. They may use on-device Apple
/// frameworks, but must never route input to a network service implicitly.
public protocol InputClassifierEngine: Sendable {
    func classify(_ input: String) async -> InputClassification
}
