import Foundation
import Testing
@testable import SkinKit2Core

/// The standard parts library (`parts.std@2.0`), the thumbstick `click` input and the section 11 image limits.
@Suite("Standard parts, thumbstick click, image limits")
struct StdPartsTests {
    static let allNames = ["std.dpad", "std.faceButton", "std.keypadKey", "std.kidneyButton", "std.pill", "std.stick", "std.stickWithClick", "std.triggerBar"]

    static let psx = #"["com.provenance.psx"]"#
    static let pad = #"["layout.anchors", "shapes.parametric", "paint.gradients", "effects.shadow", "text", "parts", "parts.std@2.0", "states", "layout.repeat", "controls.dpad", "controls.thumbstick"]"#

    static func doc(_ children: String, gameTypes: String = psx) throws -> Skin2Document {
        try Skin2Document.inline(skinJSON(children: children, gameTypes: gameTypes, requires: pad))
    }

    // MARK: The library

    @Test("The library holds the eight standard parts, and each is a valid part")
    func libraryParts() throws {
        #expect(Skin2StdParts.names == Self.allNames)
        let defs = Skin2Schema.document["$defs"] ?? .null
        let validator = SchemaValidator(root: ["$ref": "#/$defs/part", "$defs": defs])
        for (name, part) in Skin2StdParts.library {
            #expect(validator.errors(part) == [], "\(name)")
            // Self-contained: a skin's tokens are not the library's.
            #expect(!String(decoding: try part.data(), as: UTF8.self).contains("\"$"), "\(name) refers to a $token")
        }
    }

    @Test("Every standard part expands with only its required arguments")
    func expandsWithDefaults() throws {
        let uses: [(String, String)] = [
            (#"{ "use": "std.faceButton", "id": "p", "with": { "input": "cross" } }"#, "button"),
            (#"{ "use": "std.kidneyButton", "id": "p", "with": { "input": "l2" } }"#, "button"),
            (#"{ "use": "std.pill", "id": "p", "with": { "input": "start" } }"#, "button"),
            (#"{ "use": "std.triggerBar", "id": "p", "with": { "input": "l1" } }"#, "trigger"),
            (#"{ "use": "std.dpad", "id": "p" }"#, "dpad"),
            (#"{ "use": "std.stick", "id": "p", "with": { "input": "leftThumbstick" } }"#, "thumbstick"),
            (#"{ "use": "std.stickWithClick", "id": "p", "with": { "input": "leftThumbstick", "click": "l3" } }"#, "thumbstick"),
            (#"{ "use": "std.keypadKey", "id": "p", "with": { "input": "select" } }"#, "button"),
        ]
        for (use, kind) in uses {
            let d = try Self.doc(use)
            #expect(d.root.children.first?.kind?.rawValue == kind, "\(use)")
        }
    }

    @Test("Part arguments theme the art, and a trigger can be a button")
    func arguments() throws {
        let d = try Self.doc(##"""
            { "use": "std.faceButton", "id": "a", "with": { "input": "cross", "label": "X", "top": "#112233", "bottom": "#445566",
                                                            "shape": { "kind": "squircle", "cornerRadius": 12 } } },
            { "use": "std.triggerBar", "id": "z", "with": { "input": "r2", "kind": "button", "taper": 0.2 } }
            """##)
        let a = try #require(d.node(id: "a"))
        #expect(a.children.last?.text == "X")
        #expect(a.node(named: "a.body")?.shape?.kind == .squircle)
        #expect(a.node(named: "a.body")?.fills.first?.stops.first?.color == Skin2Color(hex: "#112233"))
        let z = try #require(d.node(id: "z"))
        #expect(z.kind == .button)
        #expect(z.children.first?.shape?.taper == 0.2)
    }

    @Test("Inner ids are scoped to the instance; the d-pad's lit arrows and states follow")
    func scopedIDs() throws {
        let d = try Self.doc(##"{ "use": "std.dpad", "id": "pad", "with": { "up": "up", "down": "down", "left": "left", "right": "right" } }"##)
        let pad = try #require(d.node(id: "pad"))
        #expect(d.node(id: "pad.cross") != nil)
        #expect(d.node(id: "pad.arrow")?.repeat?.count == 4)
        #expect(pad.states["pressed.left"]?.patch.first?.target == "#pad.arrow[3]")
        #expect(pad.input == .directions(Skin2Directions(up: "up", down: "down", left: "left", right: "right")))
        // Two instances never collide.
        let two = try Self.doc(#"{ "use": "std.faceButton", "id": "a", "with": { "input": "cross" } }, { "use": "std.faceButton", "id": "b", "with": { "input": "circle" } }"#)
        #expect(two.node(id: "a.body") != nil && two.node(id: "b.body") != nil)
        let report = Skin2Validator.validate(json: try Skin2JSON.parse(Data(skinJSON(
            children: #"{ "use": "std.faceButton", "with": { "input": "cross" } }"#, gameTypes: Self.psx, requires: Self.pad).utf8)))
        #expect(report.errors.first?.message.contains("give this instance an id") == true)
    }

    @Test("The library is reserved: a skin can't define std.* parts, and an unknown one lists the real ones")
    func reserved() {
        let own = skinJSON(children: "", extra: #""parts": { "std.mine": { "node": { "type": "group" } } }"#, gameTypes: Self.psx)
        let e = Skin2Validator.validate(data: Data(own.utf8)).errors.first
        #expect(e?.pointer == "/parts/std.mine")
        #expect(e?.message.contains("standard parts library") == true)
        let unknown = Skin2Validator.validate(data: Data(skinJSON(children: #"{ "use": "std.nope", "id": "x" }"#, gameTypes: Self.psx).utf8)).errors.first
        #expect(unknown?.message.contains("std.faceButton") == true)
    }

    @Test("A caller's library entry overrides the standard one")
    func callerLibraryWins() throws {
        let custom: [String: Skin2JSON] = ["std.pill": ["node": ["type": "group", "id": "mine"]]]
        let json = try Skin2JSON.parse(Data(skinJSON(children: #"{ "use": "std.pill" }"#, gameTypes: Self.psx).utf8))
        let d = try Skin2Document.load(json: json, library: custom)
        #expect(d.root.children.first?.id == "mine")
    }

    @Test("std.* use is a parts.std@2.0 requirement, listed or reported")
    func requiresStd() {
        let child = #"{ "use": "std.pill", "id": "s", "with": { "input": "start" }, "layout": { "size": { "width": 60, "height": 44 } } }"#
        let missing = Skin2Validator.validate(data: Data(skinJSON(children: child, gameTypes: Self.psx, requires: "[]").utf8))
        #expect(missing.errors.contains { $0.message.contains("parts.std@2.0") })
        let ok = Skin2Validator.validate(data: Data(skinJSON(children: child, gameTypes: Self.psx, requires: Self.pad).utf8))
        #expect(ok.errors.isEmpty, "\(ok.errors)")
    }

    // MARK: Fixtures

    @Test("std-parts resolves the std controls with their inputs on every trait set")
    func stdPartsFixture() throws {
        let doc = try Skin2Document.fixture("std-parts")
        for trait in Skin2TraitSet.sets(for: doc) {
            let r = Skin2Resolver.resolve(doc, in: trait.environment)
            let ids = Set(r.controls.compactMap(\.id))
            #expect(ids == ["l1", "l2", "dpad", "leftStick", "r1", "r2", "triangle", "circle", "cross", "square", "rightStick", "select", "start"], "\(trait.name)")
            #expect(r.node(id: "leftStick")?.node.click == "l3")
            #expect(r.node(id: "rightStick")?.node.click == nil)
            #expect(r.node(id: "leftStick")?.travel ?? 0 > 0)
            #expect(r.node(id: "l1")?.node.kind == .trigger)
        }
        let mono = try Skin2Document.fixture("std-parts", theme: "mono")
        let base = Skin2Resolver.resolve(doc, in: Skin2TraitSet.sets(for: doc)[0].environment)
        let themed = Skin2Resolver.resolve(mono, in: Skin2TraitSet.sets(for: doc)[0].environment)
        #expect(base.node(id: "cross.body")?.node.fills != themed.node(id: "cross.body")?.node.fills || base.node(id: "l2.body")?.node.fills != themed.node(id: "l2.body")?.node.fills)
    }

    @Test("std-keypad lays twelve keys on a grid")
    func keypadFixture() throws {
        let doc = try Skin2Document.fixture("std-keypad")
        let r = Skin2Resolver.resolve(doc, in: Skin2TraitSet.sets(for: doc)[0].environment)
        let keys = r.controls.filter { $0.id?.hasPrefix("k") == true || $0.id == "clear" || $0.id == "enter" }
        #expect(keys.count == 12)
        #expect(Set(keys.map(\.frame.x)).count == 3 && Set(keys.map(\.frame.y)).count == 4)
    }

    // MARK: Thumbstick click

    static func stick(click: String?, kind: String = "thumbstick", input: String = "leftThumbstick") -> String {
        let c = click.map { #", "click": "\#($0)""# } ?? ""
        return #"{ "type": "control", "id": "s", "kind": "\#(kind)", "input": "\#(input)"\#(c), "layout": { "frame": [0, 0, 100, 100] }, "children": [ { "type": "shape", "role": "knob", "shape": { "kind": "ellipse" } } ] }"#
    }

    static func clickReport(_ child: String, gameTypes: String = psx) -> Skin2ValidationReport {
        Skin2Validator.validate(data: Data(skinJSON(children: child, gameTypes: gameTypes, requires: #"["controls.thumbstick", "shapes.parametric"]"#).utf8))
    }

    @Test("A thumbstick click is part of the model, survives resolution, and is not one of the stick's axes")
    func clickModel() throws {
        let d = try Skin2Document.inline(skinJSON(children: Self.stick(click: "l3"), gameTypes: Self.psx,
                                                   requires: #"["controls.thumbstick", "shapes.parametric"]"#))
        let s = try #require(d.node(id: "s"))
        #expect(s.click == "l3")
        #expect(s.inputNames == ["leftThumbstick"])
        let r = Skin2Resolver.resolve(d, in: Skin2Environment(size: Skin2Size(width: 400, height: 800)))
        #expect(r.node(id: "s")?.node.click == "l3")
        #expect(Self.clickReport(Self.stick(click: "l3")).issues == [])
        #expect(Self.clickReport(Self.stick(click: nil)).issues == [])
    }

    @Test("The validator checks a click against the stick and the game type")
    func clickValidation() {
        let button = Self.clickReport(Self.stick(click: "l3", kind: "button", input: "cross"))
        #expect(ValidatorTests.has(button.errors, at: "/root/children/0/click", "belongs to a thumbstick"))
        let wrongSystem = Self.clickReport(Self.stick(click: "l3"), gameTypes: #"["com.rileytestut.delta.game.n64"]"#)
        #expect(ValidatorTests.has(wrongSystem.errors, at: "/root/children/0/click", "not an input of game type"))
        #expect(ValidatorTests.has(Self.clickReport(Self.stick(click: "leftThumbstick")).errors, "also one of the stick's axes"))
        #expect(ValidatorTests.has(Self.clickReport(Self.stick(click: "")).errors, "names an input"))
    }

    @Test("The schema takes a string click and rejects any other type")
    func clickSchema() throws {
        let schema = SchemaValidator(root: Skin2Schema.document)
        let ok = try Skin2JSON.parse(Data(skinJSON(children: Self.stick(click: "l3")).utf8))
        #expect(schema.errors(ok) == [])
        let bad = try Skin2JSON.parse(Data(skinJSON(children: Self.stick(click: "l3").replacingOccurrences(of: #""click": "l3""#, with: #""click": 3"#)).utf8))
        #expect(!schema.errors(bad).isEmpty)
        #expect(throws: Skin2Error.self) { try Skin2Document.load(json: bad) }
    }

    // MARK: Image limits (section 11)

    static func png(_ width: Int, _ height: Int) -> Data {
        var b: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
        for n in [width, height] { b += [UInt8(n >> 24 & 255), UInt8(n >> 16 & 255), UInt8(n >> 8 & 255), UInt8(n & 255)] }
        b += [8, 6, 0, 0, 0, 0, 0, 0, 0]
        return Data(b)
    }

    static func imageSkin(_ srcs: [String]) -> Data {
        let nodes = srcs.enumerated().map { #"{ "type": "image", "src": "\#($1)", "id": "i\#($0)" }"# }
        return Data(skinJSON(children: nodes.joined(separator: ","), requires: "[]").utf8)
    }

    static func reader(_ files: [String: Data]) -> Skin2Validator.AssetReader { { files[$0] } }

    @Test("A raster image may be 4096 px on a side, not more")
    func sideLimit() {
        let ok = Skin2Validator.validate(data: Self.imageSkin(["a.png"]), assets: Self.reader(["a.png": Self.png(4096, 1000)]))
        #expect(ok.issues == [])
        let big = Skin2Validator.validate(data: Self.imageSkin(["a.png"]), assets: Self.reader(["a.png": Self.png(1000, 4097)]))
        #expect(ValidatorTests.has(big.errors, at: "/root/children/0/src", "assets/a.png is 1000 × 4097 px; the longest side may be 4096 px"))
    }

    @Test("All images together decode to at most 64 MB, each file counted once")
    func totalLimit() {
        let files = ["a.png": Self.png(4096, 2048), "b.png": Self.png(4096, 2048)] // 32 MB each
        let atLimit = Skin2Validator.validate(data: Self.imageSkin(["a.png", "b.png", "a.png"]), assets: Self.reader(files))
        #expect(atLimit.issues == [])
        let over = Skin2Validator.validate(data: Self.imageSkin(["a.png", "b.png", "c.png"]),
                                           assets: Self.reader(files.merging(["c.png": Self.png(100, 100)]) { a, _ in a }))
        #expect(ValidatorTests.has(over.errors, at: "", "decode to 64.04 MB; the limit is 64 MB (largest: assets/a.png, 4096 × 2048 px, 32.00 MB)"))
    }

    @Test("Missing images are errors; vectors and unknown formats are not measured; no reader means no check")
    func otherImageCases() {
        let missing = Skin2Validator.validate(data: Self.imageSkin(["gone.png"]), assets: Self.reader([:]))
        #expect(ValidatorTests.has(missing.errors, at: "/root/children/0/src", "assets/gone.png is not in the bundle"))
        let vector = Skin2Validator.validate(data: Self.imageSkin(["a.pdf", "b.svg"]), assets: Self.reader(["a.pdf": Data("%PDF".utf8), "b.svg": Data("<svg/>".utf8)]))
        #expect(vector.issues == [])
        let unknown = Skin2Validator.validate(data: Self.imageSkin(["a.webp"]), assets: Self.reader(["a.webp": Data("RIFF".utf8)]))
        #expect(ValidatorTests.has(unknown.warnings, "could not read the size of assets/a.webp"))
        #expect(Skin2Validator.validate(data: Self.imageSkin(["gone.png"])).issues == [])
    }

    @Test("Fills and state patches count too")
    func fillImages() {
        let fill = #"{ "type": "shape", "shape": { "kind": "rect" }, "fills": [ { "type": "image", "src": "tile.png", "mode": "tile" } ] }"#
        let r = Skin2Validator.validate(data: Data(skinJSON(children: fill, requires: #"["shapes.parametric", "paint.image"]"#).utf8),
                                        assets: Self.reader(["tile.png": Self.png(5000, 10)]))
        #expect(ValidatorTests.has(r.errors, at: "/root/children/0/fills/0/src", "5000 × 10 px"))
    }

    @Test("The header probe reads PNG, GIF and JPEG sizes")
    func probe() {
        #expect(Skin2ImageProbe.pixelSize(of: Self.png(640, 480)) == .init(width: 640, height: 480))
        #expect(Skin2ImageProbe.pixelSize(of: Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x80, 0x02, 0xE0, 0x01, 0, 0])) == .init(width: 640, height: 480))
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8, 0x01, 0xE0, 0x02, 0x80, 1, 1, 0x11, 0]
        #expect(Skin2ImageProbe.pixelSize(of: Data(jpeg)) == .init(width: 640, height: 480))
        #expect(Skin2ImageProbe.pixelSize(of: Data("hello".utf8)) == nil)
        #expect(Skin2ImageProbe.pixelSize(of: Self.png(0, 5)) == nil)
    }

    @Test("A header claiming a huge size is a side-limit error, not an overflow")
    func hugeHeader() {
        let huge = Self.png(Int(Int32.max), Int(Int32.max))
        let report = Skin2Validator.validate(data: Self.imageSkin(["a.png"]), assets: Self.reader(["a.png": huge]))
        #expect(ValidatorTests.has(report.errors, at: "/root/children/0/src", "the longest side may be 4096 px"))
        #expect(!ValidatorTests.has(report.errors, at: "", "decode to"), "an oversized image is left out of the total")
    }

    @Test("A JPEG frame after more than 64 KiB of metadata is still found, in a slice too")
    func jpegPastLongMetadata() {
        var bytes: [UInt8] = [0xFF, 0xD8]
        for _ in 0..<2 { // two maximum-length APP1 segments: the frame starts past 128 KiB
            bytes += [0xFF, 0xE1, 0xFF, 0xFF] + [UInt8](repeating: 0, count: 0xFFFF - 2)
        }
        bytes += [0xFF, 0xC0, 0, 11, 8, 0x13, 0x88, 0x01, 0x40, 1, 1, 0x11, 0] // 320 × 5000
        #expect(bytes.count > 128 * 1024)
        #expect(Skin2ImageProbe.pixelSize(of: Data(bytes)) == .init(width: 320, height: 5000))
        let sliced = (Data([0, 0, 0]) + Data(bytes))[3...] // nonzero startIndex
        #expect(Skin2ImageProbe.pixelSize(of: sliced) == .init(width: 320, height: 5000))
        let report = Skin2Validator.validate(data: Self.imageSkin(["a.jpg"]), assets: Self.reader(["a.jpg": Data(bytes)]))
        #expect(ValidatorTests.has(report.errors, at: "/root/children/0/src", "assets/a.jpg is 320 × 5000 px"))
    }

    @Test("The assets folder reader stays inside the folder")
    func directoryReader() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skin2-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Self.png(10, 10).write(to: dir.appendingPathComponent("assets/a.png"))
        try Data("secret".utf8).write(to: dir.appendingPathComponent("skin.json"))
        let read = Skin2Validator.assetReader(directory: dir.appendingPathComponent("assets"))
        #expect(read("a.png") != nil)
        #expect(read("../skin.json") == nil)
        #expect(read("missing.png") == nil)
    }
}

private extension Skin2Node {
    func node(named id: String) -> Skin2Node? {
        var found: Skin2Node?
        preorder { if found == nil, $0.id == id { found = $0 } }
        return found
    }
}
