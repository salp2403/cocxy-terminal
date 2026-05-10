// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+AutoUpdate.swift - Sparkle auto-update initialization.

import AppKit
import Combine

extension AppDelegate {

    /// Initializes the Sparkle auto-update system.
    ///
    /// Called during `applicationDidFinishLaunching`. The updater reads
    /// `SUPublicEDKey` from the app's Info.plist and resolves the appcast
    /// feed from the selected Cocxy update channel.
    func setupAutoUpdate() {
        let initialChannel = configService?.current.updates.channel
            ?? ChannelResolver().currentChannel()
        let updater = SparkleUpdater(channel: initialChannel)
        self.sparkleUpdater = updater
        for controller in allWindowControllers {
            controller.sparkleUpdater = updater
        }
        configService?.configChangedPublisher
            .map(\.updates.channel)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak updater] channel in
                updater?.setChannel(channel)
            }
            .store(in: &hookCancellables)
        updater.startAutomaticUpdateDetection()
    }

    /// Menu action: triggers a user-initiated update check.
    @objc func checkForUpdatesMenu(_ sender: Any?) {
        sparkleUpdater?.checkForUpdates()
    }
}
