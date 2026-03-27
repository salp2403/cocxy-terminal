// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDownloadsView.swift - Downloads panel showing progress and completed files.

import SwiftUI

// MARK: - Download State

/// Represents the lifecycle state of a file download.
enum DownloadState: Equatable, Sendable {

    /// Download is in progress with a fractional progress value (0.0 to 1.0).
    case downloading(progress: Double)

    /// Download has completed successfully.
    case completed

    /// Download failed with an error description.
    case failed(reason: String)
}

// MARK: - Download Item

/// A single file download tracked by the browser.
///
/// Each item records the file name, URL, size, state, and local file path
/// (once completed). Items are displayed in the downloads panel with
/// progress indicators for active downloads.
///
/// - SeeAlso: ``BrowserDownloadsView``
struct DownloadItem: Identifiable, Sendable {

    /// Unique identifier for this download.
    let id: UUID

    /// The display name of the file being downloaded.
    let fileName: String

    /// The source URL from which the file is being downloaded.
    let sourceURL: String

    /// Total file size in bytes. Nil if the server did not report Content-Length.
    let totalBytes: Int64?

    /// Bytes received so far.
    var receivedBytes: Int64

    /// Current download state.
    var state: DownloadState

    /// Local file path where the download was saved. Nil until completed.
    var localPath: String?

    /// When the download was initiated.
    let startedAt: Date

    /// Whether this download has finished (successfully or not).
    var isFinished: Bool {
        switch state {
        case .downloading: return false
        case .completed, .failed: return true
        }
    }
}

// MARK: - Browser Downloads View

/// A panel listing file downloads with progress bars and management actions.
///
/// ## Layout
///
/// ```
/// +-- Downloads ----------------------+
/// |                                 X |
/// +-----------------------------------+
/// | [file] report.pdf    2.1 MB       |
/// |    ||||||||..  80%                |
/// | [check] data.csv    450 KB        |
/// | [check] image.png   1.2 MB        |
/// +-----------------------------------+
/// | [Clear Completed]                 |
/// +-----------------------------------+
/// ```
///
/// ## Features
///
/// - Progress bar for active downloads.
/// - Completed downloads with checkmark icon.
/// - Failed downloads with error icon and reason.
/// - Click completed download to reveal in Finder.
/// - Clear completed button removes finished items.
///
/// - SeeAlso: ``DownloadItem`` for the download model.
/// - SeeAlso: ``DownloadState`` for lifecycle states.
struct BrowserDownloadsView: View {

    /// The list of downloads to display.
    let downloads: [DownloadItem]

    /// Called to clear all completed downloads from the list.
    let onClearCompleted: () -> Void

    /// Called when the user clicks a completed download to open it.
    let onRevealInFinder: (DownloadItem) -> Void

    /// Called when the user taps the close button.
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            Divider()
            downloadsList
            Divider()
            footerView
        }
        .background(
            ZStack {
                Color(nsColor: CocxyColors.mantle)
                VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Downloads")
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("Downloads")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .accessibilityLabel("Close downloads")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Downloads List

    @ViewBuilder
    private var downloadsList: some View {
        if downloads.isEmpty {
            downloadsEmptyState
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(downloads) { item in
                        downloadRow(item)
                        Divider()
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }

    // MARK: - Download Row

    private func downloadRow(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                stateIcon(for: item)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fileName)
                        .font(.system(size: 12))
                        .foregroundColor(Color(nsColor: CocxyColors.text))
                        .lineLimit(1)

                    Text(sizeLabel(for: item))
                        .font(.system(size: 9))
                        .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                }

                Spacer()
            }

            if case .downloading(let progress) = item.state {
                progressBar(progress: progress)
            }

            if case .failed(let reason) = item.state {
                Text(reason)
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: CocxyColors.red))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.state == .completed {
                onRevealInFinder(item)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    // MARK: - State Icon

    private func stateIcon(for item: DownloadItem) -> some View {
        Group {
            switch item.state {
            case .downloading:
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundColor(Color(nsColor: CocxyColors.blue))

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(nsColor: CocxyColors.green))

            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(nsColor: CocxyColors.red))
            }
        }
        .frame(width: 18, height: 18)
    }

    // MARK: - Progress Bar

    private func progressBar(progress: Double) -> some View {
        HStack(spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: CocxyColors.surface1))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: CocxyColors.blue))
                        .frame(width: geometry.size.width * CGFloat(min(max(progress, 0), 1)), height: 4)
                }
            }
            .frame(height: 4)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.leading, 26)
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            let completedCount = downloads.filter { $0.isFinished }.count

            Button(action: onClearCompleted) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Clear Completed")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(
                    completedCount > 0
                        ? Color(nsColor: CocxyColors.subtext0)
                        : Color(nsColor: CocxyColors.surface2)
                )
            }
            .buttonStyle(.plain)
            .disabled(completedCount == 0)
            .accessibilityLabel("Clear completed downloads")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Empty State

    private var downloadsEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 28))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
            Text("No downloads")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(nsColor: CocxyColors.subtext0))
            Text("Files you download will appear here.")
                .font(.system(size: 10))
                .foregroundColor(Color(nsColor: CocxyColors.overlay0))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Formatting

    private func sizeLabel(for item: DownloadItem) -> String {
        if let total = item.totalBytes {
            return formatBytes(total)
        }
        if item.receivedBytes > 0 {
            return "\(formatBytes(item.receivedBytes)) received"
        }
        return "Unknown size"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1_048_576 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else if bytes < 1_073_741_824 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        }
    }

    private func accessibilityLabel(for item: DownloadItem) -> String {
        switch item.state {
        case .downloading(let progress):
            return "\(item.fileName), downloading, \(Int(progress * 100)) percent"
        case .completed:
            return "\(item.fileName), completed, tap to open"
        case .failed(let reason):
            return "\(item.fileName), failed: \(reason)"
        }
    }
}
