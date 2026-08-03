// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Models.swift - App-scoped mobile mirror state.

enum MobileMirrorServiceState: Equatable {
    case stopped
    case starting
    case offering
    case awaitingConfirmation
    case active
    case denied
    case unavailable(String)
    case failed(String)
}

extension MobileMirrorCoordinator {
    struct OwnedStream {
        let bridge: CocxyCoreBridge
        let surfaceID: SurfaceID
        let port: UInt16
        let token: String
    }
}
