import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Semantic inputs")
struct SemanticInputTests {
    static func button(_ input: String, kind: String = "button", id: String = "coin") -> String {
        #"{"type":"control","id":"\#(id)","kind":"\#(kind)","input":"\#(input)","layout":{"frame":[100,100,60,60]}}"#
    }

    static func report(_ children: String) -> Skin2ValidationReport {
        Skin2Validator.validate(data: Data(skinJSON(children: children, extra: #""optional":["inputs.semantic"]"#,
                                                    requires: "[]").utf8))
    }

    static func has(_ issues: [Skin2Issue], at pointer: String, _ text: String) -> Bool {
        issues.contains { $0.pointer == pointer && $0.message.contains(text) }
    }

    @Test("A semantic control exists only while the app has wired its input")
    func semanticControlNeedsItsCapability() throws {
        let doc = try Skin2Document.inline(skinJSON(children: Self.button("arcade.coin1")))
        let size = Skin2Size(width: 390, height: 844)
        #expect(Skin2Resolver.resolve(doc, in: Skin2Environment(size: size)).node(id: "coin") == nil)
        #expect(Skin2Resolver.resolve(doc, in: Skin2Environment(size: size, capabilities: ["input.arcade.coin2"])).node(id: "coin") == nil)
        #expect(Skin2Resolver.resolve(doc, in: Skin2Environment(size: size, capabilities: ["input.arcade.coin1"])).node(id: "coin") != nil)
        #expect(doc.mentionedCapabilities == ["input.arcade.coin1"])
        #expect(Skin2Capabilities.isKnown("input.arcade.coin1") && !Skin2Capabilities.isKnown("input.arcade.jukebox"))
    }

    @Test("A dotted input outside the registry is an error")
    func unknownDottedInputIsAnError() {
        #expect(Self.has(Self.report(Self.button("arcade.jukebox")).errors, at: "/root/children/0", "arcade.jukebox"))
        #expect(Self.report(Self.button("arcade.coin1")).issues == [])
    }

    @Test("Two-position inputs wait for the switch control")
    func twoPositionInputIsRejectedForNow() {
        #expect(Self.has(Self.report(Self.button("console.tvType")).errors, at: "/root/children/0", "switch"))
    }

    @Test("Semantic inputs go on buttons and triggers")
    func kinds() {
        #expect(Self.report(Self.button("arcade.coin1", kind: "trigger")).errors.isEmpty)
        #expect(Self.has(Self.report(Self.button("arcade.coin1", kind: "action")).errors, at: "/root/children/0", "arcade.coin1"))
    }

    @Test("Using one is the inputs.semantic feature")
    func feature() {
        let r = Skin2Validator.validate(data: Data(skinJSON(children: Self.button("arcade.coin1"), requires: "[]").utf8))
        #expect(Self.has(r.errors, at: "/requires", "uses inputs.semantic"))
    }

    @Test("The registry holds the design's rows, in order")
    func registryHasTheSpecRows() {
        #expect(Skin2SemanticInputs.all.map(\.name) == [
            "arcade.coin1", "arcade.coin2", "arcade.service", "arcade.test",
            "console.reset", "console.select",
            "console.difficulty.left", "console.difficulty.right", "console.tvType",
            "vmu.a", "vmu.b", "vmu.mode", "vmu.sleep", "vmu.up", "vmu.down", "vmu.left", "vmu.right",
        ])
        #expect(Skin2SemanticInputs.all.filter { $0.kind == .twoPosition }.map(\.name)
            == ["console.difficulty.left", "console.difficulty.right", "console.tvType"])
        #expect(Skin2SemanticInputs.entry("arcade.coin1")?.label == "Coin 1")
        #expect(Skin2SemanticInputs.entry("a") == nil)
        #expect(Skin2SemanticInputs.isSemantic("vmu.a") && !Skin2SemanticInputs.isSemantic("a"))
        #expect(Skin2SemanticInputs.all.allSatisfy { !$0.label.isEmpty })
    }
}
