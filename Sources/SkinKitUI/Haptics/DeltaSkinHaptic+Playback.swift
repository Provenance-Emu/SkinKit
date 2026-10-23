#if canImport(UIKit) && !os(tvOS)
import UIKit
import SkinKitCore

/// Whether button haptics are allowed.
///
/// Provenance gated `DeltaSkinHaptic.play()` on its `buttonVibration` setting
/// (`Defaults[.buttonVibration]`). SkinKitUI has no settings store, so the host app injects the check.
/// The default allows haptics.
public enum DeltaSkinHapticSettings {
    private static let lock = NSLock()
    private static var _isEnabled: @Sendable () -> Bool = { true }

    /// Returns `true` when the user wants button haptics. Provenance:
    /// `DeltaSkinHapticSettings.isEnabled = { Defaults[.buttonVibration] }`.
    public static var isEnabled: @Sendable () -> Bool {
        get { lock.withLock { _isEnabled } }
        set { lock.withLock { _isEnabled = newValue } }
    }
}

public extension DeltaSkinHaptic {
    /// Map style string to UIImpactFeedbackGenerator.FeedbackStyle
    var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch style.lowercased() {
        case "light":  return .light
        case "heavy":  return .heavy
        case "soft":   return .soft
        case "rigid":  return .rigid
        default:       return .medium
        }
    }

    /// Play this haptic, respecting user preferences (see ``DeltaSkinHapticSettings``).
    func play() {
        guard DeltaSkinHapticSettings.isEnabled() else { return }
        if style.lowercased() == "selection" {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        } else {
            let generator = UIImpactFeedbackGenerator(style: feedbackStyle)
            generator.prepare()
            generator.impactOccurred(intensity: CGFloat(max(0.0, min(1.0, intensity))))
        }
    }
}
#endif
