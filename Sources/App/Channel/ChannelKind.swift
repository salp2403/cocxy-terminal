// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ChannelKind.swift - Stable, preview, and nightly update channel metadata.

import Foundation

enum ChannelKind: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case stable
    case preview
    case nightly

    var id: String { rawValue }

    init(bundleIdentifier: String?) {
        switch bundleIdentifier {
        case Self.preview.bundleIdentifier:
            self = .preview
        case Self.nightly.bundleIdentifier:
            self = .nightly
        default:
            self = .stable
        }
    }

    init(configRawValue: String?) {
        guard let configRawValue,
              let channel = Self(rawValue: configRawValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            self = .stable
            return
        }
        self = channel
    }

    var bundleIdentifier: String {
        switch self {
        case .stable:
            return "dev.cocxy.terminal"
        case .preview:
            return "dev.cocxy.terminal.preview"
        case .nightly:
            return "dev.cocxy.terminal.nightly"
        }
    }

    var feedURLString: String {
        switch self {
        case .stable:
            return "https://cocxy.dev/appcast.xml"
        case .preview:
            return "https://cocxy.dev/appcast-preview.xml"
        case .nightly:
            return "https://cocxy.dev/appcast-nightly.xml"
        }
    }

    var displayName: String {
        switch self {
        case .stable:
            return "Stable"
        case .preview:
            return "Preview"
        case .nightly:
            return "Nightly"
        }
    }
}
