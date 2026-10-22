// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+ProjectSocketAuthorization.swift - Exact project command approval targets.

import AppKit

extension AppDelegate {
    func projectSocketPresentationTarget(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        controller: MainWindowController
    ) -> SocketPrivilegedCommandPresentationTarget? {
        switch request.command {
        case .projectOpen:
            return projectOpenSocketPresentationTarget(
                for: request,
                controller: controller
            )
        case .projectClone:
            return projectCloneSocketPresentationTarget(
                for: request,
                controller: controller
            )
        default:
            return nil
        }
    }

    private func projectOpenSocketPresentationTarget(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        controller: MainWindowController
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard let rawPath = boundedProjectPath(request.params["path"]) else { return nil }
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

    private func projectCloneSocketPresentationTarget(
        for request: SocketPrivilegedCommandAuthorizationRequest,
        controller: MainWindowController
    ) -> SocketPrivilegedCommandPresentationTarget? {
        guard let rawParent = boundedProjectPath(request.params["parent"]),
              let rawRemote = request.params["remote"],
              let remote = try? ProjectCloneService.validatedRemote(rawRemote) else {
            return nil
        }
        let parent = URL(fileURLWithPath: (rawParent as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        let remoteDisplay = [remote.host, remote.path]
            .compactMap { $0 }
            .joined()
        return SocketPrivilegedCommandPresentationTarget(
            context: SocketPrivilegedCommandContext(
                scope: .project,
                windowControllerIdentifier: ObjectIdentifier(controller),
                tabID: nil,
                workingDirectory: parent.path,
                localResourcePaths: ["parent": parent.path],
                authorityDetails: [
                    "operation": "clone",
                    "remote": remote.absoluteString,
                ],
                surfaceID: nil,
                browserViewModelIdentifier: nil,
                browserTabID: nil,
                browserURL: nil,
                targetDisplayName: "Clone \(remoteDisplay) into \(parent.path)"
            ),
            controller: controller
        )
    }

    private func boundedProjectPath(_ path: String?) -> String? {
        guard let path,
              !path.isEmpty,
              path.utf8.count <= 4_096,
              !path.contains("\0") else {
            return nil
        }
        return path
    }
}
