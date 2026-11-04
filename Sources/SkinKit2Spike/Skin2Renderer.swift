// SkinKit2Spike: THROWAWAY code for the format 2.0 spike (SkinKit#24). Not shipped.
// Core Graphics renderer for a resolved tree. Top-left origin; the caller flips the context if needed.

import CoreGraphics
import CoreText
import Foundation

public struct Skin2RenderOptions {
    public var showHitFrames = false
    public var showScreenPlaceholder = true
    public init() {}
}

public enum Skin2Renderer {
    public static func draw(_ root: Skin2ResolvedNode, in ctx: CGContext, options: Skin2RenderOptions = .init()) {
        draw(node: root, ctx: ctx, options: options)
        if options.showHitFrames {
            ctx.setStrokeColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 0.8))
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            for c in root.controls() { ctx.stroke(c.hitFrame) }
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }

    static func draw(node r: Skin2ResolvedNode, ctx: CGContext, options: Skin2RenderOptions) {
        let n = r.node
        ctx.saveGState()
        if let o = n.opacity { ctx.setAlpha(CGFloat(o)) }
        // A node-level shadow (the d-pad's) applies to the node's whole content via a transparency layer.
        let nodeShadow = n.effects?.first { $0.type == "shadow" && n.type != .shape }
        if let s = nodeShadow { apply(shadow: s, ctx: ctx); ctx.beginTransparencyLayer(auxiliaryInfo: nil) }

        let transforms = [CGAffineTransform.identity] + r.copies
        for t in transforms {
            ctx.saveGState()
            ctx.concatenate(t)
            switch n.type {
            case .shape: drawShape(r, ctx: ctx)
            case .text: drawText(r, ctx: ctx)
            case .screen: if options.showScreenPlaceholder { drawScreen(r, ctx: ctx) }
            case .group, .control, .image: break
            }
            for child in r.children { draw(node: child, ctx: ctx, options: options) }
            ctx.restoreGState()
        }
        if nodeShadow != nil { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    // MARK: Shapes

    static func drawShape(_ r: Skin2ResolvedNode, ctx: CGContext) {
        guard let shape = r.node.shape else { return }
        let path = Skin2Shapes.path(for: shape, in: r.frame)
        // Shadows are drawn once from the first fill so stacked fills don't stack shadows.
        let shadows = (r.node.effects ?? []).filter { $0.type == "shadow" }
        var first = true
        for paint in r.node.fills ?? [] {
            ctx.saveGState()
            if first { for s in shadows { apply(shadow: s, ctx: ctx) }; if shadows.count > 1 { drawExtraShadows(shadows.dropFirst(), path: path, ctx: ctx) } }
            fill(path: path, paint: paint, bounds: r.frame, ctx: ctx)
            ctx.restoreGState()
            first = false
        }
        for stroke in r.node.strokes ?? [] {
            ctx.saveGState()
            ctx.addPath(path)
            let width = CGFloat(stroke.width)
            if stroke.align == "inner" { ctx.clip(); ctx.addPath(path); ctx.setLineWidth(width * 2) } else { ctx.setLineWidth(width) }
            ctx.setStrokeColor(cg(stroke.color.withOpacity(stroke.opacity)))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Core Graphics has one shadow per draw; the second shadow (the glow) is a second pass under the fill.
    static func drawExtraShadows(_ shadows: ArraySlice<Skin2Effect>, path: CGPath, ctx: CGContext) {
        for s in shadows {
            ctx.saveGState()
            apply(shadow: s, ctx: ctx)
            ctx.addPath(path)
            ctx.setFillColor(cg(s.color ?? Skin2Color(r: 0, g: 0, b: 0, a: 1)))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    static func apply(shadow s: Skin2Effect, ctx: CGContext) {
        let color = (s.color ?? Skin2Color(r: 0, g: 0, b: 0, a: 1)).withOpacity(s.opacity)
        let off = s.offset ?? [0, 0]
        ctx.setShadow(offset: CGSize(width: off[0], height: off[1]), blur: CGFloat(s.radius ?? 0) * 2, color: cg(color))
    }

    static func fill(path: CGPath, paint: Skin2Paint, bounds: CGRect, ctx: CGContext) {
        switch paint.type {
        case "solid":
            ctx.addPath(path)
            ctx.setFillColor(cg((paint.color ?? Skin2Color(r: 0, g: 0, b: 0, a: 1)).withOpacity(paint.opacity)))
            ctx.fillPath()
        case "linear", "radial":
            guard let stops = paint.stops, let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: stops.map { cg($0.color) } as CFArray,
                locations: stops.map { CGFloat($0.at) }) else { return }
            ctx.addPath(path)
            ctx.clip()
            if paint.type == "linear" {
                let s = paint.start ?? [0.5, 0], e = paint.end ?? [0.5, 1]
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: bounds.minX + s[0] * bounds.width, y: bounds.minY + s[1] * bounds.height),
                                       end: CGPoint(x: bounds.minX + e[0] * bounds.width, y: bounds.minY + e[1] * bounds.height),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            } else {
                let c = paint.center ?? [0.5, 0.5]
                let center = CGPoint(x: bounds.minX + c[0] * bounds.width, y: bounds.minY + c[1] * bounds.height)
                let radius = CGFloat(paint.radius ?? 0.5) * max(bounds.width, bounds.height)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius,
                                       options: [.drawsAfterEndLocation])
            }
        default:
            break
        }
    }

    // MARK: Text

    static func drawText(_ r: Skin2ResolvedNode, ctx: CGContext) {
        guard let text = r.node.text else { return }
        let size = CGFloat(r.node.font?.size ?? 12) * (r.frame.height / 44).clamped(0.8, 1.35)
        let weight = r.node.font?.weight == "bold" ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(weight as CFString, size, nil)
        let color = cg(r.node.color ?? Skin2Color(r: 1, g: 1, b: 1, a: 1))
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary))
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        ctx.saveGState()
        ctx.textMatrix = .identity
        // Flip locally: CoreText draws with a bottom-left origin.
        ctx.translateBy(x: r.frame.midX - bounds.width / 2, y: r.frame.midY + bounds.height / 2 - bounds.minY - size * 0.1)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func drawScreen(_ r: Skin2ResolvedNode, ctx: CGContext) {
        ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1))
        ctx.fill(r.frame)
        ctx.setStrokeColor(CGColor(red: 0.4, green: 0.4, blue: 0.5, alpha: 1))
        ctx.setLineWidth(1)
        ctx.stroke(r.frame.insetBy(dx: 0.5, dy: 0.5))
        ctx.move(to: CGPoint(x: r.frame.minX, y: r.frame.minY)); ctx.addLine(to: CGPoint(x: r.frame.maxX, y: r.frame.maxY))
        ctx.move(to: CGPoint(x: r.frame.maxX, y: r.frame.minY)); ctx.addLine(to: CGPoint(x: r.frame.minX, y: r.frame.maxY))
        ctx.strokePath()
    }

    static func cg(_ c: Skin2Color) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: c.a) }
}

extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

// MARK: - Parametric shapes and SVG paths

public enum Skin2Shapes {
    public static func path(for shape: Skin2Shape, in rect: CGRect) -> CGPath {
        switch shape.kind {
        case "rect":
            let r = CGFloat(shape.cornerRadius ?? 0)
            return r > 0 ? CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil) : CGPath(rect: rect, transform: nil)
        case "ellipse", "circle":
            return CGPath(ellipseIn: rect, transform: nil)
        case "capsule":
            let r = min(rect.width, rect.height) / 2
            return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
        case "polygon":
            return polygon(sides: shape.sides ?? 6, rotation: shape.rotation ?? 0, in: rect)
        case "star":
            return star(points: shape.points ?? 5, innerRatio: shape.innerRatio ?? 0.5, rotation: shape.rotation ?? 0, in: rect)
        case "path":
            return svgPath(shape.d ?? "", box: shape.box ?? [0, 0, 1, 1], in: rect)
        default:
            return CGPath(rect: rect, transform: nil)
        }
    }

    static func polygon(sides: Int, rotation: Double, in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<max(3, sides) {
            let a = CGFloat(Double(i) / Double(sides) * 2 * .pi + rotation * .pi / 180)
            let pt = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    static func star(points: Int, innerRatio: Double, rotation: Double, in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * CGFloat(innerRatio)
        for i in 0..<(points * 2) {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = CGFloat(Double(i) / Double(points * 2) * 2 * .pi + rotation * .pi / 180)
            let pt = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    /// Minimal SVG path parser: M L H V C Q Z, absolute and relative. `box` is the path's own
    /// coordinate box, stretched (non-uniformly) over `rect`.
    static func svgPath(_ d: String, box: [Double], in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        let sx = rect.width / CGFloat(box[2]), sy = rect.height / CGFloat(box[3])
        func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + (x - CGFloat(box[0])) * sx, y: rect.minY + (y - CGFloat(box[1])) * sy)
        }
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter { if !current.isEmpty { tokens.append(current); current = "" }; tokens.append(String(ch)) }
            else if ch == " " || ch == "," || ch == "\n" { if !current.isEmpty { tokens.append(current); current = "" } }
            else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") { tokens.append(current); current = "-" }
            else { current.append(ch) }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var cmd = "M"
        var cur = CGPoint.zero, start = CGPoint.zero
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        while i < tokens.count {
            if tokens[i].first!.isLetter { cmd = tokens[i]; i += 1 }
            let rel = cmd == cmd.lowercased() && cmd != "Z" && cmd != "z"
            let o = rel ? cur : .zero
            switch cmd.uppercased() {
            case "M": cur = CGPoint(x: o.x + num(), y: o.y + num()); start = cur; p.move(to: map(cur.x, cur.y)); cmd = rel ? "l" : "L"
            case "L": cur = CGPoint(x: o.x + num(), y: o.y + num()); p.addLine(to: map(cur.x, cur.y))
            case "H": cur.x = o.x + num(); p.addLine(to: map(cur.x, cur.y))
            case "V": cur.y = o.y + num(); p.addLine(to: map(cur.x, cur.y))
            case "C":
                let c1 = CGPoint(x: o.x + num(), y: o.y + num()), c2 = CGPoint(x: o.x + num(), y: o.y + num())
                cur = CGPoint(x: o.x + num(), y: o.y + num())
                p.addCurve(to: map(cur.x, cur.y), control1: map(c1.x, c1.y), control2: map(c2.x, c2.y))
            case "Q":
                let c1 = CGPoint(x: o.x + num(), y: o.y + num())
                cur = CGPoint(x: o.x + num(), y: o.y + num())
                p.addQuadCurve(to: map(cur.x, cur.y), control: map(c1.x, c1.y))
            case "Z": p.closeSubpath(); cur = start
            default: i += 1
            }
        }
        return p
    }
}
