import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SkinKit2Core

/// How to draw a resolved skin.
public struct Skin2RenderOptions {
    /// Control states by control id (6.4). Controls not listed draw at rest.
    public var states: [String: Skin2ControlState]
    /// Draw screen nodes as a dark placeholder (reference images, editors). Apps leave it off and put the video
    /// in the screen frame.
    public var screenPlaceholders: Bool
    /// Outline every control's hit frame (debugging).
    public var showHitFrames: Bool
    /// Pixels per point for effects drawn into a vector target.
    public var effectScale: CGFloat?
    /// The bytes of a file the skin references: an image `src` (a path under `assets/`) or a font as
    /// `fonts/<family>`. Nil or a missing file draws nothing for that image and the default face for that font.
    public var asset: ((String) -> Data?)?

    public init(states: [String: Skin2ControlState] = [:], screenPlaceholders: Bool = false, showHitFrames: Bool = false,
                asset: ((String) -> Data?)? = nil) {
        self.states = states; self.screenPlaceholders = screenPlaceholders; self.showHitFrames = showHitFrames; self.asset = asset
    }
}

/// The Core Graphics drawer for a resolved tree (sections 5 and 6.4).
///
/// Order per node: its copies (`repeat`), then, for each copy, the control state (scale about the frame's centre,
/// opacity, patches on descendants), shadows (listed order, each under the content), the content (fills,
/// material, strokes; text; image; children), blur, then blend and opacity when it is composited onto its parent.
/// Shadows, inner shadows and blur rasterise the node to a bitmap at the context's pixel scale and use a Gaussian
/// with σ = radius / 2 (Accelerate), so the kernel is known to the TypeScript port. Group opacity and blend use a
/// transparency layer.
public enum Skin2Renderer {
    /// Draws `resolution` into `ctx`, whose user space is canvas points with a top-left origin and y down.
    public static func draw(_ resolution: Skin2Resolution, in ctx: CGContext, options: Skin2RenderOptions = .init()) {
        var painter = Painter(resolution: resolution, options: options, vectorContext: options.effectScale == nil ? nil : ctx)
        ctx.saveGState()
        Skin2Bitmap.configure(ctx)
        painter.draw(resolution.root, in: ctx, control: nil)
        if options.showHitFrames {
            ctx.setStrokeColor(Skin2Color2CG.cg(Skin2Color(red: 1, green: 0.2, blue: 0.2)))
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            for c in resolution.controls { if let h = c.hitFrame { ctx.stroke(h.cg.insetBy(dx: 0.5, dy: 0.5)) } }
        }
        ctx.restoreGState()
    }

    /// The canvas as an image at `scale` pixels per point (RGBA8 premultiplied, sRGB, transparent background).
    public static func image(_ resolution: Skin2Resolution, scale: CGFloat = 2, options: Skin2RenderOptions = .init()) -> CGImage? {
        let size = resolution.environment.size
        let w = Int((CGFloat(size.width) * scale).rounded()), h = Int((CGFloat(size.height) * scale).rounded())
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                space: Skin2Color2CG.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(resolution, in: ctx, options: options)
        return ctx.makeImage()
    }
}

extension Skin2Rect {
    var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

extension Skin2Transform {
    var cg: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

/// The control a node is drawn inside, with its active state.
private struct ControlContext {
    var state: Skin2ControlState
    /// Patches by target id, in apply order; `copy` nil means every copy.
    var patches: [String: [(copy: Int?, patch: Skin2Patch)]]
    /// Knob displacement in canvas points.
    var knob: CGSize
}

private struct Painter {
    let resolution: Skin2Resolution
    let options: Skin2RenderOptions
    let unit: Double
    let vectorContext: CGContext?
    var images: [String: CGImage?] = [:]
    var fonts: [String: CGFont?] = [:]

    init(resolution: Skin2Resolution, options: Skin2RenderOptions, vectorContext: CGContext?) {
        self.resolution = resolution
        self.options = options
        self.vectorContext = vectorContext
        unit = resolution.unit
    }

    // MARK: Tree

    mutating func draw(_ r: Skin2ResolvedNode, in ctx: CGContext, control: ControlContext?) {
        if r.node.role == .highlight, !(control?.state.isPressed ?? false) { return }
        let transforms = r.copies.isEmpty ? [CGAffineTransform.identity] : r.copies.map(\.cg)
        for (i, t) in transforms.enumerated() {
            var n = r.node
            if let id = n.id, let list = control?.patches[id] {
                for (copy, patch) in list where copy == nil || copy == i { n = patch.apply(to: n) }
            }
            guard isVisible(n) else { continue }
            ctx.saveGState()
            ctx.concatenate(t)
            drawSingle(r, node: n, in: ctx, control: control)
            ctx.restoreGState()
        }
    }

    func isVisible(_ n: Skin2Node) -> Bool {
        switch n.visible {
        case nil: return true
        case .always(let b)?: return b
        case .when(let c)?: return matches(c)
        }
    }

    /// The resolver's condition test (4.6), for `visible` set by a state patch.
    func matches(_ c: Skin2Condition) -> Bool {
        let e = resolution.environment
        if let v = c.orientation, v != e.orientation { return false }
        if let v = c.device, v != e.device { return false }
        if let v = c.displayType, v != e.displayType { return false }
        if let v = c.flag, !e.flags.contains(v) { return false }
        if let v = c.minWidth, e.size.width < v { return false }
        if let v = c.minHeight, e.size.height < v { return false }
        if let v = c.theme, v != resolution.theme { return false }
        if let v = c.variant, v != resolution.variant { return false }
        return true
    }

    mutating func drawSingle(_ r: Skin2ResolvedNode, node n: Skin2Node, in ctx: CGContext, control outer: ControlContext?) {
        let frame = r.frame.cg
        var control = outer
        // The resolved opacity carries the player's edit; a patched opacity replaces the node's own part.
        let editFactor = (r.node.opacity ?? 1) > 0 ? r.opacity / (r.node.opacity ?? 1) : 1
        var opacity = (n.opacity ?? 1) * editFactor

        if n.type == .control {
            let state = n.id.flatMap { options.states[$0] } ?? Skin2ControlState()
            var patches: [String: [(copy: Int?, patch: Skin2Patch)]] = [:]
            var scale = 1.0
            for name in state.stateNames {
                guard let s = n.states[name] else { continue }
                if let v = s.scale { scale *= v }
                if let v = s.opacity { opacity *= v }
                for p in s.patch {
                    guard let target = p.targetID else { continue }
                    patches[target.id, default: []].append((target.copy, p))
                }
            }
            if state.easingOut, !state.isPressed, let v = n.states["pressed"]?.scale { scale *= v }
            scale = 1 + (scale - 1) * min(max(state.scaleProgress, 0), 1)
            if scale != 1 {
                ctx.translateBy(x: frame.midX, y: frame.midY)
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -frame.midX, y: -frame.midY)
            }
            let travel = r.travel ?? 0
            control = ControlContext(state: state, patches: patches,
                                     knob: CGSize(width: state.stick.x * travel, height: state.stick.y * travel))
        }
        if n.role == .knob, let k = control?.knob, k != .zero {
            ctx.translateBy(x: k.width, y: k.height)
        }

        let shadows = n.effects.filter { $0.type == .shadow && !$0.inner }
        let innerShadows = n.effects.filter { $0.type == .shadow && $0.inner }
        let blurs = n.effects.filter { $0.type == .blur }
        let blend = n.effects.last { $0.type == .blend }?.mode.map(Self.blendMode) ?? .normal

        // PDF shadings do not reliably preserve alpha and Quartz cannot emit conic shadings.
        let rasterPaint = ctx === vectorContext && (n.material != nil || n.type == .image || n.fills.contains {
            $0.type == .angular || $0.type == .image || $0.stops.contains { $0.color.alpha * ($0.opacity ?? 1) < 1 }
                || (!$0.stops.isEmpty && ($0.opacity ?? 1) < 1)
        })
        if shadows.isEmpty && innerShadows.isEmpty && blurs.isEmpty && !rasterPaint {
            let layered = opacity < 1 || blend != .normal
            if layered {
                ctx.setAlpha(CGFloat(opacity))
                ctx.setBlendMode(blend)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            }
            drawContent(r, node: n, in: ctx, control: control)
            if layered { ctx.endTransparencyLayer() }
            return
        }

        // Rasterised path: shadows, inner shadows and blur.
        let pad = effectPadding(n.effects)
        var region = visualBounds(r, node: n).insetBy(dx: -pad, dy: -pad)
        let clip = ctx.boundingBoxOfClipPath
        if !clip.isNull, !clip.isInfinite { region = region.intersection(clip.insetBy(dx: -pad, dy: -pad)) }
        guard !region.isNull, !region.isEmpty, let content = Skin2Bitmap(region: region, scale: options.effectScale ?? ctx.pixelScale) else { return }
        drawContent(r, node: n, in: content.context, control: control)

        // A shape's shadow is cast by the union of its fills (5.3); anything else by its whole content.
        var silhouette = content
        if n.type == .shape, !n.fills.isEmpty, let shape = n.shape, let fillsOnly = Skin2Bitmap(region: region, scale: options.effectScale ?? ctx.pixelScale) {
            let path = Skin2Shapes.path(for: shape, in: frame, unit: unit)
            fillShape(path, fills: n.fills, material: nil, frame: frame, in: fillsOnly.context)
            silhouette = fillsOnly
        }
        let alpha = silhouette.alpha()

        // PDF masks and the bitmap renderer composite differently. Flatten the effect itself into a
        // single image before placing it on the vector page.
        if ctx === vectorContext, let scale = options.effectScale,
           let layer = Skin2Bitmap(region: region, scale: scale) {
            compositeEffect(content, alpha: alpha, shadows: shadows, innerShadows: innerShadows,
                            blurs: blurs, frame: frame, in: layer.context)
            ctx.saveGState()
            ctx.setAlpha(CGFloat(opacity))
            ctx.setBlendMode(blend)
            if let image = layer.image() { ctx.drawTopDown(image, in: layer.region) }
            ctx.restoreGState()
        } else {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(opacity))
            ctx.setBlendMode(blend)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            compositeEffect(content, alpha: alpha, shadows: shadows, innerShadows: innerShadows,
                            blurs: blurs, frame: frame, in: ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    func compositeEffect(_ content: Skin2Bitmap, alpha: Skin2Mask?, shadows: [Skin2Effect],
                         innerShadows: [Skin2Effect], blurs: [Skin2Effect], frame: CGRect, in ctx: CGContext) {
        if let alpha {
            for shadow in shadows { drawShadow(shadow, mask: alpha, in: ctx) }
        }
        if let sigma = blurs.compactMap({ $0.radius?.resolve(along: Double(min(frame.width, frame.height)), unit: unit) }).max(), sigma > 0 {
            content.blur(sigma: CGFloat(sigma) / 2)
        }
        if let image = content.image() { ctx.drawTopDown(image, in: content.region) }
        if let alpha {
            for shadow in innerShadows { drawInnerShadow(shadow, mask: alpha, in: ctx) }
        }
    }

    mutating func drawContent(_ r: Skin2ResolvedNode, node n: Skin2Node, in ctx: CGContext, control: ControlContext?) {
        let frame = r.frame.cg
        switch n.type {
        case .shape:
            if let shape = n.shape { drawShape(shape, node: n, frame: frame, in: ctx) }
        case .text:
            drawText(n, frame: frame, in: ctx)
        case .image:
            if let src = n.src, let image = image(src) {
                ctx.saveGState()
                ctx.clip(to: frame)
                drawImage(image, mode: n.mode ?? .fit, scale: 1, tint: n.tint, in: frame, ctx: ctx)
                ctx.restoreGState()
            }
        case .screen:
            if options.screenPlaceholders { drawScreen(frame, in: ctx) }
        case .group, .control:
            break
        }
        for child in r.children { draw(child, in: ctx, control: control) }
    }

    // MARK: Shapes, paint, strokes (5.1, 5.2, 5.4)

    mutating func drawShape(_ shape: Skin2Shape, node n: Skin2Node, frame: CGRect, in ctx: CGContext) {
        let path = Skin2Shapes.path(for: shape, in: frame, unit: unit)
        if !Skin2Shapes.isOpen(shape) { fillShape(path, fills: n.fills, material: n.material, frame: frame, in: ctx) }
        for stroke in n.strokes { drawStroke(stroke, path: path, open: Skin2Shapes.isOpen(shape), frame: frame, in: ctx) }
    }

    mutating func fillShape(_ path: CGPath, fills: [Skin2Paint], material: Skin2Material?, frame: CGRect, in ctx: CGContext) {
        for paint in fills { fill(path, paint: paint, frame: frame, in: ctx) }
        if let material { drawMaterial(material, path: path, frame: frame, in: ctx) }
    }

    mutating func fill(_ path: CGPath, paint: Skin2Paint, frame: CGRect, in ctx: CGContext) {
        let opacity = paint.opacity ?? 1
        ctx.saveGState()
        defer { ctx.restoreGState() }
        func at(_ p: Skin2UnitPoint?, _ fallback: CGPoint) -> CGPoint {
            guard let p else { return fallback }
            return CGPoint(x: frame.minX + CGFloat(p.x) * frame.width, y: frame.minY + CGFloat(p.y) * frame.height)
        }
        switch paint.type {
        case .solid:
            ctx.addPath(path)
            ctx.setFillColor(Skin2Color2CG.cg(paint.color ?? Skin2Color(red: 0, green: 0, blue: 0), opacity: opacity))
            ctx.fillPath()
        case .linear:
            guard let g = Skin2Color2CG.gradient(paint.stops, opacity: opacity) else { return }
            ctx.addPath(path); ctx.clip()
            ctx.drawLinearGradient(g, start: at(paint.start, CGPoint(x: frame.midX, y: frame.minY)),
                                   end: at(paint.end, CGPoint(x: frame.midX, y: frame.maxY)),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .radial:
            guard let g = Skin2Color2CG.gradient(paint.stops, opacity: opacity) else { return }
            ctx.addPath(path); ctx.clip()
            let c = at(paint.center, CGPoint(x: frame.midX, y: frame.midY))
            let radius = CGFloat(paint.radius ?? 0.5) * max(frame.width, frame.height)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: radius,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case .angular:
            guard let g = Skin2Color2CG.gradient(paint.stops, opacity: opacity) else { return }
            ctx.addPath(path); ctx.clip()
            // 0° along +x; the angle grows toward +y, which is clockwise on the y-down canvas.
            CGContextDrawConicGradient(ctx, g, at(paint.center, CGPoint(x: frame.midX, y: frame.midY)),
                                       CGFloat((paint.startAngle ?? 0) * .pi / 180))
        case .image:
            guard let src = paint.src, let image = image(src) else { return }
            ctx.addPath(path); ctx.clip()
            ctx.setAlpha(CGFloat(opacity))
            drawImage(image, mode: paint.mode ?? .tile, scale: paint.scale ?? 1, tint: nil, in: frame, ctx: ctx)
        }
    }

    func drawStroke(_ s: Skin2Stroke, path: CGPath, open: Bool, frame: CGRect, in ctx: CGContext) {
        let short = Double(min(frame.width, frame.height))
        let width = CGFloat(s.width.resolve(along: short, unit: unit))
        guard width > 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        let align: Skin2StrokeAlign = open ? .center : s.align
        switch align {
        case .center:
            ctx.setLineWidth(width)
        case .inner:
            ctx.addPath(path); ctx.clip()
            ctx.setLineWidth(width * 2)
        case .outer:
            let outside = CGMutablePath()
            outside.addRect(path.boundingBoxOfPath.insetBy(dx: -width * 2 - 1, dy: -width * 2 - 1))
            outside.addPath(path)
            ctx.addPath(outside); ctx.clip(using: .evenOdd)
            ctx.setLineWidth(width * 2)
        }
        let dash = s.dash.map { CGFloat($0.resolve(along: short, unit: unit)) }
        if !dash.isEmpty, dash.contains(where: { $0 > 0 }) { ctx.setLineDash(phase: 0, lengths: dash) }
        ctx.setLineCap(Self.cap(s.cap))
        ctx.setLineJoin(Self.join(s.join))
        ctx.setStrokeColor(Skin2Color2CG.cg(s.color, opacity: s.opacity ?? 1))
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// Materials as recipes of the primitives (5.4). `params` are not read yet.
    mutating func drawMaterial(_ m: Skin2Material, path: CGPath, frame: CGRect, in ctx: CGContext) {
        let i = m.intensity
        guard i > 0 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.addPath(path); ctx.clip()
        let white = Skin2Color(red: 1, green: 1, blue: 1), black = Skin2Color(red: 0, green: 0, blue: 0)
        func stops(_ list: [(Skin2Color, Double, Double)]) -> CGGradient? {
            var components: [CGFloat] = [], locations: [CGFloat] = []
            for (c, a, at) in list { components += [CGFloat(c.red), CGFloat(c.green), CGFloat(c.blue), CGFloat(a)]; locations.append(CGFloat(at)) }
            return CGGradient(colorSpace: Skin2Color2CG.sRGB, colorComponents: components, locations: locations, count: list.count)
        }
        switch m.name {
        case .gloss:
            // A top-half white-to-clear sheen plus a dark band along the bottom edge (the inner shadow).
            if let g = stops([(white, 0.45 * i, 0), (white, 0, 1)]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: frame.midX, y: frame.minY), end: CGPoint(x: frame.midX, y: frame.midY), options: [])
            }
            if let g = stops([(black, 0, 0), (black, 0.3 * i, 1)]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: frame.midX, y: frame.maxY - frame.height * 0.2),
                                       end: CGPoint(x: frame.midX, y: frame.maxY), options: [])
            }
        case .brushedMetal:
            if let g = stops([(white, 0.35 * i, 0), (black, 0.25 * i, 0.25), (white, 0.35 * i, 0.5), (black, 0.25 * i, 0.75), (white, 0.35 * i, 1)]) {
                CGContextDrawConicGradient(ctx, g, CGPoint(x: frame.midX, y: frame.midY), 0)
            }
            drawNoise(alpha: 0.15 * i, frame: frame, in: ctx)
        case .plasticGrain:
            drawNoise(alpha: 0.08 * i, frame: frame, in: ctx)
        case .crt:
            ctx.setFillColor(Skin2Color2CG.cg(black, opacity: 0.35 * i))
            let pitch = CGFloat(3 * unit), line = CGFloat(unit)
            var y = frame.minY
            while y < frame.maxY { ctx.fill(CGRect(x: frame.minX, y: y, width: frame.width, height: line)); y += pitch }
            if let g = stops([(black, 0, 0.5), (black, 0.5 * i, 1)]) {
                let c = CGPoint(x: frame.midX, y: frame.midY)
                ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: 0.75 * max(frame.width, frame.height),
                                       options: [.drawsAfterEndLocation])
            }
        }
    }

    /// A tiled 64 × 64 grey noise image drawn at 32 × 32 points (deterministic: xorshift32 from a fixed seed).
    func drawNoise(alpha: Double, frame: CGRect, in ctx: CGContext) {
        guard let tile = Self.noise else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(alpha))
        let side: CGFloat = 32
        var y = (frame.minY / side).rounded(.down) * side
        while y < frame.maxY {
            var x = (frame.minX / side).rounded(.down) * side
            while x < frame.maxX { ctx.drawTopDown(tile, in: CGRect(x: x, y: y, width: side, height: side)); x += side }
            y += side
        }
        ctx.restoreGState()
    }

    static let noise: CGImage? = {
        var state: UInt32 = 0x9E37_79B9
        var bytes = [UInt8](repeating: 0, count: 64 * 64 * 4)
        for i in 0..<(64 * 64) {
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            let v = UInt8(truncatingIfNeeded: state >> 24)
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 256, space: Skin2Color2CG.sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }()

    // MARK: Effects (5.3)

    func effectPadding(_ effects: [Skin2Effect]) -> CGFloat {
        var pad: CGFloat = 2
        for e in effects where e.type == .shadow || e.type == .blur {
            let r = CGFloat(e.radius?.resolve(along: 0, unit: unit) ?? 0)
            let spread = CGFloat(e.spread?.resolve(along: 0, unit: unit) ?? 0)
            let offset = e.offset.count == 2 ? CGFloat(max(abs(e.offset[0].resolve(along: 0, unit: unit)), abs(e.offset[1].resolve(along: 0, unit: unit)))) : 0
            pad = max(pad, 1.5 * r + abs(spread) + offset + 2)
        }
        return pad
    }

    func shadowGeometry(_ s: Skin2Effect) -> (sigma: CGFloat, spread: CGFloat, offset: CGSize) {
        let r = CGFloat(s.radius?.resolve(along: 0, unit: unit) ?? 0)
        let spread = CGFloat(s.spread?.resolve(along: 0, unit: unit) ?? 0)
        var offset = CGSize.zero
        if s.offset.count == 2 {
            offset = CGSize(width: s.offset[0].resolve(along: 0, unit: unit), height: s.offset[1].resolve(along: 0, unit: unit))
        }
        return (r / 2, spread, offset)
    }

    func copy(_ m: Skin2Mask) -> Skin2Mask {
        let c = Skin2Mask(width: m.width, height: m.height, region: m.region, scale: m.scale)
        c.bytes = m.bytes
        return c
    }

    /// One drop shadow: the silhouette, spread, blurred (σ = radius / 2), moved by the offset and filled with the
    /// shadow colour.
    func drawShadow(_ s: Skin2Effect, mask silhouette: Skin2Mask, in ctx: CGContext) {
        let g = shadowGeometry(s)
        let m = copy(silhouette)
        m.spread(g.spread)
        m.blur(sigma: g.sigma)
        guard let image = m.image() else { return }
        ctx.saveGState()
        ctx.translateBy(x: g.offset.width, y: g.offset.height)
        ctx.clipTopDown(to: m.region, mask: image)
        ctx.setFillColor(Skin2Color2CG.cg(s.color ?? Skin2Color(red: 0, green: 0, blue: 0), opacity: s.opacity ?? 1))
        ctx.fill(m.region)
        ctx.restoreGState()
    }

    /// An inner shadow: the inverted silhouette, spread inward, blurred and moved, drawn over the content and
    /// clipped to the silhouette.
    func drawInnerShadow(_ s: Skin2Effect, mask silhouette: Skin2Mask, in ctx: CGContext) {
        let g = shadowGeometry(s)
        let m = copy(silhouette)
        m.invert()
        m.spread(g.spread)
        m.blur(sigma: g.sigma)
        guard let image = m.image(), let clip = silhouette.image() else { return }
        ctx.saveGState()
        ctx.clipTopDown(to: silhouette.region, mask: clip)
        ctx.translateBy(x: g.offset.width, y: g.offset.height)
        ctx.clipTopDown(to: m.region, mask: image)
        ctx.setFillColor(Skin2Color2CG.cg(s.color ?? Skin2Color(red: 0, green: 0, blue: 0), opacity: s.opacity ?? 1))
        ctx.fill(m.region.insetBy(dx: -abs(g.offset.width) - 1, dy: -abs(g.offset.height) - 1))
        ctx.restoreGState()
    }

    /// Where a node can draw, in its parent's space: its frame, its strokes, its text, and its children's
    /// bounds (through their copies and a thumbstick's travel). Effects add their own padding on top.
    mutating func visualBounds(_ r: Skin2ResolvedNode, node n: Skin2Node) -> CGRect {
        var b = r.frame.cg
        let short = Double(min(b.width, b.height))
        let stroke = n.strokes.map { CGFloat($0.width.resolve(along: short, unit: unit)) }.max() ?? 0
        b = b.insetBy(dx: -stroke - 1, dy: -stroke - 1)
        if n.type == .text, let text = n.text {
            b = b.union(textPath(text, node: n, frame: r.frame.cg).boundingBoxOfPath.insetBy(dx: -1, dy: -1))
        }
        let travel = CGFloat(r.travel ?? 0)
        for child in r.children {
            var cb = visualBounds(child, node: child.node).insetBy(dx: -effectPadding(child.node.effects), dy: -effectPadding(child.node.effects))
            if child.node.role == .knob { cb = cb.insetBy(dx: -travel, dy: -travel) }
            if !child.copies.isEmpty { cb = child.copies.reduce(CGRect.null) { $0.union(cb.applying($1.cg)) } }
            b = b.union(cb)
        }
        return b
    }

    static func blendMode(_ m: Skin2BlendMode) -> CGBlendMode {
        switch m {
        case .normal: return .normal
        case .multiply: return .multiply
        case .screen: return .screen
        case .overlay: return .overlay
        case .softLight: return .softLight
        case .plus: return .plusLighter
        }
    }

    static func cap(_ c: Skin2LineCap) -> CGLineCap {
        switch c {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }

    static func join(_ j: Skin2LineJoin) -> CGLineJoin {
        switch j {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }

    // MARK: Text

    mutating func textPath(_ text: String, node n: Skin2Node, frame: CGRect) -> CGPath {
        let weight = n.font?.weight ?? .regular
        var face: CGFont?
        if let family = n.font?.family { face = font(family) }
        guard let font = face ?? Skin2Text.defaultFont(weight) else { return CGMutablePath() }
        let size = CGFloat(n.font?.size.resolve(along: Double(frame.height), unit: unit) ?? 12 * unit)
        return Skin2Text.path(text, font: font, size: size, align: n.align ?? .center, fit: n.fit ?? false, in: frame)
    }

    mutating func drawText(_ n: Skin2Node, frame: CGRect, in ctx: CGContext) {
        guard let text = n.text, !text.isEmpty else { return }
        let path = textPath(text, node: n, frame: frame)
        ctx.addPath(path)
        ctx.setFillColor(Skin2Color2CG.cg(n.color ?? Skin2Color(red: 1, green: 1, blue: 1)))
        ctx.fillPath()
    }

    mutating func font(_ family: String) -> CGFont? {
        if let cached = fonts[family] { return cached }
        let f = options.asset?("fonts/\(family)").flatMap(Skin2Text.font(data:))
        fonts[family] = f
        return f
    }

    // MARK: Images and screens

    mutating func image(_ src: String) -> CGImage? {
        if let cached = images[src] { return cached }
        var out: CGImage?
        if let data = options.asset?(src) {
            if let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 {
                out = CGImageSourceCreateImageAtIndex(source, 0, nil)
            }
            if out == nil { out = Self.rasterizePDF(data) }
        }
        images[src] = out
        return out
    }

    /// The first page of a PDF at 3 pixels per PDF point.
    static func rasterizePDF(_ data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 3
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0, w <= 8192, h <= 8192, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                                                     space: Skin2Color2CG.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    /// `fit`/`fill` keep the aspect ratio and centre; `stretch` fills the frame; `tile` repeats the image at its
    /// pixel size × `scale` in points from the frame's top-left. A tint draws the image as a template.
    func drawImage(_ image: CGImage, mode: Skin2ImageMode, scale: Double, tint: Skin2Color?, in frame: CGRect, ctx: CGContext) {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0 else { return }
        var rects: [CGRect] = []
        switch mode {
        case .stretch:
            rects = [frame]
        case .fit, .fill:
            let s = mode == .fit ? min(frame.width / iw, frame.height / ih) : max(frame.width / iw, frame.height / ih)
            let size = CGSize(width: iw * s, height: ih * s)
            rects = [CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)]
        case .tile:
            let tw = iw * CGFloat(scale), th = ih * CGFloat(scale)
            var y = frame.minY
            while y < frame.maxY, rects.count < 4096 {
                var x = frame.minX
                while x < frame.maxX, rects.count < 4096 { rects.append(CGRect(x: x, y: y, width: tw, height: th)); x += tw }
                y += th
            }
        }
        for rect in rects {
            if let tint {
                ctx.saveGState()
                ctx.clipTopDown(to: rect, mask: image)
                ctx.setFillColor(Skin2Color2CG.cg(tint))
                ctx.fill(rect)
                ctx.restoreGState()
            } else {
                ctx.drawTopDown(image, in: rect)
            }
        }
    }

    func drawScreen(_ frame: CGRect, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(Skin2Color2CG.cg(Skin2Color(hex: "#101018")!))
        ctx.fill(frame)
        ctx.setStrokeColor(Skin2Color2CG.cg(Skin2Color(hex: "#404050")!))
        ctx.setLineWidth(1)
        ctx.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }
}
