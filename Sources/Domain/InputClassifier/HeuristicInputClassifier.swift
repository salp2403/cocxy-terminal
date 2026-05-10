// Copyright (c) 2026 Said Arturo Lopez. MIT License.

public struct HeuristicInputClassifier: Sendable {
    private let dangerousCommands: DangerousCommandDictionary

    public init(dangerousCommands: DangerousCommandDictionary = .default) {
        self.dangerousCommands = dangerousCommands
    }

    public func classify(_ input: String) -> InputClassification {
        let normalized = ShellInputRecognizer.normalized(input)
        guard !normalized.isEmpty else {
            return InputClassification(
                category: .empty,
                confidence: 1.0,
                routingHint: .ignore
            )
        }

        if let match = dangerousCommands.match(normalized) {
            return InputClassification(
                category: .dangerousCommand,
                confidence: match.severity == .critical ? 0.98 : 0.92,
                dangerReason: match.reason,
                dangerSeverity: match.severity,
                shouldWarnBeforeExecution: true,
                routingHint: .requireConfirmation
            )
        }

        if ShellInputRecognizer.looksLikeShellCommand(normalized) {
            return InputClassification(
                category: .shellCommand,
                confidence: 0.9,
                routingHint: .executeInShell
            )
        }

        if let suggestion = nearestCommandSuggestion(for: normalized) {
            return InputClassification(
                category: .shellCommand,
                confidence: 0.72,
                routingHint: .executeInShell,
                suggestedCommand: suggestion
            )
        }

        return InputClassification(
            category: .unknown,
            confidence: 0.25,
            routingHint: .none
        )
    }

    private func nearestCommandSuggestion(for input: String) -> String? {
        guard let firstToken = ShellInputRecognizer.firstToken(in: input),
              firstToken.count >= 2,
              !firstToken.contains("/")
        else {
            return nil
        }
        guard hasShellArgumentCue(afterFirstTokenIn: input) else {
            return nil
        }

        return ShellInputRecognizer.commonCommands
            .filter { abs($0.count - firstToken.count) <= 1 }
            .map { command in
                (command: command, distance: editDistance(firstToken, command))
            }
            .filter { $0.distance == 1 || isAdjacentTransposition(firstToken, $0.command) }
            .sorted { lhs, rhs in
                lhs.command < rhs.command
            }
            .first?
            .command
    }

    private func hasShellArgumentCue(afterFirstTokenIn input: String) -> Bool {
        let parts = ShellInputRecognizer.normalized(input).split(separator: " ").map(String.init)
        let rest = parts.dropFirst()
        guard !rest.isEmpty else { return false }

        let knownSubcommands: Set<String> = [
            "add", "build", "checkout", "commit", "diff", "install", "list",
            "log", "pull", "push", "run", "status", "test", "version"
        ]
        return rest.contains { token in
            token.hasPrefix("-")
                || token.contains("/")
                || token.contains(".")
                || knownSubcommands.contains(token.lowercased())
        }
    }

    private func isAdjacentTransposition(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs)
        let right = Array(rhs)
        guard left.count == right.count, left.count >= 2 else { return false }

        for index in 0..<(left.count - 1) {
            var swapped = left
            swapped.swapAt(index, index + 1)
            if swapped == right {
                return true
            }
        }
        return false
    }

    private func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                if left[leftIndex - 1] == right[rightIndex - 1] {
                    current[rightIndex] = previous[rightIndex - 1]
                } else {
                    current[rightIndex] = min(
                        previous[rightIndex],
                        current[rightIndex - 1],
                        previous[rightIndex - 1]
                    ) + 1
                }
            }
            previous = current
        }

        return previous[right.count]
    }
}
