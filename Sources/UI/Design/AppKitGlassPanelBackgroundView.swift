// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppKitGlassPanelBackgroundView.swift - Shared AppKit glass backing for panel chrome.

import AppKit

extension Design {
    @MainActor
    final class AppKitGlassPanelBackgroundView: NSView {
        private let effectView = NSVisualEffectView()
        private let tintView = NSView()
        private let tintColor: NSColor
        private let opaqueFallbackColor: NSColor

        init(
            material: NSVisualEffectView.Material = .hudWindow,
            tintColor: NSColor = CocxyColors.surface0.withAlphaComponent(0.34),
            opaqueFallbackColor: NSColor = CocxyColors.base
        ) {
            self.tintColor = tintColor
            self.opaqueFallbackColor = opaqueFallbackColor
            super.init(frame: .zero)
            configure(material: material)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("AppKitGlassPanelBackgroundView does not support NSCoding")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            refreshAccessibilityMode()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            refreshAccessibilityMode()
        }

        private func configure(material: NSVisualEffectView.Material) {
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor

            effectView.material = material
            effectView.blendingMode = .withinWindow
            effectView.state = .active
            effectView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(effectView)

            tintView.wantsLayer = true
            tintView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(tintView)

            NSLayoutConstraint.activate([
                effectView.topAnchor.constraint(equalTo: topAnchor),
                effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                effectView.bottomAnchor.constraint(equalTo: bottomAnchor),

                tintView.topAnchor.constraint(equalTo: topAnchor),
                tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
                tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
                tintView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])

            refreshAccessibilityMode()
        }

        private func refreshAccessibilityMode() {
            let forceOpaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
                || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            effectView.isHidden = forceOpaque
            tintView.layer?.backgroundColor = (forceOpaque ? opaqueFallbackColor : tintColor).cgColor
        }
    }
}

extension NSView {
    @MainActor
    @discardableResult
    func installAppKitGlassPanelBackground(
        material: NSVisualEffectView.Material = .hudWindow,
        tintColor: NSColor = CocxyColors.surface0.withAlphaComponent(0.34),
        opaqueFallbackColor: NSColor = CocxyColors.base
    ) -> Design.AppKitGlassPanelBackgroundView {
        let background = Design.AppKitGlassPanelBackgroundView(
            material: material,
            tintColor: tintColor,
            opaqueFallbackColor: opaqueFallbackColor
        )
        background.translatesAutoresizingMaskIntoConstraints = false
        if let firstSubview = subviews.first {
            addSubview(background, positioned: .below, relativeTo: firstSubview)
        } else {
            addSubview(background)
        }
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        return background
    }
}
