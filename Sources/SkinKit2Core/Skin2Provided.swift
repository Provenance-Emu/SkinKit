import Foundation

/// What a resolved skin gives the player itself, so the app can hide its own copy (Task 5 fills this in).
public struct Skin2Provided: Equatable, Sendable {
    /// The smallest hit frame, in points, a provided control or a shelf's handle may have.
    public static let minimumControl = Skin2Size(width: 44, height: 44)
}
