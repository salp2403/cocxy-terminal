// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TaskQueue.swift - Task queue sheet and palette wiring.

import AppKit
import SwiftUI

private enum TaskQueueCenterAccessError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "Task queue is still starting or unavailable"
    }
}

@MainActor
extension MainWindowController {
    func showTaskQueueCenter() {
        guard let window,
              let delegate = NSApp.delegate as? AppDelegate else {
            return
        }

        let localizer = appLocalizer()
        let defaultWorktree = tabManager.activeTab?.workingDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path ?? FileManager.default.homeDirectoryForCurrentUser.path
        let defaultProject = projectResolver.resolveProject(
            for: URL(fileURLWithPath: defaultWorktree, isDirectory: true)
        ).groupingRootURL.path
        let operations = TaskQueueCenterOperations(
            load: { [weak delegate] in
                guard let delegate,
                      delegate.taskQueueIsReady,
                      let queue = delegate.taskQueue else {
                    throw TaskQueueCenterAccessError.unavailable
                }
                return await queue.list()
            },
            enqueue: { [weak delegate] draft in
                guard let delegate,
                      delegate.taskQueueIsReady,
                      let queue = delegate.taskQueue else {
                    throw TaskQueueCenterAccessError.unavailable
                }
                let item = try await Task.detached(priority: .userInitiated) {
                    try draft.makeItem()
                }.value
                return try await queue.enqueue(item)
            },
            cancel: { [weak delegate] taskID in
                guard let delegate,
                      delegate.taskQueueIsReady,
                      let queue = delegate.taskQueue else {
                    throw TaskQueueCenterAccessError.unavailable
                }
                return try await queue.cancel(id: taskID)
            },
            rerun: { [weak delegate] taskID in
                guard let delegate,
                      delegate.taskQueueIsReady,
                      let queue = delegate.taskQueue else {
                    throw TaskQueueCenterAccessError.unavailable
                }
                return try await queue.rerun(id: taskID)
            },
            remove: { [weak delegate] taskID in
                guard let delegate,
                      delegate.taskQueueIsReady,
                      let queue = delegate.taskQueue else {
                    throw TaskQueueCenterAccessError.unavailable
                }
                return try await queue.remove(id: taskID)
            }
        )
        let viewModel = TaskQueueCenterViewModel(
            defaultWorktree: defaultWorktree,
            defaultProject: defaultProject,
            localizer: localizer,
            operations: operations
        )

        var sheet: NSWindow!
        let view = TaskQueueCenterView(
            viewModel: viewModel,
            localizer: localizer,
            onDismiss: { [weak window] in
                guard let sheet, sheet.sheetParent === window else { return }
                window?.endSheet(sheet)
            }
        )
        sheet = NSWindow(contentViewController: makeShellHostingController(rootView: view))
        markAsApplicationManaged(sheet)
        sheet.title = localizer.string("taskQueue.title", fallback: "Task Queue")
        sheet.styleMask = [.titled, .resizable]
        sheet.contentMinSize = NSSize(width: 900, height: 620)
        sheet.setContentSize(NSSize(width: 980, height: 680))
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
    }
}
