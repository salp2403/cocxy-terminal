// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+SessionReplay.swift - Local session replay lifecycle wiring.

import AppKit
import Foundation

@MainActor
extension MainWindowController {
    func sessionReplayStorageURL(from config: SessionReplayConfig) -> URL {
        URL(
            fileURLWithPath: (config.storageDirectory as NSString).expandingTildeInPath,
            isDirectory: true
        )
        .standardizedFileURL
    }

    func sessionReplayStore(from config: SessionReplayConfig) -> SessionReplayStore {
        SessionReplayStore(rootDirectory: sessionReplayStorageURL(from: config))
    }

    func sessionReplayPlaybackController() -> (any SessionReplayPlaybackControlling)? {
        MainWindowSessionReplayPlaybackRouter(windowController: self)
    }

    @discardableResult
    func startAutomaticSessionReplayIfNeeded(
        surfaceID: SurfaceID,
        tabID: TabID
    ) -> Bool {
        let config = configService?.current.sessionReplay ?? .defaults
        guard config.policy.canAutoRecord else {
            return false
        }
        guard let controller = sessionReplayController(for: surfaceID, config: config) else {
            return false
        }
        guard controller.activeRecording(for: surfaceID) == nil else {
            return false
        }

        let title = tabManager.tab(for: tabID)?.displayTitle ?? "Terminal"
        do {
            try controller.startRecording(
                surfaceID: surfaceID,
                title: title,
                mode: .automatic
            )
            return true
        } catch SessionReplayControllerError.recordingAlreadyActive {
            return false
        } catch {
            NSLog(
                "[MainWindowController] Failed to start Session Replay for surface %@: %@",
                surfaceID.rawValue.uuidString,
                String(describing: error)
            )
            return false
        }
    }

    func stopSessionReplayIfActive(surfaceID: SurfaceID) {
        guard let controller = sessionReplayControllers[surfaceID] else {
            return
        }
        guard controller.activeRecording(for: surfaceID) != nil else {
            sessionReplayControllers.removeValue(forKey: surfaceID)
            sessionReplayControllerStorageKeys.removeValue(forKey: surfaceID)
            return
        }

        do {
            try controller.stopRecording(surfaceID: surfaceID)
        } catch SessionReplayControllerError.recordingNotActive {
            // The surface is already inactive; dropping the controller keeps
            // future surface IDs from inheriting stale replay state.
        } catch {
            NSLog(
                "[MainWindowController] Failed to stop Session Replay for surface %@: %@",
                surfaceID.rawValue.uuidString,
                String(describing: error)
            )
        }

        sessionReplayControllers.removeValue(forKey: surfaceID)
        sessionReplayControllerStorageKeys.removeValue(forKey: surfaceID)
    }

    func sessionReplayController(
        for surfaceID: SurfaceID,
        config providedConfig: SessionReplayConfig? = nil
    ) -> SessionReplayController? {
        let config = providedConfig ?? configService?.current.sessionReplay ?? .defaults
        let storageURL = sessionReplayStorageURL(from: config)
        let storageKey = storageURL.path

        if let existing = sessionReplayControllers[surfaceID] {
            existing.config = config
            if sessionReplayControllerStorageKeys[surfaceID] == storageKey ||
                existing.activeRecording(for: surfaceID) != nil {
                return existing
            }
        }

        guard let replayBridge = terminalEngine(for: surfaceID) as? any SessionReplayTerminalBridging else {
            sessionReplayControllers.removeValue(forKey: surfaceID)
            sessionReplayControllerStorageKeys.removeValue(forKey: surfaceID)
            return nil
        }

        let controller = SessionReplayController(
            config: config,
            store: SessionReplayStore(rootDirectory: storageURL),
            bridge: replayBridge
        )
        sessionReplayControllers[surfaceID] = controller
        sessionReplayControllerStorageKeys[surfaceID] = storageKey
        return controller
    }

    func detachSessionReplayControllers(
        for surfaceIDs: some Sequence<SurfaceID>
    ) -> (
        controllers: [SurfaceID: SessionReplayController],
        storageKeys: [SurfaceID: String]
    ) {
        var controllers: [SurfaceID: SessionReplayController] = [:]
        var storageKeys: [SurfaceID: String] = [:]
        for surfaceID in surfaceIDs {
            if let controller = sessionReplayControllers.removeValue(forKey: surfaceID) {
                controllers[surfaceID] = controller
            }
            if let storageKey = sessionReplayControllerStorageKeys.removeValue(forKey: surfaceID) {
                storageKeys[surfaceID] = storageKey
            }
        }
        return (controllers, storageKeys)
    }

    func installSessionReplayControllers(
        _ controllers: [SurfaceID: SessionReplayController],
        storageKeys: [SurfaceID: String]
    ) {
        for (surfaceID, controller) in controllers {
            sessionReplayControllers[surfaceID] = controller
        }
        for (surfaceID, storageKey) in storageKeys {
            sessionReplayControllerStorageKeys[surfaceID] = storageKey
        }
    }
}

@MainActor
private final class MainWindowSessionReplayPlaybackRouter: SessionReplayPlaybackControlling {
    private weak var windowController: MainWindowController?

    init(windowController: MainWindowController) {
        self.windowController = windowController
    }

    func replay(
        recordingID: UUID,
        to surfaceID: SurfaceID,
        seekNs: UInt64,
        speedMultiplier: Float
    ) throws {
        guard let controller = windowController?.sessionReplayController(for: surfaceID) else {
            throw SessionReplayControllerError.replayFailed(recordingID)
        }
        try controller.replay(
            recordingID: recordingID,
            to: surfaceID,
            seekNs: seekNs,
            speedMultiplier: speedMultiplier
        )
    }
}
