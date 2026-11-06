import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Preprocessor: tokens, parts, variants")
struct PreprocessorTests {
    static let part = #"""
        "parts": {
          "button": {
            "params": { "input": { "type": "string" }, "size": { "type": "length", "default": { "pt": 44 } },
                        "color": { "type": "color", "default": "$accent" } },
            "node": { "type": "control", "kind": "button", "input": "@input",
                      "layout": { "size": { "width": "@size", "height": "@size" } },
                      "states": { "pressed": { "patch": [ { "target": "#body", "fills": [ { "type": "solid", "color": "@color" } ] } ] } },
                      "children": [ { "type": "shape", "id": "body", "shape": { "kind": "ellipse" },
                                      "fills": [ { "type": "solid", "color": "@color" } ] } ] } },
          "pair": {
            "params": { "first": { "type": "string" } },
            "node": { "type": "group", "children": [ { "use": "button", "id": "one", "with": { "input": "@first" } } ] } }
        },
        "tokens": { "accent": "#FF0000", "gap": 8, "half": { "length": "50%" }, "name": { "string": "Hi" } },
        "themes": { "blue": { "accent": "#0000FF", "gap": 12 } }
        """#

    static func doc(_ children: String, extra: String = part, theme: String? = nil) throws -> Skin2Document {
        try Skin2Document.inline(skinJSON(children: children, extra: extra), theme: theme)
    }

    static func error(_ children: String, extra: String = part, theme: String? = nil) -> Skin2Error? {
        do { _ = try doc(children, extra: extra, theme: theme); return nil } catch { return error as? Skin2Error }
    }

    @Test("Tokens replace whole-string references; typed length tokens become explicit lengths")
    func tokens() throws {
        let d = try Self.doc(#"{ "type": "text", "id": "t", "text": "$name", "color": "$accent", "layout": { "size": { "width": "$half", "height": "$gap" } } }"#)
        let t = try #require(d.node(id: "t"))
        #expect(t.text == "Hi")
        #expect(t.color == Skin2Color(hex: "#FF0000"))
        #expect(t.layout?.size?.width == .frac(0.5))
        #expect(t.layout?.size?.height == .pt(8))
        let pre = try Skin2Preprocessor(source: try Skin2JSON.parse(Data(skinJSON(children: "", extra: Self.part).utf8)))
        #expect(try pre.tokens()["half"]?.value == ["frac": 0.5])
        // Strings that only look like references stay text.
        #expect(try Self.doc(#"{ "type": "text", "id": "t", "text": "$5 off" }"#).node(id: "t")?.text == "$5 off")
    }

    @Test("A theme overrides tokens, and only declared ones of the same type")
    func themes() throws {
        let d = try Self.doc(#"{ "type": "text", "id": "t", "text": "x", "color": "$accent", "layout": { "size": { "height": "$gap" } } }"#, theme: "blue")
        #expect(d.node(id: "t")?.color == Skin2Color(hex: "#0000FF"))
        #expect(d.node(id: "t")?.layout?.size?.height == .pt(12))
        #expect(d.themeNames == ["blue"])
        #expect(Self.error("", extra: ##""tokens": { "a": "#000000" }, "themes": { "t": { "b": "#FFFFFF" } }"##)?.pointer == "/themes/t/b")
        #expect(Self.error("", extra: ##""tokens": { "a": "#000000" }, "themes": { "t": { "a": 3 } }"##)?.message.contains("but the token is a color") == true)
        #expect(Self.error("", theme: "missing")?.message.contains("no theme") == true)
    }

    @Test("Unknown tokens and stray parameters fail with their location")
    func unknownReferences() {
        #expect(Self.error(#"{ "type": "text", "text": "$nope" }"#)?.pointer == "/root/children/0/text")
        #expect(Self.error(#"{ "type": "text", "text": "@input" }"#)?.message.contains("part parameter") == true)
    }

    @Test("Parts expand with arguments, defaults and the caller's keys; inner ids are scoped")
    func parts() throws {
        let d = try Self.doc(##"{ "use": "button", "id": "a", "with": { "input": "a", "color": "#00FF00" }, "layout": { "anchor": { "x": "leading" } } }"##)
        let a = try #require(d.node(id: "a"))
        #expect(a.kind == .button)
        #expect(a.input == .name("a"))
        #expect(a.layout?.size?.width == .pt(44))
        #expect(a.layout?.anchor?.x == .leading)
        #expect(a.children.first?.id == "a.body")
        #expect(a.children.first?.fills.first?.color == Skin2Color(hex: "#00FF00"))
        #expect(a.states["pressed"]?.patch.first?.target == "#a.body")
        // Defaults read tokens.
        let b = try Self.doc(#"{ "use": "button", "id": "b", "with": { "input": "b" } }"#)
        #expect(b.node(id: "b.body")?.fills.first?.color == Skin2Color(hex: "#FF0000"))
        // Nested parts scope twice.
        let p = try Self.doc(#"{ "use": "pair", "id": "p", "with": { "first": "x" } }"#)
        #expect(p.node(id: "p.one")?.input == .name("x"))
        #expect(p.node(id: "p.one.body") != nil)
        #expect(p.node(id: "p.one")?.states["pressed"]?.patch.first?.target == "#p.one.body")
    }

    @Test("Part arguments are typed: a length needs {pt} or {frac}")
    func typedParameters() {
        let bare = Self.error(#"{ "use": "button", "id": "a", "with": { "input": "a", "size": 0.5 } }"#)
        #expect(bare?.pointer == "/root/children/0/with/size")
        #expect(bare?.message.contains("explicit") == true)
        #expect(Self.error(#"{ "use": "button", "id": "a", "with": { "input": "a", "size": "$gap" } }"#) != nil)
        #expect(Self.error(#"{ "use": "button", "id": "a", "with": { "input": "a", "size": "$half" } }"#) == nil)
        #expect(Self.error(#"{ "use": "button", "id": "a", "with": { "input": "a", "color": "blue" } }"#)?.message.contains("colour") == true)
        #expect(Self.error(#"{ "use": "button", "id": "a", "with": { "input": 3 } }"#)?.message.contains("string") == true)
    }

    @Test("Part instances fail clearly", arguments: [
        (#"{ "use": "nope" }"#, "no part named"),
        (#"{ "use": "button", "id": "a" }"#, "needs \"input\""),
        (#"{ "use": "button", "id": "a", "with": { "input": "a", "extra": 1 } }"#, "no parameter"),
        (#"{ "use": "button", "with": { "input": "a" } }"#, "give this instance an id"),
        (#"{ "use": "button", "id": "a", "with": { "input": "a" }, "opacity": 0.5 }"#, "takes only"),
        (#"{ "use": "std.faceButton", "id": "a" }"#, "standard parts library"),
    ])
    func partErrors(_ child: String, _ message: String) {
        let e = Self.error(child)
        #expect(e?.message.contains(message) == true, "\(String(describing: e))")
    }

    @Test("Recursive and too-deep parts are rejected")
    func recursion() {
        let loop = #""parts": { "a": { "node": { "use": "b" } }, "b": { "node": { "use": "a" } } }"#
        #expect(Self.error(#"{ "use": "a" }"#, extra: loop)?.message.contains("uses itself") == true)
        var chain: [String] = []
        for i in 0..<10 { chain.append("\"p\(i)\": { \"node\": { \"use\": \"p\(i + 1)\" } }") }
        chain.append(#""p10": { "node": { "type": "group" } }"#)
        let deep = "\"parts\": { \(chain.joined(separator: ", ")) }"
        #expect(Self.error(#"{ "use": "p0" }"#, extra: deep)?.message.contains("8 deep") == true)
        #expect(Self.error(#"{ "use": "p3" }"#, extra: deep) == nil)
    }

    @Test("A variant's patches apply to the nodes they target before decoding")
    func variants() throws {
        let extra = #"""
            "variants": {
              "big": { "match": { "any": true }, "patch": [ { "target": "#g", "layout": { "size": { "width": 99 } }, "opacity": 0.5, "visible": null } ] },
              "bad": { "patch": [ { "target": "#missing", "opacity": 1 } ] } }
            """#
        let child = #"{ "type": "group", "id": "g", "visible": false, "layout": { "size": { "width": 10, "height": 20 } } }"#
        let base = try Skin2Document.inline(skinJSON(children: child, extra: extra))
        #expect(base.variants.keys.sorted() == ["bad", "big"])
        #expect(base.variants["big"]?.isPlayerSelectable == true)
        let big = try Skin2Document.inline(skinJSON(children: child, extra: extra), variant: "big")
        let g = try #require(big.node(id: "g"))
        #expect(g.layout?.size == Skin2SizeLengths(width: .pt(99), height: .pt(20)))
        #expect(g.opacity == 0.5)
        #expect(g.visible == nil)
        #expect(big.variant == "big")
        do {
            _ = try Skin2Document.inline(skinJSON(children: child, extra: extra), variant: "bad")
            Issue.record("expected an error")
        } catch let e as Skin2Error {
            #expect(e.pointer == "/variants/bad/patch/0/target")
        }
    }

    @Test("Expansion stops at the node limit: branching parts can't build a huge tree")
    func nodeBudget() throws {
        // Eight levels of parts with ten children each: 10^8 leaves from about 2 KB of JSON.
        var parts: [String] = []
        for level in 0..<8 {
            let child = level == 7 ? #"{ "type": "group" }"# : "{ \"use\": \"p\(level + 1)\" }"
            parts.append("\"p\(level)\": { \"node\": { \"type\": \"group\", \"children\": [ \(Array(repeating: child, count: 10).joined(separator: ", ")) ] } }")
        }
        let extra = "\"parts\": { \(parts.joined(separator: ", ")) }"
        let json = skinJSON(children: #"{ "type": "group" }, { "use": "p0" }"#, extra: extra)
        #expect(json.utf8.count < 2500)
        let clock = ContinuousClock()
        var caught: Skin2Error?
        let elapsed = clock.measure {
            do { _ = try Skin2Document.inline(json) } catch { caught = error as? Skin2Error }
        }
        #expect(caught?.pointer == "/root/children/1", "the error points at the instance in the document")
        #expect(caught?.message.contains("more than 2000 nodes") == true)
        #expect(elapsed < .seconds(5))
        // The validator reports it as an error with the same path.
        let report = Skin2Validator.validate(data: Data(json.utf8))
        #expect(report.errors.map(\.pointer) == ["/root/children/1"])
        // Two levels (111 nodes) still expand.
        let small = skinJSON(children: #"{ "use": "p6" }"#, extra: extra)
        #expect(try Skin2Document.inline(small).root.nodeCount == 1 + 1 + 10 + 100)
    }
}
