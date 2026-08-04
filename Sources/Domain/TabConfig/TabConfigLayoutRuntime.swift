// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabConfigLayoutRuntime.swift - Runtime validation for project pane layouts.

import Foundation

enum TabConfigLayoutRuntimeError: Error, Equatable, LocalizedError {
    case projectDirectoryUnavailable(String)
    case pathUnavailable(String)
    case pathOutsideProject(String)
    case expectedDirectory(String)
    case expectedFile(String)
    case inconsistentLayout(String)

    var errorDescription: String? {
        switch self {
        case .projectDirectoryUnavailable:
            return "The project directory is unavailable."
        case .pathUnavailable:
            return "A saved pane path is unavailable."
        case .pathOutsideProject:
            return "A saved pane path is outside the project."
        case .expectedDirectory:
            return "A saved terminal directory is unavailable."
        case .expectedFile:
            return "A saved pane file is unavailable."
        case .inconsistentLayout:
            return "The saved pane layout is inconsistent."
        }
    }
}

struct ResolvedTabConfigPane: Equatable, Sendable {
    let type: PanelType
    let workingDirectory: URL?
    let fileURL: URL?
    let initialURL: URL?
    let title: String?
}

struct TabConfigLayoutRuntimeWarning: Equatable, Sendable {
    let paneType: PanelType
    let title: String?
    let reason: String
}

struct ResolvedTabConfigLayoutReport: Equatable, Sendable {
    let layout: ResolvedTabConfigLayout
    let warnings: [TabConfigLayoutRuntimeWarning]
}

indirect enum ResolvedTabConfigLayout: Equatable, Sendable {
    case pane(ResolvedTabConfigPane)
    case split(
        direction: SplitDirection,
        ratio: Double,
        first: ResolvedTabConfigLayout,
        second: ResolvedTabConfigLayout
    )

    var firstPane: ResolvedTabConfigPane {
        switch self {
        case .pane(let pane):
            return pane
        case .split(_, _, let first, _):
            return first.firstPane
        }
    }
}

struct TabConfigLayoutRuntimeResolver {
    private enum ExpectedPathKind {
        case directory
        case file
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func resolve(
        _ layout: TabConfigLayout,
        projectDirectory: URL
    ) throws -> ResolvedTabConfigLayout {
        try TabConfigLayoutTOMLCodec.validate(layout)
        let projectRoot = try canonicalProjectDirectory(projectDirectory)
        return try resolveNode(layout, projectRoot: projectRoot)
    }

    func resolveBestEffort(
        _ layout: TabConfigLayout,
        projectDirectory: URL
    ) throws -> ResolvedTabConfigLayoutReport {
        try TabConfigLayoutTOMLCodec.validate(layout)
        let projectRoot = try canonicalProjectDirectory(projectDirectory)
        var warnings: [TabConfigLayoutRuntimeWarning] = []
        let resolved = resolveNodeBestEffort(
            layout,
            projectRoot: projectRoot,
            warnings: &warnings
        )
        return ResolvedTabConfigLayoutReport(layout: resolved, warnings: warnings)
    }

    func canonicalProjectDirectory(_ directory: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        let standardized = directory.standardizedFileURL
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw TabConfigLayoutRuntimeError.projectDirectoryUnavailable(standardized.path)
        }
        return standardized.resolvingSymlinksInPath().standardizedFileURL
    }

    func projectRelativePath(
        for target: URL,
        projectDirectory: URL,
        expectedDirectory: Bool
    ) throws -> String {
        let projectRoot = try canonicalProjectDirectory(projectDirectory)
        let kind: ExpectedPathKind = expectedDirectory ? .directory : .file
        let canonicalTarget = try canonicalExistingPath(target, expectedKind: kind)
        guard Self.contains(canonicalTarget, in: projectRoot) else {
            throw TabConfigLayoutRuntimeError.pathOutsideProject(target.path)
        }
        if canonicalTarget.path == projectRoot.path {
            return "."
        }
        return String(canonicalTarget.path.dropFirst(projectRoot.path.count + 1))
    }

    private func resolveNode(
        _ layout: TabConfigLayout,
        projectRoot: URL
    ) throws -> ResolvedTabConfigLayout {
        switch layout {
        case .pane(let pane):
            return .pane(try resolvePane(pane, projectRoot: projectRoot))
        case .split(let direction, let ratio, let first, let second):
            return .split(
                direction: direction,
                ratio: ratio,
                first: try resolveNode(first, projectRoot: projectRoot),
                second: try resolveNode(second, projectRoot: projectRoot)
            )
        }
    }

    private func resolveNodeBestEffort(
        _ layout: TabConfigLayout,
        projectRoot: URL,
        warnings: inout [TabConfigLayoutRuntimeWarning]
    ) -> ResolvedTabConfigLayout {
        switch layout {
        case .pane(let pane):
            do {
                return .pane(try resolvePane(pane, projectRoot: projectRoot))
            } catch {
                warnings.append(TabConfigLayoutRuntimeWarning(
                    paneType: pane.type,
                    title: pane.title,
                    reason: error.localizedDescription
                ))
                return .pane(ResolvedTabConfigPane(
                    type: .terminal,
                    workingDirectory: projectRoot,
                    fileURL: nil,
                    initialURL: nil,
                    title: pane.title
                ))
            }
        case .split(let direction, let ratio, let first, let second):
            return .split(
                direction: direction,
                ratio: ratio,
                first: resolveNodeBestEffort(
                    first,
                    projectRoot: projectRoot,
                    warnings: &warnings
                ),
                second: resolveNodeBestEffort(
                    second,
                    projectRoot: projectRoot,
                    warnings: &warnings
                )
            )
        }
    }

    private func resolvePane(
        _ pane: TabConfigPane,
        projectRoot: URL
    ) throws -> ResolvedTabConfigPane {
        let workingDirectory: URL?
        if pane.type == .terminal {
            workingDirectory = try resolveRelativePath(
                pane.workingDirectory ?? ".",
                projectRoot: projectRoot,
                expectedKind: .directory
            )
        } else {
            workingDirectory = nil
        }

        let fileURL: URL?
        if let filePath = pane.filePath {
            fileURL = try resolveRelativePath(
                filePath,
                projectRoot: projectRoot,
                expectedKind: Self.pathKind(for: pane.type)
            )
        } else if Self.usesProjectDirectoryByDefault(pane.type) {
            fileURL = projectRoot
        } else {
            fileURL = nil
        }

        return ResolvedTabConfigPane(
            type: pane.type,
            workingDirectory: workingDirectory,
            fileURL: fileURL,
            initialURL: pane.initialURL,
            title: pane.title
        )
    }

    private func resolveRelativePath(
        _ relativePath: String,
        projectRoot: URL,
        expectedKind: ExpectedPathKind
    ) throws -> URL {
        guard TabConfigLayoutTOMLCodec.isSafeRelativePath(relativePath) else {
            throw TabConfigLayoutRuntimeError.pathOutsideProject(relativePath)
        }
        let candidate = projectRoot
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        guard Self.contains(candidate, in: projectRoot) else {
            throw TabConfigLayoutRuntimeError.pathOutsideProject(relativePath)
        }
        let canonical = try canonicalExistingPath(candidate, expectedKind: expectedKind)
        guard Self.contains(canonical, in: projectRoot) else {
            throw TabConfigLayoutRuntimeError.pathOutsideProject(relativePath)
        }
        return canonical
    }

    private func canonicalExistingPath(
        _ target: URL,
        expectedKind: ExpectedPathKind
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        let standardized = target.standardizedFileURL
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
            throw TabConfigLayoutRuntimeError.pathUnavailable(standardized.path)
        }
        let canonical = standardized.resolvingSymlinksInPath().standardizedFileURL
        switch expectedKind {
        case .directory where !isDirectory.boolValue:
            throw TabConfigLayoutRuntimeError.expectedDirectory(standardized.path)
        case .file:
            let values = try? canonical.resourceValues(forKeys: [.isRegularFileKey])
            guard !isDirectory.boolValue, values?.isRegularFile == true else {
                throw TabConfigLayoutRuntimeError.expectedFile(standardized.path)
            }
        default:
            break
        }
        return canonical
    }

    private static func pathKind(for type: PanelType) -> ExpectedPathKind {
        switch type {
        case .aiEditHistory, .templates, .macros, .dbCloud, .projectHome:
            return .directory
        default:
            return .file
        }
    }

    private static func usesProjectDirectoryByDefault(_ type: PanelType) -> Bool {
        switch type {
        case .aiEditHistory, .templates, .macros, .dbCloud, .projectHome:
            return true
        default:
            return false
        }
    }

    private static func contains(_ target: URL, in root: URL) -> Bool {
        if root.path == "/" {
            return target.path.hasPrefix("/")
        }
        return target.path == root.path || target.path.hasPrefix(root.path + "/")
    }
}
