// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VerticalTabHoverSidecar.swift - Hover inspector placement for the Aurora vertical sidebar.

import SwiftUI

extension Design {

    struct VerticalTabHoverSidecarPlacement: Equatable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat

        static func placement(
            for tooltip: AuroraSidebarTooltipSnapshot,
            sidebarFrame: CGRect,
            containerSize: CGSize,
            layoutDirection: LayoutDirection
        ) -> VerticalTabHoverSidecarPlacement {
            let availableSpace = layoutDirection == .rightToLeft
                ? max(0, sidebarFrame.minX - 18)
                : max(0, containerSize.width - sidebarFrame.maxX - 18)
            let width = min(360, max(260, availableSpace - 18))
            let x: CGFloat
            if layoutDirection == .rightToLeft {
                x = max(width * 0.5 + 12, sidebarFrame.minX - 18 - width * 0.5)
            } else {
                x = min(
                    containerSize.width - width * 0.5 - 12,
                    sidebarFrame.maxX + 18 + width * 0.5
                )
            }
            let sidebarTopY = max(0, containerSize.height - sidebarFrame.maxY)
            let rawY = sidebarTopY + tooltip.rowFrame.midY
            let approximateHalfHeight: CGFloat = 158
            let y = min(
                max(rawY, approximateHalfHeight + 12),
                max(approximateHalfHeight + 12, containerSize.height - approximateHalfHeight - 12)
            )
            return VerticalTabHoverSidecarPlacement(x: x, y: y, width: width)
        }
    }

    struct VerticalTabHoverSidecar: View {
        let tooltip: AuroraSidebarTooltipSnapshot
        let sidebarFrame: CGRect
        let containerSize: CGSize
        var localizer: AppLocalizer = AppLocalizer(languagePreference: .system)
        @Environment(\.layoutDirection) private var layoutDirection

        var body: some View {
            let placement = VerticalTabHoverSidecarPlacement.placement(
                for: tooltip,
                sidebarFrame: sidebarFrame,
                containerSize: containerSize,
                layoutDirection: layoutDirection
            )
            AuroraSessionTooltipCard(
                session: tooltip.session,
                workspaceName: tooltip.workspaceName,
                workspaceBranch: tooltip.workspaceBranch,
                localizer: localizer
            )
            .frame(width: placement.width)
            .allowsHitTesting(false)
            .position(x: placement.x, y: placement.y)
            .transition(.opacity.combined(with: .scale(
                scale: 0.98,
                anchor: layoutDirection == .rightToLeft ? .trailing : .leading
            )))
        }
    }
}
