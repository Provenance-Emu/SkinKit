import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Capabilities and optional features")
struct CapabilityTests {
    static let lamp = #"""
      {"type":"shape","id":"lamp","shape":{"kind":"rect"},"layout":{"size":{"width":40,"height":40}},
       "visible":{"has":"picture.vmu.p1"}}
    """#

    static func env(_ capabilities: Set<String> = []) -> Skin2Environment {
        Skin2Environment(size: Skin2Size(width: 390, height: 844), capabilities: capabilities)
    }

    static func report(_ children: String, requires: String = #"["shapes.parametric"]"#, extra: String = "") -> Skin2ValidationReport {
        Skin2Validator.validate(data: Data(skinJSON(children: children, extra: extra, requires: requires).utf8))
    }

    static func has(_ issues: [Skin2Issue], at pointer: String, _ text: String) -> Bool {
        issues.contains { $0.pointer == pointer && $0.message.contains(text) }
    }

    @Test("A has condition holds only while the app supplies the capability")
    func hasConditionFollowsCapabilities() throws {
        let doc = try Skin2Document.inline(skinJSON(children: Self.lamp, extra: #""optional":["capabilities"]"#))
        #expect(doc.optional == ["capabilities"])
        #expect(Skin2Resolver.resolve(doc, in: Self.env()).node(id: "lamp") == nil)
        #expect(Skin2Resolver.resolve(doc, in: Self.env(["picture.vmu.p1"])).node(id: "lamp") != nil)
    }

    @Test("A has list needs every name")
    func hasAcceptsAList() throws {
        let children = #"{"type":"group","id":"both","visible":{"has":["picture.vmu.p1","picture.vmu.p2"]}}"#
        let doc = try Skin2Document.inline(skinJSON(children: children, extra: #""optional":["capabilities"]"#))
        #expect(Skin2Resolver.resolve(doc, in: Self.env(["picture.vmu.p1"])).node(id: "both") == nil)
        #expect(Skin2Resolver.resolve(doc, in: Self.env(["picture.vmu.p1", "picture.vmu.p2"])).node(id: "both") != nil)
    }

    @Test("has works in a when entry")
    func hasInWhen() throws {
        let children = #"{"type":"group","id":"g","when":[{"has":"picture.vmu.p1","opacity":0.5}]}"#
        let doc = try Skin2Document.inline(skinJSON(children: children, extra: #""optional":["capabilities"]"#))
        #expect(Skin2Resolver.resolve(doc, in: Self.env()).node(id: "g")?.opacity == 1)
        #expect(Skin2Resolver.resolve(doc, in: Self.env(["picture.vmu.p1"])).node(id: "g")?.opacity == 0.5)
    }

    @Test("A capability outside the registry is an error")
    func unknownCapabilityIsAValidationError() {
        let children = #"{"type":"group","id":"g","visible":{"has":"picture.gameboy"}}"#
        let r = Self.report(children, requires: "[]", extra: #""optional":["capabilities"]"#)
        #expect(Self.has(r.errors, at: "/root/children/0/visible/has", "picture.gameboy"))
        let inWhen = #"{"type":"group","id":"g","when":[{"has":["picture.vmu.p1","nope"],"opacity":0.5}]}"#
        let w = Self.report(inWhen, requires: "[]", extra: #""optional":["capabilities"]"#)
        #expect(Self.has(w.errors, at: "/root/children/0/when/0/has", "nope"))
    }

    @Test("Every feature the content uses is in requires or optional")
    func featureUsedMustBeRequiredOrOptional() {
        let missing = Self.report(Self.lamp)
        #expect(Self.has(missing.errors, at: "/requires", "uses capabilities"))
        #expect(Self.report(Self.lamp, extra: #""optional":["capabilities"]"#).issues == [])
        #expect(Self.report(Self.lamp, requires: #"["shapes.parametric","capabilities"]"#).issues == [])
    }

    @Test("optional names are known features, used, and not also required")
    func unknownOptionalNameIsAnError() {
        let unknown = Self.report(Self.lamp, extra: #""optional":["nope","capabilities"]"#)
        #expect(Self.has(unknown.errors, at: "/optional/0", "nope"))
        let both = Self.report(Self.lamp, requires: #"["shapes.parametric","capabilities"]"#, extra: #""optional":["capabilities"]"#)
        #expect(Self.has(both.errors, at: "/optional/0", "both"))
        let unused = Self.report(#"{"type":"group"}"#, requires: "[]", extra: #""optional":["capabilities"]"#)
        #expect(unused.errors.isEmpty)
        #expect(Self.has(unused.warnings, at: "/optional/0", "does not use"))
    }

    @Test("The registry names four memory-unit pictures")
    func registry() {
        #expect(Skin2Capabilities.pictureSources == ["vmu.p1", "vmu.p2", "vmu.p3", "vmu.p4"])
        #expect(Skin2Capabilities.picture("vmu.p1") == "picture.vmu.p1")
        #expect(Skin2Capabilities.input("arcade.coin1") == "input.arcade.coin1")
        #expect(Skin2Capabilities.isKnown("picture.vmu.p4"))
        #expect(!Skin2Capabilities.isKnown("picture.vmu.p5"))
        #expect(!Skin2Capabilities.isKnown("vmu.p1"))
    }

    @Test("Schema and decoder agree on has and optional")
    func schemaShapes() throws {
        let schema = SchemaValidator(root: Skin2Schema.document)
        let good = try Skin2JSON.parse(Data(skinJSON(children: Self.lamp, extra: #""optional":["capabilities"]"#).utf8))
        #expect(schema.errors(good) == [])
        for bad in [skinJSON(children: #"{"type":"group","visible":{"has":7}}"#),
                    skinJSON(children: #"{"type":"group"}"#, extra: #""optional":"capabilities""#)] {
            let source = try Skin2JSON.parse(Data(bad.utf8))
            #expect(!schema.errors(source).isEmpty)
            #expect(throws: Skin2Error.self) { try Skin2Document.load(json: source) }
        }
    }
}
