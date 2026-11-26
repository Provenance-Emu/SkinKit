import CoreGraphics
import Foundation
import SkinKit2Core

/// Draws a resolved skin without painting the whole tree each time (issue 162).
///
/// The skin with every control in `baseStates` is painted once into an image at the target's pixel scale. A draw
/// whose states are the base states draws that image. A draw with other states draws the image everywhere except
/// around the controls whose state differs, and paints the tree again for those rectangles only, into a bitmap of
/// the cache's own: every node that can reach a rectangle is drawn in tree order with the rectangles as the clip,
/// so a node above or below a held control, a blend mode or a group's opacity comes out as it does in one full
/// draw. A shadowed or blurred node that has not changed is not rasterised again: its bitmaps are kept from the
/// first painting and only composited. The rectangles then go to the target as images.
///
/// The target only ever receives images, so what it shows is `Skin2Renderer.image`, byte for byte, whatever the
/// target's own rasteriser does with paths and gradients (a SwiftUI `Canvas` context is not a bitmap and does not
/// give the bytes the reference renderer gives).
///
/// The image is thrown away when anything it was painted from changes: the resolution (the document, the canvas,
/// the flags, the player's edits), the base states (the host's `selected` controls), the options, the pictures,
/// `assetIdentity`, or the target's pixel size. One image is kept per `Skin2DrawPart`.
///
/// The target must be cleared first (a SwiftUI `Canvas` is). Vector targets (`effectScale`) and targets whose
/// transform is not a pixel-aligned scale are drawn directly. Not thread-safe: use one cache from one thread.
public final class Skin2RenderCache {
    /// What the cache has done, for tests and diagnostics.
    public struct Statistics: Equatable, Sendable {
        /// Whole trees painted into a cached image.
        public var restRenders = 0
        /// Whole trees painted straight into the target (a target the cache cannot serve).
        public var directRenders = 0
        /// Draws that copied the cached image and painted nothing.
        public var restDraws = 0
        /// Draws that copied the cached image and repainted the changed controls' rectangles.
        public var partialDraws = 0
        /// Nodes painted by partial draws, each counted once per rectangle it was painted in.
        public var partialNodes = 0
        /// Whole trees painted, wherever they went.
        public var fullTreeRenders: Int { restRenders + directRenders }
    }

    public private(set) var statistics = Statistics()
    /// Images kept at once: one per part of one layout.
    public var capacity = 8

    private var entries: [Entry] = []

    public init() {}

    /// Forgets every image.
    public func removeAll() { entries.removeAll() }

    /// Forgets the counters.
    public func resetStatistics() { statistics = Statistics() }

    /// Bytes of pixels held: the images, and the shadow and blur bitmaps kept beside them.
    public var byteCount: Int { entries.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height + $1.effectBytes } }

    /// The transform of the last target the cache could not serve (diagnostics).
    public private(set) var lastRejection: String?

    /// The rectangles (canvas points) the last partial draw repainted.
    public private(set) var lastRepainted: [CGRect] = []

    /// Draws `resolution` into `ctx` as `Skin2Renderer.draw` does. `options.states` are the states to show;
    /// `baseStates` are the states the cached image holds (controls that stay `selected`). `assetIdentity` names
    /// what `options.asset` reads from: change it when the files behind the closure change.
    public func draw(_ resolution: Skin2Resolution, in ctx: CGContext, options: Skin2RenderOptions = .init(),
                     baseStates: [String: Skin2ControlState] = [:], assetIdentity: AnyHashable? = nil) {
        lastRepainted = []
        guard options.effectScale == nil, let target = Target(ctx, size: resolution.environment.size) else {
            lastRejection = Target.describe(ctx)
            statistics.directRenders += 1
            Skin2Renderer.draw(resolution, in: ctx, options: options)
            return
        }
        let key = Key(part: options.part, screenPlaceholders: options.screenPlaceholders, showHitFrames: options.showHitFrames,
                      pictures: options.pictures.mapValues { ObjectIdentifier($0) }, baseStates: Self.normalized(baseStates),
                      assetIdentity: assetIdentity, hasAsset: options.asset != nil, target: target)
        guard let entry = entry(for: resolution, key: key, options: options) else {
            statistics.directRenders += 1
            Skin2Renderer.draw(resolution, in: ctx, options: options)
            return
        }

        let changed = Self.changedControls(options.states, base: key.baseStates)
        if changed.isEmpty {
            statistics.restDraws += 1
            copy(entry.image, to: ctx, target: target, excluding: [])
            return
        }

        // Where the changed controls paint, before and after, snapped out to whole pixels.
        var now = Painter(resolution: resolution, options: options, vectorContext: nil)
        var open = Set<String>()
        var dirty: [CGRect] = []
        for id in changed {
            for pointer in entry.controlPointers[id] ?? [] {
                var p = Substring(pointer)
                while !p.isEmpty {
                    open.insert(String(p))
                    guard let cut = p.range(of: "/children/", options: .backwards) else { break }
                    p = p[..<cut.lowerBound]
                }
            }
            dirty += entry.controlBounds[id] ?? []
        }
        dirty += now.controlBounds(ids: changed).values.flatMap { $0 }
        let regions = target.regions(dirty)
        guard !regions.isEmpty, let scratch = target.makeScratch() else {
            // The changed controls are not in this layout.
            statistics.restDraws += 1
            copy(entry.image, to: ctx, target: target, excluding: [])
            return
        }
        let replay = Skin2Replay(bounds: entry.bounds, changed: changed, open: open, regions: regions, canvas: target.rect, effects: entry.effects)
        let painted = Skin2Renderer.draw(resolution, in: scratch, options: options, replay: replay)
        var patches: [(image: CGImage, region: CGRect)] = []
        for region in regions {
            let x = Int((region.minX * target.scale).rounded()), top = Int((region.minY * target.scale).rounded())
            let w = Int((region.width * target.scale).rounded()), h = Int((region.height * target.scale).rounded())
            if let patch = Skin2Scratch.image(from: scratch, x: x, top: top, width: w, height: h) { patches.append((patch, region)) }
        }
        guard patches.count == regions.count else {
            // Out of memory for a rectangle: paint the tree rather than leave a hole.
            statistics.directRenders += 1
            Skin2Renderer.draw(resolution, in: ctx, options: options)
            return
        }
        statistics.partialDraws += 1
        statistics.partialNodes += painted
        lastRepainted = regions
        copy(entry.image, to: ctx, target: target, excluding: regions)
        ctx.saveGState()
        ctx.interpolationQuality = .none
        for patch in patches { ctx.drawTopDown(patch.image, in: patch.region) }
        ctx.restoreGState()
    }

    // MARK: Entries

    private struct Key: Equatable {
        var part: Skin2DrawPart
        var screenPlaceholders: Bool
        var showHitFrames: Bool
        var pictures: [String: ObjectIdentifier]
        var baseStates: [String: Skin2ControlState]
        var assetIdentity: AnyHashable?
        var hasAsset: Bool
        var target: Target

        /// The same layout and inputs, whatever the part.
        func sameGeneration(_ other: Key) -> Bool {
            var a = self
            a.part = other.part
            return a == other
        }
    }

    private struct Entry {
        var key: Key
        var resolution: Skin2Resolution
        var image: CGImage
        var bounds: [String: CGRect]
        /// Each control's bounds under the base states, in canvas points (one per copy).
        var controlBounds: [String: [CGRect]]
        var controlPointers: [String: [String]]
        /// The shadows and blurs of the nodes in the image, ready to composite again in a partial redraw.
        var effects: [String: [EffectStep]]
        var effectBytes: Int
    }

    private func entry(for resolution: Skin2Resolution, key: Key, options: Skin2RenderOptions) -> Entry? {
        if let i = entries.firstIndex(where: { $0.key == key && $0.resolution == resolution }) {
            if i != entries.count - 1 { entries.append(entries.remove(at: i)) }
            return entries[entries.count - 1]
        }
        // Anything painted from another layout or other inputs is of no use any more.
        entries.removeAll { !$0.key.sameGeneration(key) || $0.resolution != resolution }

        var base = options
        base.states = key.baseStates
        guard let bitmap = key.target.makeBitmap() else { return nil }
        // The bitmaps of shadows and blurs are kept as well, up to as many bytes again as the image.
        let recorder = Skin2EffectRecorder(budget: bitmap.bytesPerRow * bitmap.height)
        Skin2Renderer.draw(resolution, in: bitmap, options: base, replay: nil, recorder: recorder)
        guard let image = bitmap.makeImage() else { return nil }
        statistics.restRenders += 1

        var painter = Painter(resolution: resolution, options: base, vectorContext: nil)
        var bounds: [String: CGRect] = [:]
        _ = painter.paintBounds(resolution.root, control: nil, table: &bounds)
        var pointers: [String: [String]] = [:]
        for node in resolution.nodes where node.node.type == .control {
            if let id = node.node.id { pointers[id, default: []].append(node.pointer) }
        }
        let entry = Entry(key: key, resolution: resolution, image: image, bounds: bounds,
                          controlBounds: painter.controlBounds(ids: Set(pointers.keys)), controlPointers: pointers,
                          effects: recorder.effects, effectBytes: recorder.byteCount)
        entries.append(entry)
        if entries.count > max(1, capacity) { entries.removeFirst(entries.count - max(1, capacity)) }
        return entry
    }

    // MARK: States

    /// A state that draws as the rest state is the rest state.
    static func normalized(_ states: [String: Skin2ControlState]) -> [String: Skin2ControlState] {
        states.compactMapValues { drawsAtRest($0) ? nil : $0 }
    }

    static func drawsAtRest(_ s: Skin2ControlState) -> Bool {
        s.stateNames.isEmpty && s.stick == .zero && !(s.easingOut && s.scaleProgress > 0)
    }

    /// Ids whose state draws differently from the base. Pressure is not drawn.
    static func changedControls(_ states: [String: Skin2ControlState], base: [String: Skin2ControlState]) -> Set<String> {
        var out = Set<String>()
        for (id, state) in states {
            var a = state, b = base[id] ?? Skin2ControlState()
            a.pressure = nil; b.pressure = nil
            if drawsAtRest(a), drawsAtRest(b) { continue }
            if a != b { out.insert(id) }
        }
        for id in base.keys where states[id] == nil { out.insert(id) }
        return out
    }

    // MARK: Target

    /// A target the cache can serve: user space is canvas points scaled by a whole-pixel-aligned transform.
    struct Target: Equatable {
        /// Pixels per point.
        var scale: CGFloat
        var width: Int
        var height: Int
        /// The canvas in points, grown to whole pixels.
        var rect: CGRect

        init?(_ ctx: CGContext, size: Skin2Size) {
            let t = ctx.userSpaceToDeviceSpaceTransform
            let aligned: (CGFloat) -> Bool = { abs($0 - $0.rounded()) < 1e-6 }
            guard t.b == 0, t.c == 0, t.a > 0, abs(abs(t.d) - t.a) < 1e-9, aligned(t.tx), aligned(t.ty) else { return nil }
            scale = t.a
            let w = (CGFloat(size.width) * scale - 1e-6).rounded(.up), h = (CGFloat(size.height) * scale - 1e-6).rounded(.up)
            guard w >= 1, h >= 1, w <= 8192, h <= 8192, w * h <= 40_000_000 else { return nil }
            width = Int(w); height = Int(h)
            rect = CGRect(x: 0, y: 0, width: w / scale, height: h / scale)
        }

        static func describe(_ ctx: CGContext) -> String {
            let t = ctx.userSpaceToDeviceSpaceTransform
            return "transform [\(t.a) \(t.b) \(t.c) \(t.d) \(t.tx) \(t.ty)]"
        }

        /// A cleared working bitmap for one partial redraw, set up like `makeBitmap`'s.
        func makeScratch() -> CGContext? {
            guard let ctx = Skin2Scratch.context(width: width, height: height) else { return nil }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: scale, y: -scale)
            return ctx
        }

        /// A cleared bitmap like `Skin2Renderer.image`'s.
        func makeBitmap() -> CGContext? {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: Skin2Color2CG.sRGB,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: scale, y: -scale)
            return ctx
        }

        /// `rects` clipped to the canvas, grown to whole pixels, and merged until none touch.
        func regions(_ rects: [CGRect]) -> [CGRect] {
            var out: [CGRect] = []
            for r in rects {
                let c = r.intersection(rect)
                guard !c.isNull, !c.isEmpty else { continue }
                let x0 = (c.minX * scale).rounded(.down), y0 = (c.minY * scale).rounded(.down)
                let x1 = (c.maxX * scale).rounded(.up), y1 = (c.maxY * scale).rounded(.up)
                var merged = CGRect(x: x0 / scale, y: y0 / scale, width: (x1 - x0) / scale, height: (y1 - y0) / scale)
                while let i = out.firstIndex(where: { $0.intersects(merged) }) { merged = merged.union(out.remove(at: i)) }
                out.append(merged)
            }
            return out
        }
    }

    /// Copies the cached image pixel for pixel, leaving `holes` untouched.
    private func copy(_ image: CGImage, to ctx: CGContext, target: Target, excluding holes: [CGRect]) {
        ctx.saveGState()
        if !holes.isEmpty {
            let path = CGMutablePath()
            path.addRect(target.rect)
            for hole in holes { path.addRect(hole) }
            ctx.addPath(path)
            ctx.clip(using: .evenOdd)
        }
        ctx.interpolationQuality = .none
        ctx.drawTopDown(image, in: target.rect)
        ctx.restoreGState()
    }
}

// MARK: Bounds

extension Painter {
    /// Whether a node rasterises its content for a shadow or a blur.
    func isRasterised(_ n: Skin2Node) -> Bool {
        n.effects.contains { $0.type == .shadow || $0.type == .blur }
    }

    /// An upper bound on where `draw(r, in:control:)` can put a pixel, in the user space it is called in. `table`
    /// collects the bound of every node visited, by pointer.
    mutating func paintBounds(_ r: Skin2ResolvedNode, control: ControlContext?, table: inout [String: CGRect]) -> CGRect {
        if r.node.role == .highlight, !(control?.state.isPressed ?? false) { return .null }
        var out = CGRect.null
        let transforms = r.copies.isEmpty ? [CGAffineTransform.identity] : r.copies.map(\.cg)
        for (i, t) in transforms.enumerated() {
            var n = r.node
            if let id = n.id, let list = control?.patches[id] {
                for (copy, patch) in list where copy == nil || copy == i { n = patch.apply(to: n) }
            }
            guard isVisible(n) else { continue }
            let b = singleBounds(r, node: n, control: control, table: &table)
            if !b.isNull { out = out.union(b.applying(t)) }
        }
        table[r.pointer] = out
        return out
    }

    /// One copy's bound, with its own control scale and knob displacement applied.
    mutating func singleBounds(_ r: Skin2ResolvedNode, node n: Skin2Node, control outer: ControlContext?, table: inout [String: CGRect]) -> CGRect {
        let frame = r.frame.cg
        var control = outer
        var transform = CGAffineTransform.identity
        if n.type == .control {
            let pose = pose(r, node: n)
            if pose.scale != 1 { transform = Self.scale(pose.scale, about: frame) }
            control = pose.context
        }
        if n.role == .knob, let k = control?.knob, k != .zero {
            transform = CGAffineTransform(translationX: k.width, y: k.height).concatenating(transform)
        }
        var b = ownBounds(r, node: n)
        for child in r.children {
            let cb = paintBounds(child, control: control, table: &table)
            if !cb.isNull { b = b.union(cb) }
        }
        if isRasterised(n) {
            // The content is cropped to its bitmap (the visual bounds plus the padding, grown to whole pixels) and
            // a shadow is that bitmap moved by an offset the padding already counts.
            let pad = effectPadding(n.effects)
            b = visualBounds(r, node: n).insetBy(dx: -2 * pad - 2, dy: -2 * pad - 2)
        }
        return b.applying(transform)
    }

    static func scale(_ s: Double, about frame: CGRect) -> CGAffineTransform {
        CGAffineTransform(translationX: -frame.midX, y: -frame.midY)
            .concatenating(CGAffineTransform(scaleX: s, y: s))
            .concatenating(CGAffineTransform(translationX: frame.midX, y: frame.midY))
    }

    /// What the node paints itself, children aside: its shape with strokes (mitres included), its text, its frame.
    mutating func ownBounds(_ r: Skin2ResolvedNode, node n: Skin2Node) -> CGRect {
        let frame = r.frame.cg
        var b = frame
        switch n.type {
        case .shape:
            guard let shape = n.shape else { break }
            let box = Skin2Shapes.path(for: shape, in: frame, unit: unit).boundingBoxOfPath
            guard !box.isNull, !box.isInfinite else { break }
            let short = Double(min(frame.width, frame.height))
            var reach: CGFloat = 0
            for s in n.strokes {
                let width = CGFloat(s.width.resolve(along: short, unit: unit))
                // Inner and outer strokes are drawn twice as wide and clipped; a mitre reaches ten half-widths.
                reach = max(reach, 2 * width * (s.join == .miter ? 5 : 1))
            }
            b = b.union(box.insetBy(dx: -reach, dy: -reach))
        case .text:
            if let text = n.text, !text.isEmpty {
                let box = textPath(text, node: n, frame: frame).boundingBoxOfPath
                if !box.isNull, !box.isInfinite { b = b.union(box) }
            }
        case .image, .screen, .group, .control:
            break
        }
        return b.insetBy(dx: -1, dy: -1)
    }

    /// Where each of `ids`' controls paints, in canvas points: one rectangle per copy, grown by the padding of
    /// every rasterised ancestor (a change inside a shadowed or blurred group moves that group's effect too).
    mutating func controlBounds(ids: Set<String>) -> [String: [CGRect]] {
        var out: [String: [CGRect]] = [:]
        collectControlBounds(resolution.root, control: nil, transform: .identity, pad: 0, ids: ids, into: &out)
        return out
    }

    private mutating func collectControlBounds(_ r: Skin2ResolvedNode, control: ControlContext?, transform: CGAffineTransform, pad: CGFloat,
                                               ids: Set<String>, into out: inout [String: [CGRect]]) {
        if r.node.type == .control, let id = r.node.id, ids.contains(id) {
            var scratch: [String: CGRect] = [:]
            let b = paintBounds(r, control: control, table: &scratch)
            // An unpressed highlight or a hidden control paints nothing now; its frame still marks where it was.
            let local = b.isNull ? r.frame.cg.insetBy(dx: -1, dy: -1) : b
            out[id, default: []].append(local.applying(transform).insetBy(dx: -pad, dy: -pad))
        }
        let transforms = r.copies.isEmpty ? [CGAffineTransform.identity] : r.copies.map(\.cg)
        for (i, t) in transforms.enumerated() {
            var n = r.node
            if let id = n.id, let list = control?.patches[id] {
                for (copy, patch) in list where copy == nil || copy == i { n = patch.apply(to: n) }
            }
            var inner = control
            var local = t
            if n.type == .control {
                let pose = pose(r, node: n)
                if pose.scale != 1 { local = Self.scale(pose.scale, about: r.frame.cg).concatenating(local) }
                inner = pose.context
            }
            if n.role == .knob, let k = inner?.knob, k != .zero {
                local = CGAffineTransform(translationX: k.width, y: k.height).concatenating(local)
            }
            let full = local.concatenating(transform)
            var innerPad = pad
            if isRasterised(n) {
                let s = sqrt(abs(full.a * full.d - full.b * full.c))
                innerPad += (2 * effectPadding(n.effects) + 2) * max(s, 1)
            }
            for child in r.children {
                collectControlBounds(child, control: inner, transform: full, pad: innerPad, ids: ids, into: &out)
            }
        }
    }
}
