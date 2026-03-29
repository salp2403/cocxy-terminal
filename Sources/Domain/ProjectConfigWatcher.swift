// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectConfigWatcher.swift - Hot-reload watcher for per-project .cocxy.toml files.

import Foundation

// MARK: - Project Config Watcher

/// Watches a `.cocxy.toml` file for changes and notifies via callback.
///
/// Uses the same `DispatchSourceFileSystemObject` pattern as `ConfigWatcher`.
/// One watcher is active at a time — when the user switches tabs, the old
/// watcher is stopped and a new one is started for the new tab's config file.
///
/// Debounces rapid changes (500ms) to avoid redundant reloads when editors
/// perform atomic writes (delete + create).
final class ProjectConfigWatcher {

    /// The path to the `.cocxy.toml` file being watched.
    let watchedPath: String

    /// Whether the watcher is currently active.
    private(set) var isWatching: Bool = false

    /// Debounce interval in seconds.
    private let debounceInterval: TimeInterval

    /// Callback invoked when the file changes.
    private var onChange: (() -> Void)?

    /// Dispatch source for file system events.
    private var fileSource: DispatchSourceFileSystemObject?

    /// Pending debounced reload.
    private var debounceWorkItem: DispatchWorkItem?

    init(configFilePath: String, debounceInterval: TimeInterval = 0.5) {
        self.watchedPath = configFilePath
        self.debounceInterval = debounceInterval
    }

    deinit {
        stopWatching()
    }

    /// Starts watching the file for changes.
    func startWatching(onChange: @escaping () -> Void) {
        guard !isWatching else { return }
        self.onChange = onChange

        let fd = open(watchedPath, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist yet — mark as watching but defer observation.
            isWatching = true
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        fileSource = source
        isWatching = true
    }

    /// Stops watching and releases resources.
    func stopWatching() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        fileSource?.cancel()
        fileSource = nil
        onChange = nil
        isWatching = false
    }

    /// Debounces file change events.
    private func scheduleReload() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: work
        )
    }
}
