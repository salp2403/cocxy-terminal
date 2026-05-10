// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+FinderServices.swift - Finder Services wiring.

import AppKit

extension AppDelegate {
    func installFinderServices() {
        let provider = FinderServiceProvider(
            openWorkspace: { [weak self] urls in
                self?.openFinderWorkspaceURLs(urls)
            },
            openWindow: { [weak self] urls in
                self?.openFinderWindowURLs(urls)
            }
        )
        finderServiceProvider = provider
        NSApp.servicesProvider = provider
        NSUpdateDynamicServices()
    }

    private func openFinderWorkspaceURLs(_ urls: [URL]) {
        guard let controller = focusedWindowController() ?? windowController else { return }
        controller.window?.makeKeyAndOrderFront(nil)
        for url in urls {
            controller.createTab(workingDirectory: url)
        }
    }

    private func openFinderWindowURLs(_ urls: [URL]) {
        for url in urls {
            guard let controller = makeWindowController(registerInitialSession: false) else { continue }
            if let activeTabID = controller.tabManager.activeTabID {
                controller.tabManager.updateTab(id: activeTabID) { tab in
                    tab.workingDirectory = url
                }
                if let tab = controller.tabManager.tab(for: activeTabID) {
                    registerSession(for: tab, in: controller)
                }
            }
            controller.showWindow(nil)
            controller.window?.center()
            controller.createTerminalSurface()
            controller.window?.makeKeyAndOrderFront(nil)
            if let surfaceView = controller.terminalSurfaceView {
                controller.window?.makeFirstResponder(surfaceView)
            }
            additionalWindowControllers.append(controller)
        }
    }
}
