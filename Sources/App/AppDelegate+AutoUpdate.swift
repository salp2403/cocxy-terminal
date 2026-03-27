// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+AutoUpdate.swift - Sparkle auto-update initialization.

import AppKit

extension AppDelegate {

    /// Initializes the Sparkle auto-update system.
    ///
    /// Called during `applicationDidFinishLaunching`. The updater reads
    /// `SUFeedURL` and `SUPublicEDKey` from the app's Info.plist.
    func setupAutoUpdate() {
        let updater = SparkleUpdater()
        self.sparkleUpdater = updater
        windowController?.sparkleUpdater = updater
    }
}
