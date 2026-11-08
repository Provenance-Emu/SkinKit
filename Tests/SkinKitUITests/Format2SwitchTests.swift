#if canImport(UIKit)
import Foundation
import SkinKit2Core
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

/// The format 2.0 switch (section 1): `DeltaSkinView` draws `skin.json` only for a bundle whose `format2` entry
/// this build supports and whose source loads; everything else stays classic.
@Suite("Format 2.0 switch")
struct Format2SwitchTests {
    private static let skinJSON = """
    { "formatVersion": "2.0", "requires": ["layout.anchors", "shapes.parametric"], "identifier": "f2", "name": "F2",
      "gameTypes": ["com.rileytestut.delta.game.snes"], "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1 },
      "root": { "type": "group", "children": [
        { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [20, 600, 60, 60] },
          "children": [ { "type": "shape", "shape": { "kind": "ellipse" }, "fills": [ { "type": "solid", "color": "#52DB66" } ] } ] } ] } }
    """

    private func makeSkin(format2: String?, skin: String? = skinJSON) throws -> DeltaSkin {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("F2-\(UUID().uuidString).deltaskin", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = format2.map { ", \"format2\": \($0)" } ?? ""
        let info = """
        { "name": "F2", "identifier": "com.example.f2", "gameTypeIdentifier": "com.rileytestut.delta.game.snes"\(key),
          "representations": { "iphone": { "edgeToEdge": { "portrait": {
            "assets": { "resizable": "skin.pdf" }, "mappingSize": { "width": 414, "height": 896 },
            "items": [ { "inputs": ["a"], "frame": { "x": 20, "y": 600, "width": 60, "height": 60 } } ] } } } } }
        """
        try Data(info.utf8).write(to: dir.appendingPathComponent("info.json"))
        if let skin { try Data(skin.utf8).write(to: dir.appendingPathComponent("skin.json")) }
        return try DeltaSkin(fileURL: dir)
    }

    @Test("A supported format2 entry loads skin.json")
    func supported() throws {
        let skin = try makeSkin(format2: #"{ "source": "skin.json", "formatVersion": "2.0", "requires": ["layout.anchors", "shapes.parametric"] }"#)
        let doc = try #require(DeltaSkinFormat2.document(for: skin))
        #expect(doc.identifier == "f2")
    }

    @Test("A classic skin, an unsupported feature, a missing, broken or invalid source all stay classic")
    func fallsBack() throws {
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: nil)) == nil)
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "formatVersion": "2.0", "requires": ["quantum.foam"] }"#)) == nil)
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "formatVersion": "2.0", "requires": ["effects.ci"] }"#)) == nil)
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "formatVersion": "3.0", "requires": [] }"#)) == nil)
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "requires": [] }"#, skin: nil)) == nil)
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "requires": [] }"#, skin: "{ not json")) == nil)
        // skin.json itself asks for more than info.json admitted.
        let greedy = Self.skinJSON.replacingOccurrences(of: "\"layout.anchors\"", with: "\"effects.ci\"")
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "requires": [] }"#, skin: greedy)) == nil)
        // Decodes, but fails validation: two controls share an id.
        let twin = #"{ "type": "control", "id": "a", "kind": "button", "input": "b", "layout": { "frame": [200, 600, 60, 60] } }"#
        let duplicate = Self.skinJSON.replacingOccurrences(of: "] } ] } }", with: "] }, \(twin) ] } }")
        #expect(duplicate != Self.skinJSON)
        #expect((try? Skin2Document.load(data: Data(duplicate.utf8))) != nil, "the shape is fine")
        #expect(!Skin2Validator.validate(data: Data(duplicate.utf8)).isValid, "the validator rejects it")
        #expect(DeltaSkinFormat2.document(for: try makeSkin(format2: #"{ "requires": [] }"#, skin: duplicate)) == nil)
    }

    @Test("The sink negates stick y, maps touchScreen to the DS screen, and routes the alt toggle")
    func sink() {
        final class Handler: DeltaSkinInputHandling {
            let turboManager = TurboManager()
            let stickyManager = StickyButtonManager()
            var dsScreensSwapped = false
            var log: [String] = []
            func buttonPressed(_ buttonId: String) { log.append("+\(buttonId)") }
            func buttonReleased(_ buttonId: String) { log.append("-\(buttonId)") }
            func analogStickMoved(_ stickId: String, x: Float, y: Float) { log.append("stick \(stickId) \(x) \(y)") }
            func ndsBottomScreenTouched(at normalizedPoint: CGPoint) { log.append("touch \(normalizedPoint.x) \(normalizedPoint.y)") }
            func ndsBottomScreenTouchReleased() { log.append("touch up") }
            func toggleAltRepresentations() { log.append("alt") }
        }
        let handler = Handler()
        let sink = DeltaSkinFormat2Sink(handler)
        sink.stick("leftThumbstick", x: 0.5, y: 1)
        sink.surface("touchScreen", point: .init(x: 0.25, y: 0.5))
        sink.surface("touchScreen", point: nil)
        sink.surface("pointer", point: .init(x: 0, y: 0))
        sink.action("menu")
        sink.action("toggleAltRepresentations")
        #expect(handler.log == ["stick leftThumbstick 0.5 -1.0", "touch 0.25 0.5", "touch up", "+menu", "-menu", "alt"])
    }

    @Test("Traits map onto the 2.0 environment")
    func traitMapping() {
        #expect(DeltaSkinFormat2.device(.ipad) == .ipad)
        #expect(DeltaSkinFormat2.displayType(.stageManager) == .standard)
        #expect(DeltaSkinFormat2.displayType(.splitView) == .splitView)
        #expect(DeltaSkinFormat2.flags(DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait, usesAltRepresentations: true)) == ["altToggled"])
    }
}
#endif
