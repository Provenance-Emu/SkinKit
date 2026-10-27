import Foundation

/// User settings the skin views read while a skin is on screen.
///
/// Provenance read these from `Defaults` (`PVSettings`) inside the views. SkinKitUI has no settings
/// store, so the app supplies closures; each is read at the moment it is needed, so a changed setting
/// applies on the next press. The defaults match Provenance's `Defaults` defaults.
public struct DeltaSkinInteractionSettings: Sendable {
    /// `Defaults[.buttonVibration]`. Also gates `DeltaSkinHaptic.play()`.
    public var isButtonVibrationEnabled: @Sendable () -> Bool
    /// `Defaults[.buttonSound] != .none`.
    public var isButtonSoundEnabled: @Sendable () -> Bool
    /// `Defaults[.turboEnabled]`.
    public var isTurboEnabled: @Sendable () -> Bool
    /// `Defaults[.stickyButtonsEnabled]`.
    public var isStickyButtonsEnabled: @Sendable () -> Bool
    /// `Defaults[.skinMultiButtonTouch]`.
    public var isMultiButtonTouchEnabled: @Sendable () -> Bool
    /// `Defaults[.turboRateHz]`.
    public var turboRateHz: @Sendable () -> Double
    /// `ButtonSoundGenerator.shared.playButtonPressSound(pan:volume:)`: plays the user's chosen button-press
    /// sound. `pan` is -1...1 by button position and `volume` 0.5...1 by button size. The default is silent.
    public var playButtonPressSound: @Sendable (_ pan: Float, _ volume: Float) -> Void
    /// `Defaults[.caseCompanionSkins]`: whether the skin picker lists phone-case companion skins.
    public var isCaseCompanionSkinsEnabled: @Sendable () -> Bool
    /// Whether a combo hotspot (`"inputs": ["a", "b"]`, `DeltaSkinButton.comboInputs`) presses all of its
    /// inputs. Off (Provenance's behavior): it presses the first one only. iFly turns this on.
    public var pressesComboInputs: @Sendable () -> Bool
    /// Replaces the on/off vibration check with the app's own haptics preference. Given the intensity
    /// a haptic would use (button 1.0, D-pad direction 0.6, thumbstick edge 0.7, thumbstick drag up to
    /// 0.5), it returns the intensity to play, scaled by the user's setting, or `nil` for none. `nil` here
    /// (the default) keeps `isButtonVibrationEnabled` and the fixed intensities. A skin button's own
    /// `haptic` configuration still takes precedence.
    public var scaledHapticIntensity: (@Sendable (_ baseIntensity: Double) -> Double?)?
    /// Whether the skin view draws press feedback: a soft highlight over a button (or D-pad direction)
    /// while it is touched, and a circle under each finger. Off (Provenance's behavior): neither.
    public var showsTouchFeedback: @Sendable () -> Bool
    /// Whether a D-pad plays its haptic and click only when a direction newly engages, instead of on
    /// every touch-move while a direction is held. Off (Provenance's behavior): every move. iFly turns this
    /// on: firing on every move produced hundreds of clicks and highlights a second during a drag.
    public var dpadFeedbackOnChangeOnly: @Sendable () -> Bool

    public init(
        isButtonVibrationEnabled: @escaping @Sendable () -> Bool = { true },
        isButtonSoundEnabled: @escaping @Sendable () -> Bool = { false },
        isTurboEnabled: @escaping @Sendable () -> Bool = { true },
        isStickyButtonsEnabled: @escaping @Sendable () -> Bool = { false },
        isMultiButtonTouchEnabled: @escaping @Sendable () -> Bool = { false },
        turboRateHz: @escaping @Sendable () -> Double = { 10 },
        playButtonPressSound: @escaping @Sendable (_ pan: Float, _ volume: Float) -> Void = { _, _ in },
        isCaseCompanionSkinsEnabled: @escaping @Sendable () -> Bool = { false },
        pressesComboInputs: @escaping @Sendable () -> Bool = { false },
        scaledHapticIntensity: (@Sendable (_ baseIntensity: Double) -> Double?)? = nil,
        showsTouchFeedback: @escaping @Sendable () -> Bool = { false },
        dpadFeedbackOnChangeOnly: @escaping @Sendable () -> Bool = { false }
    ) {
        self.isButtonVibrationEnabled = isButtonVibrationEnabled
        self.isButtonSoundEnabled = isButtonSoundEnabled
        self.isTurboEnabled = isTurboEnabled
        self.isStickyButtonsEnabled = isStickyButtonsEnabled
        self.isMultiButtonTouchEnabled = isMultiButtonTouchEnabled
        self.turboRateHz = turboRateHz
        self.playButtonPressSound = playButtonPressSound
        self.isCaseCompanionSkinsEnabled = isCaseCompanionSkinsEnabled
        self.pressesComboInputs = pressesComboInputs
        self.scaledHapticIntensity = scaledHapticIntensity
        self.showsTouchFeedback = showsTouchFeedback
        self.dpadFeedbackOnChangeOnly = dpadFeedbackOnChangeOnly
    }

    /// The intensity a button or D-pad haptic of `baseIntensity` plays at, or `nil` for none: the app's
    /// scaled preference when it supplies one, otherwise `baseIntensity` while button vibration is on.
    public func hapticIntensity(_ baseIntensity: Double) -> Double? {
        if let scaledHapticIntensity { return scaledHapticIntensity(baseIntensity) }
        return isButtonVibrationEnabled() ? baseIntensity : nil
    }

    private static let lock = NSLock()
    private static var _current = DeltaSkinInteractionSettings()

    /// The settings in effect. Set once at launch.
    public static var current: DeltaSkinInteractionSettings {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}
