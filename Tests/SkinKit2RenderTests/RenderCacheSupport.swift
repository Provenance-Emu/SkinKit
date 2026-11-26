import CoreGraphics
import Foundation
import SkinKit2Core
@testable import SkinKit2Render

/// Skins and canvases for the render cache's tests and benchmark.
enum CacheFixtures {
    /// The `states` fixture with what makes a redraw dear and an overlap hard: a blurred glow under the thumbstick,
    /// a shadowed panel under the d-pad, shadows on the start button, and two nodes drawn above the controls that
    /// overlap them (a translucent `overlay`-blended sheen over the stick and the d-pad, and a shadowed badge over
    /// the A button).
    static func heavyDocument() throws -> Skin2Document {
        guard var json = try JSONSerialization.jsonObject(with: RenderPaths.skinData("states")) as? [String: Any],
              var root = json["root"] as? [String: Any], var children = root["children"] as? [[String: Any]] else {
            throw RenderTestError("states/skin.json is not the shape the cache fixture expects")
        }
        json["requires"] = (json["requires"] as? [String] ?? []) + ["effects.blur", "effects.blend"]
        json["identifier"] = "com.skinkit.tests.cache-heavy"
        func shape(_ kind: String, _ w: Any, _ h: Any, x: String, _ dx: Double, _ dy: Double, fills: [[String: Any]],
                   effects: [[String: Any]], opacity: Double? = nil) -> [String: Any] {
            var node: [String: Any] = [
                "type": "shape", "shape": ["kind": kind], "fills": fills, "effects": effects,
                "layout": ["size": ["width": w, "height": h], "anchor": ["x": x, "y": "bottom", "to": "safeArea"],
                           "offset": ["x": dx, "y": dy]],
            ]
            if let opacity { node["opacity"] = opacity }
            return node
        }
        let under: [[String: Any]] = [
            shape("ellipse", 170, 170, x: "leading", 0, 10, fills: [["type": "solid", "color": "#9E7AF2"]],
                  effects: [["type": "blur", "radius": 14]], opacity: 0.6),
            shape("rect", 160, 160, x: "leading", 5, -135, fills: [["type": "linear", "start": [0.5, 0], "end": [0.5, 1], "stops": [["#34343F", 0], ["#22222A", 1]]]],
                  effects: [["type": "shadow", "color": "#000000", "opacity": 0.7, "radius": 10, "offset": [0, 4]],
                            ["type": "shadow", "color": "#FFFFFF", "opacity": 0.2, "radius": 2, "offset": [0, -1], "inner": true]]),
            shape("capsule", 130, 70, x: "trailing", -22, -28, fills: [["type": "solid", "color": "#52A0FF"]],
                  effects: [["type": "blur", "radius": 10]], opacity: 0.5),
        ]
        let over: [[String: Any]] = [
            shape("ellipse", 200, 120, x: "leading", -10, -100,
                  fills: [["type": "linear", "start": [0.5, 0], "end": [0.5, 1], "stops": [["#FFFFFF", 0], ["#FFFFFF00", 1]]]],
                  effects: [["type": "blend", "mode": "overlay"]], opacity: 0.5),
            shape("ellipse", 26, 26, x: "trailing", -14, -200, fills: [["type": "solid", "color": "#F24D47"]],
                  effects: [["type": "shadow", "color": "#000000", "opacity": 0.6, "radius": 5, "offset": [0, 2]]]),
        ]
        children.insert(contentsOf: under, at: 2)
        children.append(contentsOf: over)
        root["children"] = children
        json["root"] = root
        return try Skin2Document.load(data: JSONSerialization.data(withJSONObject: json))
    }

    static func resolution(_ document: Skin2Document, _ trait: Skin2TraitSet = phone) -> Skin2Resolution {
        Skin2Resolver.resolve(document, in: trait.environment)
    }

    static func fixture(_ name: String, _ trait: Skin2TraitSet = phone) throws -> Skin2Resolution {
        resolution(try Skin2Document.load(data: RenderPaths.skinData(name)), trait)
    }

    static let phone = Skin2TraitSet.all.first { $0.name == "iphone-edgeToEdge-portrait" }!

    static func options(_ fixture: String? = nil, states: [String: Skin2ControlState] = [:]) -> Skin2RenderOptions {
        guard let fixture else { return Skin2RenderOptions(states: states, screenPlaceholders: true) }
        let assets = RenderPaths.fixtures.appendingPathComponent("\(fixture)/assets", isDirectory: true)
        return Skin2RenderOptions(states: states, screenPlaceholders: true) { try? Data(contentsOf: assets.appendingPathComponent($0)) }
    }

    /// A cleared bitmap the size of `resolution`'s canvas at `scale`, set up like `Skin2Renderer.image`'s (and like a
    /// SwiftUI `Canvas`): user space in points, top-left origin.
    static func canvas(_ resolution: Skin2Resolution, scale: CGFloat) -> CGContext {
        let size = resolution.environment.size
        let w = Int((CGFloat(size.width) * scale).rounded()), h = Int((CGFloat(size.height) * scale).rounded())
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        return ctx
    }

    /// What a `Canvas` does before each redraw.
    static func clear(_ ctx: CGContext) {
        ctx.saveGState()
        ctx.concatenate(ctx.ctm.inverted())
        ctx.clear(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        ctx.restoreGState()
    }

    /// A thumb circling a stick: `count` touch-moves.
    static func stickSweep(_ id: String, count: Int) -> [[String: Skin2ControlState]] {
        (0..<count).map { i in
            let a = Double(i) / Double(count) * 2 * .pi
            return [id: Skin2ControlState(pressed: true, stick: Skin2StickValue(x: 0.9 * cos(a), y: 0.9 * sin(a)))]
        }
    }

    /// The display frames of a press easing in over 80 ms at 120 Hz.
    static func pressEase(_ id: String) -> [[String: Skin2ControlState]] {
        (1...10).map { [id: Skin2ControlState(pressed: true, scaleProgress: Double($0) / 10)] }
    }
}
