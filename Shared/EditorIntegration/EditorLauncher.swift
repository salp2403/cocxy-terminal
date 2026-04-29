// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorLauncher.swift - Shared editor integration models.

import Foundation

public enum EditorLaunchStyle: String, Codable, Sendable, Equatable {
    case gui
    case terminal
    case systemDefault
}

public struct EditorLauncher: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let bundleIdentifiers: [String]
    public let executableNames: [String]
    public let style: EditorLaunchStyle
    public let supportsLineColumn: Bool

    public init(
        id: String,
        displayName: String,
        bundleIdentifiers: [String],
        executableNames: [String],
        style: EditorLaunchStyle = .gui,
        supportsLineColumn: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.executableNames = executableNames
        self.style = style
        self.supportsLineColumn = supportsLineColumn
    }
}

public struct EditorOpenRequest: Sendable, Equatable {
    public let filePath: String
    public let editorID: String?
    public let line: Int?
    public let column: Int?

    public init(filePath: String, editorID: String?, line: Int? = nil, column: Int? = nil) {
        self.filePath = filePath
        self.editorID = editorID
        self.line = line
        self.column = column
    }
}

public struct EditorLaunchPlan: Sendable, Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let displayName: String
    public let launchesTerminalEditor: Bool

    public init(
        executablePath: String,
        arguments: [String],
        displayName: String,
        launchesTerminalEditor: Bool = false
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.displayName = displayName
        self.launchesTerminalEditor = launchesTerminalEditor
    }
}

public enum EditorRegistry {
    public static let systemDefaultID = "system"

    public static let builtIn: [EditorLauncher] = [
        EditorLauncher(
            id: "vscode",
            displayName: "VS Code",
            bundleIdentifiers: ["com.microsoft.VSCode"],
            executableNames: ["code"]
        ),
        EditorLauncher(
            id: "cursor",
            displayName: "Cursor",
            bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
            executableNames: ["cursor"]
        ),
        EditorLauncher(
            id: "sublime",
            displayName: "Sublime Text",
            bundleIdentifiers: ["com.sublimetext.4", "com.sublimetext.3"],
            executableNames: ["subl"]
        ),
        EditorLauncher(
            id: "zed",
            displayName: "Zed",
            bundleIdentifiers: ["dev.zed.Zed"],
            executableNames: ["zed"]
        ),
        EditorLauncher(
            id: "xcode",
            displayName: "Xcode",
            bundleIdentifiers: ["com.apple.dt.Xcode"],
            executableNames: ["xed"]
        ),
        EditorLauncher(
            id: "emacs",
            displayName: "Emacs",
            bundleIdentifiers: ["org.gnu.Emacs"],
            executableNames: ["emacsclient"]
        ),
        EditorLauncher(
            id: "aquamacs",
            displayName: "Aquamacs",
            bundleIdentifiers: ["org.gnu.Aquamacs"],
            executableNames: []
        ),
        EditorLauncher(
            id: "bbedit",
            displayName: "BBEdit",
            bundleIdentifiers: ["com.barebones.bbedit"],
            executableNames: ["bbedit"]
        ),
        EditorLauncher(
            id: "textmate",
            displayName: "TextMate",
            bundleIdentifiers: ["com.macromates.TextMate"],
            executableNames: ["mate"]
        ),
        EditorLauncher(
            id: "intellij",
            displayName: "IntelliJ IDEA",
            bundleIdentifiers: ["com.jetbrains.intellij"],
            executableNames: ["idea"]
        ),
        EditorLauncher(
            id: "neovim",
            displayName: "Neovim",
            bundleIdentifiers: [],
            executableNames: ["nvim"],
            style: .terminal
        ),
        EditorLauncher(
            id: "helix",
            displayName: "Helix",
            bundleIdentifiers: [],
            executableNames: ["hx"],
            style: .terminal
        ),
    ]

    public static func launcher(matching rawID: String?) -> EditorLauncher? {
        guard let rawID, rawID.isEmpty == false else { return nil }
        let normalized = normalize(rawID)
        return builtIn.first { launcher in
            normalize(launcher.id) == normalized
                || normalize(launcher.displayName) == normalized
                || launcher.executableNames.contains { normalize($0) == normalized }
        }
    }

    public static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

public enum EditorLaunchPlanner {
    public static func plan(
        request: EditorOpenRequest,
        launcher: EditorLauncher?,
        executablePath: String?,
        bundleIdentifier: String?
    ) -> EditorLaunchPlan {
        let filePath = URL(fileURLWithPath: request.filePath).standardizedFileURL.path

        guard let launcher else {
            return EditorLaunchPlan(
                executablePath: "/usr/bin/open",
                arguments: [filePath],
                displayName: "Default Editor"
            )
        }

        if let executablePath {
            return EditorLaunchPlan(
                executablePath: executablePath,
                arguments: commandArguments(for: launcher, filePath: filePath, line: request.line, column: request.column),
                displayName: launcher.displayName,
                launchesTerminalEditor: launcher.style == .terminal
            )
        }

        if let bundleIdentifier {
            return EditorLaunchPlan(
                executablePath: "/usr/bin/open",
                arguments: ["-b", bundleIdentifier, filePath],
                displayName: launcher.displayName,
                launchesTerminalEditor: false
            )
        }

        return EditorLaunchPlan(
            executablePath: "/usr/bin/open",
            arguments: [filePath],
            displayName: "Default Editor"
        )
    }

    public static func commandArguments(
        for launcher: EditorLauncher,
        filePath: String,
        line: Int?,
        column: Int?
    ) -> [String] {
        let line = line.flatMap { $0 > 0 ? $0 : nil }
        let column = column.flatMap { $0 > 0 ? $0 : nil }

        switch launcher.id {
        case "vscode", "cursor":
            if let line {
                return ["-g", "\(filePath):\(line):\(column ?? 1)"]
            }
            return [filePath]
        case "sublime", "zed":
            if let line {
                return ["\(filePath):\(line):\(column ?? 1)"]
            }
            return [filePath]
        case "xcode":
            if let line {
                return ["--line", "\(line)", filePath]
            }
            return [filePath]
        case "bbedit", "textmate":
            if let line {
                return ["\(filePath):\(line)"]
            }
            return [filePath]
        case "intellij":
            if let line {
                return ["--line", "\(line)", filePath]
            }
            return [filePath]
        case "emacs":
            if let line {
                return ["-n", "+\(line):\(column ?? 1)", filePath]
            }
            return ["-n", filePath]
        case "aquamacs":
            return [filePath]
        case "neovim", "helix":
            if let line {
                return ["+\(line)", filePath]
            }
            return [filePath]
        default:
            return [filePath]
        }
    }
}
