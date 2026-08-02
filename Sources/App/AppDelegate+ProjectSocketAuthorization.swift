// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+ProjectSocketAuthorization.swift - Exact project-open approval target.

import AppKit

extension AppDelegate {
    func projectSocketPresentationTarget(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        controller: MainWindowController
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard request.command == .projectOpen,
              let rawPath = request.params["path"],
              !rawPath.isEmpty,
              rawPath.utf8.count <= 4_096,
              !rawPath.contains("\0") else {
            return nil
        }
        let requestedPath = URL(fileURLWithPath: (rawPath as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: requestedPath.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        let path = projectResolver.resolveProject(for: requestedPath).groupingRootURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return SocketPrivilegedCommandPresentationTarget(
            context: SocketPrivilegedCommandContext(
                scope: .project,
                windowControllerIdentifier: ObjectIdentifier(controller),
                tabID: nil,
                workingDirectory: path.path,
                localResourcePaths: ["path": path.path],
                surfaceID: nil,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                targetDisplayName: "Open project \(path.path)"
            ),
            controller: controller
        )
    }
}
