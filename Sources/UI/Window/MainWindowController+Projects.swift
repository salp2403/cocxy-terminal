// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Projects.swift - Project lifecycle integration.

import Foundation

extension MainWindowController {
    func observeProjectDirectory(
        _ directory: URL,
        previousDirectory: URL? = nil
    ) {
        guard let projectRegistry else { return }
        let descriptor = projectResolver.resolveProject(for: directory)
        guard descriptor.rootSource != .workingDirectory else { return }
        if let previousDirectory,
           projectResolver.resolveProject(for: previousDirectory).groupingID
                == descriptor.groupingID {
            return
        }
        do {
            try projectRegistry.recordOpen(descriptor)
        } catch {
            NSLog("[ProjectRegistry] Project update failed")
        }
    }

    func setProjectCollapsed(_ collapsed: Bool, projectID: ProjectID) {
        do {
            try projectRegistry?.setCollapsed(collapsed, projectID: projectID)
        } catch {
            NSLog("[ProjectRegistry] Collapse update failed")
        }
    }

    func setProjectPinned(_ pinned: Bool, projectID: ProjectID) {
        do {
            try projectRegistry?.setPinned(pinned, projectID: projectID)
        } catch {
            NSLog("[ProjectRegistry] Pin update failed")
        }
    }

    func refreshProjectPresentation() {
        auroraChromeController?.refreshProjects()
    }
}
