#if canImport(UIKit) && !os(tvOS)
import UIKit
import SkinKitCore

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

    /// Play this haptic, respecting user preferences (`DeltaSkinInteractionSettings.isButtonVibrationEnabled`;
    /// Provenance gated this on `Defaults[.buttonVibration]`).
    func play() {
        guard DeltaSkinInteractionSettings.current.isButtonVibrationEnabled() else { return }
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
