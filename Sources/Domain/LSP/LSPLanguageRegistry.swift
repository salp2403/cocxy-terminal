// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPLanguageRegistry.swift - Language-to-server metadata for local LSP use.

import Foundation

struct LSPInstallSuggestion: Equatable, Sendable {
    let message: String
    let command: String?
    let allowsAutomaticInstall: Bool

    init(message: String, command: String? = nil, allowsAutomaticInstall: Bool = false) {
        self.message = message
        self.command = command
        self.allowsAutomaticInstall = allowsAutomaticInstall
    }
}

struct LSPServerConfiguration: Equatable, Sendable {
    let languageID: String
    let displayName: String
    let fileExtensions: [String]
    let executableNames: [String]
    let arguments: [String]
    let installSuggestion: LSPInstallSuggestion

    var allowsAutomaticInstall: Bool {
        installSuggestion.allowsAutomaticInstall
    }
}

struct LSPLanguageRegistry: Equatable, Sendable {
    let servers: [LSPServerConfiguration]

    var languageIDs: [String] {
        servers.map(\.languageID)
    }

    func server(forLanguageID languageID: String) -> LSPServerConfiguration? {
        let normalized = languageID.lowercased()
        return servers.first { $0.languageID == normalized }
    }

    func server(forFileURL fileURL: URL) -> LSPServerConfiguration? {
        let ext = fileURL.pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return servers.first { $0.fileExtensions.contains(ext) }
    }

    static let defaults = LSPLanguageRegistry(servers: [
        LSPServerConfiguration(
            languageID: "swift",
            displayName: "Swift",
            fileExtensions: ["swift"],
            executableNames: ["sourcekit-lsp"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install Xcode or Xcode Command Line Tools to provide sourcekit-lsp."
            )
        ),
        LSPServerConfiguration(
            languageID: "rust",
            displayName: "Rust",
            fileExtensions: ["rs"],
            executableNames: ["rust-analyzer"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install rust-analyzer with Homebrew, then enable Rust LSP in Cocxy preferences.",
                command: "brew install rust-analyzer"
            )
        ),
        LSPServerConfiguration(
            languageID: "typescript",
            displayName: "TypeScript",
            fileExtensions: ["ts", "tsx"],
            executableNames: ["typescript-language-server"],
            arguments: ["--stdio"],
            installSuggestion: LSPInstallSuggestion(
                message: "Install typescript-language-server with Homebrew, then enable TypeScript LSP in Cocxy preferences.",
                command: "brew install typescript-language-server"
            )
        ),
        LSPServerConfiguration(
            languageID: "javascript",
            displayName: "JavaScript",
            fileExtensions: ["js", "jsx", "mjs", "cjs"],
            executableNames: ["typescript-language-server"],
            arguments: ["--stdio"],
            installSuggestion: LSPInstallSuggestion(
                message: "Install typescript-language-server with Homebrew, then enable JavaScript LSP in Cocxy preferences.",
                command: "brew install typescript-language-server"
            )
        ),
        LSPServerConfiguration(
            languageID: "python",
            displayName: "Python",
            fileExtensions: ["py", "pyi"],
            executableNames: ["pyright-langserver"],
            arguments: ["--stdio"],
            installSuggestion: LSPInstallSuggestion(
                message: "Install pyright with Homebrew, then enable Python LSP in Cocxy preferences.",
                command: "brew install pyright"
            )
        ),
        LSPServerConfiguration(
            languageID: "go",
            displayName: "Go",
            fileExtensions: ["go"],
            executableNames: ["gopls"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install gopls with Homebrew, then enable Go LSP in Cocxy preferences.",
                command: "brew install gopls"
            )
        ),
        LSPServerConfiguration(
            languageID: "kotlin",
            displayName: "Kotlin",
            fileExtensions: ["kt", "kts"],
            executableNames: ["kotlin-language-server"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install kotlin-language-server with Homebrew, then enable Kotlin LSP in Cocxy preferences.",
                command: "brew install kotlin-language-server"
            )
        ),
        LSPServerConfiguration(
            languageID: "java",
            displayName: "Java",
            fileExtensions: ["java"],
            executableNames: ["jdtls"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install jdtls with Homebrew, then enable Java LSP in Cocxy preferences.",
                command: "brew install jdtls"
            )
        ),
        LSPServerConfiguration(
            languageID: "c",
            displayName: "C",
            fileExtensions: ["c"],
            executableNames: ["clangd"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install llvm with Homebrew to provide clangd, then enable C LSP in Cocxy preferences.",
                command: "brew install llvm"
            )
        ),
        LSPServerConfiguration(
            languageID: "cpp",
            displayName: "C++",
            fileExtensions: ["cc", "cpp", "cxx", "hpp", "hh", "hxx"],
            executableNames: ["clangd"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install llvm with Homebrew to provide clangd, then enable C++ LSP in Cocxy preferences.",
                command: "brew install llvm"
            )
        ),
        LSPServerConfiguration(
            languageID: "ruby",
            displayName: "Ruby",
            fileExtensions: ["rb"],
            executableNames: ["ruby-lsp"],
            arguments: [],
            installSuggestion: LSPInstallSuggestion(
                message: "Install ruby-lsp with Homebrew, then enable Ruby LSP in Cocxy preferences.",
                command: "brew install ruby-lsp"
            )
        ),
        LSPServerConfiguration(
            languageID: "php",
            displayName: "PHP",
            fileExtensions: ["php"],
            executableNames: ["intelephense"],
            arguments: ["--stdio"],
            installSuggestion: LSPInstallSuggestion(
                message: "Install Intelephense, configure its path, then enable PHP LSP in Cocxy preferences."
            )
        ),
        LSPServerConfiguration(
            languageID: "bash",
            displayName: "Bash",
            fileExtensions: ["sh", "bash", "zsh"],
            executableNames: ["bash-language-server"],
            arguments: ["start"],
            installSuggestion: LSPInstallSuggestion(
                message: "Install bash-language-server with Homebrew, then enable Bash LSP in Cocxy preferences.",
                command: "brew install bash-language-server"
            )
        ),
    ])
}
