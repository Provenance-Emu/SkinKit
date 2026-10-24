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

    public init(
        isButtonVibrationEnabled: @escaping @Sendable () -> Bool = { true },
        isButtonSoundEnabled: @escaping @Sendable () -> Bool = { false },
        isTurboEnabled: @escaping @Sendable () -> Bool = { true },
        isStickyButtonsEnabled: @escaping @Sendable () -> Bool = { false },
        isMultiButtonTouchEnabled: @escaping @Sendable () -> Bool = { false },
        turboRateHz: @escaping @Sendable () -> Double = { 10 },
        playButtonPressSound: @escaping @Sendable (_ pan: Float, _ volume: Float) -> Void = { _, _ in },
        isCaseCompanionSkinsEnabled: @escaping @Sendable () -> Bool = { false }
    ) {
        self.isButtonVibrationEnabled = isButtonVibrationEnabled
        self.isButtonSoundEnabled = isButtonSoundEnabled
        self.isTurboEnabled = isTurboEnabled
        self.isStickyButtonsEnabled = isStickyButtonsEnabled
        self.isMultiButtonTouchEnabled = isMultiButtonTouchEnabled
        self.turboRateHz = turboRateHz
        self.playButtonPressSound = playButtonPressSound
        self.isCaseCompanionSkinsEnabled = isCaseCompanionSkinsEnabled
    }

    private static let lock = NSLock()
    private static var _current = DeltaSkinInteractionSettings()

    /// The settings in effect. Set once at launch.
    public static var current: DeltaSkinInteractionSettings {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}
