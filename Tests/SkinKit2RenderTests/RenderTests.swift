import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

/// A minimal skin around `children` (one root group), for unit tests.
func renderSkin(_ children: String, requires: String = "[\"shapes.parametric\"]", extra: String = "") throws -> Skin2Document {
    try Skin2Document.load(data: Data("""
    { "formatVersion": "2.0", "requires": \(requires), "identifier": "test", "name": "Test",
      "gameTypes": ["com.rileytestut.delta.game.snes"], "reference": { "shortSide": 100, "minScale": 1, "maxScale": 1 }
      \(extra.isEmpty ? "" : ", " + extra),
      "root": { "type": "group", "children": [ \(children) ] } }
    """.utf8))
}

func render(_ doc: Skin2Document, width: Double = 100, height: Double = 100, scale: CGFloat = 1,
            states: [String: Skin2ControlState] = [:]) throws -> Pixels {
    let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: width, height: height)))
    let image = try #require(Skin2Renderer.image(r, scale: scale, options: Skin2RenderOptions(states: states)))
    return try #require(Pixels(image))
}

@Suite("Format 2.0 renderer")
struct RenderTests {
    @Test("Colours are sRGB: #808080 reads back as 0x80")
    func srgb() throws {
        let doc = try renderSkin(##"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "#808080" } ] }"##)
        let px = try render(doc)
        #expect(px[50, 50].r == 0x80 && px[50, 50].g == 0x80 && px[50, 50].b == 0x80 && px[50, 50].a == 0xFF)
    }

    @Test("Top-left origin, y down")
    func orientation() throws {
        let doc = try renderSkin(##"""
        { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [0, 0, 100, 20] },
          "fills": [ { "type": "solid", "color": "#FF0000" } ] }
        """##)
        let px = try render(doc, scale: 2)
        #expect(px[100, 10].r == 255 && px[100, 10].a == 255)
        #expect(px[100, 190].a == 0)
    }

    @Test("A drop shadow falls below the shape and scales with the context", arguments: [CGFloat(1), CGFloat(2)])
    func shadowDirection(_ scale: CGFloat) throws {
        let doc = try renderSkin(##"""
        { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [30, 30, 40, 40] },
          "fills": [ { "type": "solid", "color": "#FFFFFF" } ],
          "effects": [ { "type": "shadow", "color": "#000000", "radius": 0, "offset": [0, 10] } ] }
        """##, requires: "[\"shapes.parametric\", \"effects.shadow\"]")
        let px = try render(doc, scale: scale)
        let s = Int(scale)
        // Below the rect: shadow. Above it: nothing.
        #expect(px[50 * s, 75 * s].a == 255 && px[50 * s, 75 * s].r == 0)
        #expect(px[50 * s, 25 * s].a == 0)
        // Inside: the white fill on top.
        #expect(px[50 * s, 50 * s].r == 255)
        // The shadow ends 10 points below the rect at either scale.
        #expect(px[50 * s, 79 * s].a == 255)
        #expect(px[50 * s, 81 * s].a == 0)
    }

    @Test("A blurred shadow spreads about σ = radius / 2")
    func shadowBlur() throws {
        let doc = try renderSkin(##"""
        { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [30, 30, 40, 40] },
          "fills": [ { "type": "solid", "color": "#FFFFFF" } ],
          "effects": [ { "type": "shadow", "color": "#000000", "radius": 8, "offset": [0, 0] } ] }
        """##, requires: "[\"shapes.parametric\", \"effects.shadow\"]")
        let px = try render(doc)
        // At the edge a Gaussian edge is half covered; 3σ (12 pt) out it is gone.
        #expect((100...160).contains(Int(px[50, 70].a)) || (100...160).contains(Int(px[50, 71].a)))
        #expect(px[50, 84].a < 8)
    }

    @Test("Group opacity composites the subtree once")
    func groupOpacity() throws {
        let doc = try renderSkin(##"""
        { "type": "group", "opacity": 0.5, "children": [
          { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [0, 0, 60, 100] }, "fills": [ { "type": "solid", "color": "#000000" } ] },
          { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [40, 0, 60, 100] }, "fills": [ { "type": "solid", "color": "#000000" } ] } ] }
        """##)
        let px = try render(doc)
        // The overlap is as transparent as either half: no double darkening.
        #expect(abs(Int(px[50, 50].a) - Int(px[20, 50].a)) <= 1)
        #expect((126...129).contains(Int(px[20, 50].a)))
    }

    @Test("Text draws glyph outlines from the bundled font")
    func text() throws {
        #expect(Skin2Text.defaultFont(.regular) != nil)
        #expect(Skin2Text.defaultFont(.bold) != nil)
        let doc = try renderSkin(##"""
        { "type": "text", "text": "AB", "font": { "size": 40, "weight": "bold" }, "color": "#000000", "align": "center" }
        """##, requires: "[\"text\"]")
        let px = try render(doc)
        let inked = stride(from: 0, to: px.bytes.count, by: 4).filter { px.bytes[$0 + 3] > 128 }.count
        #expect(inked > 300)
        #expect(px[2, 2].a == 0)
    }

    @Test("fit shrinks the text to the frame, down to 60 %")
    func textFit() throws {
        let font = try #require(Skin2Text.defaultFont(.regular))
        let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        let full = Skin2Text.path("WWWWWW", font: font, size: 20, align: .leading, fit: false, in: frame).boundingBoxOfPath
        let fitted = Skin2Text.path("WWWWWW", font: font, size: 20, align: .leading, fit: true, in: frame).boundingBoxOfPath
        #expect(full.width > 40)
        #expect(fitted.width < full.width)
        #expect(fitted.width >= full.width * 0.59)
    }

    @Test("Pressed states scale the control and patch its art; highlight art draws only while pressed")
    func states() throws {
        let doc = try renderSkin(##"""
        { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 100, 100] },
          "states": { "pressed": { "scale": 0.5, "patch": [ { "target": "#body", "fills": [ { "type": "solid", "color": "#0000FF" } ] } ] } },
          "children": [
            { "type": "shape", "id": "body", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "#FF0000" } ] },
            { "type": "shape", "role": "highlight", "shape": { "kind": "rect" }, "layout": { "frame": [45, 45, 10, 10] },
              "fills": [ { "type": "solid", "color": "#00FF00" } ] } ] }
        """##, requires: "[\"shapes.parametric\", \"states\"]")
        let rest = try render(doc)
        #expect(rest[5, 5].r == 255 && rest[50, 50].r == 255)
        let pressed = try render(doc, states: ["a": Skin2ControlState(pressed: true)])
        #expect(pressed[5, 5].a == 0)
        #expect(pressed[30, 30].b == 255)
        #expect(pressed[50, 50].g == 255)
        // Halfway through the 80 ms ease: scale 0.75.
        let easing = try render(doc, states: ["a": Skin2ControlState(pressed: true, scaleProgress: 0.5)])
        #expect(easing[15, 15].b == 255 && easing[10, 10].a == 0)
        // Easing back out after release: only the scale remains; the art is at rest (red, no highlight).
        let release = try render(doc, states: ["a": Skin2ControlState(scaleProgress: 0.5, easingOut: true)])
        #expect(release[15, 15].r == 255 && release[10, 10].a == 0)
        #expect(release[50, 50].r == 255 && release[50, 50].g == 0)
    }

    @Test("Repeat copies take per-copy state patches (#arrow[i])")
    func copyPatches() throws {
        let doc = try renderSkin(##"""
        { "type": "control", "id": "dpad", "kind": "dpad", "input": { "up": "up", "down": "down", "left": "left", "right": "right" },
          "layout": { "frame": [0, 0, 100, 100] },
          "states": { "pressed.right": { "patch": [ { "target": "#arrow[1]", "fills": [ { "type": "solid", "color": "#FF0000" } ] } ] } },
          "children": [
            { "type": "shape", "id": "arrow", "shape": { "kind": "rect" }, "layout": { "frame": [45, 5, 10, 10] },
              "repeat": { "count": 4, "rotate": 90, "pivot": "parent" },
              "fills": [ { "type": "solid", "color": "#000000" } ] } ] }
        """##, requires: "[\"shapes.parametric\", \"states\", \"layout.repeat\", \"controls.dpad\"]")
        let rest = try render(doc)
        #expect(rest[90, 50].a == 255 && rest[90, 50].r == 0)
        let right = try render(doc, states: ["dpad": Skin2ControlState(directions: [.right])])
        #expect(right[90, 50].r == 255)
        #expect(right[50, 10].r == 0 && right[50, 10].a == 255)
    }

    @Test("The thumbstick knob follows the stick value within travel")
    func knob() throws {
        let doc = try renderSkin(##"""
        { "type": "control", "id": "stick", "kind": "thumbstick", "input": "leftThumbstick", "travel": 30,
          "layout": { "frame": [0, 0, 100, 100] },
          "children": [ { "type": "shape", "role": "knob", "shape": { "kind": "ellipse" }, "layout": { "size": { "width": 20, "height": 20 } },
                          "fills": [ { "type": "solid", "color": "#000000" } ] } ] }
        """##, requires: "[\"shapes.parametric\", \"controls.thumbstick\"]")
        let rest = try render(doc)
        #expect(rest[50, 50].a == 255 && rest[80, 50].a == 0)
        let moved = try render(doc, states: ["stick": Skin2ControlState(pressed: true, stick: Skin2StickValue(x: 1, y: 0))])
        #expect(moved[80, 50].a == 255 && moved[50, 50].a == 0)
    }

    @Test("Every parametric kind draws inside its frame")
    func shapeKinds() throws {
        let rect = CGRect(x: 10, y: 20, width: 80, height: 40)
        for kind in Skin2ShapeKind.allCases where kind != .path && kind != .line {
            var json = #"{"kind": "\#(kind.rawValue)""#
            switch kind {
            case .polygon: json += #", "sides": 6"#
            case .star: json += #", "points": 5"#
            case .arc: json += #", "startAngle": 0, "endAngle": 270"#
            default: break
            }
            json += "}"
            let shape = try JSONDecoder().decode(Skin2Shape.self, from: Data(json.utf8))
            let b = Skin2Shapes.path(for: shape, in: rect, unit: 1).boundingBoxOfPath
            #expect(!b.isEmpty, "\(kind)")
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(b), "\(kind): \(b) outside \(rect)")
        }
    }
}

@Suite("SVG path data")
struct SVGPathTests {
    func bounds(_ d: String) -> CGRect { Skin2SVGPath.parse(d).boundingBoxOfPath }

    @Test("Absolute and relative lines, H and V")
    func lines() {
        #expect(bounds("M10 10 L20 10 L20 20 Z") == CGRect(x: 10, y: 10, width: 10, height: 10))
        #expect(bounds("m10 10 l10 0 l0 10 z") == CGRect(x: 10, y: 10, width: 10, height: 10))
        #expect(bounds("M0 0 H30 V5 h-10 v10") == CGRect(x: 0, y: 0, width: 30, height: 15))
        // Pairs after a moveto are linetos.
        #expect(bounds("M0 0 10 0 10 10") == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("Compact numbers: 1.5.5, -1-2, exponents")
    func numbers() {
        #expect(bounds("M0 0L1.5.5") == CGRect(x: 0, y: 0, width: 1.5, height: 0.5))
        #expect(bounds("M0 0L-1-2") == CGRect(x: -1, y: -2, width: 1, height: 2))
        #expect(bounds("M0 0L1e1 2E0") == CGRect(x: 0, y: 0, width: 10, height: 2))
    }

    @Test("C S Q T curves stay within their control hull")
    func curves() {
        let c = bounds("M0 0 C0 10 10 10 10 0 S20 -10 20 0")
        #expect(c.minX == 0 && c.maxX == 20 && c.maxY > 5 && c.minY < -5)
        let q = bounds("M0 0 Q5 10 10 0 T20 0")
        #expect(q.maxX == 20 && q.maxY > 4 && q.minY < -4)
    }

    @Test("Arcs: a half circle reaches its radius; compact flags parse")
    func arcs() {
        let a = bounds("M0 0 A10 10 0 0 1 20 0")
        #expect(abs(a.width - 20) < 0.01 && abs(a.minY + 10) < 0.05)
        let b = bounds("M0 0 a10 10 0 0 0 20 0")
        #expect(abs(b.maxY - 10) < 0.05)
        let compact = bounds("M0 0a10 10 0 0120 0")
        #expect(abs(compact.minY + 10) < 0.05)
    }

    @Test("The box stretches non-uniformly onto the frame")
    func box() {
        let p = Skin2SVGPath.path("M0 0 L1 1", box: CGRect(x: 0, y: 0, width: 1, height: 1), in: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(p.boundingBoxOfPath == CGRect(x: 10, y: 20, width: 100, height: 50))
    }

    @Test("Malformed data stops at the last complete command")
    func malformed() {
        #expect(bounds("M0 0 L10 10 L5") == CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(Skin2SVGPath.parse("hello").isEmpty)
    }
}

@Suite("Hit testing")
struct HitTestingTests {
    func resolution(_ json: String) throws -> Skin2Resolution {
        let doc = try renderSkin(json, requires: "[\"shapes.parametric\", \"controls.dpad\", \"controls.thumbstick\", \"controls.touchSurface\"]")
        return Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 300, height: 300)))
    }

    @Test("The last control in document order wins; touch surfaces sit underneath; hit.extend counts")
    func order() throws {
        let r = try resolution(##"""
        { "type": "control", "id": "touch", "kind": "touchSurface", "inputs": ["touchScreen"], "layout": { "frame": [0, 0, 300, 300] } },
        { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [100, 100, 50, 50] }, "hit": { "extend": 10 } },
        { "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "frame": [160, 100, 50, 50] } }
        """##)
        let t = Skin2HitTester(r)
        #expect(t.control(at: 125, 125)?.id == "a")
        #expect(t.control(at: 95, 125)?.id == "a")
        #expect(t.control(at: 185, 125)?.id == "b")
        #expect(t.control(at: 10, 10)?.id == "touch")
        let p = Skin2HitTester.surfacePoint(frame: t.control(id: "touch")!.frame, x: 150, y: 75)
        #expect(p.x == 0.5 && p.y == 0.25)
    }

    @Test("D-pad: 3 × 3 zones around a 20 % dead zone; corners press two")
    func dpad() {
        let f = Skin2Rect(x: 0, y: 0, width: 100, height: 100)
        #expect(Skin2HitTester.dpadDirections(in: f, x: 50, y: 50) == [])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 58, y: 42) == [])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 50, y: 10) == [.up])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 90, y: 50) == [.right])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 90, y: 90) == [.down, .right])
        #expect(Skin2HitTester.dpadDirections(in: f, x: 5, y: 5) == [.up, .left])
    }

    @Test("Thumbstick: offset over travel, clamped to the unit circle")
    func stick() throws {
        let f = Skin2Rect(x: 0, y: 0, width: 100, height: 100)
        let half = Skin2HitTester.stickValue(frame: f, travel: 20, x: 60, y: 50)
        #expect(half.x == 0.5 && half.y == 0)
        let far = Skin2HitTester.stickValue(frame: f, travel: 20, x: 150, y: 150)
        #expect(abs(far.x - 0.7071) < 0.001 && abs(far.y - 0.7071) < 0.001)

        let r = try resolution(##"""
        { "type": "control", "id": "dpad", "kind": "dpad", "input": { "up": "up", "down": "down", "left": "left", "right": "right" },
          "layout": { "frame": [0, 0, 100, 100] } }
        """##)
        let c = try #require(Skin2HitTester(r).control(id: "dpad"))
        let s = Skin2HitTester.state(for: c, x: 95, y: 5)
        #expect(Skin2HitTester.inputs(for: c, state: s) == ["up", "right"])
    }

    @Test("Every GameCube control takes a touch at the centre of its hit frame")
    func gamecube() throws {
        let doc = try Skin2Document.load(data: RenderPaths.skinData("gamecube-icube"))
        let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 393, height: 852),
                                                                 safeArea: Skin2Insets(top: 59, left: 0, bottom: 34, right: 0)))
        let t = Skin2HitTester(r)
        for c in t.controls {
            #expect(t.control(at: c.hitFrame.midX, c.hitFrame.midY)?.id == c.id, "\(c.id)")
        }
    }
}
