// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DiffViewerView.swift - Unified/split diff viewer with per-hunk actions.

import SwiftUI

enum DiffViewerMode: String, CaseIterable, Identifiable, Sendable {
    case unified
    case split

    var id: String { rawValue }
}

struct DiffViewerView: View {
    let diffs: [FileDiff]
    @Binding var mode: DiffViewerMode
    var onStage: (FileDiff, DiffHunk, DiffStagingAction) -> Void
    var localizer: AppLocalizer = AppLocalizer(languagePreference: .english)

    @State private var selectedFilePath: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if diffs.isEmpty {
                SourceControlEmptyState(
                    title: localizer.string("diff.viewer.empty", fallback: "No local changes"),
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                HStack(spacing: 0) {
                    fileList
                    Divider()
                    diffContent
                }
            }
        }
        .onAppear {
            if selectedFilePath == nil {
                selectedFilePath = diffs.first?.filePath
            }
        }
        .onChange(of: diffs.map(\.filePath)) { _, paths in
            if let selectedFilePath, paths.contains(selectedFilePath) {
                return
            }
            self.selectedFilePath = paths.first
        }
        .frame(maxHeight: .infinity)
    }

    private var selectedFile: FileDiff? {
        if let selectedFilePath,
           let match = diffs.first(where: { $0.filePath == selectedFilePath }) {
            return match
        }
        return diffs.first
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $mode) {
                Text("Unified").tag(DiffViewerMode.unified)
                Text("Split").tag(DiffViewerMode.split)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Spacer()
            Text("\(diffs.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(diffs) { diff in
                    Button(action: { selectedFilePath = diff.filePath }) {
                        HStack(spacing: 8) {
                            Text(diff.status.rawValue)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(diff.filePath)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            Text("+\(diff.additions) -\(diff.deletions)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(selectedFile?.filePath == diff.filePath ? Color.accentColor.opacity(0.12) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 180)
    }

    @ViewBuilder
    private var diffContent: some View {
        if let selectedFile {
            switch mode {
            case .unified:
                UnifiedDiffView(fileDiff: selectedFile, onStage: onStage, localizer: localizer)
            case .split:
                SplitDiffView(fileDiff: selectedFile, onStage: onStage, localizer: localizer)
            }
        } else {
            SourceControlEmptyState(
                title: localizer.string("diff.viewer.selectFile", fallback: "Select a file"),
                systemImage: "doc.text"
            )
        }
    }
}

struct UnifiedDiffView: View {
    let fileDiff: FileDiff
    var onStage: (FileDiff, DiffHunk, DiffStagingAction) -> Void
    var localizer: AppLocalizer

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(fileDiff.hunks) { hunk in
                    DiffHunkView(
                        fileDiff: fileDiff,
                        hunk: hunk,
                        mode: .unified,
                        onStage: onStage,
                        localizer: localizer
                    )
                }
            }
            .padding(10)
        }
    }
}

struct SplitDiffView: View {
    let fileDiff: FileDiff
    var onStage: (FileDiff, DiffHunk, DiffStagingAction) -> Void
    var localizer: AppLocalizer

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(fileDiff.hunks) { hunk in
                    DiffHunkView(
                        fileDiff: fileDiff,
                        hunk: hunk,
                        mode: .split,
                        onStage: onStage,
                        localizer: localizer
                    )
                }
            }
            .padding(10)
        }
    }
}

struct DiffHunkView: View {
    let fileDiff: FileDiff
    let hunk: DiffHunk
    let mode: DiffViewerMode
    var onStage: (FileDiff, DiffHunk, DiffStagingAction) -> Void
    var localizer: AppLocalizer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(hunk.header)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                DiffStagingControls { action in
                    onStage(fileDiff, hunk, action)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08))

            if mode == .split {
                splitRows
            } else {
                unifiedRows
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.18)))
    }

    private var unifiedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(hunk.lines) { line in
                DiffLineText(line: line)
            }
        }
    }

    private var splitRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(SplitDiffLayout.rows(for: hunk)) { row in
                HStack(spacing: 0) {
                    rowSide(row.left, placeholder: row.right != nil)
                    Divider()
                    rowSide(row.right, placeholder: row.left != nil)
                }
            }
        }
    }

    private func rowSide(_ line: SplitDiffLineCell?, placeholder: Bool) -> some View {
        Group {
            if let line {
                SplitDiffLineText(line: line)
            } else {
                Text(placeholder ? "" : " ")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiffStagingControls: View {
    var onAction: (DiffStagingAction) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { onAction(.stage) }) {
                Image(systemName: "plus.square")
            }
            .buttonStyle(.borderless)
            .help("Stage hunk")

            Button(action: { onAction(.unstage) }) {
                Image(systemName: "minus.square")
            }
            .buttonStyle(.borderless)
            .help("Unstage hunk")

            Button(action: { onAction(.discard) }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Discard hunk")
        }
    }
}

private struct DiffLineText: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 6) {
            Text(line.displayLineNumber.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(prefix)
                .frame(width: 10, alignment: .center)
            Text(line.content)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background)
    }

    private var prefix: String {
        switch line.kind {
        case .context: return " "
        case .addition: return "+"
        case .deletion: return "-"
        }
    }

    private var background: Color {
        switch line.kind {
        case .context: return Color.clear
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        }
    }
}

private struct SplitDiffLineText: View {
    let line: SplitDiffLineCell

    var body: some View {
        HStack(spacing: 6) {
            Text(line.lineNumber.map(String.init) ?? "")
                .frame(width: 40, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(prefix)
                .frame(width: 10, alignment: .center)
            Text(line.content)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(background)
    }

    private var prefix: String {
        switch line.kind {
        case .context: return " "
        case .addition: return "+"
        case .deletion: return "-"
        }
    }

    private var background: Color {
        switch line.kind {
        case .context: return Color.clear
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        }
    }
}
