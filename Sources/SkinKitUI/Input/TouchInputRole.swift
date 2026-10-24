import Foundation

/// Whether a touch control is a gameplay input or a frontend / console-system control.
///
/// Gameplay controls take part in drag-across (a finger sliding onto them presses them) and in
/// multi-button touch. System controls never do: they fire only for a touch that begins on them, and a
/// touch that began on one never slides onto anything else.
///
/// Copied from Provenance's `PVTouchOverlay`, together with ``SkinTouchSelection``, which the skin view
/// needs. The token classifier (`TouchInputClassifier`) stays in the app and reaches the view through
/// ``DeltaSkinInputHandling/touchRole(forToken:)``.
public enum TouchInputRole: Sendable, Hashable {
    case gameplay
    case system

    public var isGameplay: Bool { self == .gameplay }
}
