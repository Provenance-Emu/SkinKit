import CoreGraphics
import Foundation
import SkinKit2Core

/// Shape outlines (section 3, "Shape kinds") as `CGPath`s in canvas points.
///
/// Conventions the TypeScript renderer copies: angles are degrees, 0 along +x, positive clockwise on screen (y is
/// down). Polygons and stars start with a vertex along +x (0°) before `rotation`, as the spike did, so a triangle
/// with `rotation: -90` points up. Lengths (`cornerRadius`) resolve with `%` against the frame's short side.
/// Ellipses and arcs use Core Graphics' four-cubic circle.
public enum Skin2Shapes {
    /// The outline of `shape` in `rect`. `unit` scales point lengths.
    public static func path(for shape: Skin2Shape, in rect: CGRect, unit: Double) -> CGPath {
        let short = Double(min(rect.width, rect.height))
        func len(_ l: Skin2Length?, _ fallback: Double) -> CGFloat {
            CGFloat(l?.resolve(along: short, unit: unit) ?? fallback * unit)
        }
        switch shape.kind {
        case .rect:
            if let corners = shape.corners, corners.count == 4 {
                return roundedRect(rect, radii: corners.map { len($0, 0) })
            }
            let r = len(shape.cornerRadius, 0)
            return roundedRect(rect, radii: [r, r, r, r])
        case .squircle:
            return squircle(rect, radius: len(shape.cornerRadius, 0))
        case .ellipse:
            return CGPath(ellipseIn: rect, transform: nil)
        case .capsule:
            let r = min(rect.width, rect.height) / 2
            return roundedRect(rect, radii: [r, r, r, r])
        case .polygon:
            return polygon(sides: shape.sides ?? 6, rotation: shape.rotation ?? 0, cornerRadius: len(shape.cornerRadius, 0), in: rect)
        case .star:
            return star(points: shape.points ?? 5, innerRatio: shape.innerRatio ?? 0.5, rotation: shape.rotation ?? 0, in: rect)
        case .arc:
            return arc(start: shape.startAngle ?? 0, end: shape.endAngle ?? 360, inner: shape.inner ?? 0, in: rect)
        case .line:
            let p = CGMutablePath()
            let a = shape.from ?? Skin2UnitPoint(x: 0, y: 0.5), b = shape.to ?? Skin2UnitPoint(x: 1, y: 0.5)
            p.move(to: point(a, in: rect))
            p.addLine(to: point(b, in: rect))
            return p
        case .cross:
            return cross(armRatio: shape.armRatio ?? 0.34, cornerRadius: len(shape.cornerRadius, 6), in: rect)
        case .kidney:
            return kidney(bulge: shape.bulge ?? 0.5, in: rect)
        case .trapezoid:
            return trapezoid(taper: shape.taper ?? 0.14, in: rect)
        case .path:
            let box = shape.box ?? [0, 0, 1, 1]
            return Skin2SVGPath.path(shape.d ?? "", box: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]), in: rect)
        }
    }

    /// True for outlines that are lines, not areas: they are stroked only, and inner/outer stroke alignment
    /// falls back to centre.
    public static func isOpen(_ shape: Skin2Shape) -> Bool { shape.kind == .line }

    static func point(_ p: Skin2UnitPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(p.x) * rect.width, y: rect.minY + CGFloat(p.y) * rect.height)
    }

    /// A rectangle with per-corner radii `[topLeft, topRight, bottomRight, bottomLeft]`, each clamped to half the
    /// short side. Corners are circular arcs (`arcTo` in Canvas 2D).
    static func roundedRect(_ rect: CGRect, radii: [CGFloat]) -> CGPath {
        let limit = min(rect.width, rect.height) / 2
        let r = radii.map { max(0, min($0, limit)) }
        if r.allSatisfy({ $0 == 0 }) { return CGPath(rect: rect, transform: nil) }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX + r[0], y: rect.minY))
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r[1])
        p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r[2])
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r[3])
        p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r[0])
        p.closeSubpath()
        return p
    }

    /// Continuous ("squircle") corners, the shared approximation both renderers use: each corner starts
    /// `e = min(1.528665 × radius, short side / 2)` from the corner along each edge and is one cubic whose control
    /// points sit `0.1 × e` from the corner on each edge.
    static func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let e = min(1.528665 * max(0, radius), min(rect.width, rect.height) / 2)
        if e == 0 { return CGPath(rect: rect, transform: nil) }
        let k: CGFloat = 0.1 * e
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x0 + e, y: y0))
        p.addLine(to: CGPoint(x: x1 - e, y: y0))
        p.addCurve(to: CGPoint(x: x1, y: y0 + e), control1: CGPoint(x: x1 - k, y: y0), control2: CGPoint(x: x1, y: y0 + k))
        p.addLine(to: CGPoint(x: x1, y: y1 - e))
        p.addCurve(to: CGPoint(x: x1 - e, y: y1), control1: CGPoint(x: x1, y: y1 - k), control2: CGPoint(x: x1 - k, y: y1))
        p.addLine(to: CGPoint(x: x0 + e, y: y1))
        p.addCurve(to: CGPoint(x: x0, y: y1 - e), control1: CGPoint(x: x0 + k, y: y1), control2: CGPoint(x: x0, y: y1 - k))
        p.addLine(to: CGPoint(x: x0, y: y0 + e))
        p.addCurve(to: CGPoint(x: x0 + e, y: y0), control1: CGPoint(x: x0, y: y0 + k), control2: CGPoint(x: x0 + k, y: y0))
        p.closeSubpath()
        return p
    }

    static func radians(_ degrees: Double) -> CGFloat { CGFloat(degrees * .pi / 180) }

    /// A closed outline through `points`, with the corners at the indexes in `rounded` rounded by `radius`.
    static func roundedPolygon(_ points: [CGPoint], radius: CGFloat, rounded: (Int) -> Bool) -> CGPath {
        let p = CGMutablePath()
        let n = points.count
        if radius <= 0 || n < 3 {
            p.addLines(between: points)
            p.closeSubpath()
            return p
        }
        // Start halfway along the last edge so every corner is reached through addArc(tangent1End:).
        let last = points[n - 1], first = points[0]
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in 0..<n {
            let corner = points[i], next = points[(i + 1) % n]
            if rounded(i) {
                let prev = points[(i + n - 1) % n]
                // Clamp so two arcs on one edge never overlap.
                let edge = min(hypot(corner.x - prev.x, corner.y - prev.y), hypot(next.x - corner.x, next.y - corner.y)) / 2
                let a1 = atan2(prev.y - corner.y, prev.x - corner.x), a2 = atan2(next.y - corner.y, next.x - corner.x)
                var half = abs(a1 - a2)
                if half > .pi { half = 2 * .pi - half }
                half /= 2
                let maxRadius = edge * tan(half)
                p.addArc(tangent1End: corner, tangent2End: next, radius: min(radius, maxRadius))
            } else {
                p.addLine(to: corner)
            }
        }
        p.closeSubpath()
        return p
    }

    /// A regular polygon inscribed in a circle of the frame's short side, centred.
    static func polygon(sides: Int, rotation: Double, cornerRadius: CGFloat, in rect: CGRect) -> CGPath {
        let n = max(3, sides)
        let c = CGPoint(x: rect.midX, y: rect.midY), radius = min(rect.width, rect.height) / 2
        let points = (0..<n).map { i -> CGPoint in
            let a = radians(rotation + 360 * Double(i) / Double(n))
            return CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        }
        return roundedPolygon(points, radius: cornerRadius) { _ in true }
    }

    static func star(points: Int, innerRatio: Double, rotation: Double, in rect: CGRect) -> CGPath {
        let n = max(3, points)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * CGFloat(innerRatio)
        let vertices = (0..<(2 * n)).map { i -> CGPoint in
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = radians(rotation + 180 * Double(i) / Double(n))
            return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        let p = CGMutablePath()
        p.addLines(between: vertices)
        p.closeSubpath()
        return p
    }

    /// A pie slice (`inner` 0) or ring sector of the circle on the frame's short side, clockwise from `start` to
    /// `end` degrees.
    static func arc(start: Double, end: Double, inner: Double, in rect: CGRect) -> CGPath {
        let c = CGPoint(x: rect.midX, y: rect.midY), outer = min(rect.width, rect.height) / 2
        var sweep = end - start
        if sweep > 360 { sweep = 360 }
        let a0 = radians(start), a1 = radians(start + sweep)
        let p = CGMutablePath()
        if inner > 0 {
            let r = outer * CGFloat(inner)
            p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: sweep < 0)
            p.addArc(center: c, radius: r, startAngle: a1, endAngle: a0, clockwise: sweep >= 0)
        } else {
            if abs(sweep) < 360 { p.move(to: c) }
            p.addArc(center: c, radius: outer, startAngle: a0, endAngle: a1, clockwise: sweep < 0)
        }
        p.closeSubpath()
        return p
    }

    /// The d-pad body: a plus whose horizontal arm is `armRatio × height` tall and vertical arm `armRatio × width`
    /// wide, reaching the frame's edges. The eight outer corners are rounded; the four inner ones are sharp.
    static func cross(armRatio: Double, cornerRadius: CGFloat, in rect: CGRect) -> CGPath {
        let aw = rect.width * CGFloat(armRatio), ah = rect.height * CGFloat(armRatio)
        let l = rect.midX - aw / 2, r = rect.midX + aw / 2, t = rect.midY - ah / 2, b = rect.midY + ah / 2
        let (x0, y0, x1, y1) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        let pts = [
            CGPoint(x: l, y: y0), CGPoint(x: r, y: y0), CGPoint(x: r, y: t), CGPoint(x: x1, y: t),
            CGPoint(x: x1, y: b), CGPoint(x: r, y: b), CGPoint(x: r, y: y1), CGPoint(x: l, y: y1),
            CGPoint(x: l, y: b), CGPoint(x: x0, y: b), CGPoint(x: x0, y: t), CGPoint(x: l, y: t),
        ]
        let inner: Set<Int> = [2, 5, 8, 11]
        return roundedPolygon(pts, radius: cornerRadius) { !inner.contains($0) }
    }

    /// The bean (Provenance's and iCube's kidney button), long axis horizontal. The top edge dips toward the
    /// middle by `0.3 × bulge` of the height; the bottom edge is convex. In the unit box:
    /// `M0 .5 C0 .05 .3 0 .5 D C.7 0 1 .05 1 .5 C1 .95 .75 1 .5 1 C.25 1 0 .95 0 .5Z` with `D = .3 × bulge`.
    static func kidney(bulge: Double, in rect: CGRect) -> CGPath {
        let dip = 0.3 * bulge
        let d = "M0 0.5 C0 0.05 0.3 0 0.5 \(dip) C0.7 0 1 0.05 1 0.5 C1 0.95 0.75 1 0.5 1 C0.25 1 0 0.95 0 0.5 Z"
        return Skin2SVGPath.path(d, box: CGRect(x: 0, y: 0, width: 1, height: 1), in: rect)
    }

    /// iCube's bar: the top edge is inset by `taper × width` on each side.
    static func trapezoid(taper: Double, in rect: CGRect) -> CGPath {
        let inset = rect.width * CGFloat(taper)
        let p = CGMutablePath()
        p.addLines(between: [
            CGPoint(x: rect.minX + inset, y: rect.minY), CGPoint(x: rect.maxX - inset, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY),
        ])
        p.closeSubpath()
        return p
    }
}
