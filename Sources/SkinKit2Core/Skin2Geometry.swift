import Foundation

// Plain Double geometry so the resolver has no CoreGraphics dependency and its output maps one-to-one onto
// `layout.json` and the TypeScript port. Top-left origin, y down, canvas points.

public struct Skin2Size: Equatable, Hashable, Sendable, Codable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
    public var shortSide: Double { min(width, height) }
}

public struct Skin2Insets: Equatable, Hashable, Sendable, Codable {
    public var top: Double, left: Double, bottom: Double, right: Double
    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
    public static let zero = Skin2Insets()

    public func value(_ edge: Skin2Edge) -> Double {
        switch edge {
        case .top: return top
        case .left: return left
        case .bottom: return bottom
        case .right: return right
        }
    }
}

public struct Skin2Rect: Equatable, Hashable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(size: Skin2Size) { self.init(x: 0, y: 0, width: size.width, height: size.height) }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var size: Skin2Size { Skin2Size(width: width, height: height) }

    /// Grows each edge outward by the inset (negative values shrink).
    public func outset(_ i: Skin2Insets) -> Skin2Rect {
        Skin2Rect(x: x - i.left, y: y - i.top, width: width + i.left + i.right, height: height + i.top + i.bottom)
    }

    public func inset(_ i: Skin2Insets) -> Skin2Rect {
        outset(Skin2Insets(top: -i.top, left: -i.left, bottom: -i.bottom, right: -i.right))
    }

    /// True when the two rectangles share area. Rectangles that only touch along an edge do not overlap.
    public func overlaps(_ other: Skin2Rect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    public func contains(_ other: Skin2Rect) -> Bool {
        other.minX >= minX && other.maxX <= maxX && other.minY >= minY && other.maxY <= maxY
    }

    /// Edges rounded to the half point (section 2, "Rounding"): `floor(2v + 0.5) / 2` on each edge, so two
    /// renderers and the baker agree and rectangles that touch before rounding still touch after.
    public var roundedToHalfPoint: Skin2Rect {
        let x0 = Skin2Rounding.halfPoint(minX), x1 = Skin2Rounding.halfPoint(maxX)
        let y0 = Skin2Rounding.halfPoint(minY), y1 = Skin2Rounding.halfPoint(maxY)
        return Skin2Rect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// `[x, y, width, height]`, the form `layout.json` and classic `frame`s use.
    public var array: [Double] { [x, y, width, height] }
}

public enum Skin2Rounding {
    /// Half-point rounding, ties toward +infinity: the same in Swift (`floor`) and JavaScript (`Math.floor`).
    /// Negative zero becomes zero so encoded JSON never says `-0`.
    public static func halfPoint(_ v: Double) -> Double {
        let r = (2 * v + 0.5).rounded(.down) / 2
        return r == 0 ? 0 : r
    }

    /// Rounds to `places` decimals (used for transform matrices in `layout.json`), ties toward +infinity.
    public static func decimals(_ v: Double, _ places: Int) -> Double {
        let f = pow(10, Double(places))
        let r = (v * f + 0.5).rounded(.down) / f
        return r == 0 ? 0 : r
    }
}

/// An affine transform in canvas points: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty` (the Core Graphics and
/// Canvas 2D convention). Positive angles turn clockwise on screen because y points down.
public struct Skin2Transform: Equatable, Hashable, Sendable {
    public var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public static let identity = Skin2Transform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ x: Double, _ y: Double) -> Skin2Transform {
        Skin2Transform(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func rotation(degrees: Double) -> Skin2Transform {
        let r = degrees * .pi / 180
        let cosR = cos(r), sinR = sin(r)
        return Skin2Transform(a: cosR, b: sinR, c: -sinR, d: cosR, tx: 0, ty: 0)
    }

    public static func scale(_ s: Double) -> Skin2Transform { Skin2Transform(a: s, b: 0, c: 0, d: s, tx: 0, ty: 0) }

    /// `self` applied first, then `next`.
    public func then(_ next: Skin2Transform) -> Skin2Transform {
        Skin2Transform(
            a: a * next.a + b * next.c, b: a * next.b + b * next.d,
            c: c * next.a + d * next.c, d: c * next.b + d * next.d,
            tx: tx * next.a + ty * next.c + next.tx, ty: tx * next.b + ty * next.d + next.ty)
    }

    public func apply(x: Double, y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }

    /// `[a, b, c, d, tx, ty]`, the matrix rounded to 4 decimals and the translation to the half point.
    public var roundedArray: [Double] {
        [Skin2Rounding.decimals(a, 4), Skin2Rounding.decimals(b, 4), Skin2Rounding.decimals(c, 4),
         Skin2Rounding.decimals(d, 4), Skin2Rounding.halfPoint(tx), Skin2Rounding.halfPoint(ty)]
    }
}
