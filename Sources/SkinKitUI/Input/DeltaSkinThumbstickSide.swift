import Foundation
import SkinKitCore

/// Which physical stick a skin thumbstick item represents.
///
/// Moved out of Provenance's `DeltaSkinNintendoHomeConsoleMapping`, whose other tables (GameCube and Wii
/// buttons) need `PVCoreBridge` and stay in the app. Provenance's `stickSide(for:buttonId:)` can forward here.
public enum DeltaSkinThumbstickSide: Equatable, Sendable {
    case left
    case right

    /// Identifier passed to `DeltaSkinInputHandling.analogStickMoved(_:x:y:)`.
    public var analogStickId: String {
        switch self {
        case .left: return "leftAnalog"
        case .right: return "rightAnalog"
        }
    }

    /// Decides left vs right for a thumbstick item.
    ///
    /// `DeltaSkin.buttons(for:)` mints ids like `"<skinId>-button-<n>"`, so the id
    /// never says which stick it is. The authoritative signal is the item's
    /// directional mapping (`{"up": "rightThumbstickUp", ...}`); the id is only a
    /// fallback for older skins that encode the side there.
    public static func resolve(for input: DeltaSkinInput, buttonId: String) -> DeltaSkinThumbstickSide {
        if case .directional(let mapping) = input {
            // Only stick-flavoured values count: a plain D-pad mapping is
            // {"left": "left", "right": "right"} and must not read as a right stick.
            let values = mapping.values.map { $0.lowercased() }.filter { $0.contains("stick") || $0.contains("analog") }
            if values.contains(where: { $0.hasPrefix("right") }) { return .right }
            if values.contains(where: { $0.hasPrefix("left") }) { return .left }
        }
        return buttonId.lowercased().contains("right") ? .right : .left
    }
}
