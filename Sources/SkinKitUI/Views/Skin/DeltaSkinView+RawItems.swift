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
        rawButtonItems()?.first { item in
            guard let frame = item["frame"] as? [String: Any],
                  let x = frame["x"] as? CGFloat,
                  let y = frame["y"] as? CGFloat,
                  let width = frame["width"] as? CGFloat,
                  let height = frame["height"] as? CGFloat else { return false }
            return CGRect(x: x, y: y, width: width, height: height) == button.frame
        }
    }
}
#endif
