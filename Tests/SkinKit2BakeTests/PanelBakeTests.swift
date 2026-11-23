import CoreGraphics
import Foundation
import ImageIO
import SkinKit2Bake
import SkinKitCore
import Testing

private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().appendingPathComponent("Format2Fixtures")

private let notBaked = "panels, accessory screens and semantic controls are not baked"

private func classicInfo(_ bundle: Skin2BakedBundle) throws -> DeltaSkin.Info {
    try JSONDecoder().decode(DeltaSkin.Info.self, from: #require(bundle.files["info.json"]))
}

/// Every classic input name of every baked representation.
private func inputNames(_ info: DeltaSkin.Info) -> [[String]] {
    var out: [[String]] = []
    for (_, device) in info.representations {
        for orientations in [device.standard, device.edgeToEdge, device.splitView].compactMap({ $0 }) {
            for (_, representation) in orientations {
                out.append((representation.items ?? []).flatMap { item -> [String] in
                    switch item.inputs {
                    case .single(let names): return names
                    case .directional(let map): return Array(map.values)
                    }
                })
            }
        }
    }
    return out
}

private func pixels(_ png: Data) throws -> [UInt8] {
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let ctx = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return true
    }
    try #require(ok)
    return bytes
}

/// A shelf and a fixed panel that need nothing, an accessory screen outside any panel and one game screen.
private let bare = """
{ "formatVersion": "2.0", "requires": ["shapes.parametric"], "optional": ["panels", "screens.accessory"],
  "identifier": "com.example.bare", "name": "Bare", "gameTypes": ["com.rileytestut.delta.game.dc"],
  "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1.35 },
  "bake": { "traits": ["iphone.standard", "iphone.edgeToEdge"] },
  "root": { "type": "group", "children": [
    { "type": "screen", "id": "main", "layout": { "frame": [100, 60, 200, 150] } },
    { "type": "screen", "id": "loose", "source": "vmu.p1", "layout": { "frame": [100, 220, 96, 64] } },
    { "type": "group", "id": "shelf", "layout": { "frame": [100, 300, 200, 60] },
      "panel": { "name": "shelf", "presentation": "shelf", "handle": "#tab", "open": true },
      "children": [
        { "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "#FF00FF" } ] },
        { "type": "control", "id": "tab", "kind": "action", "input": "togglePanel", "layout": { "frame": [0, 0, 48, 48] } } ] },
    { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [100, 400, 60, 60] } }
  ] } }
"""

@Test("A baked skin has no panel handle and no semantic control among its items")
func bakedSkinHasNoPanelItems() throws {
    let bundles = try Skin2Baker.bake(sourceURL: fixtures.appendingPathComponent("panels/skin.json"))
    let names = inputNames(try classicInfo(#require(bundles.first)))
    #expect(names.count == 6)
    for representation in names { #expect(representation.sorted() == ["a", "b"]) }
    // A shelf that needs nothing is present without any capability; its handle still is not an item.
    let plain = inputNames(try classicInfo(#require(try Skin2Baker.bake(source: Data(bare.utf8)).first)))
    #expect(plain.count == 4)
    for representation in plain { #expect(representation == ["a"]) }
}

@Test("Baked art does not draw a panel")
func bakedArtDoesNotDrawThePanel() throws {
    let source = try Data(contentsOf: fixtures.appendingPathComponent("panels/skin.json"))
    var document = try #require(JSONSerialization.jsonObject(with: source) as? [String: Any])
    var root = try #require(document["root"] as? [String: Any])
    var children = try #require(root["children"] as? [[String: Any]])
    // "status" is a fixed panel that needs nothing, so only the bake rule keeps it out.
    let removed = children.remove(at: try #require(children.firstIndex { $0["id"] as? String == "status" }))
    #expect((removed["panel"] as? [String: Any])?["name"] as? String == "status")
    root["children"] = children
    document["root"] = root
    let with = try #require(try Skin2Baker.bake(source: source).first)
    let without = try #require(try Skin2Baker.bake(source: JSONSerialization.data(withJSONObject: document)).first)
    #expect(try pixels(#require(with.files["preview.png"])) == pixels(#require(without.files["preview.png"])))
    for name in with.files.keys.sorted() where name.hasSuffix(".pdf") { #expect(with.files[name] == without.files[name], "\(name)") }
}

@Test("Baked screens are game screens only")
func bakedScreensAreGameScreensOnly() throws {
    for source in [try Data(contentsOf: fixtures.appendingPathComponent("accessory-screen/skin.json")), Data(bare.utf8)] {
        let info = try classicInfo(#require(try Skin2Baker.bake(source: source).first))
        let portrait = try #require(info.representations[.iphone]?.edgeToEdge?["portrait"])
        #expect(portrait.screens?.count == 1)
    }
}

@Test("The bake says once that panels are left out")
func bakeWarnsOnce() throws {
    let panels = try #require(try Skin2Baker.bake(sourceURL: fixtures.appendingPathComponent("panels/skin.json")).first)
    #expect(panels.warnings.filter { $0 == notBaked }.count == 1)
    #expect(panels.warnings.count == 1)
    let plain = try #require(try Skin2Baker.bake(sourceURL: fixtures.appendingPathComponent("dual-screen/skin.json")).first)
    #expect(!plain.warnings.contains(notBaked))
}
