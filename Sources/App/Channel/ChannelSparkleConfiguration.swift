// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ChannelSparkleConfiguration.swift - Sparkle appcast metadata per update channel.

import Foundation

struct ChannelSparkleConfiguration: Sendable, Equatable {
    static let defaultPublicEDKey = "gMWhWC+AqrUZqRg1RbTr32MDdkk7H3DhLfnEqtQnWQU="

    let channel: ChannelKind
    let publicEDKey: String

    init(
        channel: ChannelKind,
        publicEDKey: String = Self.defaultPublicEDKey
    ) {
        self.channel = channel
        self.publicEDKey = publicEDKey
    }

    var feedURLString: String {
        channel.feedURLString
    }

    var feedURL: URL {
        URL(string: feedURLString)!
    }
}
