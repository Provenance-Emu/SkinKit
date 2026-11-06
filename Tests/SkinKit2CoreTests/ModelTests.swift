import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Lengths, JSON and the model")
struct ModelTests {
    @Test("JSON keeps booleans and numbers apart and prints integers without a fraction")
    func jsonValues() throws {
        let v = try Skin2JSON.parse(Data(#"{"b": true, "n": 1, "f": 1.5, "s": "x", "a": [null]}"#.utf8))
        #expect(v["b"] == .bool(true))
        #expect(v["n"] == .number(1))
        #expect(v["a"] == .array([.null]))
        #expect(String(decoding: try v.data(), as: UTF8.self) == #"{"a":[null],"b":true,"f":1.5,"n":1,"s":"x"}"#)
        #expect(Skin2Pointer.appending("/a", "b/c~d") == "/a/b~1c~0d")
    }

    @Test("Length forms resolve: points scale, fractions follow the axis, operators nest")
    func lengths() throws {
        let safe = Skin2Insets(top: 59, left: 0, bottom: 34, right: 21)
        func eval(_ json: Skin2JSON, along: Double = 200, unit: Double = 2) throws -> Double {
            try Skin2Length(json: json).resolve(along: along, unit: unit, safeArea: safe)
        }
        #expect(try eval(8) == 16)
        #expect(try eval("50%") == 100)
        #expect(try eval("-12.5%") == -25)
        #expect(try eval(["pt": 8]) == 16)
        #expect(try eval(["frac": 0.25]) == 50)
        #expect(try eval(["safe": "right"]) == 21)
        // iCube's edge rule: max(safe, 8) + 8, with safe insets in canvas points (never scaled).
        let edge: Skin2JSON = ["sum": [["max": [["safe": "left"], 8]], 8]]
        #expect(try eval(edge) == 32)
        #expect(try eval(["sum": [["max": [["safe": "top"], 8]], 8]]) == 75)
        #expect(try eval(["min": [-6, ["sum": [["safe": "bottom"], -14]]]], unit: 1) == -6)
        #expect(try Skin2Length(json: edge).depth == 2)
        #expect(try Skin2Length(json: edge).usesSafeArea)
    }

    @Test("Bad lengths say what is wrong", arguments: [
        Skin2JSON.string("50"), .string("abc%"), ["pt": "8"], ["max": [1]], ["avg": [1, 2]], ["pt": 1, "frac": 1], .bool(true),
        ["safe": "middle"],
    ])
    func badLengths(_ json: Skin2JSON) {
        #expect(throws: Skin2LengthError.self) { try Skin2Length(json: json) }
    }

    @Test("Colours parse with and without alpha")
    func colours() {
        let c = Skin2Color(hex: "#FF000080")
        #expect(c?.red == 1)
        #expect(abs((c?.alpha ?? 0) - 128.0 / 255) < 0.0001)
        #expect(Skin2Color(hex: "#00FF00")?.alpha == 1)
        #expect(Skin2Color(hex: "red") == nil)
        #expect(Skin2Color(hex: "#12345") == nil)
        #expect(Skin2Color(hex: "#9E7AF2")?.description == "#9E7AF2FF")
    }

    @Test("Decoding errors name the place with a JSON Pointer")
    func decodingErrorPointer() throws {
        let json = skinJSON(children: #"{ "type": "group", "children": [ { "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "red" } ] } ] }"#)
        do {
            _ = try Skin2Document.inline(json)
            Issue.record("expected an error")
        } catch let e as Skin2Error {
            #expect(e.pointer == "/root/children/0/children/0/fills/0/color")
            #expect(e.message.contains("#RRGGBB"))
        }
    }

    @Test("Layout patches merge size, anchor and offset by field and clear with null")
    func layoutMerge() throws {
        let doc = try Skin2Document.inline(skinJSON(children: #"""
            { "type": "group", "id": "g",
              "layout": { "size": { "width": 10, "height": 20 }, "aspect": 2, "offset": { "x": 1, "y": 2 }, "anchor": { "x": "leading", "y": "top" } },
              "when": [ { "layout": { "size": { "width": 30 }, "aspect": null, "offset": { "y": null }, "anchor": { "to": "canvas" } } } ] }
            """#))
        let g = try #require(doc.node(id: "g"))
        let merged = (g.layout ?? Skin2Layout()).merged(with: try #require(g.when.first?.patch.layout))
        #expect(merged.size?.width == .pt(30))
        #expect(merged.size?.height == .pt(20))
        #expect(merged.aspect == nil)
        #expect(merged.offset?.x == .pt(1))
        #expect(merged.offset?.y == nil)
        #expect(merged.anchor == Skin2Anchor(x: .leading, y: .top, to: .canvas))
    }

    @Test("Trait sets follow section 8.1")
    func traitSets() {
        #expect(Skin2TraitSet.all.count == 9)
        #expect(Skin2TraitSet.familyNames == ["iphone.standard", "iphone.edgeToEdge", "ipad.standard", "ipad.splitView", "tv.standard"])
        let split = Skin2TraitSet.all.first { $0.name == "ipad-splitView-landscape" }
        #expect(split?.size == Skin2Size(width: 639, height: 834))
        #expect(split?.environment.orientation == .landscape)
        #expect(Skin2TraitSet.all.first { $0.name == "iphone-edgeToEdge-landscape" }?.safeArea == Skin2Insets(top: 0, left: 59, bottom: 21, right: 59))
    }

    @Test("Half-point rounding ties toward +infinity and keeps touching edges touching")
    func rounding() {
        #expect(Skin2Rounding.halfPoint(1.25) == 1.5)
        #expect(Skin2Rounding.halfPoint(-0.25) == 0)
        #expect(Skin2Rounding.halfPoint(-0.26) == -0.5)
        #expect(Skin2Rounding.halfPoint(2.74) == 2.5)
        let a = Skin2Rect(x: 0.3, y: 0, width: 10.1, height: 1).roundedToHalfPoint
        let b = Skin2Rect(x: 10.4, y: 0, width: 5, height: 1).roundedToHalfPoint
        #expect(a.maxX == b.minX)
        #expect(!a.overlaps(b))
    }
}
