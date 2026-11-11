import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Validator")
struct ValidatorTests {
    static func button(_ id: String, input: String? = nil, frame: String) -> String {
        #"{ "type": "control", "id": "\#(id)", "kind": "button", "input": "\#(input ?? id)", "layout": { "frame": \#(frame) } }"#
    }

    static func report(_ children: String, extra: String = "", requires: String = "[]",
                       gameTypes: String = "[\"com.rileytestut.delta.game.snes\"]") -> Skin2ValidationReport {
        Skin2Validator.validate(data: Data(skinJSON(children: children, extra: extra, gameTypes: gameTypes, requires: requires).utf8))
    }

    static func has(_ issues: [Skin2Issue], at pointer: String? = nil, _ text: String) -> Bool {
        issues.contains { ($0.pointer == pointer || pointer == nil) && $0.message.contains(text) }
    }

    @Test("A small, plain skin validates cleanly")
    func clean() {
        let r = Self.report([Self.button("a", frame: "[0, 0, 60, 60]"), Self.button("b", frame: "[60, 0, 60, 60]")].joined(separator: ","))
        #expect(r.issues == [])
        #expect(r.isValid)
        #expect(r.document?.root.nodeCount == 3)
    }

    @Test("requires must list what the skin uses; extra names are warnings")
    func requires() {
        let stack = #"{ "type": "group", "stack": { "axis": "vertical" }, "children": [ \#(Self.button("a", frame: "[0, 0, 60, 60]")) ] }"#
        let missing = Self.report(stack)
        #expect(Self.has(missing.errors, at: "/requires", "uses layout.stack"))
        let extra = Self.report(stack, requires: #"["layout.stack", "layout.grid", "future.thing"]"#)
        #expect(extra.errors.isEmpty)
        #expect(Self.has(extra.warnings, at: "/requires/1", "does not use"))
        #expect(Self.has(extra.warnings, at: "/requires/2", "not a 2.0 feature name"))
        // Source-level features count too.
        let tokens = Self.report(Self.button("a", frame: "[0, 0, 60, 60]"), extra: ##""tokens": { "c": "#000000" }"##)
        #expect(Self.has(tokens.errors, "uses tokens"))
    }

    @Test("Overlapping hit frames are errors on the trait sets where they overlap; touch surfaces are exempt")
    func overlaps() {
        let r = Self.report([Self.button("a", frame: "[0, 0, 60, 60]"), Self.button("b", frame: "[59, 0, 60, 60]")].joined(separator: ","))
        #expect(Self.has(r.errors, at: "/root/children/0", "overlaps #b on iphone-standard-portrait"))
        let touching = Self.report([Self.button("a", frame: "[0, 0, 60, 60]"), Self.button("b", frame: "[60, 0, 60, 60]")].joined(separator: ","))
        #expect(touching.errors.isEmpty)
        let extended = Self.report(#"""
            { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 60, 60] }, "hit": { "extend": { "right": 8 } } },
            \#(Self.button("b", frame: "[64, 0, 60, 60]"))
            """#)
        #expect(Self.has(extended.errors, "overlaps"))
        let touch = Self.report(#"""
            { "type": "control", "id": "t", "kind": "touchSurface", "inputs": ["touchScreen"], "layout": { "frame": [0, 0, 200, 200] } },
            \#(Self.button("a", frame: "[0, 0, 60, 60]"))
            """#, extra: "", requires: #"["controls.touchSurface"]"#, gameTypes: #"["com.rileytestut.delta.game.ds"]"#)
        #expect(touch.errors.isEmpty, "\(touch.errors)")
        // Only some layouts overlap: reported with the trait set.
        let landscape = Self.report(#"""
            \#(Self.button("a", frame: "[0, 0, 60, 60]")),
            { "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "frame": [100, 0, 60, 60] },
              "when": [ { "orientation": "landscape", "layout": { "frame": [30, 0, 60, 60] } } ] }
            """#)
        #expect(Self.has(landscape.errors, "on iphone-standard-landscape"))
        #expect(!Self.has(landscape.errors, "portrait"))
    }

    @Test("Provenance input aliases keep their existing tokens", arguments: [
        ("psp", "l1"), ("psp", "r1"), ("gamegear", "c"), ("mastersystem", "c"), ("sg1000", "c"),
        ("wii", "1"), ("wii", "2"), ("wii", "+"), ("wii", "-")
    ])
    func provenanceInputs(system: String, input: String) {
        let report = Self.report(Self.button("button", input: input, frame: "[0, 0, 60, 60]"),
                                 gameTypes: "[\"com.provenance.\(system)\"]")
        #expect(report.errors.isEmpty)
    }

    @Test("Inputs must fit the control kind and the game type")
    func inputs() {
        #expect(Self.has(Self.report(Self.button("c", frame: "[0, 0, 60, 60]")).errors, "\"c\" is not an input of game type"))
        #expect(Self.report(Self.button("menu", frame: "[0, 0, 60, 60]")).errors.isEmpty)
        let unknown = Self.report(Self.button("c", frame: "[0, 0, 60, 60]"), gameTypes: #"["com.example.mystery"]"#)
        #expect(unknown.errors.isEmpty)
        #expect(Self.has(unknown.warnings, at: "/gameTypes/0", "no input table"))
        // Valid for every listed game type: c is an N64 input but not a SNES one.
        let both = Self.report(Self.button("c", input: "cUp", frame: "[0, 0, 60, 60]"),
                               gameTypes: #"["com.rileytestut.delta.game.n64", "com.rileytestut.delta.game.snes"]"#)
        #expect(Self.has(both.errors, "snes"))
        #expect(!Self.has(both.errors, "n64"))
        let action = #"{ "type": "control", "id": "m", "kind": "action", "input": "a", "layout": { "frame": [0, 0, 60, 60] } }"#
        #expect(Self.has(Self.report(action).errors, "not an app action"))
        let surface = #"{ "type": "control", "id": "t", "kind": "touchSurface", "inputs": ["a"], "layout": { "frame": [0, 0, 60, 60] } }"#
        #expect(Self.has(Self.report(surface, requires: #"["controls.touchSurface"]"#).errors, "a touch surface takes"))
        let dpadOnButton = #"{ "type": "control", "id": "x", "kind": "button", "input": { "up": "up", "down": "down", "left": "left", "right": "right" }, "layout": { "frame": [0, 0, 60, 60] } }"#
        #expect(Self.has(Self.report(dpadOnButton).errors, "only a d-pad"))
    }

    @Test("Tree rules: unique ids, earlier anchors, safe only in offset and inset, local assets, no repeated controls",
          arguments: [
            ([Self.button("a", frame: "[0, 0, 60, 60]"), Self.button("a", input: "b", frame: "[60, 0, 60, 60]")].joined(separator: ","),
             "/root/children/1/id", "already used at /root/children/0"),
            (##"{ "type": "group", "layout": { "size": { "width": 10, "height": 10 }, "anchor": { "to": "#later" } } }, { "type": "group", "id": "later" }"##,
             "/root/children/0/layout/anchor/to", "not a node earlier"),
            (#"{ "type": "group", "layout": { "size": { "width": 10, "height": 10 }, "anchor": { "to": "screen" } } }"#,
             "/root/children/0/layout/anchor/to", "no screen node comes earlier"),
            (#"{ "type": "group", "layout": { "size": { "width": { "safe": "top" } } } }"#,
             "/root/children/0/layout/size/width", "safe is only allowed"),
            (#"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "image", "src": "../secret.png" } ] }"#,
             "/root/children/0/fills/0/src", "without .."),
            (#"{ "type": "image", "src": "https://example.com/a.png" }"#, "/root/children/0/src", "no remote"),
            (#"{ "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 60, 60] }, "repeat": { "count": 2 } }"#,
             "/root/children/0/repeat", "controls can't repeat"),
            (#"{ "type": "shape", "role": "knob", "shape": { "kind": "ellipse" } }"#, "/root/children/0/role", "inside a thumbstick"),
            (#"{ "type": "screen" }"#, "/root/children/0", "a screen needs an id"),
          ])
    func treeRules(_ children: String, _ pointer: String, _ message: String) {
        let r = Self.report(children, requires: #"["layout.anchors", "layout.repeat", "shapes.parametric", "paint.image"]"#)
        #expect(Self.has(r.errors, at: pointer, message), "\(r.errors.map(\.description))")
    }

    @Test("State patches target art inside the control, within its copies")
    func states() {
        let dpad = #"""
            { "type": "control", "id": "d", "kind": "dpad", "input": { "up": "up", "down": "down", "left": "left", "right": "right" },
              "layout": { "frame": [0, 0, 120, 120] },
              "states": { "pressed.up": { "patch": [ { "target": "#arrow[1]", "opacity": 1 } ] },
                          "pressed.down": { "patch": [ { "target": "#arrow[4]", "opacity": 1 } ] },
                          "pressed": { "patch": [ { "target": "#outside", "opacity": 1 } ] } },
              "children": [ { "type": "shape", "id": "arrow", "shape": { "kind": "rect" }, "repeat": { "count": 4, "rotate": 90 } } ] },
            { "type": "group", "id": "outside" },
            { "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "frame": [200, 0, 60, 60] },
              "states": { "pressed.left": { "opacity": 0.5 } } }
            """#
        let r = Self.report(dpad, requires: #"["controls.dpad", "states", "layout.repeat", "shapes.parametric"]"#)
        #expect(!Self.has(r.errors, at: "/root/children/0/states/pressed.up/patch/0/target", ""))
        #expect(Self.has(r.errors, at: "/root/children/0/states/pressed.down/patch/0/target", "[4] is out of range"))
        #expect(Self.has(r.errors, at: "/root/children/0/states/pressed/patch/0/target", "not inside this control"))
        #expect(Self.has(r.errors, at: "/root/children/2/states/pressed.left", "for d-pads"))
    }

    @Test("Document rules: bake families, screens list, size limits")
    func documentRules() {
        let bake = Self.report(Self.button("a", frame: "[0, 0, 60, 60]"), extra: #""bake": { "traits": ["iphone.standard", "ipad.standard"] }"#)
        #expect(Self.has(bake.errors, at: "/bake/traits", "iphone.edgeToEdge"))
        let screens = Self.report(Self.button("a", frame: "[0, 0, 60, 60]"), extra: #""screens": ["a"]"#)
        #expect(Self.has(screens.errors, at: "/screens/0", "not the id of a screen"))
        let big = Skin2Validator.validate(data: Data(count: Skin2Document.maxFileBytes + 1))
        #expect(Self.has(big.errors, "the limit is"))
        #expect(Self.has(Skin2Validator.validate(data: Data("{".utf8)).errors, "not valid JSON"))
        // The root plus 1,999 children is the limit; one more stops expansion at that child.
        let atLimit = (0..<1999).map { _ in #"{ "type": "group" }"# }.joined(separator: ",")
        #expect(!Self.has(Self.report(atLimit).errors, "the limit is 2000"))
        let many = (0..<2000).map { _ in #"{ "type": "group" }"# }.joined(separator: ",")
        let over = Self.report(many)
        #expect(Self.has(over.errors, at: "/root/children/1999", "the limit is 2000"))
        #expect(over.document == nil)
        let decode = Self.report(#"{ "type": "group", "opacity": 2 }"#)
        #expect(decode.document == nil)
        #expect(decode.errors.first?.pointer == "/root/children/0/opacity")
    }

    @Test("Bake traits limit which trait sets are checked; small controls warn")
    func bakeTraitsAndSmallControls() {
        // Overlaps only on the iPad layouts, which this skin may leave out of bake.traits.
        let children = [Self.button("a", frame: "[0, 0, 60, 60]"),
                        #"{ "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "frame": [100, 0, 60, 60] }, "when": [ { "device": "ipad", "layout": { "frame": [30, 0, 60, 60] } } ] }"#,
        ].joined(separator: ",")
        let all = Self.report(children)
        #expect(Self.has(all.errors, "on ipad-standard-portrait"))
        let phones = Self.report(children, extra: #""bake": { "traits": ["iphone.standard", "iphone.edgeToEdge"] }"#)
        #expect(phones.errors.isEmpty, "\(phones.errors.map(\.description))")
        let small = Self.report(Self.button("a", frame: "[0, 0, 30, 60]"))
        #expect(Self.has(small.warnings, at: "/root/children/0", "30.0 pt on its short side"))
        #expect(small.errors.isEmpty)
    }

    @Test("Themes and variants are validated too")
    func themesAndVariants() {
        let variant = Self.report([Self.button("a", frame: "[0, 0, 60, 60]"), Self.button("b", frame: "[100, 0, 60, 60]")].joined(separator: ","),
                                  extra: ##""variants": { "tight": { "patch": [ { "target": "#b", "layout": { "frame": [30, 0, 60, 60] } } ] } }"##,
                                  requires: #"["variants"]"#)
        #expect(Self.has(variant.errors, "variant tight"))
        let badVariant = Self.report(Self.button("a", frame: "[0, 0, 60, 60]"),
                                     extra: ##""variants": { "v": { "patch": [ { "target": "#nope", "opacity": 1 } ] } }"##, requires: ##"["variants"]"##)
        #expect(Self.has(badVariant.errors, at: "/variants/v/patch/0/target", "variant v"))
    }

    @Test("A theme's string tokens reach ids and inputs: each themed tree gets the tree checks")
    func themedTrees() {
        let children = #"""
            { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [0, 0, 60, 60] } },
            { "type": "control", "id": "$secondID", "kind": "button", "input": "$secondInput", "layout": { "frame": [100, 0, 60, 60] } }
            """#
        let extra = #"""
            "tokens": { "secondID": { "string": "b" }, "secondInput": { "string": "b" } },
            "themes": { "clash": { "secondID": { "string": "a" } }, "wrong": { "secondInput": { "string": "c" } }, "fine": { "secondInput": { "string": "y" } } }
            """#
        let r = Self.report(children, extra: extra, requires: #"["tokens", "themes"]"#)
        #expect(Self.has(r.errors, at: "/root/children/1/id", "already used at /root/children/0 (theme clash)"))
        #expect(Self.has(r.errors, at: "/root/children/1", "\"c\" is not an input of game type com.rileytestut.delta.game.snes (theme wrong)"))
        #expect(!Self.has(r.issues, "theme fine"))
        #expect(r.errors.count == 2, "\(r.errors.map(\.description))")
        // A problem the base tree already has is reported once, not again per theme.
        let base = Self.report(Self.button("c", frame: "[0, 0, 60, 60]"), extra: #""tokens": { "n": 1 }, "themes": { "t": { "n": 2 } }"#,
                               requires: #"["tokens", "themes"]"#)
        #expect(base.errors.map(\.pointer) == ["/root/children/0"])
    }

    @Test("Asset paths are checked in when and state patches too")
    func patchedAssetPaths() {
        let children = ##"""
            { "type": "shape", "shape": { "kind": "rect" }, "layout": { "frame": [0, 0, 60, 60] },
              "when": [ { "orientation": "landscape", "fills": [ { "type": "image", "src": "../secret.png" } ] } ] },
            { "type": "control", "id": "b", "kind": "button", "input": "b", "layout": { "frame": [100, 0, 60, 60] },
              "states": { "pressed": { "patch": [ { "target": "#body", "fills": [ { "type": "solid", "color": "#000000" }, { "type": "image", "src": "https://example.com/x.png" } ] } ] } },
              "children": [ { "type": "shape", "id": "body", "shape": { "kind": "ellipse" }, "fills": [ { "type": "image", "src": "art/b.png" } ] } ] }
            """##
        let r = Self.report(children, requires: #"["shapes.parametric", "paint.image", "states"]"#)
        #expect(Self.has(r.errors, at: "/root/children/0/when/0/fills/0/src", "without .."))
        #expect(Self.has(r.errors, at: "/root/children/1/states/pressed/patch/0/fills/1/src", "no remote"))
        #expect(r.errors.count == 2, "\(r.errors.map(\.description))")
    }
}
