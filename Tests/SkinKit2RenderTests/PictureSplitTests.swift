import Combine
import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

private func fixtureResolution(_ fixture: String, scene name: String, trait traitName: String = "iphone-standard-portrait") throws -> (Skin2Resolution, [String: CGImage]) {
    let doc = try Skin2Document.load(data: RenderPaths.skinData(fixture))
    let scene = try #require(try FixtureScene.load(fixture).first { $0.name == name })
    var environment = try #require(Skin2TraitSet.all.first { $0.name == traitName }).environment
    environment.capabilities = scene.capabilities
    environment.flags = scene.flags
    return (Skin2Resolver.resolve(doc, in: environment), Skin2Fixtures.pictures(fixture))
}

@Suite("Drawing a skin in parts around its accessory screens")
struct PictureSplitTests {
    @Test("Under, picture, over compose to the one-shot image", arguments: [["accessory-screen", "with-pictures"], ["panels", "open"]])
    func partsComposeToTheWholeImage(_ fixture: [String]) throws {
        let (resolution, pictures) = try fixtureResolution(fixture[0], scene: fixture[1])
        let screen = try #require(resolution.accessoryScreens.first)
        let still = try #require(pictures["vmu.p1"])
        var whole = Skin2RenderOptions(screenPlaceholders: true)
        whole.pictures = pictures
        let expectedImage = try #require(Skin2Renderer.image(resolution, scale: 2, options: whole))
        let expected = try #require(Pixels(expectedImage))

        let size = resolution.environment.size
        let w = Int(size.width * 2), h = Int(size.height * 2)
        let ctx = try #require(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Skin2Color2CG.sRGB,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 2, y: -2)
        var under = Skin2RenderOptions(screenPlaceholders: true)
        under.part = .upTo(screen: screen.pointer)
        Skin2Renderer.draw(resolution, in: ctx, options: under)
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.drawTopDown(still, in: screen.frame.cg)
        ctx.restoreGState()
        var over = Skin2RenderOptions(screenPlaceholders: true)
        over.part = .after(screen: screen.pointer)
        Skin2Renderer.draw(resolution, in: ctx, options: over)
        let composedImage = try #require(ctx.makeImage())
        let composed = try #require(Pixels(composedImage))
        #expect(composed.identical(expected))

        // The parts differ from each other and neither draws the screen itself.
        let underImage = try #require(Skin2Renderer.image(resolution, scale: 2, options: under))
        let overImage = try #require(Skin2Renderer.image(resolution, scale: 2, options: over))
        let underOnly = try #require(Pixels(underImage)), overOnly = try #require(Pixels(overImage))
        #expect(!underOnly.identical(overOnly))
        #expect(!underOnly.identical(expected) && !overOnly.identical(expected))
    }

    @Test("Three parts split at two screens")
    func betweenTwoScreens() throws {
        func rect(_ color: String, _ x: Int) -> String {
            ##"{ "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [\##(x), 0, 10, 10] }, "fills": [ { "type": "solid", "color": "\##(color)" } ] }"##
        }
        func lcd(_ id: String, _ source: String) -> String {
            #"{ "type": "screen", "id": "\#(id)", "source": "\#(source)", "layout": { "frame": [0, 20, 48, 32] } }"#
        }
        let doc = try renderSkin([rect("#FF0000", 0), lcd("one", "vmu.p1"), rect("#00FF00", 10), lcd("two", "vmu.p2"), rect("#0000FF", 20)].joined(separator: ","),
                                 extra: #""optional": ["screens.accessory"]"#)
        let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100)))
        let screens = r.accessoryScreens.map(\.pointer)
        func alphas(_ part: Skin2DrawPart) throws -> [UInt8] {
            var options = Skin2RenderOptions()
            options.part = part
            let image = try #require(Skin2Renderer.image(r, scale: 1, options: options))
            let px = try #require(Pixels(image))
            return [px[5, 5].a, px[15, 5].a, px[25, 5].a]
        }
        #expect(try alphas(.upTo(screen: screens[0])) == [255, 0, 0])
        #expect(try alphas(.between(after: screens[0], upTo: screens[1])) == [0, 255, 0])
        #expect(try alphas(.after(screen: screens[1])) == [0, 0, 255])
        #expect(try alphas(.all) == [255, 255, 255])
    }
}

@Suite("Picture store")
@MainActor
struct PictureStoreTests {
    static func image(_ value: UInt8) -> CGImage { Pixels.image([value, value, value, 255], width: 1, height: 1)! }

    @Test("Setting the same image again publishes nothing")
    func storePublishesOnlyOnChange() {
        let store = Skin2PictureStore()
        var changes = 0, sources: [String] = []
        let a = store.objectWillChange.sink { changes += 1 }
        let b = store.didChange.sink { sources.append($0) }
        let one = Self.image(1)
        store.set(one, for: "vmu.p1")
        store.set(one, for: "vmu.p1")
        #expect(changes == 1 && sources == ["vmu.p1"])
        store.set(Self.image(2), for: "vmu.p1")
        store.set(nil, for: "vmu.p1")
        store.set(nil, for: "vmu.p1")
        #expect(changes == 3 && sources.count == 3)
        _ = (a, b)
    }

    @Test("delivered follows set and clear")
    func storeDeliveredFollowsSetAndClear() {
        let store = Skin2PictureStore()
        var seen: [Set<String>] = []
        let c = store.deliveredChanges.sink { seen.append($0) }
        #expect(store.delivered.isEmpty && store.image(for: "vmu.p1") == nil)
        store.set(Self.image(1), for: "vmu.p1")
        store.set(Self.image(2), for: "vmu.p1")
        store.set(Self.image(3), for: "vmu.p2")
        #expect(store.delivered == ["vmu.p1", "vmu.p2"] && store.image(for: "vmu.p2") != nil)
        store.set(nil, for: "vmu.p1")
        #expect(store.delivered == ["vmu.p2"])
        // The current set first, then one value per change of the set: a new image for a source already there is not one.
        #expect(seen == [[], ["vmu.p1"], ["vmu.p1", "vmu.p2"], ["vmu.p2"]])
        _ = c
    }
}

private final class PanelSink: Skin2InputSink {
    var log: [String] = []
    func press(_ input: String) { log.append("+\(input)") }
    func release(_ input: String) { log.append("-\(input)") }
    func stick(_ input: String, x: Double, y: Double) {}
    func surface(_ input: String, point: Skin2SurfacePoint?) {}
    func action(_ name: String) { log.append("action \(name)") }
}

@Suite("Panel handles and held inputs")
struct PanelTouchTests {
    /// A shelf with a coin button in it, and an A button outside.
    static func tester(open: Bool, capabilities: Set<String> = ["input.arcade.coin1"]) throws -> Skin2HitTester {
        let doc = try renderSkin(#"""
        { "type": "group", "id": "shelf", "panel": { "name": "cab", "presentation": "shelf", "handle": "#tab" },
          "children": [
            { "type": "control", "id": "tab", "kind": "action", "input": "togglePanel", "layout": { "frame": [0, 0, 48, 48] } },
            { "type": "control", "id": "coin", "kind": "button", "input": "arcade.coin1", "layout": { "frame": [50, 0, 48, 48] } } ] },
        { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 50, 48, 48] } }
        """#, requires: "[]", extra: #""optional": ["panels", "inputs.semantic"]"#)
        let environment = Skin2Environment(size: Skin2Size(width: 100, height: 100), flags: open ? ["panel.cab.open"] : [], capabilities: capabilities)
        return Skin2HitTester(Skin2Resolver.resolve(doc, in: environment))
    }

    @Test("A touch on a handle toggles its panel and is not an input")
    func handleTouchTogglesAndSendsNoInput() throws {
        let tester = try Self.tester(open: false)
        var tracker = Skin2TouchTracker<Int>(tester: tester)
        tracker.began(1, x: 24, y: 24)
        let down = tracker.snapshot()
        #expect(skin2PanelToggles(from: .empty, to: down, tester: tester) == ["cab"])
        #expect(skin2InputEvents(from: .empty, to: down, tester: tester).isEmpty)
        // Holding and lifting toggle nothing more.
        #expect(skin2PanelToggles(from: down, to: down, tester: tester).isEmpty)
        tracker.ended(1)
        #expect(skin2PanelToggles(from: down, to: tracker.snapshot(), tester: tester).isEmpty)
        #expect(skin2InputEvents(from: down, to: tracker.snapshot(), tester: tester).isEmpty)
        // Other controls are unaffected.
        tracker.began(2, x: 24, y: 74)
        #expect(skin2PanelToggles(from: .empty, to: tracker.snapshot(), tester: tester).isEmpty)
        #expect(skin2InputEvents(from: .empty, to: tracker.snapshot(), tester: tester).map(\.control.id) == ["a"])
    }

    /// Holds the coin, changes the layout to `next`, and returns what the sink saw, following the host's rule:
    /// a held control missing from the new layout lets go of everything.
    static func holdCoinThenChange(to next: Skin2HitTester) throws -> [String] {
        let open = try tester(open: true)
        var tracker = Skin2TouchTracker<Int>(tester: open)
        var bridge = Skin2InputBridge()
        let sink = PanelSink()
        tracker.began(1, x: 74, y: 24)
        let held = tracker.snapshot()
        for event in skin2InputEvents(from: .empty, to: held, tester: open) { bridge.handle(event, sink: sink) }
        #expect(sink.log == ["+arcade.coin1"])
        #expect(held.holdsControls(missingFrom: next))
        tracker.removeAll()
        for event in skin2InputEvents(from: held, to: tracker.snapshot(), tester: open) { bridge.handle(event, sink: sink) }
        bridge.releaseAll(sink: sink)
        return sink.log
    }

    @Test("Closing a shelf releases an input held inside it")
    func closingShelfReleasesHeldInputs() throws {
        #expect(try Self.holdCoinThenChange(to: try Self.tester(open: false)) == ["+arcade.coin1", "-arcade.coin1"])
    }

    @Test("Losing a capability releases the input it carried")
    func capabilityLossReleasesHeldInputs() throws {
        let without = try Self.tester(open: true, capabilities: [])
        #expect(without.control(id: "coin") == nil && without.control(id: "tab") != nil)
        #expect(try Self.holdCoinThenChange(to: without) == ["+arcade.coin1", "-arcade.coin1"])
    }
}

@Suite("Blending two layouts")
struct LayoutBlendTests {
    @Test("A shelf slides and its contents fade between closed and open")
    func blendShelf() throws {
        let (closed, _) = try fixtureResolution("panels", scene: "closed")
        let (open, _) = try fixtureResolution("panels", scene: "open")
        #expect(Skin2LayoutBlend.blend(from: closed, to: open, progress: 1) == open)
        #expect(Skin2LayoutBlend.blend(from: open, to: closed, progress: 1) == closed)
        let x0 = try #require(closed.node(id: "vmuPanel")?.frame.x), x1 = try #require(open.node(id: "vmuPanel")?.frame.x)
        #expect(x0 - x1 > 100)
        for (from, to) in [(closed, open), (open, closed)] {
            let half = Skin2LayoutBlend.blend(from: from, to: to, progress: 0.5)
            #expect(half.node(id: "vmuPanel")?.frame.x == (x0 + x1) / 2)
            // The LCD exists only in the open layout: it rides with its group and is half faded.
            let lcd = try #require(half.node(id: "vmu.lcd")), openLCD = try #require(open.node(id: "vmu.lcd"))
            #expect(abs(lcd.frame.x - (openLCD.frame.x + (x0 - x1) / 2)) < 0.001 && lcd.opacity == 0.5)
            #expect(half.node(id: "a")?.frame == open.node(id: "a")?.frame)
        }
        let start = Skin2LayoutBlend.blend(from: closed, to: open, progress: 0)
        #expect(start.node(id: "vmuPanel")?.frame.x == x0 && start.node(id: "vmu.lcd")?.opacity == 0)
        #expect(start.node(id: "vmuTab")?.frame == closed.node(id: "vmuTab")?.frame)
    }

    @Test("A node's drawn opacity multiplies down the tree")
    func effectiveOpacity() throws {
        let doc = try renderSkin(#"""
        { "type": "group", "id": "g", "opacity": 0.5, "children": [
          { "type": "screen", "id": "lcd", "source": "vmu.p1", "opacity": 0.5, "layout": { "frame": [0, 0, 48, 32] } } ] }
        """#, extra: #""optional": ["screens.accessory"]"#)
        let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100)))
        let lcd = try #require(r.node(id: "lcd"))
        #expect(r.effectiveOpacity(of: lcd.pointer) == 0.25)
        #expect(r.effectiveOpacity(of: "/root") == 1)
        #expect(r.effectiveOpacity(of: "/root/children/9") == 1)
    }
}
