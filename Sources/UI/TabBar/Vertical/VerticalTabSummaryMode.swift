// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabSummaryMode.swift - Always-visible summary line for vertical tab rows.

import Foundation

extension Design {

    struct VerticalTabSummaryMode: Equatable, Sendable {
        let state: AgentStateRole
        let metadataLine: String

        init(session: AuroraSession, primaryInfo: AuroraSidebarPrimaryInfo) {
            self.state = session.state
            self.metadataLine = session.primaryMetadataLine(selection: primaryInfo)
        }

        init(
            session: AuroraSession,
            primaryInfo: AuroraSidebarPrimaryInfo,
            localizer: AppLocalizer
        ) {
            self.state = session.state
            self.metadataLine = session.localizedPrimaryMetadataLine(
                selection: primaryInfo,
                using: localizer
            )
        }
    }
}
