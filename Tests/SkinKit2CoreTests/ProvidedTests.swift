import Foundation
import Testing
@testable import SkinKit2Core

@Suite("What a resolved skin provides")
struct ProvidedTests {
    static let caps: Set<String> = ["picture.vmu.p1", "input.arcade.coin1"]

    static func env(capabilities: Set<String> = caps, flags: Set<String> = []) -> Skin2Environment {
        Skin2Environment(size: Skin2Size(width: 390, height: 844), flags: flags, capabilities: capabilities)
    }

    static func provided(_ children: String, capabilities: Set<String> = caps, flags: Set<String> = [],
                         edits: [String: Skin2Edit] = [:]) throws -> Skin2Provided {
        let doc = try Skin2Document.inline(skinJSON(children: children))
        return Skin2Resolver.resolve(doc, in: env(capabilities: capabilities, flags: flags), edits: edits).provided
    }

    static func lcd(_ id: String = "lcd", frame: String = "[10,10,96,64]", extra: String = "") -> String {
        #"{"type":"screen","id":"\#(id)","source":"vmu.p1","layout":{"frame":\#(frame)}\#(extra)}"#
    }

    static func coin(_ id: String = "coin", frame: String = "[10,200,60,60]", input: String = "arcade.coin1", extra: String = "") -> String {
        #"{"type":"control","id":"\#(id)","kind":"button","input":"\#(input)","layout":{"frame":\#(frame)}\#(extra)}"#
    }

    @Test("The thresholds are the design's")
    func constants() {
        #expect(Skin2Provided.minimumPicture == Skin2Size(width: 48, height: 32))
        #expect(Skin2Provided.minimumControl == Skin2Size(width: 44, height: 44))
        #expect(Skin2Provided.minimumOpacity == 0.05)
        #expect(Skin2Provided.none == Skin2Provided(pictures: [], inputs: [], panels: [:]))
    }

    @Test("A screen and a control outside any panel are provided")
    func noPanel() throws {
        let p = try Self.provided(Self.lcd() + "," + Self.coin())
        #expect(p == Skin2Provided(pictures: ["vmu.p1"], inputs: ["arcade.coin1"], panels: [:]))
    }

    @Test("A fixed panel provides its picture")
    func fixedPanelProvidesItsPicture() throws {
        let p = try Self.provided(PanelTests.panel(presentation: "fixed"))
        #expect(p.pictures == ["vmu.p1"] && p.panels == ["vmu": true])
    }

    @Test("An open shelf provides its picture")
    func openShelfProvidesItsPicture() throws {
        let p = try Self.provided(PanelTests.panel(), flags: ["panel.vmu.open"])
        #expect(p.pictures == ["vmu.p1"] && p.panels == ["vmu": true])
    }

    @Test("A closed shelf the player can open still provides")
    func closedShelfWithReachableHandleStillProvides() throws {
        let p = try Self.provided(PanelTests.panel(extraChildren: Self.coin("coin", frame: "[60,60,60,60]")))
        #expect(p == Skin2Provided(pictures: ["vmu.p1"], inputs: ["arcade.coin1"], panels: ["vmu": false]))
    }

    @Test("A closed shelf whose handle is off screen provides nothing")
    func closedShelfWithUnreachableHandleProvidesNothing() throws {
        let p = try Self.provided(PanelTests.panel(), edits: ["tab": Skin2Edit(offset: .init(x: -400, y: 0))])
        #expect(p.pictures.isEmpty && p.panels == ["vmu": false])
        let hidden = try Self.provided(PanelTests.panel(), edits: ["tab": Skin2Edit(hidden: true)])
        #expect(hidden.pictures.isEmpty)
    }

    @Test("What a closed shelf would show when open is what counts")
    func closedShelfIsJudgedOpen() throws {
        // Open, the LCD shrinks below the minimum: closed, the shelf does not claim it.
        let small = #","when":[{"flag":"panel.vmu.open","layout":{"frame":[56,8,40,27]}}]"#
        let lcd = #"{"type":"screen","id":"lcd2","source":"vmu.p1","layout":{"frame":[56,8,96,64]}\#(small)}"#
        let panel = #"""
        {"type":"group","id":"shelf","layout":{"frame":[100,100,160,120]},"panel":{"name":"vmu","presentation":"shelf","handle":"#tab"},
         "children":[\#(lcd),{"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[0,0,48,48]}}]}
        """#
        #expect(try Self.provided(panel).pictures.isEmpty)
    }

    @Test("A picture smaller than 48 by 32 points is not provided")
    func pictureSmallerThan48x32IsNotProvided() throws {
        #expect(try Self.provided(Self.lcd(frame: "[10,10,40,27]")).pictures.isEmpty)
        #expect(try Self.provided(Self.lcd(frame: "[10,10,48,32]")).pictures == ["vmu.p1"])
    }

    @Test("A picture that leaves the canvas is not provided")
    func pictureOutsideTheCanvasIsNotProvided() throws {
        #expect(try Self.provided(Self.lcd(frame: "[350,10,96,64]")).pictures.isEmpty)
        #expect(try Self.provided(Self.lcd(), edits: ["lcd": Skin2Edit(offset: .init(x: -60, y: 0))]).pictures.isEmpty)
    }

    @Test("A nearly transparent picture is not provided")
    func nearlyTransparentPictureIsNotProvided() throws {
        #expect(try Self.provided(Self.lcd(extra: #","opacity":0.04"#)).pictures.isEmpty)
        #expect(try Self.provided(Self.lcd(extra: #","opacity":0.06"#)).pictures == ["vmu.p1"])
        // Opacity multiplies down the tree.
        let faded = #"{"type":"group","id":"g","opacity":0.2,"children":[\#(Self.lcd(extra: #","opacity":0.2"#))]}"#
        #expect(try Self.provided(faded).pictures.isEmpty)
    }

    @Test("A control smaller than 44 by 44 points is not provided")
    func controlSmallerThan44IsNotProvided() throws {
        #expect(try Self.provided(Self.coin(frame: "[10,200,40,40]")).inputs.isEmpty)
        #expect(try Self.provided(Self.coin(frame: "[10,200,40,40]", extra: #","hit":{"extend":2}"#)).inputs == ["arcade.coin1"])
        #expect(try Self.provided(Self.coin(frame: "[-30,200,60,60]")).inputs.isEmpty)
    }

    @Test("A node marked duplicate does not claim")
    func duplicateNodeDoesNotClaim() throws {
        #expect(try Self.provided(Self.lcd(extra: #","duplicate":true"#)).pictures.isEmpty)
        #expect(try Self.provided(Self.lcd(extra: #","duplicate":true"#) + "," + Self.lcd("second", frame: "[10,100,96,64]")).pictures == ["vmu.p1"])
        #expect(try Self.provided(Self.coin(extra: #","duplicate":true"#)).inputs.isEmpty)
    }

    @Test("duplicate belongs on a screen or a control")
    func duplicateOnAGroupIsAValidationError() {
        let r = Skin2Validator.validate(data: Data(skinJSON(children: #"{"type":"group","id":"g","duplicate":true}"#, requires: "[]").utf8))
        #expect(r.errors.contains { $0.pointer == "/root/children/0/duplicate" })
        let ok = Skin2Validator.validate(data: Data(skinJSON(children: Self.lcd(extra: #","duplicate":true"#),
                                                             extra: #""optional":["screens.accessory"]"#, requires: "[]").utf8))
        #expect(ok.errors.isEmpty)
    }

    @Test("Panels report their open state")
    func panelsReportTheirOpenState() throws {
        #expect(try Self.provided(PanelTests.panel()).panels == ["vmu": false])
        #expect(try Self.provided(PanelTests.panel(), flags: ["panel.vmu.open"]).panels == ["vmu": true])
    }

    @Test("Without the capability nothing is provided")
    func missingCapabilityProvidesNothing() throws {
        #expect(try Self.provided(PanelTests.panel() + "," + Self.coin(frame: "[10,400,60,60]"), capabilities: []) == .none)
        // A bare accessory screen still lays out without its capability, but shows nothing, so it claims nothing.
        #expect(try Self.provided(Self.lcd(), capabilities: []).pictures.isEmpty)
    }

    @Test("Classic button names are never in inputs")
    func classicButtonNamesAreNeverInInputs() throws {
        #expect(try Self.provided(Self.coin("a", input: "a")).inputs.isEmpty)
    }

    @Test("keeping narrows pictures to the ones delivered")
    func keepingNarrowsToDeliveredPictures() {
        let p = Skin2Provided(pictures: ["vmu.p1", "vmu.p2"], inputs: ["arcade.coin1"], panels: ["vmu": true])
        #expect(p.keeping(pictures: ["vmu.p2", "vmu.p3"]) == Skin2Provided(pictures: ["vmu.p2"], inputs: ["arcade.coin1"], panels: ["vmu": true]))
        #expect(p.keeping(pictures: []).pictures.isEmpty)
    }
}
