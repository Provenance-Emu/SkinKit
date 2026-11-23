import Foundation
import Testing
@testable import SkinKit2Core

@Suite("Panels and shelves")
struct PanelTests {
    /// A panel group at `origin` holding a body, an LCD and a 48×48 tab.
    static func panel(name: String = "vmu", id: String = "vmuPanel", origin: String = "100, 100", presentation: String? = "shelf",
                      handle: String? = "#tab", open: Bool = false, needs: String = #"["picture.vmu.p1"]"#,
                      when: String = "", tab: String? = nil, extraChildren: String = "") -> String {
        var fields = [#""name":"\#(name)""#, #""label":"Visual Memory""#, #""needs":\#(needs)"#, #""open":\#(open)"#]
        if let presentation { fields.append(#""presentation":"\#(presentation)""#) }
        if let handle { fields.append(#""handle":"\#(handle)""#) }
        let tabNode = tab ?? #"{"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[0,0,48,48]}}"#
        return #"""
        {"type":"group","id":"\#(id)","layout":{"frame":[\#(origin),160,120]},"panel":{\#(fields.joined(separator: ","))}
         \#(when.isEmpty ? "" : #","when":[\#(when)]"#),
         "children":[
           {"type":"shape","id":"\#(id).body","shape":{"kind":"rect"}},
           {"type":"screen","id":"\#(id).lcd","source":"vmu.p1","layout":{"frame":[56,8,96,64]}},
           \#(tabNode)\#(extraChildren.isEmpty ? "" : "," + extraChildren)
         ]}
        """#
    }

    static let caps: Set<String> = ["picture.vmu.p1"]

    static func env(_ w: Double = 390, _ h: Double = 844, capabilities: Set<String> = caps, flags: Set<String> = []) -> Skin2Environment {
        Skin2Environment(size: Skin2Size(width: w, height: h), flags: flags, capabilities: capabilities)
    }

    static func doc(_ children: String) throws -> Skin2Document { try Skin2Document.inline(skinJSON(children: children)) }

    static func report(_ children: String) -> Skin2ValidationReport {
        Skin2Validator.validate(data: Data(skinJSON(children: children, extra: #""optional":["capabilities","screens.accessory","panels"]"#,
                                                    gameTypes: #"["com.rileytestut.delta.game.dc"]"#, requires: #"["shapes.parametric"]"#).utf8))
    }

    static func has(_ issues: [Skin2Issue], at pointer: String? = nil, _ text: String) -> Bool {
        issues.contains { (pointer == nil || $0.pointer == pointer) && $0.message.contains(text) }
    }

    // MARK: Resolver

    @Test("A panel whose needs the app lacks is absent with everything in it")
    func panelWithoutItsNeedsIsAbsent() throws {
        let doc = try Self.doc(Self.panel())
        let r = Skin2Resolver.resolve(doc, in: Self.env(capabilities: []))
        #expect(r.panels.isEmpty)
        #expect(r.node(id: "vmuPanel") == nil && r.node(id: "tab") == nil && r.node(id: "vmuPanel.lcd") == nil)
        #expect(doc.panels.map(\.name) == ["vmu"])
    }

    @Test("A closed shelf keeps only its handle")
    func closedShelfKeepsOnlyItsHandle() throws {
        let r = Skin2Resolver.resolve(try Self.doc(Self.panel()), in: Self.env())
        #expect(r.nodes.compactMap(\.id) == ["vmuPanel", "tab"])
        let panel = try #require(r.panels.first)
        #expect(r.panels.count == 1 && panel.panel.name == "vmu" && panel.presentation == .shelf)
        #expect(!panel.isOpen && panel.handleReachable)
        #expect(panel.frame == Skin2Rect(x: 100, y: 100, width: 160, height: 120))
        #expect(r.node(id: "tab")?.panelName == "vmu" && r.node(id: "vmuPanel")?.panelName == "vmu")
        #expect(r.accessoryScreens.isEmpty)
    }

    @Test("A handle nested in a subgroup keeps its ancestors")
    func nestedHandleKeepsAncestors() throws {
        let tab = #"""
        {"type":"group","id":"rail","layout":{"frame":[0,0,48,120]},"children":[
          {"type":"shape","id":"railArt","shape":{"kind":"rect"}},
          {"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[0,0,48,48]},
           "children":[{"type":"shape","id":"tabArt","shape":{"kind":"rect"}}]}]}
        """#
        let r = Skin2Resolver.resolve(try Self.doc(Self.panel(tab: tab)), in: Self.env())
        #expect(r.nodes.compactMap(\.id) == ["vmuPanel", "rail", "tab", "tabArt"])
    }

    @Test("An open shelf shows everything")
    func openShelfShowsEverything() throws {
        let r = Skin2Resolver.resolve(try Self.doc(Self.panel()), in: Self.env(flags: ["panel.vmu.open"]))
        #expect(r.nodes.compactMap(\.id) == ["vmuPanel", "vmuPanel.body", "vmuPanel.lcd", "tab"])
        #expect(r.panels.first?.isOpen == true)
        #expect(r.node(id: "vmuPanel.lcd")?.panelName == "vmu")
        #expect(r.nodes.first?.panelName == nil)
    }

    @Test("A fixed panel is always shown and hides its handle")
    func fixedPanelHidesItsHandle() throws {
        let r = Skin2Resolver.resolve(try Self.doc(Self.panel(presentation: "fixed")), in: Self.env())
        #expect(r.nodes.compactMap(\.id) == ["vmuPanel", "vmuPanel.body", "vmuPanel.lcd"])
        let panel = try #require(r.panels.first)
        #expect(panel.presentation == .fixed && panel.isOpen && !panel.handleReachable)
        let byDefault = Skin2Resolver.resolve(try Self.doc(Self.panel(presentation: nil, handle: nil, tab: #"{"type":"group","id":"tab"}"#)), in: Self.env())
        #expect(byDefault.panels.first?.presentation == .fixed)
        #expect(byDefault.node(id: "tab") != nil)
    }

    @Test("A when entry can change the presentation")
    func whenPatchCanChangePresentation() throws {
        let doc = try Self.doc(Self.panel(when: #"{"minWidth":700,"panel":{"presentation":"fixed"}}"#))
        #expect(Skin2Resolver.resolve(doc, in: Self.env(1024, 768)).panels.first?.presentation == .fixed)
        #expect(Skin2Resolver.resolve(doc, in: Self.env(1024, 768)).node(id: "vmuPanel.lcd") != nil)
        #expect(Skin2Resolver.resolve(doc, in: Self.env()).panels.first?.presentation == .shelf)
    }

    @Test("A shelf's own when entries read its open flag")
    func openFlagDrivesWhen() throws {
        let doc = try Self.doc(Self.panel(when: #"{"flag":"panel.vmu.open","layout":{"frame":[10,100,160,120]}}"#))
        #expect(Skin2Resolver.resolve(doc, in: Self.env()).panels.first?.frame.x == 100)
        #expect(Skin2Resolver.resolve(doc, in: Self.env(flags: ["panel.vmu.open"])).panels.first?.frame.x == 10)
    }

    @Test("The first-run flags follow open")
    func initialPanelFlagsFollowOpen() throws {
        #expect(try Self.doc(Self.panel(open: true)).initialPanelFlags == ["panel.vmu.open"])
        #expect(try Self.doc(Self.panel()).initialPanelFlags == [])
        #expect(Skin2Panel.openFlag("vmu") == "panel.vmu.open")
        #expect(Skin2Panel.toggleInput == "togglePanel" && Skin2Panel.flagPrefix == "panel.")
    }

    @Test("A handle pushed outside the safe area is not reachable")
    func handleOutsideSafeAreaIsNotReachable() throws {
        let doc = try Self.doc(Self.panel())
        let moved = Skin2Resolver.resolve(doc, in: Self.env(), edits: ["tab": Skin2Edit(offset: .init(x: -400, y: 0))])
        #expect(moved.panels.first?.handleReachable == false)
        let insets = Skin2Environment(size: Skin2Size(width: 390, height: 844), safeArea: Skin2Insets(top: 0, left: 120, bottom: 0, right: 0),
                                      capabilities: Self.caps)
        #expect(Skin2Resolver.resolve(doc, in: insets).panels.first?.handleReachable == false)
        let hidden = Skin2Resolver.resolve(doc, in: Self.env(), edits: ["tab": Skin2Edit(hidden: true)])
        #expect(hidden.panels.first?.handleReachable == false)
    }

    @Test("A stack sizes a closed shelf to its handle")
    func closedShelfInAStackTakesHandleSpace() throws {
        let children = #"""
        {"type":"group","id":"shelf","stack":{"axis":"horizontal","spacing":0},
         "panel":{"name":"vmu","presentation":"shelf","handle":"#tab"},
         "children":[
           {"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"size":{"width":48,"height":48}}},
           {"type":"shape","id":"body","shape":{"kind":"rect"},"layout":{"size":{"width":100,"height":48}}}]}
        """#
        let doc = try Self.doc(children)
        #expect(Skin2Resolver.resolve(doc, in: Self.env()).node(id: "shelf")?.frame.width == 48)
        #expect(Skin2Resolver.resolve(doc, in: Self.env(flags: ["panel.vmu.open"])).node(id: "shelf")?.frame.width == 148)
    }

    // MARK: Validator

    @Test("The base panel validates cleanly")
    func clean() {
        #expect(Self.report(Self.panel()).issues == [])
        #expect(Self.report(Self.panel(presentation: "fixed", handle: nil, tab: #"{"type":"group","id":"tab"}"#)).issues == [])
    }

    @Test("A shelf needs a handle inside its group")
    func shelfNeedsAHandleInsideTheGroup() {
        let missing = Self.report(Self.panel(handle: nil))
        #expect(Self.has(missing.errors, at: "/root/children/0/panel/handle", "handle"))
        let outside = Self.report(Self.panel(tab: #"{"type":"group","id":"nothing"}"#)
            + #","# + #"{"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[100,300,48,48]}}"#)
        #expect(Self.has(outside.errors, at: "/root/children/0/panel/handle", "inside"))
        let byCondition = Self.report(Self.panel(presentation: "fixed", handle: nil, when: #"{"minWidth":700,"panel":{"presentation":"shelf"}}"#))
        #expect(Self.has(byCondition.errors, at: "/root/children/0/panel/handle", "handle"))
    }

    @Test("A handle is an action control that sends togglePanel")
    func handleMustBeAnActionWithTogglePanel() {
        let button = Self.report(Self.panel(tab: #"{"type":"control","id":"tab","kind":"button","input":"a","layout":{"frame":[0,0,48,48]}}"#))
        #expect(Self.has(button.errors, at: "/root/children/0/panel/handle", "togglePanel"))
        let stray = Self.report(Self.panel() + #","# + #"{"type":"control","id":"other","kind":"action","input":"togglePanel","layout":{"frame":[100,300,48,48]}}"#)
        #expect(Self.has(stray.errors, at: "/root/children/1", "handle"))
    }

    @Test("A handle is at least 44 by 44 points")
    func handleSmallerThan44IsAnError() {
        let r = Self.report(Self.panel(tab: #"{"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[0,0,40,40]}}"#))
        #expect(Self.has(r.errors, at: "/root/children/0/children/2", "44"))
        let extended = Self.report(Self.panel(tab: #"{"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[2,2,40,40]},"hit":{"extend":2}}"#))
        #expect(!Self.has(extended.errors, "44"))
    }

    @Test("A handle may not overlap another control in either state")
    func handleOverlappingAControlInEitherStateIsAnError() {
        let tab = #"""
        {"type":"control","id":"tab","kind":"action","input":"togglePanel","layout":{"frame":[0,0,48,48]},
         "when":[{"flag":"panel.vmu.open","layout":{"frame":[200,0,48,48]}}]}
        """#
        let a = #"{"type":"control","id":"a","kind":"button","input":"a","layout":{"frame":[300,100,60,60]}}"#
        let r = Self.report(Self.panel(tab: tab) + "," + a)
        #expect(Self.has(r.errors, "overlaps"))
        #expect(Self.report(Self.panel() + "," + a).errors.isEmpty)
    }

    @Test("A handle lies inside the safe area on every bake trait")
    func handleOutsideSafeAreaOnABakeTraitIsAnError() {
        let r = Self.report(Self.panel(origin: "20, 100"))
        #expect(Self.has(r.errors, at: "/root/children/0/children/2", "safe area"))
        #expect(r.errors.contains { $0.message.contains("iphone-edgeToEdge-landscape") })
    }

    @Test("Panels do not nest")
    func nestedPanelIsAnError() {
        let inner = Self.panel(name: "inner", id: "innerPanel", origin: "0, 60", presentation: "fixed", handle: nil,
                               tab: #"{"type":"group","id":"innerPanel.pad"}"#)
        let r = Self.report(Self.panel(extraChildren: inner))
        #expect(Self.has(r.errors, at: "/root/children/0/children/3/panel", "inside"))
    }

    @Test("Panel names are unique")
    func duplicatePanelNameIsAnError() {
        let second = Self.panel(id: "second", origin: "100, 300", presentation: "fixed", handle: nil, tab: #"{"type":"group","id":"second.pad"}"#)
        #expect(Self.has(Self.report(Self.panel() + "," + second).errors, at: "/root/children/1/panel/name", "already"))
    }

    @Test("At most six panels")
    func sevenPanelsIsAnError() {
        func fixed(_ i: Int) -> String {
            #"{"type":"group","id":"p\#(i)","layout":{"frame":[0,\#(i * 20),20,20]},"panel":{"name":"p\#(i)"}}"#
        }
        #expect(Self.report((1...6).map(fixed).joined(separator: ",")).errors.isEmpty)
        #expect(Self.has(Self.report((1...7).map(fixed).joined(separator: ",")).errors, at: "/root", "6 panels"))
    }

    @Test("A panel name is at most 64 characters of letters, digits, _ and -")
    func panelNameOver64CharactersIsAnError() {
        let long = String(repeating: "n", count: 65)
        let r = Self.report(#"{"type":"group","id":"p","panel":{"name":"\#(long)"}}"#)
        #expect(Self.has(r.errors, at: "/root/children/0/panel/name", "64"))
        #expect(Self.report(#"{"type":"group","id":"p","panel":{"name":"\#(String(repeating: "n", count: 64))"}}"#).errors.isEmpty)
        #expect(!Self.report(#"{"type":"group","id":"p","panel":{"name":"a.b"}}"#).errors.isEmpty)
    }

    @Test("A panel flag names a panel of this skin")
    func appFlagsMayNotUsePanelPrefix() {
        let lamp = #"{"type":"group","id":"lamp","visible":{"flag":"panel.x.open"}}"#
        #expect(Self.has(Self.report(Self.panel() + "," + lamp).errors, at: "/root/children/1/visible/flag", "panel.x.open"))
        let good = #"{"type":"group","id":"lamp","visible":{"flag":"panel.vmu.open"}}"#
        #expect(Self.report(Self.panel() + "," + good).errors.isEmpty)
    }

    @Test("needs names capabilities; using a panel is the panels feature")
    func needsAndFeature() {
        let r = Self.report(Self.panel(needs: #"["picture.nope"]"#))
        #expect(Self.has(r.errors, at: "/root/children/0/panel/needs/0", "picture.nope"))
        let unlisted = Skin2Validator.validate(data: Data(skinJSON(children: #"{"type":"group","id":"p","panel":{"name":"p"}}"#, requires: "[]").utf8))
        #expect(Self.has(unlisted.errors, at: "/requires", "uses panels"))
    }

    @Test("Schema and decoder agree on panel")
    func schemaShapes() throws {
        let schema = SchemaValidator(root: Skin2Schema.document)
        let good = try Skin2JSON.parse(Data(skinJSON(children: Self.panel(when: #"{"minWidth":700,"panel":{"presentation":"fixed"}}"#)).utf8))
        #expect(schema.errors(good) == [])
        for bad in [#"{"type":"group","panel":{"label":"no name"}}"#, #"{"type":"group","panel":{"name":"p","presentation":"drawer"}}"#,
                    #"{"type":"group","panel":{"name":"p","handle":"tab"}}"#, #"{"type":"group","panel":{"name":"a b"}}"#,
                    #"{"type":"group","panel":{"name":"p"},"when":[{"minWidth":1,"panel":{"presentation":"popout"}}]}"#] {
            let source = try Skin2JSON.parse(Data(skinJSON(children: bad).utf8))
            #expect(!schema.errors(source).isEmpty, "schema accepts \(bad)")
            #expect(throws: Skin2Error.self, "decoder accepts \(bad)") { try Skin2Document.load(json: source) }
        }
    }
}
