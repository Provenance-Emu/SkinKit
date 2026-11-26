import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

/// The render cache (issue 162): a held control repaints its own rectangle, not the tree, and the pixels are the
/// ones a full draw gives.
///
/// "The same pixels" is byte equality with `Skin2Renderer.image`. Core Graphics does not give the same bytes for the
/// same full draw every time when other threads are drawing too (concurrent full draws of `gamecube-icube` differ
/// from a serial one a few times in a hundred, by up to 34 levels in one gradient), and the other suites draw while
/// this one runs. So a comparison that fails is drawn again, both sides: a real difference fails every time.
@Suite("Format 2.0 render cache", .serialized)
struct RenderCacheTests {
    /// Whether `got` and `want` come out byte-identical, drawing both again when another thread's drawing got in
    /// the way. Returns the last pair for the failure report.
    static func same(attempts: Int = 8, _ got: () -> Pixels?, _ want: () -> Pixels?) -> (same: Bool, got: Pixels?, want: Pixels?) {
        var last: (Pixels?, Pixels?) = (nil, nil)
        for _ in 0..<attempts {
            last = (got(), want())
            if let a = last.0, let b = last.1, a.identical(b) { return (true, a, b) }
        }
        return (false, last.0, last.1)
    }

    /// State sets that exercise every control of a layout: each control alone, all at once, a press easing in, a
    /// release easing out, and the fixture's own `states.json`.
    static func stateSets(_ resolution: Skin2Resolution, fixture: String?) throws -> [(String, [String: Skin2ControlState])] {
        var out: [(String, [String: Skin2ControlState])] = []
        var all: [String: Skin2ControlState] = [:]
        var seen = Set<Skin2ControlKind>()
        for control in resolution.controls {
            guard let id = control.id, let kind = control.node.kind else { continue }
            var state = Skin2ControlState(pressed: true)
            switch kind {
            case .dpad: state = Skin2ControlState(directions: [.up, .right])
            case .thumbstick: state = Skin2ControlState(pressed: true, stick: Skin2StickValue(x: 0.7, y: -0.6))
            default: break
            }
            all[id] = state
            out.append(("\(id) held", [id: state]))
            var easing = state
            easing.scaleProgress = 0.4
            out.append(("\(id) easing in", [id: easing]))
            // Once per kind of control is enough for the states that only scale or patch.
            guard seen.insert(kind).inserted else { continue }
            out.append(("\(id) easing out", [id: Skin2ControlState(scaleProgress: 0.6, easingOut: true)]))
            out.append(("\(id) selected", [id: Skin2ControlState(selected: true)]))
        }
        if !all.isEmpty { out.append(("everything held", all)) }
        if let fixture { out += try StateSets.load(fixture).map { ("states.json \($0.0)", $0.1) } }
        return out
    }

    /// Draws through `cache` into a cleared canvas and returns the pixels.
    static func drawn(_ cache: Skin2RenderCache, _ resolution: Skin2Resolution, _ options: Skin2RenderOptions, scale: CGFloat,
                      base: [String: Skin2ControlState] = [:], assetIdentity: AnyHashable? = nil) -> Pixels? {
        let ctx = CacheFixtures.canvas(resolution, scale: scale)
        cache.draw(resolution, in: ctx, options: options, baseStates: base, assetIdentity: assetIdentity)
        return ctx.makeImage().flatMap(Pixels.init)
    }

    static func expected(_ resolution: Skin2Resolution, _ options: Skin2RenderOptions, scale: CGFloat) -> Pixels? {
        Skin2Renderer.image(resolution, scale: scale, options: options).flatMap(Pixels.init)
    }

    /// Checks every state set of one layout against a full draw, byte for byte. Returns how many it compared.
    @discardableResult
    static func checkIdentical(_ resolution: Skin2Resolution, _ options: Skin2RenderOptions, fixture: String?, label: String,
                               scale: CGFloat) throws -> Int {
        let cache = Skin2RenderCache()
        var compared = 0
        var sets = try stateSets(resolution, fixture: fixture)
        sets.insert(("at rest", [:]), at: 0)
        for (name, states) in sets {
            var o = options
            o.states = states
            let result = same({ drawn(cache, resolution, o, scale: scale) }, { expected(resolution, o, scale: scale) })
            guard let want = result.want, let got = result.got else {
                Issue.record("\(label) \(name): could not render")
                continue
            }
            if !result.same {
                let (fraction, diff) = got.difference(want)
                let out = RenderPaths.failures.appendingPathComponent("cache", isDirectory: true)
                try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                let stem = "\(label)-\(name)".replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
                if let diff { try? PNG.data(diff)?.write(to: out.appendingPathComponent(stem + ".diff.png")) }
                var worst = 0, count = 0
                for i in got.bytes.indices where got.bytes[i] != want.bytes[i] { count += 1; worst = max(worst, abs(Int(got.bytes[i]) - Int(want.bytes[i]))) }
                Issue.record("\(label) @\(scale)x, \(name): \(count) bytes differ from a full draw (largest step \(worst), \(fraction * 100) % over the reference threshold); repainted \(cache.lastRepainted)")
            }
            compared += 1
        }
        #expect(cache.statistics.restRenders == 1, "\(label): the tree is painted into the cache once")
        #expect(cache.statistics.directRenders == 0, "\(label): nothing fell back to a full draw")
        return compared
    }

    @Test("A partial redraw gives the pixels of a full draw, for every fixture", arguments: RenderPaths.fixtureNames)
    func identicalToFullDraw(_ name: String) throws {
        let base = try Skin2Document.load(data: RenderPaths.skinData(name))
        // One portrait and one landscape canvas: the layouts differ, the drawing code does not.
        let sets = Skin2TraitSet.sets(for: base).filter { $0.device != .tv }
        let traits = [sets.first { $0.orientation == .portrait }, sets.first { $0.orientation == .landscape }].compactMap { $0 }
        for trait in traits {
            let resolution = Skin2Resolver.resolve(base, in: trait.environment)
            try Self.checkIdentical(resolution, CacheFixtures.options(name), fixture: name, label: "\(name)/\(trait.name)", scale: 2)
        }
    }

    @Test("Nodes above and below a held control, blends and blurs redraw identically", arguments: [CGFloat(1), 2, 3])
    func overlapIdentical(_ scale: CGFloat) throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let compared = try Self.checkIdentical(resolution, CacheFixtures.options(), fixture: "states", label: "heavy", scale: scale)
        #expect(compared > 10)
    }

    @Test("A stick sweep and a press ease are identical on every frame")
    func sweepIdentical() throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cache = Skin2RenderCache()
        for states in CacheFixtures.stickSweep("stick", count: 12) + CacheFixtures.pressEase("a") + CacheFixtures.pressEase("dpad") {
            let options = CacheFixtures.options(states: states)
            let ok = Self.same({ Self.drawn(cache, resolution, options, scale: 2) }, { Self.expected(resolution, options, scale: 2) }).same
            #expect(ok, "differs for \(states)")
        }
        #expect(cache.statistics.fullTreeRenders == 1)
    }

    @Test("Parts of a skin split around an accessory screen redraw identically")
    func partsIdentical() throws {
        let document = try Skin2Document.load(data: RenderPaths.skinData("dreamcast-vmu"))
        var environment = CacheFixtures.phone.environment
        environment.capabilities = [Skin2Capabilities.picture("vmu.p1")]
        let resolution = Skin2Resolver.resolve(document, in: environment)
        let screen = try #require(resolution.accessoryScreens.first)
        let cache = Skin2RenderCache()
        let id = try #require(resolution.controls.compactMap(\.id).first)
        for part in [Skin2DrawPart.upTo(screen: screen.pointer), .after(screen: screen.pointer)] {
            for states in [[:], [id: Skin2ControlState(pressed: true)]] {
                var options = CacheFixtures.options("dreamcast-vmu", states: states)
                options.part = part
                let ok = Self.same({ Self.drawn(cache, resolution, options, scale: 2) }, { Self.expected(resolution, options, scale: 2) }).same
                #expect(ok, "\(part) differs for \(states)")
            }
        }
        #expect(cache.statistics.restRenders == 2, "one image per part")
    }

    // MARK: Counting

    @Test("A touch-move on one control does not re-render the tree")
    func touchMoveDoesNotRenderTheTree() throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cache = Skin2RenderCache()
        let ctx = CacheFixtures.canvas(resolution, scale: 2)
        let total = resolution.nodes.reduce(0) { $0 + max(1, $1.copies.count) }

        cache.draw(resolution, in: ctx, options: CacheFixtures.options())
        #expect(cache.statistics.restRenders == 1)
        #expect(cache.statistics.restDraws == 1)

        let moves = CacheFixtures.stickSweep("stick", count: 30)
        for states in moves {
            CacheFixtures.clear(ctx)
            cache.draw(resolution, in: ctx, options: CacheFixtures.options(states: states))
        }
        #expect(cache.statistics.fullTreeRenders == 1, "30 touch-moves painted the whole tree \(cache.statistics.fullTreeRenders - 1) more times")
        #expect(cache.statistics.partialDraws == moves.count)
        // Each move paints the stick and what overlaps it, not the buttons, the d-pad or the screen.
        let perMove = Double(cache.statistics.partialNodes) / Double(moves.count)
        #expect(perMove <= Double(total) / 2, "a move painted \(perMove) of \(total) nodes")
        let repainted = try #require(cache.lastRepainted.first)
        let stick = try #require(resolution.node(id: "stick")).frame
        let canvas = resolution.environment.size
        #expect(cache.lastRepainted.count == 1)
        #expect(repainted.contains(CGRect(x: stick.x, y: stick.y, width: stick.width, height: stick.height)))
        #expect(repainted.width * repainted.height < 0.2 * canvas.width * canvas.height)

        // Letting go draws the image again and paints nothing.
        cache.resetStatistics()
        CacheFixtures.clear(ctx)
        cache.draw(resolution, in: ctx, options: CacheFixtures.options())
        #expect(cache.statistics == Skin2RenderCache.Statistics(restDraws: 1))
    }

    @Test("The display frames of a press ease do not re-render the tree")
    func easeDoesNotRenderTheTree() throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cache = Skin2RenderCache()
        let ctx = CacheFixtures.canvas(resolution, scale: 2)
        for states in CacheFixtures.pressEase("a") {
            CacheFixtures.clear(ctx)
            cache.draw(resolution, in: ctx, options: CacheFixtures.options(states: states))
        }
        #expect(cache.statistics.fullTreeRenders == 1)
        #expect(cache.statistics.partialDraws == 10)
    }

    @Test("Two controls held far apart repaint two rectangles")
    func disjointRegions() throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cache = Skin2RenderCache()
        let ctx = CacheFixtures.canvas(resolution, scale: 2)
        let states = ["stick": Skin2ControlState(pressed: true, stick: Skin2StickValue(x: 1, y: 0)), "a": Skin2ControlState(pressed: true)]
        cache.draw(resolution, in: ctx, options: CacheFixtures.options(states: states))
        #expect(cache.lastRepainted.count == 2)
        #expect(cache.statistics.fullTreeRenders == 1)
    }

    @Test("States that draw as rest are the rest state")
    func restEquivalents() {
        #expect(Skin2RenderCache.changedControls(["a": Skin2ControlState(scaleProgress: 0, easingOut: true)], base: [:]).isEmpty)
        #expect(Skin2RenderCache.changedControls(["a": Skin2ControlState(scaleProgress: 0.3)], base: [:]).isEmpty)
        #expect(Skin2RenderCache.changedControls(["a": Skin2ControlState(pressure: 0.4)], base: [:]).isEmpty)
        #expect(Skin2RenderCache.changedControls(["a": Skin2ControlState(scaleProgress: 0.3, easingOut: true)], base: [:]) == ["a"])
        #expect(Skin2RenderCache.changedControls(["a": Skin2ControlState(selected: true)], base: ["a": Skin2ControlState(selected: true)]).isEmpty)
        #expect(Skin2RenderCache.changedControls([:], base: ["a": Skin2ControlState(selected: true)]) == ["a"])
    }

    // MARK: Invalidation

    static func edit(_ change: (inout Skin2Edit) -> Void) -> Skin2Edit {
        var e = Skin2Edit()
        change(&e)
        return e
    }

    /// Draws at rest twice and reports how many times the tree was painted for the second draw.
    func rendersAfter(_ change: (inout Skin2Resolution, inout Skin2RenderOptions, inout [String: Skin2ControlState], inout AnyHashable?, inout CGFloat) throws -> Void) throws -> Int {
        var resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        var options = CacheFixtures.options("states")
        var base: [String: Skin2ControlState] = [:]
        var identity: AnyHashable? = "skin-1"
        var scale: CGFloat = 2
        let cache = Skin2RenderCache()
        _ = Self.drawn(cache, resolution, options, scale: scale, base: base, assetIdentity: identity)
        _ = Self.drawn(cache, resolution, options, scale: scale, base: base, assetIdentity: identity)
        #expect(cache.statistics.restRenders == 1 && cache.statistics.restDraws == 2)
        try change(&resolution, &options, &base, &identity, &scale)
        options.states = base
        cache.resetStatistics()
        let ok = Self.same({ Self.drawn(cache, resolution, options, scale: scale, base: base, assetIdentity: identity) },
                           { Self.expected(resolution, options, scale: scale) }).same
        #expect(ok, "the draw after the change is the new skin")
        let fresh = Skin2RenderCache()
        _ = Self.drawn(fresh, resolution, options, scale: scale, base: base, assetIdentity: identity)
        #expect(cache.byteCount == fresh.byteCount, "the old image is gone")
        return cache.statistics.restRenders
    }

    @Test("Nothing changed: the image is kept")
    func keptWhenNothingChanges() throws {
        #expect(try rendersAfter { _, _, _, _, _ in } == 0)
        #expect(try rendersAfter { resolution, _, _, _, _ in
            resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        } == 0, "an equal resolution resolved again is the same skin")
    }

    @Test("A new resolution drops the image: canvas size, flags, edits")
    func resolutionInvalidates() throws {
        let document = try CacheFixtures.heavyDocument()
        #expect(try rendersAfter { resolution, _, _, _, _ in
            resolution = CacheFixtures.resolution(document, Skin2TraitSet.all.first { $0.name == "iphone-edgeToEdge-landscape" }!)
        } == 1)
        #expect(try rendersAfter { resolution, _, _, _, _ in
            resolution = Skin2Resolver.resolve(document, in: CacheFixtures.phone.environment, edits: ["a": Self.edit { $0.offset = .init(x: 12, y: -8) }])
        } == 1)
        #expect(try rendersAfter { resolution, _, _, _, _ in
            resolution = Skin2Resolver.resolve(document, in: CacheFixtures.phone.environment, edits: ["stick": Self.edit { $0.opacity = 0.5 }])
        } == 1)
    }

    @Test("A new selection drops the image")
    func selectionInvalidates() throws {
        #expect(try rendersAfter { _, _, base, _, _ in base = ["a": Skin2ControlState(selected: true)] } == 1)
    }

    @Test("A new asset source drops the image")
    func assetInvalidates() throws {
        #expect(try rendersAfter { _, _, _, identity, _ in identity = "skin-2" } == 1)
        #expect(try rendersAfter { _, options, _, _, _ in options.asset = nil } == 1)
    }

    @Test("New options, pictures or pixel scale drop the image")
    func optionsInvalidate() throws {
        #expect(try rendersAfter { _, options, _, _, _ in options.screenPlaceholders = false } == 1)
        #expect(try rendersAfter { _, options, _, _, _ in options.showHitFrames = true } == 1)
        #expect(try rendersAfter { _, _, _, _, scale in scale = 3 } == 1)
        let picture = try #require(Skin2Renderer.image(CacheFixtures.resolution(try CacheFixtures.heavyDocument()), scale: 0.1))
        #expect(try rendersAfter { _, options, _, _, _ in options.pictures = ["vmu.p1": picture] } == 1)
    }

    @Test("A selected control is in the image; holding another repaints only that one")
    func selectedIsCached() throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cache = Skin2RenderCache()
        let base = ["a": Skin2ControlState(selected: true)]
        var states = base
        states["b"] = Skin2ControlState(pressed: true)
        let options = CacheFixtures.options(states: states)
        let ok = Self.same({ Self.drawn(cache, resolution, options, scale: 2, base: base) }, { Self.expected(resolution, options, scale: 2) }).same
        #expect(ok)
        #expect(cache.lastRepainted.count == 1)
        let b = try #require(resolution.node(id: "b")).frame
        #expect(cache.lastRepainted[0].contains(CGPoint(x: b.midX, y: b.midY)))
    }

    // MARK: Fallbacks

    @Test("Targets the cache cannot serve are drawn directly")
    func uncacheableTargets() throws {
        let resolution = CacheFixtures.resolution(try CacheFixtures.heavyDocument())
        let cache = Skin2RenderCache()
        // A transform off the pixel grid.
        let ctx = CacheFixtures.canvas(resolution, scale: 2)
        ctx.translateBy(x: 0.25, y: 0)
        cache.draw(resolution, in: ctx, options: CacheFixtures.options())
        #expect(cache.statistics.directRenders == 1 && cache.statistics.restRenders == 0)
        // A vector target.
        var options = CacheFixtures.options()
        options.effectScale = 2
        cache.draw(resolution, in: CacheFixtures.canvas(resolution, scale: 2), options: options)
        #expect(cache.statistics.directRenders == 2 && cache.byteCount == 0)
    }
}
