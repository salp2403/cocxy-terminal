// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TemplateVariableResolver.swift - Deterministic local placeholder rendering.

import Foundation

struct TemplateVariableResolver: Sendable {
    func resolvedValues(
        variables: [ProjectTemplateVariable],
        values: [String: String]
    ) throws -> [String: String] {
        var resolved: [String: String] = [:]

        for variable in variables {
            let explicitValue = values[variable.name]
            if let explicitValue, !explicitValue.isEmpty {
                resolved[variable.name] = explicitValue
            } else if let defaultValue = variable.defaultValue {
                resolved[variable.name] = defaultValue
            } else if variable.required {
                throw ProjectTemplateError.missingRequiredVariable(variable.name)
            } else {
                resolved[variable.name] = ""
            }
        }

        return resolved
    }

    func render(
        _ text: String,
        variables: [ProjectTemplateVariable],
        values: [String: String]
    ) throws -> String {
        try render(text, values: resolvedValues(variables: variables, values: values))
    }

    func render(_ text: String, values: [String: String]) throws -> String {
        let placeholderExpression = try NSRegularExpression(
            pattern: #"\{\{\s*([A-Za-z0-9_-]+)\s*\}\}"#,
            options: []
        )
        let nsText = text as NSString
        let matches = placeholderExpression.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else {
            return text
        }

        var rendered = text
        var unresolved: Set<String> = []

        for match in matches.reversed() {
            let name = nsText.substring(with: match.range(at: 1))
            guard let value = values[name] else {
                unresolved.insert(name)
                continue
            }
            if let range = Range(match.range(at: 0), in: rendered) {
                rendered.replaceSubrange(range, with: value)
            }
        }

        if !unresolved.isEmpty {
            throw ProjectTemplateError.unresolvedVariables(unresolved.sorted())
        }

        return rendered
    }
}
