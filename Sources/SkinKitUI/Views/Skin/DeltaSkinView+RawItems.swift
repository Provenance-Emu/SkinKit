#if canImport(UIKit)
import CoreGraphics
import SkinKitCore

extension DeltaSkinView {
    /// Raw items must use the same representation as the decoded controls and artwork.
    func rawButtonItems() -> [[String: Any]]? {
        guard let representations = skin.jsonRepresentation["representations"] as? [String: Any],
              let device = representations[traits.device.rawValue] as? [String: Any] else { return nil }
        // Match DeltaSkin's decoded representation lookup, including an absent orientation.
        // Some skins declare only edgeToEdge even when the host requests standard traits.
        for displayType in traits.displayType.lookupChain {
            guard let display = device[displayType.rawValue] as? [String: Any],
                  let orientation = display[traits.orientation.rawValue] as? [String: Any] else { continue }
            return orientation["items"] as? [[String: Any]]
        }
        return nil
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
