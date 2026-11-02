import Foundation
import CoreGraphics

/// Which D-pad directions a touch presses, from where it is relative to the pad's centre.
///
/// A touch that goes down on (or slides onto) a D-pad steers it until it lifts, wherever the finger
/// drifts: off the pad's edge, into a corner between arms, or over a neighbouring button. So the offset
/// can be far outside the pad, and the result is still a direction (never empty).
enum SkinDPadDirections {
    /// Fraction of the pad's size an offset must pass on an axis to press that axis's direction.
    static let axisThreshold: CGFloat = 0.3

    /// - Parameters:
    ///   - offset: touch location minus the pad's centre, in view points.
    ///   - padSize: the pad's size, in view points.
    /// - Returns: cardinal tokens (`up`, `down`, `left`, `right`): one, or two for a diagonal.
    static func directions(offset: CGVector, padSize: CGSize) -> Set<String> {
        let thresholdX = padSize.width * axisThreshold
        let thresholdY = padSize.height * axisThreshold
        var directions: Set<String> = []
        if offset.dy < -thresholdY {
            directions.insert("up")
        } else if offset.dy > thresholdY {
            directions.insert("down")
        }
        if offset.dx > thresholdX {
            directions.insert("right")
        } else if offset.dx < -thresholdX {
            directions.insert("left")
        }
        // Near the centre or under both thresholds: the nearest single direction.
        if directions.isEmpty {
            if abs(offset.dx) >= abs(offset.dy) {
                directions.insert(offset.dx >= 0 ? "right" : "left")
            } else {
                directions.insert(offset.dy >= 0 ? "down" : "up")
            }
        }
        return directions
    }
}
