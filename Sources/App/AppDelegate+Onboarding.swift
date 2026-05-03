// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Onboarding.swift - Guided onboarding lifecycle integration.

import Foundation

extension AppDelegate {

    func showGuidedOnboardingOnFirstLaunch() {
        guard OnboardingStateStore().shouldPresentAutomatically else { return }
        windowController?.showOnboarding()
    }

    func completeGuidedOnboarding(_ selection: OnboardingSelection) -> Bool {
        do {
            _ = try GuidedOnboardingApplier().complete(
                selection,
                workingDirectory: activeOnboardingWorkingDirectory()
            )
            OnboardingStateStore().markCompleted()
            try configService?.reload()
            return true
        } catch {
            NSLog("[AppDelegate] Failed to complete guided onboarding: %@", error.localizedDescription)
            return false
        }
    }

    func skipGuidedOnboarding() {
        OnboardingStateStore().markSkipped()
    }

    private func activeOnboardingWorkingDirectory() -> String {
        guard let controller = windowController,
              let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let tab = controller.tabManager.tab(for: tabID) else {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return tab.workingDirectory.standardizedFileURL.path
    }
}
