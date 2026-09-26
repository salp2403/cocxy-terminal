// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Models.swift - App-scoped mobile mirror state.

enum MobileMirrorServiceState: Equatable {
    case stopped
    case starting
    case offering
    case awaitingConfirmation
    case active
    case denied
    case unavailable(MobileMirrorStatusMessage)
    case failed(MobileMirrorStatusMessage)
}

/// Panel text for an unavailable or failed mirror. It keeps how it was
/// produced so the panel can render it in the current app language.
struct MobileMirrorStatusMessage: Equatable {
    private let render: (AppLocalizer) -> String
    /// The text in the language that was active when the status was set.
    let text: String

    init(using localizer: AppLocalizer, render: @escaping (AppLocalizer) -> String) {
        self.render = render
        text = render(localizer)
    }

    func text(using localizer: AppLocalizer) -> String {
        render(localizer)
    }

    static func == (lhs: MobileMirrorStatusMessage, rhs: MobileMirrorStatusMessage) -> Bool {
        lhs.text == rhs.text
    }
}

extension MobileMirrorCoordinator {
    struct OwnedStream {
        let bridge: CocxyCoreBridge
        let surfaceID: SurfaceID
        let port: UInt16
        let token: String
    }
}
