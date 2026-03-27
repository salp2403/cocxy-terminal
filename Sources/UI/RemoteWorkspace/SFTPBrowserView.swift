// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPBrowserView.swift - Remote file browser via SFTP.

import SwiftUI

// MARK: - SFTP Browser View Model

/// Drives the SFTP file browser sub-panel.
///
/// Maintains the current remote path and file listing. Navigating into
/// directories fetches the listing asynchronously. Each navigation pushes
/// onto a path stack for breadcrumb display and "up" navigation.
@MainActor
final class SFTPBrowserViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var currentPath: String = "/home"
    @Published private(set) var entries: [RemoteFileEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // MARK: - Dependencies

    private let sftpClient: SFTPClient
    private let profile: RemoteConnectionProfile

    // MARK: - Initialization

    init(sftpClient: SFTPClient, profile: RemoteConnectionProfile) {
        self.sftpClient = sftpClient
        self.profile = profile
    }

    // MARK: - Navigation

    func loadDirectory(at path: String? = nil) {
        let targetPath = path ?? currentPath
        isLoading = true
        errorMessage = nil

        do {
            let result = try sftpClient.listDirectory(path: targetPath, on: profile)
            entries = sortEntries(result)
            currentPath = targetPath
        } catch {
            errorMessage = error.localizedDescription
            entries = []
        }

        isLoading = false
    }

    func navigateToDirectory(_ entry: RemoteFileEntry) {
        guard entry.isDirectory else { return }
        loadDirectory(at: entry.id)
    }

    func navigateUp() {
        let parent = parentPath(of: currentPath)
        guard parent != currentPath else { return }
        loadDirectory(at: parent)
    }

    func refresh() {
        loadDirectory()
    }

    func downloadFile(_ entry: RemoteFileEntry) {
        guard !entry.isDirectory else { return }

        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
            .appendingPathComponent(entry.name)
            .path

        do {
            try sftpClient.download(
                remotePath: entry.id,
                localPath: downloadsPath,
                on: profile
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Private

    private func parentPath(of path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else { return "/" }
        return "/" + components.dropLast().joined(separator: "/")
    }

    private func sortEntries(_ entries: [RemoteFileEntry]) -> [RemoteFileEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - SFTP Browser View

/// Sub-panel providing a file browser for remote filesystems via SFTP.
///
/// ## Layout
///
/// ```
/// +-- /home/deploy/project ---------- [up] [R] --+
/// |                                               |
/// | [folder] src/            4.2 KB     Mar 25    |
/// | [folder] tests/          1.1 KB     Mar 24    |
/// | [doc]    README.md        892 B     Mar 26    |
/// | [doc]    package.json    1.2 KB     Mar 25    |
/// +-----------------------------------------------+
/// ```
///
/// - SeeAlso: `SFTPBrowserViewModel`
/// - SeeAlso: `SFTPClient`
struct SFTPBrowserView: View {

    @ObservedObject var viewModel: SFTPBrowserViewModel

    /// Formatter for file modification dates.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd"
        return formatter
    }()

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pathBar
            Divider()
            fileListContent
        }
        .onAppear { viewModel.loadDirectory() }
    }

    // MARK: - Path Bar

    private var pathBar: some View {
        HStack(spacing: 6) {
            pathBreadcrumb
            Spacer()
            navigationButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var pathBreadcrumb: some View {
        Text(viewModel.currentPath)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(Color(nsColor: CocxyColors.text))
            .lineLimit(1)
            .truncationMode(.head)
            .accessibilityLabel("Current path: \(viewModel.currentPath)")
    }

    private var navigationButtons: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.navigateUp() }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Navigate to parent directory")

            Button(action: { viewModel.refresh() }) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                }
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel(viewModel.isLoading ? "Loading" : "Refresh directory listing")
        }
    }

    // MARK: - File List

    private var fileListContent: some View {
        Group {
            if let error = viewModel.errorMessage {
                errorStateView(error)
            } else if viewModel.isLoading && viewModel.entries.isEmpty {
                loadingStateView
            } else if viewModel.entries.isEmpty {
                emptyStateView
            } else {
                fileList
            }
        }
    }

    private var fileList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.entries) { entry in
                    FileEntryRow(
                        entry: entry,
                        dateFormatter: Self.dateFormatter
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if entry.isDirectory {
                            viewModel.navigateToDirectory(entry)
                        } else {
                            viewModel.downloadFile(entry)
                        }
                    }
                    Divider()
                        .padding(.leading, 40)
                }
            }
        }
    }

    // MARK: - State Views

    private var loadingStateView: some View {
        VStack(spacing: 8) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text("Loading...")
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("Empty directory")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.red))
            Text("Failed to list directory")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.text))
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            Button("Retry") { viewModel.refresh() }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: CocxyColors.blue))
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - File Entry Row

/// A single row displaying a remote file or directory with metadata.
struct FileEntryRow: View {

    let entry: RemoteFileEntry
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(spacing: 8) {
            entryIcon
                .frame(width: 24, height: 24)

            Text(entry.name)
                .font(.system(size: 12, weight: entry.isDirectory ? .medium : .regular))
                .foregroundColor(Color(nsColor: CocxyColors.text))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(formattedSize)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .frame(width: 60, alignment: .trailing)

            Text(dateFormatter.string(from: entry.modifiedDate))
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay1))
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.isDirectory ? "Folder" : "File"): \(entry.name), \(formattedSize)")
    }

    // MARK: - Icon

    private var entryIcon: some View {
        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
            .font(.system(size: 12))
            .foregroundColor(
                entry.isDirectory
                    ? Color(nsColor: CocxyColors.blue)
                    : Color(nsColor: CocxyColors.overlay1)
            )
    }

    // MARK: - Size Formatting

    private var formattedSize: String {
        let bytes = entry.size
        if bytes < 1024 {
            return "\(bytes) B"
        }
        let kilobytes = Double(bytes) / 1024.0
        if kilobytes < 1024.0 {
            return String(format: "%.1f KB", kilobytes)
        }
        let megabytes = kilobytes / 1024.0
        return String(format: "%.1f MB", megabytes)
    }
}
