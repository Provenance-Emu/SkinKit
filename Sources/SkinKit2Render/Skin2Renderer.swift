import CoreGraphics
import CoreText
import Foundation
import ImageIO
import SkinKit2Core

/// Which nodes of a resolved skin one draw call paints, in document order. A live host draws an accessory screen's
/// picture in a layer of its own, so it draws the skin in parts: what comes before the screen under the layer,
/// what comes after it over the layer. A screen named as a boundary is in no part.
///
/// A group that holds a boundary screen is drawn in both parts with its own opacity, blend and effects applied to
/// each, which matches one draw exactly unless that group has such an effect over overlapping halves.
@frozen public enum Skin2DrawPart: Equatable, Sendable {
    case all
    /// Everything before the screen at this pointer.
    case upTo(screen: String)
    /// Everything after the first screen and before the second.
    case between(after: String, upTo: String)
    /// Everything after the screen at this pointer.
    case after(screen: String)

    var lower: String? {
        switch self {
        case .after(let p), .between(let p, _): return p
        case .all, .upTo: return nil
        }
    }

    var upper: String? {
        switch self {
        case .upTo(let p), .between(_, let p): return p
        case .all, .after: return nil
        }
    }
}

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
    /// Stills for accessory screens, by source name (`vmu.p1`). A screen whose source is missing draws nothing
    /// (or its placeholder). Live hosts draw the pictures in their own layers and leave this empty.
    public var pictures: [String: CGImage] = [:]
    /// The part of the tree to draw (default: all of it).
    public var part: Skin2DrawPart = .all

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
@frozen public enum Skin2Renderer {
    /// Draws `resolution` into `ctx`, whose user space is canvas points with a top-left origin and y down.
    public static func draw(_ resolution: Skin2Resolution, in ctx: CGContext, options: Skin2RenderOptions = .init()) {
        draw(resolution, in: ctx, options: options, replay: nil)
    }

    /// `draw`, or with `replay` the same drawing limited to what can reach the context's clip (the render cache's
    /// partial redraw). Returns how many nodes it painted.
    @discardableResult
    static func draw(_ resolution: Skin2Resolution, in ctx: CGContext, options: Skin2RenderOptions, replay: Skin2Replay?,
                     recorder: Skin2EffectRecorder? = nil) -> Int {
        var painter = Painter(resolution: resolution, options: options, vectorContext: options.effectScale == nil ? nil : ctx)
        painter.replay = replay
        painter.recorder = recorder
        ctx.saveGState()
        if let replay {
            Painter.clip(ctx, to: replay.regions, within: replay.canvas, scale: ctx.pixelScale)
            painter.replayRegions[ObjectIdentifier(ctx)] = replay.regions.map { $0.applying(ctx.ctm) }
            painter.replayBounds[ObjectIdentifier(ctx)] = replay.canvas.applying(ctx.ctm)
        }
        Skin2Bitmap.configure(ctx)
        painter.draw(resolution.root, in: ctx, control: nil)
        if options.showHitFrames, options.part.upper == nil {
            ctx.setStrokeColor(Skin2Color2CG.cg(Skin2Color(red: 1, green: 0.2, blue: 0.2)))
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            for c in resolution.controls { if let h = c.hitFrame { ctx.stroke(h.cg.insetBy(dx: 0.5, dy: 0.5)) } }
        }
        ctx.restoreGState()
        return painter.painted
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
struct ControlContext {
    var state: Skin2ControlState
    /// Patches by target id, in apply order; `copy` nil means every copy.
    var patches: [String: [(copy: Int?, patch: Skin2Patch)]]
    /// Knob displacement in canvas points.
    var knob: CGSize
    /// The control is not in the state the render cache holds, so the cache's bounds do not describe its subtree.
    var changed = false
}

/// What a control's state does to its drawing (6.4).
struct ControlPose {
    var context: ControlContext
    /// Scale about the frame's centre.
    var scale: Double
    /// Multiplies the control's opacity.
    var opacity: Double
}

/// A partial redraw: the nodes that cannot reach the clip are skipped.
struct Skin2Replay {
    /// Where each node can paint under the cached states, by pointer, in the space its `draw` is called in.
    var bounds: [String: CGRect]
    /// Controls whose state differs from the cached one.
    var changed: Set<String>
    /// The changed controls and their ancestors (pointers): their bounds are not the cached ones.
    var open: Set<String>
    /// The rectangles to repaint and the whole canvas, in the target's user space.
    var regions: [CGRect]
    var canvas: CGRect
    /// The finished effect of each rasterised node the cached image was painted from, by `Painter.effectKey`.
    var effects: [String: [EffectStep]] = [:]
}

/// One drawing call of a rasterised node's effect: a shadow or an inner shadow (a fill through a mask) or the
/// content (an image). The bitmap work is done; what is left is what Core Graphics composites.
struct EffectStep {
    var image: CGImage
    var region: CGRect
    /// Shadows: the colour and where the mask is moved to. Nil for the content.
    var color: CGColor?
    var offset = CGSize.zero
    /// Inner shadows: the silhouette they are clipped to.
    var clip: CGImage?
    var clipRegion = CGRect.zero

    var byteCount: Int { image.bytesPerRow * image.height + (clip.map { $0.bytesPerRow * $0.height } ?? 0) }

    /// Whole pixels of `image`, placed at `region`, that cover `rect`; nil when none do.
    static func crop(_ image: CGImage, at region: CGRect, to rect: CGRect) -> (image: CGImage, region: CGRect)? {
        let r = rect.intersection(region)
        guard !r.isNull, !r.isEmpty, region.width > 0, region.height > 0 else { return nil }
        let sx = CGFloat(image.width) / region.width, sy = CGFloat(image.height) / region.height
        let x0 = max(0, Int(((r.minX - region.minX) * sx).rounded(.down))), x1 = min(image.width, Int(((r.maxX - region.minX) * sx).rounded(.up)))
        let y0 = max(0, Int(((r.minY - region.minY) * sy).rounded(.down))), y1 = min(image.height, Int(((r.maxY - region.minY) * sy).rounded(.up)))
        guard x1 > x0, y1 > y0 else { return nil }
        if x0 == 0, y0 == 0, x1 == image.width, y1 == image.height { return (image, region) }
        guard let part = image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) else { return nil }
        return (part, CGRect(x: region.minX + CGFloat(x0) / sx, y: region.minY + CGFloat(y0) / sy,
                             width: CGFloat(x1 - x0) / sx, height: CGFloat(y1 - y0) / sy))
    }

    /// The step cut down to what can reach `rect` (in the space the step is drawn in), on the same pixels; nil
    /// when it draws nothing there. Core Graphics resamples the whole of an image it draws, clipped or not.
    func cropped(to rect: CGRect) -> EffectStep? {
        var out = self
        // A shadow's mask is moved by its offset before it is drawn.
        let moved = color == nil ? rect : rect.offsetBy(dx: -offset.width, dy: -offset.height)
        guard let main = Self.crop(image, at: region, to: moved) else { return nil }
        out.image = main.image
        out.region = main.region
        if let clip {
            guard let cut = Self.crop(clip, at: clipRegion, to: rect) else { return nil }
            out.clip = cut.image
            out.clipRegion = cut.region
        }
        return out
    }
}

/// Collects the effects a full draw computes, up to a budget of bytes, so partial redraws can reuse them.
final class Skin2EffectRecorder {
    var effects: [String: [EffectStep]] = [:]
    var byteCount = 0
    let budget: Int
    init(budget: Int) { self.budget = budget }

    func record(_ steps: [EffectStep], for key: String) {
        let bytes = steps.reduce(0) { $0 + $1.byteCount }
        guard byteCount + bytes <= budget else { return }
        effects[key] = steps
        byteCount += bytes
    }
}

struct Painter {
    let resolution: Skin2Resolution
    let options: Skin2RenderOptions
    let unit: Double
    let vectorContext: CGContext?
    var images: [String: CGImage?] = [:]
    var fonts: [String: CGFont?] = [:]
    /// Drawing a part: each node's place in document order, and the places of the part's boundary screens.
    var order: [String: Int] = [:]
    var lower = Int.min, upper = Int.max
    var boundaries: [String] = []
    var replay: Skin2Replay?
    /// A partial redraw: the rectangles each context is clipped to (the target, or an effect's bitmap), through
    /// that context's transform.
    var replayRegions: [ObjectIdentifier: [CGRect]] = [:]
    /// And the bounds each context's clip has in a full draw, the same way.
    var replayBounds: [ObjectIdentifier: CGRect] = [:]
    var recorder: Skin2EffectRecorder?
    /// How many controls whose state differs from the cached one the node being drawn is inside.
    var changedDepth = 0
    /// Which copy of each repeated ancestor (and of the node itself) is being drawn.
    var copyPath: [Int] = []

    /// Names one drawing of a rasterised node: its pointer and the copies it is drawn in.
    func effectKey(_ pointer: String) -> String {
        copyPath.isEmpty ? pointer : pointer + "#" + copyPath.map(String.init).joined(separator: ".")
    }
    /// Nodes painted (one per copy).
    var painted = 0

    init(resolution: Skin2Resolution, options: Skin2RenderOptions, vectorContext: CGContext?) {
        self.resolution = resolution
        self.options = options
        self.vectorContext = vectorContext
        unit = resolution.unit
        guard options.part != .all else { return }
        for (i, node) in resolution.nodes.enumerated() { order[node.pointer] = i }
        // A boundary that is not in this layout leaves that side open.
        if let p = options.part.lower, let i = order[p] { lower = i; boundaries.append(p) }
        if let p = options.part.upper, let i = order[p] { upper = i; boundaries.append(p) }
    }

    /// Whether a node is outside the part being drawn. A group that holds a boundary screen is always entered.
    func isOutsidePart(_ r: Skin2ResolvedNode) -> Bool {
        guard !boundaries.isEmpty else { return false }
        if boundaries.contains(where: { $0.hasPrefix(r.pointer + "/") }) { return false }
        guard let i = order[r.pointer] else { return false }
        return i <= lower || i >= upper
    }

    // MARK: Tree

    mutating func draw(_ r: Skin2ResolvedNode, in ctx: CGContext, control: ControlContext?) {
        if r.node.role == .highlight, !(control?.state.isPressed ?? false) { return }
        if isOutsidePart(r) { return }
        if replay != nil, cannotReach(r.pointer, in: ctx) { return }
        let transforms = r.copies.isEmpty ? [CGAffineTransform.identity] : r.copies.map(\.cg)
        for (i, t) in transforms.enumerated() {
            var n = r.node
            if let id = n.id, let list = control?.patches[id] {
                for (copy, patch) in list where copy == nil || copy == i { n = patch.apply(to: n) }
            }
            guard isVisible(n) else { continue }
            if transforms.count > 1 { copyPath.append(i) }
            ctx.saveGState()
            ctx.concatenate(t)
            drawSingle(r, node: n, in: ctx, control: control)
            ctx.restoreGState()
            if transforms.count > 1 { copyPath.removeLast() }
        }
    }

    /// A partial redraw: whether nothing this node paints can reach the rectangles being repainted. Kept out of
    /// `draw`, whose frame is paid once per tree level (see `StackDepthTests`).
    @inline(never)
    func cannotReach(_ pointer: String, in ctx: CGContext) -> Bool {
        guard let replay, changedDepth == 0, !replay.open.contains(pointer), let bounds = replay.bounds[pointer],
              let regions = replayRegions[ObjectIdentifier(ctx)] else { return false }
        let device = bounds.applying(ctx.ctm)
        return !regions.contains { $0.intersects(device) }
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
        if let v = c.has, !v.allSatisfy(e.capabilities.contains) { return false }
        return true
    }

    /// A control node's state: its patches, scale, opacity and knob displacement.
    func pose(_ r: Skin2ResolvedNode, node n: Skin2Node) -> ControlPose { pose(id: n.id, states: n.states, travel: r.travel ?? 0) }

    @inline(never)
    func pose(id: String?, states: [String: Skin2State], travel: Double) -> ControlPose {
        let state = id.flatMap { options.states[$0] } ?? Skin2ControlState()
        var patches: [String: [(copy: Int?, patch: Skin2Patch)]] = [:]
        var scale = 1.0, opacity = 1.0
        for name in state.stateNames {
            guard let s = states[name] else { continue }
            if let v = s.scale { scale *= v }
            if let v = s.opacity { opacity *= v }
            for p in s.patch {
                guard let target = p.targetID else { continue }
                patches[target.id, default: []].append((target.copy, p))
            }
        }
        if state.easingOut, !state.isPressed, let v = states["pressed"]?.scale { scale *= v }
        scale = 1 + (scale - 1) * min(max(state.scaleProgress, 0), 1)
        var context = ControlContext(state: state, patches: patches,
                                     knob: CGSize(width: state.stick.x * travel, height: state.stick.y * travel))
        if let id, replay?.changed.contains(id) == true { context.changed = true }
        return ControlPose(context: context, scale: scale, opacity: opacity)
    }

    mutating func drawSingle(_ r: Skin2ResolvedNode, node n: Skin2Node, in ctx: CGContext, control outer: ControlContext?) {
        painted += 1
        let frame = r.frame.cg
        var control = outer
        // The resolved opacity carries the player's edit; a patched opacity replaces the node's own part.
        let editFactor = (r.node.opacity ?? 1) > 0 ? r.opacity / (r.node.opacity ?? 1) : 1
        var opacity = (n.opacity ?? 1) * editFactor

        if n.type == .control {
            let pose = pose(id: n.id, states: n.states, travel: r.travel ?? 0)
            opacity *= pose.opacity
            if pose.scale != 1 {
                ctx.translateBy(x: frame.midX, y: frame.midY)
                ctx.scaleBy(x: pose.scale, y: pose.scale)
                ctx.translateBy(x: -frame.midX, y: -frame.midY)
            }
            control = pose.context
        }
        let enteredChanged = n.type == .control && control?.changed == true
        if enteredChanged { changedDepth += 1 }
        defer { if enteredChanged { changedDepth -= 1 } }
        if n.role == .knob, let k = control?.knob, k != .zero {
            ctx.translateBy(x: k.width, y: k.height)
        }

        let rasterised = n.effects.contains { $0.type == .shadow || $0.type == .blur }
        let blend = n.effects.last { $0.type == .blend }?.mode.map(Self.blendMode) ?? .normal

        // PDF shadings do not reliably preserve alpha and Quartz cannot emit conic shadings.
        let rasterPaint = ctx === vectorContext && (n.material != nil || n.type == .image || n.fills.contains {
            $0.type == .angular || $0.type == .image || $0.stops.contains { $0.color.alpha * ($0.opacity ?? 1) < 1 }
                || (!$0.stops.isEmpty && ($0.opacity ?? 1) < 1)
        })
        if rasterised || rasterPaint {
            drawRasterised(r, node: n, in: ctx, control: control, alpha: CGFloat(opacity), blend: blend)
            return
        }
        let layered = opacity < 1 || blend != .normal
        if layered, replay != nil {
            replayLayered(r, node: n, in: ctx, control: control, alpha: CGFloat(opacity), blend: blend)
            return
        }
        if layered {
            ctx.setAlpha(CGFloat(opacity))
            ctx.setBlendMode(blend)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        drawContent(r, node: n, in: ctx, control: control)
        if layered { ctx.endTransparencyLayer() }
    }

    /// The rasterised path: shadows, inner shadows and blur. Out of `drawSingle`, whose frame is paid once per
    /// tree level (see `StackDepthTests`).
    @inline(never)
    mutating func drawRasterised(_ r: Skin2ResolvedNode, node n: Skin2Node, in ctx: CGContext, control: ControlContext?,
                                 alpha opacity: CGFloat, blend: CGBlendMode) {
        if replay != nil {
            replayRasterised(r, node: n, in: ctx, control: control, alpha: opacity, blend: blend)
            return
        }
        let frame = r.frame.cg
        let shadows = n.effects.filter { $0.type == .shadow && !$0.inner }
        let innerShadows = n.effects.filter { $0.type == .shadow && $0.inner }
        let blurs = n.effects.filter { $0.type == .blur }
        let pad = effectPadding(n.effects)
        var region = visualBounds(r, node: n).insetBy(dx: -pad, dy: -pad)
        let clip = ctx.boundingBoxOfClipPath
        if !clip.isNull, !clip.isInfinite { region = region.intersection(clip.insetBy(dx: -pad, dy: -pad)) }
        guard !region.isNull, !region.isEmpty, let content = Skin2Bitmap(region: region, scale: options.effectScale ?? ctx.pixelScale) else { return }
        drawContent(r, node: n, in: content.context, control: control)

        // A shape's shadow is cast by the union of its fills (5.3); anything else by its whole content.
        var silhouette = content
        if n.type == .shape, !n.fills.isEmpty, let shape = n.shape, let fillsOnly = content.twin() {
            let path = Skin2Shapes.path(for: shape, in: frame, unit: unit)
            fillShape(path, fills: n.fills, material: nil, frame: frame, in: fillsOnly.context)
            silhouette = fillsOnly
        }
        let alpha = silhouette.alpha()

        let steps = effectSteps(content, alpha: alpha, shadows: shadows, innerShadows: innerShadows, blurs: blurs, frame: frame)
        if vectorContext == nil, let recorder { recorder.record(steps, for: effectKey(r.pointer)) }
        // PDF masks and the bitmap renderer composite differently. Flatten the effect itself into a
        // single image before placing it on the vector page.
        if ctx === vectorContext, options.effectScale != nil, let layer = content.twin() {
            run(steps, in: layer.context)
            ctx.saveGState()
            ctx.setAlpha(opacity)
            ctx.setBlendMode(blend)
            if let image = layer.image() { ctx.drawTopDown(image, in: layer.region) }
            ctx.restoreGState()
        } else {
            ctx.saveGState()
            ctx.setAlpha(opacity)
            ctx.setBlendMode(blend)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            run(steps, in: ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    // MARK: Partial redraws
    //
    // Everything a partial redraw does differently lives below, out of `draw` and `drawSingle`: those recurse once
    // per tree level, and a frame has room for every local in the function, used or not (see `StackDepthTests`).

    /// A node with an opacity or a blend mode, in a partial redraw.
    @inline(never)
    mutating func replayLayered(_ r: Skin2ResolvedNode, node n: Skin2Node, in ctx: CGContext, control: ControlContext?,
                                alpha: CGFloat, blend: CGBlendMode) {
        group(in: ctx, alpha: alpha, blend: blend) { painter, target in
            painter.drawContent(r, node: n, in: target, control: control)
        }
    }

    /// A node with a shadow or a blur, in a partial redraw. One nothing has changed in is composited from the
    /// bitmaps the cached image was painted from. Any other is rasterised as in a full draw, but only the part of
    /// its bitmap that can reach the rectangles being repainted is painted and kept.
    @inline(never)
    mutating func replayRasterised(_ r: Skin2ResolvedNode, node n: Skin2Node, in ctx: CGContext, control: ControlContext?,
                                   alpha opacity: CGFloat, blend: CGBlendMode) {
        if let replay, changedDepth == 0, !replay.open.contains(r.pointer), let steps = replay.effects[effectKey(r.pointer)] {
            // Only the part of each bitmap near the rectangles, with room for the resampling: Core Graphics
            // resamples the whole of an image it draws, clipped or not.
            var near = CGRect.null
            let toUser = ctx.ctm.inverted()
            for region in replayRegions[ObjectIdentifier(ctx)] ?? [] { near = near.union(region.applying(toUser)) }
            let margin = 8 + 8 / max(ctx.pixelScale, 0.0001)
            let part = near.isNull ? steps : steps.compactMap { $0.cropped(to: near.insetBy(dx: -margin, dy: -margin)) }
            group(in: ctx, alpha: opacity, blend: blend, imagesOnly: true) { painter, target in painter.run(part, in: target) }
            return
        }
        let frame = r.frame.cg
        let pad = effectPadding(n.effects)
        var region = visualBounds(r, node: n).insetBy(dx: -pad, dy: -pad)
        // The clip's bounds are the full draw's (see `clip`), so this is the full draw's bitmap.
        let clip = ctx.boundingBoxOfClipPath
        if !clip.isNull, !clip.isInfinite { region = region.intersection(clip.insetBy(dx: -pad, dy: -pad)) }
        guard !region.isNull, !region.isEmpty, let whole = Skin2Bitmap(region: region, scale: ctx.pixelScale),
              let crop = clipForReplay(whole, pad: pad, parent: ctx) else { return }
        drawContent(r, node: n, in: whole.context, control: control)
        replayRegions[ObjectIdentifier(whole.context)] = nil
        replayBounds[ObjectIdentifier(whole.context)] = nil
        guard let content = whole.cropped(x0: crop.x0, y0: crop.y0, x1: crop.x1, y1: crop.y1) else { return }

        var silhouette = content
        if n.type == .shape, !n.fills.isEmpty, let shape = n.shape, let fillsOnly = whole.twin() {
            // The same clip as the content's, so the fills land on the bytes a full draw gives them.
            _ = clipForReplay(fillsOnly, pad: pad, parent: ctx)
            replayRegions[ObjectIdentifier(fillsOnly.context)] = nil
            replayBounds[ObjectIdentifier(fillsOnly.context)] = nil
            fillShape(Skin2Shapes.path(for: shape, in: frame, unit: unit), fills: n.fills, material: nil, frame: frame, in: fillsOnly.context)
            if let part = fillsOnly.cropped(x0: crop.x0, y0: crop.y0, x1: crop.x1, y1: crop.y1) { silhouette = part }
        }
        let steps = effectSteps(content, alpha: silhouette.alpha(), shadows: n.effects.filter { $0.type == .shadow && !$0.inner },
                                innerShadows: n.effects.filter { $0.type == .shadow && $0.inner },
                                blurs: n.effects.filter { $0.type == .blur }, frame: frame)
        group(in: ctx, alpha: opacity, blend: blend, imagesOnly: true) { painter, target in painter.run(steps, in: target) }
    }

    /// Composites what `body` draws as one group with `alpha` and `blend`, in a partial redraw: what a transparency
    /// layer does in a full one.
    ///
    /// Core Graphics makes a layer the size of the clip's bounds, which in a partial redraw are the whole canvas
    /// (see `clip`), so the layer is a bitmap of this painter's own instead: the same pixels drawn under the same
    /// clip, of which only the rectangles being repainted are touched and composited.
    ///
    /// `imagesOnly`: the body draws images and fills through image masks and nothing else (a rasterised node's
    /// effect). Those come out the same under any clip, so each rectangle gets a layer of its own size.
    mutating func group(in ctx: CGContext, alpha: CGFloat, blend: CGBlendMode, imagesOnly: Bool = false,
                        _ body: (inout Painter, CGContext) -> Void) {
        let id = ObjectIdentifier(ctx)
        if imagesOnly, replay != nil, let regions = replayRegions[id], ctx.width > 0 {
            let base = ctx.ctm
            let whole = CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height)
            ctx.saveGState()
            ctx.concatenate(base.inverted())
            ctx.setAlpha(alpha)
            ctx.setBlendMode(blend)
            ctx.interpolationQuality = .none
            for region in regions {
                let r = region.integral.intersection(whole)
                guard !r.isNull, !r.isEmpty, let layer = Skin2Scratch.context(width: Int(r.width), height: Int(r.height)) else { continue }
                Skin2Bitmap.configure(layer)
                layer.translateBy(x: -r.minX, y: -r.minY)
                layer.concatenate(base)
                body(&self, layer)
                if let image = layer.makeImage() { ctx.draw(image, in: r) }
            }
            ctx.restoreGState()
            return
        }
        guard replay != nil, let regions = replayRegions[id], let bounds = replayBounds[id],
              let layer = Skin2Scratch.context(width: ctx.width, height: ctx.height) else {
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.setBlendMode(blend)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            body(&self, ctx)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            return
        }
        Skin2Bitmap.configure(layer)
        Self.clip(layer, to: regions, within: bounds, scale: 1)
        layer.concatenate(ctx.ctm)
        let layerID = ObjectIdentifier(layer)
        replayRegions[layerID] = regions
        replayBounds[layerID] = bounds
        body(&self, layer)
        replayRegions[layerID] = nil
        replayBounds[layerID] = nil

        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.setAlpha(alpha)
        ctx.setBlendMode(blend)
        ctx.interpolationQuality = .none
        let whole = CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height)
        for region in regions {
            let r = region.integral.intersection(whole)
            guard !r.isNull, !r.isEmpty,
                  let patch = Skin2Scratch.image(from: layer, x: Int(r.minX), top: ctx.height - Int(r.maxY), width: Int(r.width), height: Int(r.height)) else { continue }
            ctx.draw(patch, in: r)
        }
        ctx.restoreGState()
    }

    /// Clips `ctx` to `rects` for a partial redraw without changing a byte inside them.
    ///
    /// Under a clip Core Graphics can reduce to rectangles it anchors a gradient's dither at the clip's corner and
    /// rasterises path edges against the clip's bounds, so the same fill comes out a level or two different from
    /// an unclipped one. A clip that is a real path over the same bounds as the full draw's does not have that
    /// effect, so the clip is the rectangles plus a sliver in two opposite corners of `bounds`: each covers too
    /// little of its pixel to paint anything, and together they keep the path's bounds the full draw's.
    static func clip(_ ctx: CGContext, to rects: [CGRect], within bounds: CGRect, scale: CGFloat) {
        let e = 1 / (64 * max(scale, 0.0001))
        let path = CGMutablePath()
        for r in rects { path.addRect(r) }
        path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.minX + e, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + e))
        path.closeSubpath()
        path.move(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.maxX - e, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY - e))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.clip()
    }

    /// Clips an effect's bitmap, in a partial redraw, to what can reach the rectangles being repainted: those
    /// rectangles grown by the effect's padding and a few points more, so a blur or a shadow inside a rectangle
    /// never reads past the clip. Returns the pixels to keep, or nil when nothing reaches.
    mutating func clipForReplay(_ bitmap: Skin2Bitmap, pad: CGFloat, parent ctx: CGContext) -> (x0: Int, y0: Int, x1: Int, y1: Int)? {
        guard let regions = replayRegions[ObjectIdentifier(ctx)] else { return (0, 0, bitmap.width, bitmap.height) }
        let toUser = ctx.ctm.inverted()
        let reach = regions.compactMap { device -> CGRect? in
            let r = device.applying(toUser).insetBy(dx: -pad - 4, dy: -pad - 4).intersection(bitmap.region)
            return r.isNull || r.isEmpty ? nil : r
        }
        guard !reach.isEmpty else { return nil }
        var x0 = bitmap.width, y0 = bitmap.height, x1 = 0, y1 = 0
        for r in reach {
            x0 = min(x0, max(0, Int(((r.minX - bitmap.region.minX) * bitmap.scale).rounded(.down))))
            y0 = min(y0, max(0, Int(((r.minY - bitmap.region.minY) * bitmap.scale).rounded(.down))))
            x1 = max(x1, min(bitmap.width, Int(((r.maxX - bitmap.region.minX) * bitmap.scale).rounded(.up))))
            y1 = max(y1, min(bitmap.height, Int(((r.maxY - bitmap.region.minY) * bitmap.scale).rounded(.up))))
        }
        guard x1 > x0, y1 > y0 else { return nil }
        Self.clip(bitmap.context, to: reach, within: bitmap.region, scale: bitmap.scale)
        replayRegions[ObjectIdentifier(bitmap.context)] = reach.map { $0.applying(bitmap.context.ctm) }
        replayBounds[ObjectIdentifier(bitmap.context)] = bitmap.region.applying(bitmap.context.ctm)
        return (x0, y0, x1, y1)
    }

    /// A rasterised node's effect as drawing calls, in order: the shadows (listed order, under the content), the
    /// content (blurred, if it has a blur), the inner shadows.
    func effectSteps(_ content: Skin2Bitmap, alpha: Skin2Mask?, shadows: [Skin2Effect], innerShadows: [Skin2Effect],
                     blurs: [Skin2Effect], frame: CGRect) -> [EffectStep] {
        var steps: [EffectStep] = []
        if let alpha {
            for shadow in shadows { if let step = shadowStep(shadow, mask: alpha) { steps.append(step) } }
        }
        if let sigma = blurs.compactMap({ $0.radius?.resolve(along: Double(min(frame.width, frame.height)), unit: unit) }).max(), sigma > 0 {
            content.blur(sigma: CGFloat(sigma) / 2)
        }
        if let image = content.image() { steps.append(EffectStep(image: image, region: content.region)) }
        if let alpha {
            for shadow in innerShadows { if let step = innerShadowStep(shadow, mask: alpha) { steps.append(step) } }
        }
        return steps
    }

    func run(_ steps: [EffectStep], in ctx: CGContext) {
        for step in steps {
            guard let color = step.color else {
                ctx.drawTopDown(step.image, in: step.region)
                continue
            }
            ctx.saveGState()
            if let clip = step.clip {
                ctx.clipTopDown(to: step.clipRegion, mask: clip)
                ctx.translateBy(x: step.offset.width, y: step.offset.height)
                ctx.clipTopDown(to: step.region, mask: step.image)
                ctx.setFillColor(color)
                ctx.fill(step.region.insetBy(dx: -abs(step.offset.width) - 1, dy: -abs(step.offset.height) - 1))
            } else {
                ctx.translateBy(x: step.offset.width, y: step.offset.height)
                ctx.clipTopDown(to: step.region, mask: step.image)
                ctx.setFillColor(color)
                ctx.fill(step.region)
            }
            ctx.restoreGState()
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
            if n.isAccessoryScreen, let source = n.source {
                if let picture = options.pictures[source] {
                    ctx.saveGState()
                    ctx.interpolationQuality = (n.sampling ?? .nearest) == .nearest ? .none : .high
                    ctx.drawTopDown(picture, in: frame)
                    ctx.restoreGState()
                } else if options.screenPlaceholders {
                    drawScreen(frame, in: ctx)
                    drawSourceLabel(source, in: frame, ctx: ctx)
                }
            } else if options.screenPlaceholders {
                drawScreen(frame, in: ctx)
            }
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
    func shadowStep(_ s: Skin2Effect, mask silhouette: Skin2Mask) -> EffectStep? {
        let g = shadowGeometry(s)
        let m = copy(silhouette)
        m.spread(g.spread)
        m.blur(sigma: g.sigma)
        guard let image = m.image() else { return nil }
        return EffectStep(image: image, region: m.region,
                          color: Skin2Color2CG.cg(s.color ?? Skin2Color(red: 0, green: 0, blue: 0), opacity: s.opacity ?? 1), offset: g.offset)
    }

    /// An inner shadow: the inverted silhouette, spread inward, blurred and moved, drawn over the content and
    /// clipped to the silhouette.
    func innerShadowStep(_ s: Skin2Effect, mask silhouette: Skin2Mask) -> EffectStep? {
        let g = shadowGeometry(s)
        let m = copy(silhouette)
        m.invert()
        m.spread(g.spread)
        m.blur(sigma: g.sigma)
        guard let image = m.image(), let clip = silhouette.image() else { return nil }
        return EffectStep(image: image, region: m.region,
                          color: Skin2Color2CG.cg(s.color ?? Skin2Color(red: 0, green: 0, blue: 0), opacity: s.opacity ?? 1), offset: g.offset,
                          clip: clip, clipRegion: silhouette.region)
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

    /// The source's name centred in an accessory screen's placeholder, so a preview says what goes there.
    func drawSourceLabel(_ source: String, in frame: CGRect, ctx: CGContext) {
        guard let font = Skin2Text.defaultFont(.regular) else { return }
        let size = max(6, min(frame.height * 0.3, frame.width / CGFloat(max(1, source.count)) * 1.4))
        ctx.addPath(Skin2Text.path(source, font: font, size: size, align: .center, fit: true, in: frame.insetBy(dx: 2, dy: 2)))
        ctx.setFillColor(Skin2Color2CG.cg(Skin2Color(hex: "#8080A0")!))
        ctx.fillPath()
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
