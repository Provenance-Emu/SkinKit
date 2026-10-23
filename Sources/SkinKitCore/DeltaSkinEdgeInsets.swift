import CoreGraphics

#if canImport(UIKit)
import UIKit

/// Edge insets used by skin frames. On iOS and tvOS this is exactly `UIEdgeInsets`, so code that
/// already uses `UIEdgeInsets` for skin edges keeps compiling unchanged.
public typealias DeltaSkinEdgeInsets = UIEdgeInsets
#else
/// Edge insets used by skin frames. On platforms without UIKit (the macOS test host) this stands
/// in for `UIEdgeInsets`. It has the same members and the same `Codable` layout
/// (`[top, left, bottom, right]`).
public struct DeltaSkinEdgeInsets: Equatable, Hashable, Codable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public static let zero = DeltaSkinEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    public init() {
        self.init(top: 0, left: 0, bottom: 0, right: 0)
    }

    public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        top = try container.decode(CGFloat.self)
        left = try container.decode(CGFloat.self)
        bottom = try container.decode(CGFloat.self)
        right = try container.decode(CGFloat.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(top)
        try container.encode(left)
        try container.encode(bottom)
        try container.encode(right)
    }
}
#endif
