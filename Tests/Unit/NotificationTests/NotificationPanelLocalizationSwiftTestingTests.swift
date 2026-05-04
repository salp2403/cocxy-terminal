// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotificationPanelLocalizationSwiftTestingTests.swift - Notification panel localization contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Notification panel localization")
struct NotificationPanelLocalizationSwiftTestingTests {

    @Test("notification panel chrome strings localize to Spanish")
    func notificationPanelChromeStringsLocalize() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(localizer.string("notifications.panel.title", fallback: "Notifications") == "Notificaciones")
        #expect(
            localizer.string(
                "notifications.panel.markAllRead",
                fallback: "Mark all read"
            ) == "Marcar todo como leído"
        )
        #expect(
            localizer.string(
                "notifications.panel.markAllRead.accessibility",
                fallback: "Mark all notifications as read"
            ) == "Marcar todas las notificaciones como leídas"
        )
        #expect(
            localizer.string(
                "notifications.panel.empty.detail",
                fallback: "Alerts from your AI agents\nwill appear here."
            ) == "Las alertas de tus agentes IA\naparecerán aquí."
        )
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
