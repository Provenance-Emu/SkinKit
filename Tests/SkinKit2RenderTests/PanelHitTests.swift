import Foundation
import SkinKit2Core
@testable import SkinKit2Render
import Testing

@Suite("Panel handles in hit testing")
struct PanelHitTests {
    @Test("A shelf's handle is marked with its panel; other controls are not")
    func handleTogglesItsPanel() throws {
        let doc = try renderSkin(#"""
        { "type": "group", "id": "shelf", "panel": { "name": "vmu", "presentation": "shelf", "handle": "#tab" },
          "children": [
            { "type": "control", "id": "tab", "kind": "action", "input": "togglePanel", "layout": { "frame": [0, 0, 48, 48] } },
            { "type": "control", "id": "a", "kind": "button", "input": "a", "layout": { "frame": [50, 0, 48, 48] } } ] }
        """#, requires: "[]", extra: #""optional": ["panels"]"#)
        let open = Skin2Environment(size: Skin2Size(width: 100, height: 100), flags: ["panel.vmu.open"])
        let tester = Skin2HitTester(Skin2Resolver.resolve(doc, in: open))
        #expect(tester.control(id: "tab")?.togglesPanel == "vmu")
        #expect(tester.control(id: "a") != nil && tester.control(id: "a")?.togglesPanel == nil)
        let closed = Skin2HitTester(Skin2Resolver.resolve(doc, in: Skin2Environment(size: Skin2Size(width: 100, height: 100))))
        #expect(closed.controls.map(\.id) == ["tab"])
        #expect(SkinKit2Render.supportedFeatures.contains("panels"))
    }
}
