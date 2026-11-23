import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Accessory screens")
struct AccessoryScreenTests {
    static let main = #"{"type":"screen","id":"main","aspect":1.3333,"layout":{"size":{"width":"100%"},"anchor":{"y":"top"}}}"#
    static func lcd(_ id: String = "lcd", source: String = "vmu.p1", extra: String = "") -> String {
        #"{"type":"screen","id":"\#(id)","source":"\#(source)","layout":{"size":{"width":96},"anchor":{"y":"bottom"}}\#(extra)}"#
    }

    static let env = Skin2Environment(size: Skin2Size(width: 390, height: 844))

    static func report(_ children: String, extra: String = #""optional":["screens.accessory"]"#) -> Skin2ValidationReport {
        Skin2Validator.validate(data: Data(skinJSON(children: children, extra: extra, requires: #"["layout.anchors"]"#).utf8))
    }

    static func has(_ issues: [Skin2Issue], at pointer: String, _ text: String) -> Bool {
        issues.contains { $0.pointer == pointer && $0.message.contains(text) }
    }

    @Test("An accessory screen is never the viewport or the screen area")
    func accessoryScreenIsNotTheViewport() throws {
        let follower = #"{"type":"group","id":"follower","layout":{"anchor":{"to":"screen"}}}"#
        let doc = try Skin2Document.inline(skinJSON(children: [Self.lcd(), Self.main, follower].joined(separator: ",")))
        let r = Skin2Resolver.resolve(doc, in: Self.env)
        #expect(r.screens.map(\.id) == ["main"])
        #expect(r.accessoryScreens.map(\.id) == ["lcd"])
        #expect(r.node(id: "follower")?.frame == r.node(id: "main")?.frame)
        #expect(doc.node(id: "lcd")?.isAccessoryScreen == true)
        #expect(doc.node(id: "main")?.isAccessoryScreen == false)
    }

    @Test("source game is the game picture")
    func sourceGameIsNotAccessory() throws {
        let doc = try Skin2Document.inline(skinJSON(children: #"{"type":"screen","id":"main","source":"game"}"#))
        #expect(doc.node(id: "main")?.isAccessoryScreen == false)
        #expect(Skin2Resolver.resolve(doc, in: Self.env).screens.count == 1)
    }

    @Test("Without an aspect an accessory screen takes its source's")
    func accessoryScreenDefaultsToNativeAspect() throws {
        let doc = try Skin2Document.inline(skinJSON(children: Self.lcd()))
        let frame = try #require(Skin2Resolver.resolve(doc, in: Self.env).node(id: "lcd")?.frame)
        #expect(frame.width == 96 && frame.height == 64)
        #expect(Skin2Capabilities.nativeAspect["vmu.p3"] == 1.5)
        let own = try Skin2Document.inline(skinJSON(children: Self.lcd(extra: #","aspect":2"#)))
        #expect(Skin2Resolver.resolve(own, in: Self.env).node(id: "lcd")?.frame.height == 48)
    }

    @Test("An accessory screen takes no role or placement")
    func accessoryScreenRejectsRoleAndPlacement() {
        let r = Self.report([Self.main, Self.lcd(extra: #","role":"top","placement":"app""#)].joined(separator: ","))
        #expect(Self.has(r.errors, at: "/root/children/1/role", "role"))
        #expect(Self.has(r.errors, at: "/root/children/1/placement", "placement"))
    }

    @Test("A source is game or a registered picture")
    func accessoryScreenSourceMustBeRegistered() {
        let r = Self.report([Self.main, Self.lcd(source: "gameboy.lcd")].joined(separator: ","))
        #expect(Self.has(r.errors, at: "/root/children/1/source", "gameboy.lcd"))
        #expect(Self.report([Self.main, Self.lcd()].joined(separator: ",")).issues == [])
    }

    @Test("At most four accessory screens")
    func fiveAccessoryScreensIsAnError() {
        let four = (1...4).map { Self.lcd("lcd\($0)", source: "vmu.p\($0)") }
        #expect(Self.report(([Self.main] + four).joined(separator: ",")).errors.isEmpty)
        let r = Self.report(([Self.main] + four + [Self.lcd("lcd5")]).joined(separator: ","))
        #expect(Self.has(r.errors, at: "/root", "4 accessory screens"))
    }

    @Test("An accessory screen does not stand in for a game screen")
    func accessoryScreenAloneDoesNotSatisfyScreenChecks() {
        let follower = #"{"type":"group","id":"follower","layout":{"anchor":{"to":"screen"}}}"#
        let r = Self.report([Self.lcd(), follower].joined(separator: ","))
        #expect(Self.has(r.errors, at: "/root/children/1/layout/anchor/to", "no screen node comes earlier"))
        let listed = Self.report(Self.lcd(), extra: #""optional":["screens.accessory"],"screens":["lcd"]"#)
        #expect(Self.has(listed.errors, at: "/screens/0", "lcd"))
    }

    @Test("Using an accessory screen is the screens.accessory feature")
    func featureIsDetected() {
        let r = Self.report([Self.main, Self.lcd()].joined(separator: ","), extra: "")
        #expect(Self.has(r.errors, at: "/requires", "uses screens.accessory"))
    }

    @Test("Schema and decoder agree on source and sampling")
    func schemaShapes() throws {
        let schema = SchemaValidator(root: Skin2Schema.document)
        let good = try Skin2JSON.parse(Data(skinJSON(children: Self.lcd(extra: #","sampling":"linear""#)).utf8))
        #expect(schema.errors(good) == [])
        #expect(try Skin2Document.load(json: good).node(id: "lcd")?.sampling == .linear)
        for bad in [Self.lcd(extra: #","sampling":"cubic""#), #"{"type":"screen","id":"s","source":7}"#] {
            let source = try Skin2JSON.parse(Data(skinJSON(children: bad).utf8))
            #expect(!schema.errors(source).isEmpty)
            #expect(throws: Skin2Error.self) { try Skin2Document.load(json: source) }
        }
    }
}
