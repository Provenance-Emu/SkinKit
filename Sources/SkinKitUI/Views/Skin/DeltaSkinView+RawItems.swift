#if canImport(UIKit)
import CoreGraphics
import SkinKitCore

extension DeltaSkinView {
    /// Raw items must use the same representation as the decoded controls and artwork, including the
    /// alternate layout set when the traits select it (see `DeltaSkin.rawItems(in:for:)`).
    func rawButtonItems() -> [[String: Any]]? {
        DeltaSkin.rawItems(in: skin.jsonRepresentation, for: traits)
    }

    /// Join decoded controls to their raw per-item artwork and thumbstick metadata.
    func rawItem(matching button: DeltaSkinButton) -> [String: Any]? {
        skin.rawItem(matching: button, traits: traits)
    }
}
#endif
