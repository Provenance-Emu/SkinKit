import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

@Suite("Accessory screen drawing")
struct AccessoryScreenRenderTests {
    /// A red canvas with a 96×64 pt accessory screen at the origin: one LCD cell is 2 pt, 4 px at 2×.
    static func skin(sampling: String = "nearest", after: String = "") throws -> Skin2Document {
        try renderSkin(##"""
        { "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "#FF0000" } ] },
        { "type": "screen", "id": "lcd", "source": "vmu.p1", "sampling": "\##(sampling)", "layout": { "frame": [0, 0, 96, 64] } }
        \##(after)
        """##, extra: #""optional": ["screens.accessory"]"#)
    }

    static func pixels(_ doc: Skin2Document, pictures: [String: CGImage] = [:], placeholders: Bool = false) throws -> Pixels {
        let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100)))
        var options = Skin2RenderOptions(screenPlaceholders: placeholders)
        options.pictures = pictures
        let image = try #require(Skin2Renderer.image(r, scale: 2, options: options))
        return try #require(Pixels(image))
    }

    static func rgb(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> [UInt8] { [p.r, p.g, p.b] }

    @Test("A supplied picture fills the frame cell for cell")
    func oneShotDrawsSuppliedPictureWithNearestSampling() throws {
        let pictures = Skin2Fixtures.pictures("accessory-screen")
        let still = try #require(pictures["vmu.p1"])
        let card = try #require(Pixels(still))
        #expect(card.width == 48 && card.height == 32)
        let px = try Self.pixels(try Self.skin(), pictures: pictures)
        var mismatches = 0
        for y in 0..<32 { for x in 0..<48 where Self.rgb(px[x * 4 + 2, y * 4 + 2]) != Self.rgb(card[x, y]) { mismatches += 1 } }
        #expect(mismatches == 0)
        // Nearest sampling keeps cells hard: both pixels beside a cell edge are one of the card's two colours.
        #expect(Self.rgb(px[3, 6]) == Self.rgb(card[0, 1]) && Self.rgb(px[4, 6]) == Self.rgb(card[1, 1]))
        // Outside the frame, and everywhere when no picture was handed over: the fill behind.
        #expect(Self.rgb(px[196, 10]) == [255, 0, 0])
        #expect(Self.rgb(try Self.pixels(try Self.skin())[2, 2]) == [255, 0, 0])
    }

    @Test("Linear sampling blends neighbouring cells")
    func linearSamplingBlends() throws {
        let pictures = Skin2Fixtures.pictures("accessory-screen")
        let still = try #require(pictures["vmu.p1"])
        let card = try #require(Pixels(still))
        let px = try Self.pixels(try Self.skin(sampling: "linear"), pictures: pictures)
        let edge = Self.rgb(px[4, 6])
        #expect(edge != Self.rgb(card[0, 1]) && edge != Self.rgb(card[1, 1]))
    }

    @Test("Nodes listed after an accessory screen draw over it")
    func nodesAfterAccessoryScreenDrawOverIt() throws {
        let glass = ##", { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [0, 0, 96, 64] }, "fills": [ { "type": "solid", "color": "#FF000080" } ] }"##
        let pictures = Skin2Fixtures.pictures("accessory-screen")
        let plain = try Self.pixels(try Self.skin(), pictures: pictures)
        let covered = try Self.pixels(try Self.skin(after: glass), pictures: pictures)
        #expect(covered[10, 10].r > plain[10, 10].r)
        #expect(covered[10, 10].g < plain[10, 10].g)
    }

    @Test("A preview without a picture shows a placeholder")
    func placeholder() throws {
        let px = try Self.pixels(try Self.skin(), placeholders: true)
        #expect(Self.rgb(px[10, 10]) == [0x10, 0x10, 0x18])
    }

    @Test("A state patch's has condition reads the environment's capabilities")
    func statePatchHas() throws {
        let doc = try renderSkin(##"""
        { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 50, 50] },
          "states": { "pressed": { "patch": [ { "target": "#dot", "visible": { "has": "picture.vmu.p1" } } ] } },
          "children": [ { "type": "shape", "id": "dot", "shape": { "kind": "rect" },
                          "fills": [ { "type": "solid", "color": "#00FF00" } ] } ] }
        """##, requires: #"["shapes.parametric", "states"]"#, extra: #""optional": ["capabilities"]"#)
        func alpha(_ capabilities: Set<String>) throws -> UInt8 {
            let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100), capabilities: capabilities))
            let options = Skin2RenderOptions(states: ["a": Skin2ControlState(pressed: true)])
            let image = try #require(Skin2Renderer.image(r, scale: 1, options: options))
            return try #require(Pixels(image))[25, 25].a
        }
        #expect(try alpha([]) == 0)
        #expect(try alpha(["picture.vmu.p1"]) == 255)
    }
}
