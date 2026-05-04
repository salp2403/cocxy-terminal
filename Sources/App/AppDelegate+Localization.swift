// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Localization.swift - Runtime localization helpers.

import Foundation

struct AppAlertCopy: Equatable {
    let messageText: String
    let informativeText: String
    let primaryButton: String
    let secondaryButton: String
}

extension AppDelegate {
    func appLocalizer() -> AppLocalizer {
        AppLocalizer(languagePreference: configService?.current.appearance.appLanguage ?? .system)
    }

    static func localizedCrashRecoveryOfferCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string(
                "app.crashRecovery.restore.title",
                fallback: "Restore Previous Session?"
            ),
            informativeText: localizer.string(
                "app.crashRecovery.restore.message",
                fallback: "Cocxy did not shut down cleanly last time. A local crash-recovery snapshot is available."
            ),
            primaryButton: localizer.string("app.crashRecovery.restore.button", fallback: "Restore"),
            secondaryButton: localizer.string("app.crashRecovery.keepCurrent.button", fallback: "Keep Current")
        )
    }

    static func localizedQuitConfirmationCopy(localizer: AppLocalizer) -> AppAlertCopy {
        AppAlertCopy(
            messageText: localizer.string("app.quit.title", fallback: "Quit Cocxy Terminal?"),
            informativeText: localizer.string(
                "app.quit.message",
                fallback: "All terminal sessions will be closed."
            ),
            primaryButton: localizer.string("app.quit.button", fallback: "Quit"),
            secondaryButton: localizer.string("common.cancel", fallback: "Cancel")
        )
    }
}
