import Foundation
import Testing
@testable import SkinKit2Core

@Suite("JSON Schema")
struct SchemaTests {
    @Test("docs/schema/skin-2.0.schema.json is the generated schema")
    func publishedSchemaIsCurrent() throws {
        let generated = try Skin2Schema.encoded()
        if Skin2Paths.recording {
            try FileManager.default.createDirectory(at: Skin2Paths.schema.deletingLastPathComponent(), withIntermediateDirectories: true)
            try generated.write(to: Skin2Paths.schema)
            Issue.record("Recorded \(Skin2Paths.schema.path); run again without SKIN2_RECORD")
            return
        }
        let published = try Data(contentsOf: Skin2Paths.schema)
        #expect(published == generated, "the published schema is stale: run with SKIN2_RECORD=1")
    }

    @Test("The schema uses only keywords the test validator implements")
    func keywordsAreImplemented() {
        let used = SchemaValidator.keywords(in: Skin2Schema.document)
        #expect(used.subtracting(Skin2Schema.keywords).isEmpty, "unimplemented: \(used.subtracting(Skin2Schema.keywords).sorted())")
        #expect(Skin2Schema.document["$schema"] == "https://json-schema.org/draft/2020-12/schema")
    }

    // MARK: Schema and decoder agree

    static let parts = #""parts": { "p": { "params": { "n": { "type": "length" } }, "node": { "type": "group" } } }"#

    /// Documents both the schema and the decoder must reject.
    static let invalid: [(String, String)] = [
        ("unknown node type", skinJSON(children: #"{ "type": "blob" }"#)),
        ("unknown shape kind", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "hexagon" } }"#)),
        ("colour name", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "solid", "color": "red" } ] }"#)),
        ("string length", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "rect" }, "layout": { "size": { "width": "abc" } } }"#)),
        ("missing root", #"{ "formatVersion": "2.0", "identifier": "t", "name": "T", "gameTypes": ["snes"], "reference": { "shortSide": 390, "minScale": 1, "maxScale": 1 } }"#),
        ("two sides", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "polygon", "sides": 2 } }"#)),
        ("format 3", skinJSON(children: "").replacingOccurrences(of: "\"2.0\"", with: "\"3.0\"")),
        ("repeat 65", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "rect" }, "repeat": { "count": 65 } }"#)),
        ("stroke without width", skinJSON(children: ##"{ "type": "shape", "shape": { "kind": "rect" }, "strokes": [ { "color": "#000000" } ] }"##)),
        ("control without kind", skinJSON(children: #"{ "type": "control", "id": "a", "input": "a" }"#)),
        ("length with two keys", skinJSON(children: #"{ "type": "group", "layout": { "size": { "width": { "pt": 1, "frac": 0.5 } } } }"#)),
        ("length 5 deep", skinJSON(children: #"{ "type": "group", "layout": { "size": { "width": { "max": [1, { "max": [1, { "max": [1, { "max": [1, { "max": [1, 2] }] }] }] }] } } } }"#)),
        ("stack and grid", skinJSON(children: #"{ "type": "group", "stack": { "axis": "vertical" }, "grid": { "columns": 2 } }"#)),
        ("part instance key", skinJSON(children: #"{ "use": "p", "with": { "n": { "pt": 1 } }, "opacity": 0.5 }"#, extra: parts)),
        ("opacity above 1", skinJSON(children: #"{ "type": "group", "opacity": 1.5 }"#)),
        ("one-stop gradient", skinJSON(children: ##"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "linear", "start": [0, 0], "end": [1, 1], "stops": [["#000000", 0]] } ] }"##)),
        ("unknown state", skinJSON(children: #"{ "type": "control", "id": "a", "kind": "button", "input": "a", "states": { "hover": {} } }"#)),
        ("path over 4 KB", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "path", "box": [0, 0, 1, 1], "d": "M0 0\#(String(repeating: " L1 1", count: 900))" } }"#)),
        ("unknown area", skinJSON(children: #"{ "type": "group", "layout": { "anchor": { "to": "elsewhere" } } }"#)),
        ("no game types", skinJSON(children: "", gameTypes: "[]")),
        ("stop without position", skinJSON(children: ##"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "linear", "start": [0, 0], "end": [1, 1], "stops": [["#000000"], ["#FFFFFF", 1]] } ] }"##)),
        ("shadow without colour", skinJSON(children: #"{ "type": "group", "effects": [ { "type": "shadow", "radius": 2 } ] }"#)),
        ("unknown bake trait", skinJSON(children: "", extra: #""bake": { "traits": ["watch.standard"] }"#)),
        ("frame of three", skinJSON(children: #"{ "type": "group", "layout": { "frame": [0, 0, 10] } }"#)),
        ("text without text", skinJSON(children: #"{ "type": "text" }"#)),
        ("zero aspect", skinJSON(children: #"{ "type": "screen", "id": "s", "aspect": 0 }"#)),
        ("inset with no edge", skinJSON(children: #"{ "type": "group", "layout": { "inset": { "foo": 1 } } }"#)),
        ("visible as a string", skinJSON(children: #"{ "type": "group", "visible": "yes" }"#)),
        ("taper 0.5", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "trapezoid", "taper": 0.5 } }"#)),
        ("d-pad missing right", skinJSON(children: #"{ "type": "control", "id": "d", "kind": "dpad", "input": { "up": "up", "down": "down", "left": "left" } }"#)),
        ("stretched image paint", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "image", "src": "a.png", "mode": "stretch" } ] }"#)),
        ("integer sides as fraction", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "polygon", "sides": 3.5 } }"#)),
        ("bad id", skinJSON(children: #"{ "type": "group", "id": "1st" }"#)),
        ("bad state target", skinJSON(children: #"{ "type": "control", "id": "a", "kind": "button", "input": "a", "states": { "pressed": { "patch": [ { "target": "body" } ] } } }"#)),
        ("short token string", skinJSON(children: "", extra: #""tokens": { "x": "notacolor" }"#)),
    ]

    /// Edge cases both must accept.
    static let valid: [(String, String)] = [
        ("empty root", skinJSON(children: "")),
        ("circle alias", skinJSON(children: #"{ "type": "shape", "shape": { "kind": "circle" } }"#)),
        ("length 4 deep", skinJSON(children: #"{ "type": "group", "layout": { "size": { "width": { "max": [1, { "max": [1, { "max": [1, { "sum": ["50%", { "pt": 2 }] }] }] }] } } } }"#)),
        ("visible condition", skinJSON(children: #"{ "type": "group", "visible": { "flag": "f", "orientation": "landscape" } }"#)),
        ("unknown keys", skinJSON(children: #"{ "type": "group", "futureKey": { "anything": [1, 2] } }"#, extra: #""x-editor": { "zoom": 2 }"#)),
        ("per-edge inset", skinJSON(children: #"{ "type": "group", "layout": { "inset": { "top": { "safe": "top" }, "left": "10%" } } }"#)),
        ("null in a when patch", skinJSON(children: #"{ "type": "group", "layout": { "aspect": 2 }, "when": [ { "device": "ipad", "layout": { "aspect": null, "size": { "width": null } } } ] }"#)),
        ("typed tokens", skinJSON(children: ##"{ "type": "group", "layout": { "size": { "width": "$w" } } }"##, extra: ##""tokens": { "w": { "length": "50%" }, "c": { "color": "#FFFFFF" }, "s": { "string": "A" }, "n": { "number": 2 } }"##)),
        ("part with a length", skinJSON(children: #"{ "use": "p", "with": { "n": { "frac": 0.5 } }, "id": "x" }"#, extra: parts)),
    ]

    @Test("Schema and decoder both reject", arguments: invalid.map(\.0))
    func bothReject(_ label: String) throws {
        let json = try #require(Self.invalid.first { $0.0 == label }?.1)
        let schema = SchemaValidator(root: Skin2Schema.document)
        let source = try Skin2JSON.parse(Data(json.utf8))
        #expect(!schema.errors(source).isEmpty, "the schema accepts \(label)")
        #expect(throws: Skin2Error.self, "the decoder accepts \(label)") { try Skin2Document.load(json: source) }
    }

    @Test("Schema and decoder both accept", arguments: valid.map(\.0))
    func bothAccept(_ label: String) throws {
        let json = try #require(Self.valid.first { $0.0 == label }?.1)
        let schema = SchemaValidator(root: Skin2Schema.document)
        let source = try Skin2JSON.parse(Data(json.utf8))
        #expect(schema.errors(source) == [])
        _ = try Skin2Document.load(json: source)
    }
}
