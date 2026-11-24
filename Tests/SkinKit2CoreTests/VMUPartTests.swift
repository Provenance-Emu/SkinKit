import Foundation
import Testing
@testable import SkinKit2Core

@Suite("std.vmu and the Dreamcast VMU skin")
struct VMUPartTests {
    static func doc(_ children: String) throws -> Skin2Document {
        try Skin2Document.inline(skinJSON(children: children, gameTypes: #"["com.rileytestut.delta.game.dc"]"#))
    }

    @Test("std.vmu is a housing around an accessory screen")
    func stdVMUExpandsWithAnAccessoryScreen() throws {
        let doc = try Self.doc(#"{ "use": "std.vmu", "id": "v", "layout": { "size": { "width": 140, "height": 110 } } }"#)
        let lcd = try #require(doc.node(id: "v.lcd"))
        #expect(lcd.type == .screen && lcd.source == "vmu.p1" && lcd.isAccessoryScreen)
        for id in ["v.body", "v.window", "v.glass"] { #expect(doc.node(id: id) != nil, "\(id)") }
        // The window surrounds the screen, and the screen keeps the LCD's 48:32.
        let r = Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 390, height: 844), capabilities: ["picture.vmu.p1"]))
        let screen = try #require(r.node(id: "v.lcd")?.frame), window = try #require(r.node(id: "v.window")?.frame)
        let body = try #require(r.node(id: "v")?.frame)
        #expect(abs(screen.width / screen.height - 1.5) < 0.02)
        #expect(window.contains(screen) && body.contains(window))
        #expect(screen.width >= 96)
        #expect(r.provided.pictures == ["vmu.p1"])
        // No working buttons in this slice.
        #expect(r.controls.isEmpty)
    }

    @Test("The source parameter picks the player")
    func stdVMUSourceParameterIsPassedThrough() throws {
        let doc = try Self.doc(##"{ "use": "std.vmu", "id": "v", "with": { "source": "vmu.p2", "body": "#FFFFFF", "glass": 0, "buttons": 1 } }"##)
        #expect(doc.node(id: "v.lcd")?.source == "vmu.p2")
        #expect(doc.node(id: "v.glass")?.opacity == 0)
        #expect(doc.node(id: "v.keys")?.opacity == 1)
        #expect(try Self.doc(#"{ "use": "std.vmu", "id": "v" }"#).node(id: "v.keys")?.opacity == 0)
    }

    @Test("Using std.vmu is parts.std@2.1")
    func usingStdVMUNeedsStdParts21() throws {
        let json = skinJSON(children: #"{ "use": "std.vmu", "id": "v" }"#, requires: "[]")
        let source = try Skin2JSON.parse(Data(json.utf8))
        let used = Skin2Features.used(source: source, documents: [try Skin2Document.load(json: source)])
        #expect(used.contains("parts.std@2.1") && used.contains("parts") && used.contains("screens.accessory"))
        #expect(!used.contains("parts.std@2.0"))
        #expect(Skin2StdParts.featureName21 == "parts.std@2.1" && Skin2StdParts.parts21 == ["std.vmu"])
        let older = try Skin2JSON.parse(Data(skinJSON(children: #"{ "use": "std.pill", "id": "p", "with": { "input": "start" } }"#).utf8))
        #expect(!Skin2Features.used(source: older, documents: []).contains("parts.std@2.1"))
    }

    // MARK: The skin

    static let skin = "dreamcast-vmu"

    @Test("The skin names what it is and needs the new parts")
    func vmuSkinRequiresStdParts21() throws {
        let doc = try Skin2Document.fixture(Self.skin)
        #expect(doc.identifier == "com.provenance-emu.skinkit.dreamcast-vmu" && doc.name == "Dreamcast VMU")
        #expect(doc.requires.contains("parts.std@2.1"))
        #expect(Set(doc.optional) == ["capabilities", "screens.accessory", "panels"])
        let panel = try #require(doc.panels.first)
        #expect(doc.panels.count == 1)
        #expect(panel.name == "vmu" && panel.label == "Visual Memory" && panel.needs == ["picture.vmu.p1"] && panel.handle == "#vmuTab")
    }

    @Test("The skin validates with no errors or warnings")
    func vmuSkinValidatesClean() throws {
        let report = Skin2Validator.validate(data: try Skin2Paths.skinData(Self.skin))
        #expect(report.issues.map(\.description) == [])
    }

    @Test("The shelf starts open")
    func vmuSkinShelfStartsOpen() throws {
        #expect(try Skin2Document.fixture(Self.skin).initialPanelFlags == ["panel.vmu.open"])
    }

    @Test("The skin provides the picture on every trait, shelf open or closed")
    func vmuSkinProvidesThePictureOnEveryTrait() throws {
        let doc = try Skin2Document.fixture(Self.skin)
        var shelves = 0, fixed = 0
        for trait in Skin2TraitSet.sets(for: doc) {
            for flags in [Set<String>(), ["panel.vmu.open"]] {
                var environment = trait.environment
                environment.capabilities = ["picture.vmu.p1"]
                environment.flags = flags
                let r = Skin2Resolver.resolve(doc, in: environment)
                #expect(r.provided.pictures == ["vmu.p1"], "\(trait.name) \(flags)")
                let panel = try #require(r.panels.first)
                if panel.presentation == .shelf { shelves += 1; #expect(panel.handleReachable, "\(trait.name)") } else { fixed += 1 }
                // The LCD is big enough to read: at least two points per LCD cell.
                if panel.isOpen { #expect((r.node(id: "vmu.lcd")?.frame.width ?? 0) >= 96, "\(trait.name)") }
            }
            // Without the capability the panel is gone and nothing is claimed.
            #expect(Skin2Resolver.resolve(doc, in: trait.environment).provided == .none)
        }
        // A shelf in phone landscape, fixed in portrait and on iPad.
        #expect(shelves > 0 && fixed > 0)
        let phoneLandscape = try #require(Skin2TraitSet.all.first { $0.name == "iphone-edgeToEdge-landscape" })
        var environment = phoneLandscape.environment
        environment.capabilities = ["picture.vmu.p1"]
        #expect(Skin2Resolver.resolve(doc, in: environment).panels.first?.presentation == .shelf)
        for name in ["iphone-edgeToEdge-portrait", "ipad-standard-landscape"] {
            var e = try #require(Skin2TraitSet.all.first { $0.name == name }).environment
            e.capabilities = ["picture.vmu.p1"]
            #expect(Skin2Resolver.resolve(doc, in: e).panels.first?.presentation == .fixed, "\(name)")
        }
    }

    @Test("The controller has the Dreamcast pad's inputs")
    func vmuSkinHasThePad() throws {
        let doc = try Skin2Document.fixture(Self.skin)
        var inputs: Set<String> = []
        doc.root.preorder { if $0.type == .control { inputs.formUnion($0.inputNames) } }
        #expect(inputs.isSuperset(of: ["a", "b", "x", "y", "l", "r", "start", "up", "down", "left", "right", "leftThumbstick"]))
    }
}
