// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotificationPanelView.swift - In-app notification panel overlay.

import SwiftUI
import Combine

// MARK: - Notification Panel View Model

/// ViewModel for the in-app notification panel.
///
/// Subscribes to the `NotificationManaging` publisher to receive real-time
/// notifications and maintains a local list for display.
@MainActor
final class NotificationPanelViewModel: ObservableObject {

    // MARK: - Published State

    @Published var notifications: [CocxyNotification] = []
    @Published var unreadCount: Int = 0

    // MARK: - Dependencies

    private weak var notificationManager: NotificationManagerImpl?
    private var cancellables = Set<AnyCancellable>()

    /// Callback to navigate to a specific tab.
    var onNavigateToTab: ((TabID) -> Void)?

    // MARK: - Initialization

    init(notificationManager: NotificationManagerImpl? = nil) {
        self.notificationManager = notificationManager
        subscribeToNotifications()
    }

    // MARK: - Actions

    func markAllAsRead() {
        notificationManager?.markAllAsRead()
        for i in notifications.indices {
            notifications[i].isRead = true
        }
        unreadCount = 0
    }

    func navigateToTab(for notification: CocxyNotification) {
        notificationManager?.markAsRead(tabId: notification.tabId)
        onNavigateToTab?(notification.tabId)
    }

    // MARK: - Private

    private func subscribeToNotifications() {
        guard let manager = notificationManager else { return }

        manager.notificationsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                self.notifications.insert(notification, at: 0)
                // Keep max 50 notifications in the panel.
                if self.notifications.count > 50 {
                    self.notifications = Array(self.notifications.prefix(50))
                }
            }
            .store(in: &cancellables)

        manager.unreadCountPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in
                self?.unreadCount = count
            }
            .store(in: &cancellables)
    }
}

// MARK: - Notification Panel View

/// A side panel showing in-app notifications with timestamps and types.
///
/// ## Layout
///
/// ```
/// +-- Notifications ----------------------+
/// | [x] Close         [Mark all read]      |
/// |                                        |
/// | 14:32  [!] Agent needs input           |
/// |        cocxy-terminal - main           |
/// |                                        |
/// | 14:30  [v] Agent finished              |
/// |        my-api - feat/auth              |
/// +----------------------------------------+
/// ```
///
/// ## Behavior
///
/// - Toggle with Cmd+Shift+I.
/// - Click a notification to focus its tab.
/// - "Mark all read" clears badges.
struct NotificationPanelView: View {

    @ObservedObject var viewModel: NotificationPanelViewModel
    var onDismiss: () -> Void

    static let panelWidth: CGFloat = 320

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            notificationListView
        }
        .frame(width: Self.panelWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notification Panel")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Notifications")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            if viewModel.unreadCount > 0 {
                Text("\(viewModel.unreadCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(nsColor: CocxyColors.crust))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: CocxyColors.blue))
                    .cornerRadius(8)
            }

            Spacer()

            Button(action: { viewModel.markAllAsRead() }) {
                Text("Mark all read")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark all notifications as read")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close notification panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Notification List

    private var notificationListView: some View {
        Group {
            if viewModel.notifications.isEmpty {
                emptyStateView
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.notifications) { notification in
                            NotificationRowView(notification: notification)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    viewModel.navigateToTab(for: notification)
                                }
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 32))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No notifications yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Alerts from your AI agents\nwill appear here.")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Notification Row View

/// A single row displaying one notification.
struct NotificationRowView: View {

    let notification: CocxyNotification

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Type icon
            notificationIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title)
                        .font(.system(size: 12, weight: notification.isRead ? .regular : .semibold))
                        .foregroundColor(notification.isRead ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text(Self.timeFormatter.string(from: notification.timestamp))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(notification.isRead ? Color.clear : Color(nsColor: CocxyColors.surface0).opacity(0.3))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title), \(notification.body)")
    }

    // MARK: - Icon

    private var notificationIcon: some View {
        let (icon, color) = iconAndColor(for: notification.type)
        return Image(systemName: icon)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(color)
            .frame(width: 28, height: 28)
            .background(color.opacity(0.15))
            .cornerRadius(6)
    }

    private func iconAndColor(for type: NotificationType) -> (String, Color) {
        switch type {
        case .agentNeedsAttention:
            return ("exclamationmark.bubble.fill", Color(nsColor: CocxyColors.yellow))
        case .agentError:
            return ("xmark.circle.fill", Color(nsColor: CocxyColors.red))
        case .agentFinished:
            return ("checkmark.circle.fill", Color(nsColor: CocxyColors.green))
        case .processExited:
            return ("terminal.fill", Color(nsColor: CocxyColors.overlay1))
        case .custom:
            return ("bell.fill", Color(nsColor: CocxyColors.blue))
        }
    }
}
