import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Layout resolver")
struct ResolverTests {
    /// 390 × 844 at unit 1, no safe area unless given.
    static func env(_ w: Double = 390, _ h: Double = 844, safe: Skin2Insets = .zero, device: Skin2Device = .iphone,
                    flags: Set<String> = []) -> Skin2Environment {
        Skin2Environment(size: Skin2Size(width: w, height: h), safeArea: safe, device: device, flags: flags)
    }

    static func resolve(_ children: String, extra: String = "", in env: Skin2Environment = env(), theme: String? = nil,
                        variant: String? = nil, edits: [String: Skin2Edit] = [:]) throws -> Skin2Resolution {
        let doc = try Skin2Document.inline(skinJSON(children: children, extra: extra), theme: theme, variant: variant)
        return Skin2Resolver.resolve(doc, in: env, edits: edits)
    }

    static func frame(_ r: Skin2Resolution, _ id: String) -> Skin2Rect? { r.node(id: id)?.exactFrame }

    @Test("Anchors place a node in its reference area and offsets move it (+x right, +y down)")
    func anchors() throws {
        let r = try Self.resolve(#"""
            { "type": "group", "id": "a", "layout": { "size": { "width": 100, "height": 50 }, "anchor": { "x": "trailing", "y": "bottom" }, "offset": { "x": -10, "y": -20 } } },
            { "type": "group", "id": "b", "layout": { "size": { "width": 100, "height": 50 } } },
            { "type": "group", "id": "c", "layout": { "size": { "width": 20, "height": 10 }, "anchor": { "x": "leading", "y": "top", "to": "#a" } } },
            { "type": "group", "id": "d", "layout": { "size": { "width": 100, "height": 50 }, "anchor": { "x": "center", "y": "bottom", "to": "safeArea" } } }
            """#, in: Self.env(safe: Skin2Insets(top: 47, left: 0, bottom: 34, right: 0)))
        #expect(Self.frame(r, "a") == Skin2Rect(x: 280, y: 774, width: 100, height: 50))
        #expect(Self.frame(r, "b") == Skin2Rect(x: 145, y: 397, width: 100, height: 50))
        #expect(Self.frame(r, "c") == Skin2Rect(x: 280, y: 774, width: 20, height: 10))
        #expect(Self.frame(r, "d") == Skin2Rect(x: 145, y: 760, width: 100, height: 50))
        #expect(r.warnings.isEmpty)
        #expect(r.node(id: "c")?.pointer == "/root/children/2")
    }

    @Test("Percentages follow the reference area; a missing axis comes from aspect; min and max clamp")
    func sizes() throws {
        let r = try Self.resolve(#"""
            { "type": "screen", "id": "s", "aspect": 1.5, "layout": { "size": { "width": "100%" }, "anchor": { "y": "top" } } },
            { "type": "group", "id": "half", "layout": { "size": { "width": "50%" }, "aspect": 2, "maxSize": { "width": 150 } } },
            { "type": "group", "id": "min", "layout": { "size": { "width": "10%", "height": 20 }, "minSize": { "width": 60 } } },
            { "type": "group", "id": "cover", "layout": { "size": { "width": "100%", "height": "50%" }, "anchor": { "to": "#s" } } }
            """#)
        #expect(Self.frame(r, "s") == Skin2Rect(x: 0, y: 0, width: 390, height: 260))
        // The missing axis comes from aspect before the clamp, so clamping one axis leaves the other.
        #expect(Self.frame(r, "half")?.size == Skin2Size(width: 150, height: 97.5))
        #expect(Self.frame(r, "min")?.size == Skin2Size(width: 60, height: 20))
        // anchor.to stands in for the parent: 100% of #s, centred on it.
        #expect(Self.frame(r, "cover") == Skin2Rect(x: 0, y: 65, width: 390, height: 130))
        #expect(r.screens.map(\.id) == ["s"])
    }

    @Test("Point lengths scale by the unit, clamped to the reference range")
    func unitScaling() throws {
        let child = #"{ "type": "group", "id": "g", "layout": { "size": { "width": 100, "height": 100 } } }"#
        #expect(try Self.resolve(child, in: Self.env(468, 1000)).unit == 1.2)
        #expect(try Self.frame(Self.resolve(child, in: Self.env(468, 1000)), "g")?.width == 120)
        #expect(try Self.resolve(child, in: Self.env(1194, 834)).unit == 1.35)
        #expect(try Self.resolve(child, in: Self.env(320, 568)).unit == 1)
    }

    @Test("A stack packs its children with spacing and aligns them across the axis")
    func stacks() throws {
        let r = try Self.resolve(#"""
            { "type": "group", "id": "row", "stack": { "axis": "horizontal", "spacing": 8 }, "children": [
              { "type": "group", "id": "a", "layout": { "size": { "width": 40, "height": 40 } } },
              { "type": "group", "id": "gone", "visible": false, "layout": { "size": { "width": 500, "height": 500 } } },
              { "type": "group", "id": "b", "layout": { "size": { "width": 60, "height": 30 }, "anchor": { "y": "top" } } },
              { "type": "group", "id": "c", "layout": { "size": { "width": 10, "height": 30 } } } ] },
            { "type": "group", "id": "col", "stack": { "axis": "vertical", "distribute": "spaceBetween", "align": "trailing" },
              "layout": { "frame": [0, 0, 100, 300] }, "children": [
              { "type": "group", "id": "x", "layout": { "size": { "width": 50, "height": 50 } } },
              { "type": "group", "id": "y", "layout": { "size": { "width": 20, "height": 50 } } } ] }
            """#)
        #expect(Self.frame(r, "row") == Skin2Rect(x: 132, y: 402, width: 126, height: 40))
        #expect(Self.frame(r, "a") == Skin2Rect(x: 132, y: 402, width: 40, height: 40))
        #expect(r.node(id: "gone") == nil)
        #expect(Self.frame(r, "b") == Skin2Rect(x: 180, y: 402, width: 60, height: 30))
        #expect(Self.frame(r, "c") == Skin2Rect(x: 248, y: 407, width: 10, height: 30))
        #expect(Self.frame(r, "x") == Skin2Rect(x: 50, y: 0, width: 50, height: 50))
        #expect(Self.frame(r, "y") == Skin2Rect(x: 80, y: 250, width: 20, height: 50))
    }

    @Test("A grid fills rows in order with spans; cells are equal")
    func grids() throws {
        let r = try Self.resolve(#"""
            { "type": "group", "id": "grid", "grid": { "columns": 2, "spacing": 10 }, "children": [
              { "type": "group", "id": "a", "layout": { "size": { "width": 40, "height": 40 } } },
              { "type": "group", "id": "b", "layout": { "size": { "width": 30, "height": 30 } } },
              { "type": "group", "id": "wide", "layout": { "size": { "width": 90, "height": 40 }, "span": { "columns": 2 } } } ] },
            { "type": "group", "id": "fixed", "grid": { "columns": 3 }, "layout": { "frame": [0, 0, 300, 100] }, "children": [
              { "type": "group", "id": "k1", "layout": { "size": { "width": "100%", "height": "100%" } } },
              { "type": "group", "id": "k2", "layout": { "size": { "width": "100%", "height": "100%" } } },
              { "type": "group", "id": "k3", "layout": { "size": { "width": "100%", "height": "100%" } } },
              { "type": "group", "id": "k4", "layout": { "size": { "width": "100%", "height": "100%" } } } ] }
            """#)
        #expect(Self.frame(r, "grid") == Skin2Rect(x: 150, y: 377, width: 90, height: 90))
        #expect(Self.frame(r, "a") == Skin2Rect(x: 150, y: 377, width: 40, height: 40))
        #expect(Self.frame(r, "b") == Skin2Rect(x: 205, y: 382, width: 30, height: 30))
        #expect(Self.frame(r, "wide") == Skin2Rect(x: 150, y: 427, width: 90, height: 40))
        #expect(Self.frame(r, "k2") == Skin2Rect(x: 100, y: 0, width: 100, height: 50))
        #expect(Self.frame(r, "k4") == Skin2Rect(x: 0, y: 50, width: 100, height: 50))
    }

    @Test("repeat produces copy transforms; copy 0 is the node itself")
    func repeats() throws {
        let r = try Self.resolve(#"""
            { "type": "shape", "id": "dot", "shape": { "kind": "ellipse" }, "layout": { "size": { "width": 10, "height": 10 } },
              "repeat": { "count": 3, "offset": { "x": 20 } } },
            { "type": "shape", "id": "arrow", "shape": { "kind": "rect" }, "layout": { "frame": [190, 100, 10, 10] },
              "repeat": { "count": 4, "rotate": 90, "pivot": "parent" } }
            """#)
        let dot = try #require(r.node(id: "dot"))
        #expect(dot.copies.count == 3)
        #expect(dot.copies[0] == .identity)
        let p = dot.copies[2].apply(x: 195, y: 422)
        #expect(abs(p.x - 235) < 1e-9 && abs(p.y - 422) < 1e-9)
        let arrow = try #require(r.node(id: "arrow"))
        // A quarter turn about the canvas centre (195, 422) takes the arrow's centre (195, 105) to (512, 422).
        let q = arrow.copies[1].apply(x: 195, y: 105)
        #expect(abs(q.x - 512) < 1e-9 && abs(q.y - 422) < 1e-9)
    }

    @Test("when patches apply in order on matching environments, and visible hides")
    func conditions() throws {
        let children = #"""
            { "type": "group", "id": "g", "layout": { "size": { "width": 100, "height": 100 } },
              "when": [ { "orientation": "landscape", "layout": { "size": { "width": 200 } } },
                        { "device": "ipad", "layout": { "size": { "height": 300 } } },
                        { "flag": "big", "minWidth": 800, "opacity": 0.5 } ] },
            { "type": "group", "id": "phoneOnly", "visible": { "device": "iphone" } },
            { "type": "group", "id": "flagged", "visible": { "flag": "f" } }
            """#
        let portrait = try Self.resolve(children)
        #expect(Self.frame(portrait, "g")?.size == Skin2Size(width: 100, height: 100))
        #expect(portrait.node(id: "phoneOnly") != nil)
        #expect(portrait.node(id: "flagged") == nil)
        let landscape = try Self.resolve(children, in: Self.env(844, 390, flags: ["f"]))
        #expect(Self.frame(landscape, "g")?.size == Skin2Size(width: 200, height: 100))
        #expect(landscape.node(id: "flagged") != nil)
        let pad = try Self.resolve(children, in: Self.env(1194, 834, device: .ipad, flags: ["big"]))
        #expect(pad.node(id: "g")?.node.layout?.size == Skin2SizeLengths(width: .pt(200), height: .pt(300)))
        #expect(pad.node(id: "g")?.opacity == 0.5)
        #expect(pad.node(id: "phoneOnly") == nil)
    }

    @Test("Theme and variant conditions read the loaded document")
    func themeAndVariantConditions() throws {
        let extra = ##""tokens": { "c": "#000000" }, "themes": { "dark": { "c": "#111111" } }, "variants": { "v": { "patch": [] } }"##
        let child = #"{ "type": "group", "id": "g", "when": [ { "theme": "dark", "opacity": 0.5 }, { "variant": "v", "opacity": 0.25 } ] }"#
        #expect(try Self.resolve(child, extra: extra).node(id: "g")?.opacity == 1)
        #expect(try Self.resolve(child, extra: extra, theme: "dark").node(id: "g")?.opacity == 0.5)
        #expect(try Self.resolve(child, extra: extra, variant: "v").node(id: "g")?.opacity == 0.25)
    }

    @Test("Player edits move, scale, fade or hide a node after placement, without reflowing siblings")
    func edits() throws {
        let children = #"""
            { "type": "group", "stack": { "axis": "horizontal" }, "children": [
              { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "size": { "width": 50, "height": 50 } } },
              { "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "size": { "width": 50, "height": 50 } } } ] },
            { "type": "group", "id": "follower", "layout": { "size": { "width": 10, "height": 10 }, "anchor": { "x": "leading", "y": "top", "to": "#a" } } }
            """#
        let base = try Self.resolve(children)
        let b = try #require(Self.frame(base, "b"))
        let edited = try Self.resolve(children, in: Self.env(468, 1000), edits: [
            "a": Skin2Edit(offset: .init(x: 10, y: -5), scale: 2, opacity: 0.5),
        ])
        let ea = try #require(edited.node(id: "a"))
        let scaled = try #require(Self.frame(try Self.resolve(children, in: Self.env(468, 1000)), "a"))
        // Offsets are reference points (× unit 1.2); the scale is about the moved centre.
        #expect(ea.exactFrame.isClose(to: Skin2Rect(x: scaled.midX + 12 - 60, y: scaled.midY - 6 - 60, width: 120, height: 120)))
        #expect(ea.opacity == 0.5)
        let follower = try #require(Self.frame(edited, "follower"))
        #expect(follower.x == ea.exactFrame.x && follower.y == ea.exactFrame.y)
        let hidden = try Self.resolve(children, edits: ["a": Skin2Edit(hidden: true)])
        #expect(hidden.node(id: "a") == nil)
        #expect(Self.frame(hidden, "b") == b)
    }

    @Test("Frames round to half points; hit frames extend; thumbsticks get a travel radius")
    func controlsAndRounding() throws {
        let r = try Self.resolve(#"""
            { "type": "control", "id": "b", "kind": "button", "input": "a", "layout": { "size": { "width": 33.3, "height": 44 } },
              "hit": { "extend": 8 } },
            { "type": "control", "id": "t", "kind": "thumbstick", "input": "analogStick", "layout": { "frame": [0, 0, 100, 100] },
              "children": [ { "type": "shape", "role": "knob", "shape": { "kind": "ellipse" } } ] },
            { "type": "control", "id": "u", "kind": "thumbstick", "input": "analogStick", "travel": 20, "layout": { "frame": [200, 0, 100, 100] },
              "children": [ { "type": "shape", "role": "knob", "shape": { "kind": "ellipse" } } ] }
            """#)
        let b = try #require(r.node(id: "b"))
        #expect(abs(b.exactFrame.x - 178.35) < 1e-9)
        #expect(b.frame == Skin2Rect(x: 178.5, y: 400, width: 33, height: 44))
        #expect(b.hitFrame == Skin2Rect(x: 170.5, y: 392, width: 49, height: 60))
        #expect(r.node(id: "t")?.travel == 35)
        #expect(r.node(id: "u")?.travel == 20)
        #expect(r.controls.map(\.id) == ["b", "t", "u"])
    }

    @Test("Anchoring to something not yet laid out warns and falls back to the parent")
    func forwardReference() throws {
        let r = try Self.resolve(#"""
            { "type": "group", "id": "early", "layout": { "size": { "width": 10, "height": 10 }, "anchor": { "x": "leading", "to": "#late" } } },
            { "type": "group", "id": "s", "layout": { "anchor": { "to": "screen" } } },
            { "type": "group", "id": "late" }
            """#)
        #expect(r.warnings.map(\.pointer) == ["/root/children/0", "/root/children/1"])
        #expect(Self.frame(r, "early")?.x == 0)
    }
}
