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

    @Test("mark-all control stays compact and only appears when useful")
    func markAllControlStaysCompactAndUseful() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(NotificationPanelView.shouldShowMarkAllControl(unreadCount: 0) == false)
        #expect(NotificationPanelView.shouldShowMarkAllControl(unreadCount: 2))
        #expect(NotificationPanelView.markAllReadSystemImageName == "checkmark.circle")
        #expect(NotificationPanelView.localizedMarkAllReadHelp(using: localizer) == "Marcar todo como leído")
        #expect(
            NotificationPanelView.localizedMarkAllReadAccessibility(using: localizer)
                == "Marcar todas las notificaciones como leídas"
        )
    }

    @MainActor
    @Test("state-change notifications localize generated copy to Spanish")
    func stateChangeNotificationsLocalizeGeneratedCopy() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let emitter = NotificationLocalizationEmitter()
        let manager = NotificationManagerImpl(
            config: .defaults,
            systemEmitter: emitter,
            coalescenceWindow: 0,
            rateLimitPerTab: 0,
            localizer: localizer
        )

        manager.handleStateChange(
            state: .waitingInput,
            previousState: .working,
            for: TabID(),
            tabTitle: "Terminal 1",
            agentName: nil
        )
        manager.handleStateChange(
            state: .finished,
            previousState: .working,
            for: TabID(),
            tabTitle: "Build",
            agentName: "Local Agent"
        )
        manager.handleStateChange(
            state: .error,
            previousState: .working,
            for: TabID(),
            tabTitle: "Tests",
            agentName: "Local Agent"
        )

        let waiting = try #require(manager.attentionQueue.first { $0.type == .agentNeedsAttention })
        let finished = try #require(manager.attentionQueue.first { $0.type == .agentFinished })
        let error = try #require(manager.attentionQueue.first { $0.type == .agentError })

        #expect(waiting.title == "Agente necesita tu entrada")
        #expect(waiting.body == "La pestaña \"Terminal 1\" espera entrada.")
        #expect(finished.title == "Local Agent completó la tarea")
        #expect(finished.body == "La pestaña \"Build\" finalizó.")
        #expect(error.title == "Local Agent encontró un error")
        #expect(error.body == "La pestaña \"Tests\" tiene un error.")
        #expect(emitter.emittedNotifications.map(\.title).contains(waiting.title))
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}

@MainActor
private final class NotificationLocalizationEmitter: SystemNotificationEmitting {
    private(set) var emittedNotifications: [CocxyNotification] = []

    func emit(_ notification: CocxyNotification) {
        emittedNotifications.append(notification)
    }
}
