// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct ShellHintCorrectionProvider: CommandCorrectionProvider {
    public init() {}

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        guard let replacement = parseReplacement(from: context.stderr),
              !replacement.isEmpty
        else {
            return []
        }

        return [
            CommandCorrection(
                original: context.normalizedCommand,
                suggestion: CommandCorrectionCommandLine.replacingFirstToken(
                    in: context.command,
                    with: replacement
                ),
                reason: "Shell provided a correction hint",
                confidence: 0.94,
                source: .shellHint
            )
        ]
    }

    private func parseReplacement(from stderr: String) -> String? {
        let patterns = [
            #"correct ['"]([^'"]+)['"] to ['"]([^'"]+)['"]"#,
            #"Did you mean ['"]([^'"]+)['"]\?"#,
            #"did you mean ['"]([^'"]+)['"]\?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: stderr,
                    range: NSRange(stderr.startIndex..<stderr.endIndex, in: stderr)
                  )
            else {
                continue
            }

            let rangeIndex = match.numberOfRanges == 3 ? 2 : 1
            guard let range = Range(match.range(at: rangeIndex), in: stderr) else {
                continue
            }
            return String(stderr[range])
        }
        return nil
    }
}
