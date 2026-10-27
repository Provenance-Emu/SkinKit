#if canImport(UIKit)
import CoreGraphics
import Foundation

/// What the host does with a press-and-hold on an empty part of the skin.
///
/// iFly fast-forwards while a finger rests on the game screen's surroundings and speeds up or slows
/// down as it slides sideways. The gesture mechanics live in ``DeltaSkinView`` (turned on per view with
/// `allowsEmptyAreaHold`); what a hold *does* is the host's, behind this protocol, so SkinKit knows
/// nothing about fast-forward. A host returns its implementation from
/// ``DeltaSkinInputHandling/holdHandler``; the default is `nil`, which is no hold gesture at all.
///
/// Several fingers can hold at once. The view counts them: `holdDidBegin()` fires for the first and
/// `holdDidEnd()` for the last to lift, and only the first holder's slide is reported, so concurrent
/// holds can't fight over the same value.
public protocol DeltaSkinHoldHandling: AnyObject {
    /// Seconds a finger must rest on an empty area before the hold fires.
    var holdDelay: TimeInterval { get }
    /// The first resting finger just fired its hold.
    func holdDidBegin()
    /// The finger that owns the hold moved `dx` points horizontally (positive: right) from where it was
    /// when the hold fired.
    func holdDidSlide(dx: CGFloat)
    /// The last resting finger lifted.
    func holdDidEnd()
}

public extension DeltaSkinHoldHandling {
    var holdDelay: TimeInterval { 0.4 }
    func holdDidSlide(dx: CGFloat) {}
}
#endif
