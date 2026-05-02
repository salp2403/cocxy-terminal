// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPServerDiscovery.swift - Local server lookup without automatic installs.

import Foundation

enum LSPServerResolutionSource: Equatable, Sendable {
    case configuredPath
    case pathLookup
}

enum LSPServerResolution: Equatable, Sendable {
    case available(path: String, source: LSPServerResolutionSource)
    case missing(LSPInstallSuggestion)
}

struct LSPServerDiscovery {
    typealias ExecutableResolver = @Sendable (String) -> String?
    typealias HomebrewDetector = @Sendable () -> Bool

    private let executableResolver: ExecutableResolver
    private let homebrewDetector: HomebrewDetector

    init(
        executableResolver: @escaping ExecutableResolver = { executable in
            LSPServerDiscovery.defaultExecutableResolver(executable)
        },
        homebrewDetector: @escaping HomebrewDetector = {
            LSPServerDiscovery.defaultHomebrewDetector()
        }
    ) {
        self.executableResolver = executableResolver
        self.homebrewDetector = homebrewDetector
    }

    func resolve(
        _ server: LSPServerConfiguration,
        configuredExecutablePath: String? = nil
    ) -> LSPServerResolution {
        if let configuredExecutablePath,
           !configuredExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .available(path: configuredExecutablePath, source: .configuredPath)
        }

        for executableName in server.executableNames {
            if let path = executableResolver(executableName) {
                return .available(path: path, source: .pathLookup)
            }
        }

        return .missing(adjustedSuggestionForHomebrew(server.installSuggestion))
    }

    private func adjustedSuggestionForHomebrew(_ suggestion: LSPInstallSuggestion) -> LSPInstallSuggestion {
        guard let command = suggestion.command, command.hasPrefix("brew install"), !homebrewDetector() else {
            return suggestion
        }

        return LSPInstallSuggestion(
            message: "\(suggestion.message) Homebrew was not detected; install Homebrew first or configure the server path manually.",
            command: command,
            allowsAutomaticInstall: suggestion.allowsAutomaticInstall
        )
    }

    private static func defaultExecutableResolver(_ executable: String) -> String? {
        let pathEnvironment = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for directory in pathEnvironment.split(separator: ":") {
            let candidate = "\(directory)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func defaultHomebrewDetector() -> Bool {
        defaultExecutableResolver("brew") != nil
    }
}
