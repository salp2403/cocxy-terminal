// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

public struct CommonTyposDictionary: Sendable, Equatable {
    private let replacements: [String: String]

    public var count: Int {
        replacements.count
    }

    public init(replacements: [String: String]) {
        self.replacements = replacements.reduce(into: [:]) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
    }

    public func replacement(for token: String) -> String? {
        replacements[token.lowercased()]
    }

    public static let `default` = CommonTyposDictionary(replacements: [
        "ack-grep": "ack",
        "apt-gett": "apt-get",
        "bre": "brew",
        "breaw": "brew",
        "breq": "brew",
        "brwe": "brew",
        "brw": "brew",
        "buundle": "bundle",
        "bunlde": "bundle",
        "carog": "cargo",
        "cargp": "cargo",
        "catn": "cat",
        "cd..": "cd ..",
        "chmdo": "chmod",
        "chwon": "chown",
        "claer": "clear",
        "clera": "clear",
        "clrar": "clear",
        "cpoy": "cp",
        "dcoker": "docker",
        "dicker": "docker",
        "docke": "docker",
        "dockr": "docker",
        "docekr": "docker",
        "gti": "git",
        "got": "git",
        "grpe": "grep",
        "gtiub": "gh",
        "gtihub": "gh",
        "gut": "git",
        "improt": "import",
        "javascrip": "javascript",
        "kubctl": "kubectl",
        "kubeclt": "kubectl",
        "kuebctl": "kubectl",
        "ls-la": "ls -la",
        "mkae": "make",
        "mkidr": "mkdir",
        "mroe": "more",
        "mvoe": "mv",
        "nmp": "npm",
        "npn": "npm",
        "pnmp": "pnpm",
        "pnpmx": "pnpm",
        "pyhton": "python",
        "pyhon": "python",
        "pythno": "python",
        "pythom": "python",
        "pytohn": "python",
        "rgp": "rg",
        "rgi": "rg",
        "rmeove": "rm",
        "sl": "ls",
        "sodu": "sudo",
        "sud": "sudo",
        "swfit": "swift",
        "swft": "swift",
        "taill": "tail",
        "tets": "test",
        "touc": "touch",
        "tuch": "touch",
        "vmi": "vim",
        "wgett": "wget",
        "yarnn": "yarn",
        "zigg": "zig",
        "zshh": "zsh"
    ])
}

public struct CommonTypoCorrectionProvider: CommandCorrectionProvider {
    private let dictionary: CommonTyposDictionary

    public init(dictionary: CommonTyposDictionary = .default) {
        self.dictionary = dictionary
    }

    public func corrections(for context: CommandCorrectionContext) -> [CommandCorrection] {
        guard let split = CommandCorrectionCommandLine.splitFirstToken(context.command),
              let replacement = dictionary.replacement(for: split.firstToken),
              replacement != split.firstToken
        else {
            return []
        }

        let suggestion: String
        if replacement.contains(" ") {
            suggestion = replacement + split.suffix
        } else {
            suggestion = CommandCorrectionCommandLine.replacingFirstToken(
                in: context.command,
                with: replacement
            )
        }

        return [
            CommandCorrection(
                original: context.normalizedCommand,
                suggestion: suggestion,
                reason: "Recognized common shell typo",
                confidence: 0.97,
                source: .commonTypo
            )
        ]
    }
}
