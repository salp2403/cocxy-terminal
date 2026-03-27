// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateIndicator.swift - Visual indicator for agent lifecycle state.

import AppKit

// MARK: - Agent State Indicator

/// A visual indicator (16x16pt) that displays the current agent state
/// in a tab bar item.
///
/// ## Visual States
///
/// - **idle**: Tertiary label color circle, no badge.
/// - **launched**: Blue circle with pulse animation.
/// - **working**: Blue circle with pulse animation (opacity 0.5 -> 1.0, 1.5s cycle).
/// - **waitingInput**: Yellow circle with "?" badge.
/// - **finished**: Green circle with checkmark badge.
/// - **error**: Red circle with "!" badge.
///
/// ## Accessibility
///
/// Each state has a descriptive `accessibilityLabel` in English.
/// The pulse animation respects `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
///
/// - SeeAlso: `TabBarView` (parent view)
/// - SeeAlso: `AgentState` (domain enum)
@MainActor
final class AgentStateIndicator: NSView {

    // MARK: - Constants

    /// The size of the indicator circle in points.
    static let indicatorSize: CGFloat = 16.0

    /// Duration of one full pulse cycle (seconds).
    private static let pulseDuration: CFTimeInterval = 1.5

    // MARK: - State

    /// The semantic color name for the current state.
    private(set) var currentColorName: String = "tertiaryLabel"

    /// The badge text for the current state, or nil if no badge.
    private(set) var currentBadgeText: String?

    /// The accessibility label describing the current state.
    private(set) var currentAccessibilityLabel: String = "Agent state: idle"

    /// Whether pulse animation is logically enabled for the current state.
    ///
    /// `true` for `working` and `launched` states. Does not account for
    /// reduce motion preference.
    private(set) var isPulseAnimationEnabled: Bool = false

    /// Whether pulse animation is actively running.
    ///
    /// `false` when reduce motion is enabled, even if the state would
    /// normally pulse. Read-only; derived from `isPulseAnimationEnabled`
    /// and `reduceMotionEnabled`.
    var isPulseAnimationActive: Bool {
        isPulseAnimationEnabled && !reduceMotionEnabled
    }

    /// Override for the system reduce motion setting.
    ///
    /// When not explicitly set, reads from
    /// `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.
    var reduceMotionEnabled: Bool = false {
        didSet {
            updateAnimationState()
        }
    }

    // MARK: - Subviews

    /// The circular indicator layer.
    private let circleLayer: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = indicatorSize / 2
        layer.masksToBounds = false
        return layer
    }()

    /// The ring layer for the expanding wave effect around the circle.
    private let ringLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 2
        layer.isHidden = true
        return layer
    }()

    /// The badge label overlaid on the circle.
    private let badgeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 8, weight: .bold)
        // Catppuccin Crust -- dark text for high contrast on colored badges.
        label.textColor = CocxyColors.crust
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    // MARK: - Initialization

    init() {
        super.init(frame: NSRect(
            x: 0, y: 0,
            width: Self.indicatorSize,
            height: Self.indicatorSize
        ))
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("AgentStateIndicator does not support NSCoding")
    }

    // MARK: - Setup

    private func setupView() {
        wantsLayer = true

        // Ring layer sits behind the circle for the wave expansion effect.
        let ringRect = NSRect(
            x: -2, y: -2,
            width: Self.indicatorSize + 4,
            height: Self.indicatorSize + 4
        )
        ringLayer.path = CGPath(ellipseIn: ringRect, transform: nil)
        layer?.addSublayer(ringLayer)

        circleLayer.frame = NSRect(
            x: 0, y: 0,
            width: Self.indicatorSize,
            height: Self.indicatorSize
        )
        circleLayer.backgroundColor = nsColor(for: currentColorName).cgColor
        layer?.addSublayer(circleLayer)

        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badgeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(currentAccessibilityLabel)
    }

    // MARK: - Public API

    /// Updates the indicator to reflect a new agent state.
    ///
    /// - Parameter state: The new agent state.
    func updateState(_ state: AgentState) {
        let config = Self.stateConfiguration(for: state)

        currentColorName = config.colorName
        currentBadgeText = config.badgeText
        currentAccessibilityLabel = config.accessibilityLabel
        isPulseAnimationEnabled = config.pulseEnabled

        let stateColor = nsColor(for: config.colorName)
        animateColorTransition(to: stateColor)

        if let badge = config.badgeText {
            badgeLabel.stringValue = badge
            badgeLabel.isHidden = false
        } else {
            badgeLabel.stringValue = ""
            badgeLabel.isHidden = true
        }

        // Configure the ring effect per state.
        updateRingEffect(for: state, color: stateColor)

        // Configure the bounce animation for waitingInput.
        updateBounceAnimation(for: state)

        // For launched state, use ring-only appearance (hollow circle).
        if state == .launched {
            circleLayer.backgroundColor = NSColor.clear.cgColor
            circleLayer.borderWidth = 2
            circleLayer.borderColor = stateColor.cgColor
        } else {
            circleLayer.borderWidth = 0
            circleLayer.borderColor = nil
        }

        setAccessibilityLabel(config.accessibilityLabel)
        updateAnimationState()
    }

    // MARK: - Animation

    /// Animates the circle layer background color to a new value.
    ///
    /// Uses `CABasicAnimation` for a smooth transition. When reduce motion
    /// is active, the color changes instantly.
    private func animateColorTransition(to newColor: NSColor) {
        let duration = AnimationConfig.duration(
            AnimationConfig.stateColorTransitionDuration,
            reduceMotionOverride: reduceMotionEnabled
        )

        if duration == 0 {
            circleLayer.backgroundColor = newColor.cgColor
            return
        }

        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = circleLayer.backgroundColor
        animation.toValue = newColor.cgColor
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = true
        circleLayer.backgroundColor = newColor.cgColor
        circleLayer.add(animation, forKey: "colorTransition")
    }

    /// Starts or stops the pulse animation based on current state and preferences.
    private func updateAnimationState() {
        if isPulseAnimationActive {
            startPulseAnimation()
        } else {
            stopPulseAnimation()
        }
    }

    /// Starts the opacity pulse animation on the circle layer.
    private func startPulseAnimation() {
        guard circleLayer.animation(forKey: "pulse") == nil else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.5
        animation.toValue = 1.0
        animation.duration = Self.pulseDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        circleLayer.add(animation, forKey: "pulse")
    }

    /// Stops the pulse animation.
    private func stopPulseAnimation() {
        circleLayer.removeAnimation(forKey: "pulse")
        circleLayer.opacity = 1.0
    }

    // MARK: - Ring Effect

    /// Shows or hides the ring expansion effect based on state.
    ///
    /// - `working`: solid fill + animated ring (wave effect).
    /// - `launched`: ring-only (no fill), animated ring.
    /// - All other states: ring hidden.
    private func updateRingEffect(for state: AgentState, color: NSColor) {
        switch state {
        case .working, .launched:
            ringLayer.strokeColor = color.cgColor
            ringLayer.isHidden = false
            startRingPulseAnimation()
        default:
            stopRingPulseAnimation()
            ringLayer.isHidden = true
        }
    }

    /// Starts the ring pulse animation (opacity 0.5 -> 1.0, same cycle as circle).
    private func startRingPulseAnimation() {
        guard !reduceMotionEnabled else {
            ringLayer.removeAnimation(forKey: "ringPulse")
            return
        }
        guard ringLayer.animation(forKey: "ringPulse") == nil else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.3
        animation.toValue = 1.0
        animation.duration = Self.pulseDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ringLayer.add(animation, forKey: "ringPulse")
    }

    /// Stops the ring pulse animation.
    private func stopRingPulseAnimation() {
        ringLayer.removeAnimation(forKey: "ringPulse")
        ringLayer.opacity = 1.0
    }

    // MARK: - Bounce Animation

    /// Adds or removes the bounce animation for the `waitingInput` state.
    ///
    /// The bounce scales the indicator from 1.0 to 1.2 and back over 0.6s,
    /// making it impossible to ignore when the agent needs user input.
    private func updateBounceAnimation(for state: AgentState) {
        if state == .waitingInput && !reduceMotionEnabled {
            startBounceAnimation()
        } else {
            stopBounceAnimation()
        }
    }

    /// Starts the scale bounce animation on the view's layer.
    private func startBounceAnimation() {
        guard let viewLayer = layer else { return }
        guard viewLayer.animation(forKey: "bounce") == nil else { return }

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1.0
        animation.toValue = 1.2
        animation.duration = 0.6
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        viewLayer.add(animation, forKey: "bounce")
    }

    /// Stops the scale bounce animation.
    private func stopBounceAnimation() {
        layer?.removeAnimation(forKey: "bounce")
    }

    // MARK: - Color Mapping

    /// Returns the NSColor for a semantic color name.
    ///
    /// Uses Catppuccin Mocha colors for consistency with the overall theme.
    private func nsColor(for name: String) -> NSColor {
        switch name {
        case "tertiaryLabel":
            return CocxyColors.overlay0
        case "systemBlue":
            return CocxyColors.blue
        case "systemYellow":
            return CocxyColors.yellow
        case "systemGreen":
            return CocxyColors.green
        case "systemRed":
            return CocxyColors.red
        default:
            return CocxyColors.overlay0
        }
    }

    // MARK: - State Configuration

    /// Configuration for a specific agent state.
    private struct StateConfig {
        let colorName: String
        let badgeText: String?
        let accessibilityLabel: String
        let pulseEnabled: Bool
    }

    /// Returns the visual configuration for an agent state.
    private static func stateConfiguration(for state: AgentState) -> StateConfig {
        switch state {
        case .idle:
            return StateConfig(
                colorName: "tertiaryLabel",
                badgeText: nil,
                accessibilityLabel: "Agent state: idle",
                pulseEnabled: false
            )
        case .launched:
            return StateConfig(
                colorName: "systemBlue",
                badgeText: nil,
                accessibilityLabel: "Agent state: launched",
                pulseEnabled: true
            )
        case .working:
            return StateConfig(
                colorName: "systemBlue",
                badgeText: nil,
                accessibilityLabel: "Agent state: working",
                pulseEnabled: true
            )
        case .waitingInput:
            return StateConfig(
                colorName: "systemYellow",
                badgeText: "?",
                accessibilityLabel: "Agent state: waiting for input",
                pulseEnabled: false
            )
        case .finished:
            return StateConfig(
                colorName: "systemGreen",
                badgeText: "\u{2713}",
                accessibilityLabel: "Agent state: finished",
                pulseEnabled: false
            )
        case .error:
            return StateConfig(
                colorName: "systemRed",
                badgeText: "!",
                accessibilityLabel: "Agent state: error",
                pulseEnabled: false
            )
        }
    }
}
