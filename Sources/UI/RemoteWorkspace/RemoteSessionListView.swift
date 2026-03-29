// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteSessionListView.swift - UI for viewing and reconnecting remote tmux sessions.

import SwiftUI

// MARK: - Remote Session List View Model

/// Drives the remote session list panel.
///
/// Queries the `RemoteConnectionManager` for active tmux sessions
/// on connected remote hosts and combines them with locally-cached
/// session records for offline display.
@MainActor
final class RemoteSessionListViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var sessions: [TmuxSessionInfo] = []
    @Published private(set) var savedRecords: [RemoteSessionRecord] = []
    @Published private(set) var isLoading = false
    @Published var newSessionName: String = ""

    // MARK: - Dependencies

    private let connectionManager: RemoteConnectionManager
    private let profileID: UUID

    // MARK: - Initialization

    init(connectionManager: RemoteConnectionManager, profileID: UUID) {
        self.connectionManager = connectionManager
        self.profileID = profileID
    }

    // MARK: - Actions

    /// Fetches live tmux sessions from the remote host.
    func refresh() async {
        isLoading = true
        sessions = await connectionManager.listRemoteSessions(profileID: profileID)
        savedRecords = connectionManager.savedSessionRecords(profileID: profileID)
        isLoading = false
    }

    /// Creates a new persistent tmux session on the remote host.
    func createSession() async throws {
        let name = newSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        try await connectionManager.createRemoteSession(named: name, profileID: profileID)
        newSessionName = ""
        await refresh()
    }

    /// Kills a remote tmux session.
    func killSession(named name: String) async throws {
        try await connectionManager.killRemoteSession(named: name, profileID: profileID)
        await refresh()
    }

    /// Returns the SSH command to attach to a session (for display or clipboard).
    func attachCommand(sessionName: String) -> String? {
        connectionManager.attachCommand(sessionName: sessionName, profileID: profileID)
    }
}

// MARK: - Remote Session List View

/// Displays tmux sessions on a remote host with controls for creating,
/// attaching, and killing sessions.
///
/// This view is embedded in the Remote Workspace panel when a profile
/// is selected and connected.
struct RemoteSessionListView: View {

    @ObservedObject var viewModel: RemoteSessionListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            createSessionSection
            sessionListSection
        }
        .padding(16)
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "terminal")
                .foregroundColor(.secondary)
            Text("Persistent Sessions")
                .font(.headline)
            Spacer()

            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: {
                    Task { await viewModel.refresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .help("Refresh sessions")
            }
        }
    }

    // MARK: - Create Session

    private var createSessionSection: some View {
        HStack(spacing: 8) {
            TextField("Session name", text: $viewModel.newSessionName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { try? await viewModel.createSession() }
                }

            Button("Create") {
                Task { try? await viewModel.createSession() }
            }
            .disabled(viewModel.newSessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Session List

    @ViewBuilder
    private var sessionListSection: some View {
        if viewModel.sessions.isEmpty && viewModel.savedRecords.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No active sessions")
                .foregroundColor(.secondary)
            Text("Create a session to persist your remote work across SSH disconnects.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func sessionRow(_ session: TmuxSessionInfo) -> some View {
        HStack(spacing: 10) {
            // Status indicator.
            Circle()
                .fill(session.isAttached ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                Text(session.displayTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Copy attach command.
            if let command = viewModel.attachCommand(sessionName: session.name) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy attach command")
            }

            // Kill session.
            Button(action: {
                Task { try? await viewModel.killSession(named: session.name) }
            }) {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.borderless)
            .help("Kill session")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
}
