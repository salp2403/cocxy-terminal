// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCommandCorrections

@Suite("Command corrections engine")
struct CommandCorrectionsEngineSwiftTestingTests {

    @Test("common typo dictionary covers required shell misses")
    func commonTypoDictionaryCoversRequiredShellMisses() {
        let dictionary = CommonTyposDictionary.default

        #expect(dictionary.count >= 50)
        #expect(dictionary.replacement(for: "gti") == "git")
        #expect(dictionary.replacement(for: "sl") == "ls")
        #expect(dictionary.replacement(for: "pyhton") == "python")
    }

    @Test("failed typo command suggests full replacement with high confidence")
    func failedTypoCommandSuggestsFullReplacement() {
        let engine = CommandCorrectionEngine.localDefault()
        let context = CommandCorrectionContext(
            command: "gti status",
            exitCode: 127,
            stderr: "zsh: command not found: gti"
        )

        let suggestions = engine.corrections(for: context)

        #expect(suggestions.first?.suggestion == "git status")
        #expect((suggestions.first?.confidence ?? 0) > 0.9)
    }

    @Test("sl maps to ls even without arguments")
    func slMapsToLsEvenWithoutArguments() {
        let engine = CommandCorrectionEngine.localDefault()

        let suggestions = engine.corrections(for: CommandCorrectionContext(command: "sl", exitCode: 127))

        #expect(suggestions.first?.suggestion == "ls")
    }

    @Test("python typo preserves arguments")
    func pythonTypoPreservesArguments() {
        let engine = CommandCorrectionEngine.localDefault()

        let suggestions = engine.corrections(
            for: CommandCorrectionContext(command: "pyhton -m venv .", exitCode: 127)
        )

        #expect(suggestions.contains { $0.suggestion == "python -m venv ." || $0.suggestion == "python3 -m venv ." })
    }

    @Test("path corrections use neighboring filesystem entries")
    func pathCorrectionsUseNeighboringFilesystemEntries() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-command-correction-\(UUID().uuidString)", isDirectory: true)
        let correct = root.appendingPathComponent("local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: correct, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let engine = CommandCorrectionEngine.localDefault()
        let badPath = root.appendingPathComponent("locl/bin", isDirectory: true).path

        let suggestions = engine.corrections(
            for: CommandCorrectionContext(
                command: "cd \(badPath)",
                exitCode: 1,
                stderr: "cd: no such file or directory: \(badPath)",
                workingDirectory: root
            )
        )

        #expect(suggestions.first?.suggestion == "cd \(correct.path)")
    }

    @Test("shell hint parser extracts zsh corrections")
    func shellHintParserExtractsZshCorrections() {
        let provider = ShellHintCorrectionProvider()
        let context = CommandCorrectionContext(
            command: "gti status",
            exitCode: 127,
            stderr: "zsh: correct 'gti' to 'git' [nyae]?"
        )

        let suggestions = provider.corrections(for: context)

        #expect(suggestions.first?.suggestion == "git status")
        #expect(suggestions.first?.source == .shellHint)
    }

    @Test("composer deduplicates by suggestion and keeps strongest confidence")
    func composerDeduplicatesBySuggestionAndKeepsStrongestConfidence() {
        let composer = CorrectionComposer(providers: [
            StaticCorrectionProvider([
                CommandCorrection(
                    original: "gti status",
                    suggestion: "git status",
                    reason: "weak",
                    confidence: 0.6,
                    source: .editDistance
                )
            ]),
            StaticCorrectionProvider([
                CommandCorrection(
                    original: "gti status",
                    suggestion: "git status",
                    reason: "strong",
                    confidence: 0.96,
                    source: .commonTypo
                )
            ])
        ])

        let suggestions = composer.corrections(for: CommandCorrectionContext(command: "gti status", exitCode: 127))

        #expect(suggestions.count == 1)
        #expect(suggestions[0].confidence == 0.96)
        #expect(suggestions[0].source == .commonTypo)
    }

    @Test("listener ignores successful and disabled executions")
    func listenerIgnoresSuccessfulAndDisabledExecutions() {
        let listener = CommandCorrectionListener(engine: .localDefault())
        let execution = CommandExecutionSnapshot(command: "gti status", exitCode: 127)

        #expect(listener.suggestion(for: CommandExecutionSnapshot(command: "git status", exitCode: 0), enabled: true) == nil)
        #expect(listener.suggestion(for: execution, enabled: false) == nil)
        #expect(listener.suggestion(for: execution, enabled: true)?.suggestion == "git status")
    }

    @Test("heuristic command corrections stay under interactive latency budget")
    func heuristicCommandCorrectionsStayUnderInteractiveLatencyBudget() {
        let engine = CommandCorrectionEngine.localDefault(
            foundationModelsEnabled: false,
            agentFallback: false
        )
        let commands = [
            "gti status",
            "sl",
            "pyhton -m venv .",
            "kubctl get pods",
            "swfit test",
            "rgp CommandCorrection"
        ]
        let iterations = 500
        let start = ContinuousClock.now

        for index in 0..<iterations {
            _ = engine.corrections(
                for: CommandCorrectionContext(
                    command: commands[index % commands.count],
                    exitCode: 127,
                    stderr: "zsh: command not found"
                )
            )
        }

        let elapsed = start.duration(to: .now)
        let averageNanoseconds = Double(elapsed.components.seconds) * 1_000_000_000
            + Double(elapsed.components.attoseconds) / 1_000_000_000
        let averageMilliseconds = (averageNanoseconds / Double(iterations)) / 1_000_000

        #expect(averageMilliseconds < 5)
    }
}

private struct StaticCorrectionProvider: CommandCorrectionProvider {
    let values: [CommandCorrection]

    init(_ values: [CommandCorrection]) {
        self.values = values
    }

    func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        values
    }
}
