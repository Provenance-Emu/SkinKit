#if canImport(UIKit)
import Foundation
import SkinKit2Render
import Testing
import UIKit
@testable import SkinKitUI

@Suite("Format 2.0 input sink")
struct Format2SinkTests {
    private class Plain: DeltaSkinInputHandling {
        var buttons: [String] = []
        let turboManager = TurboManager()
        let stickyManager = StickyButtonManager()
        var dsScreensSwapped: Bool { false }
        func buttonPressed(_ buttonId: String) { buttons.append("+" + buttonId) }
        func buttonReleased(_ buttonId: String) { buttons.append("-" + buttonId) }
        func analogStickMoved(_ stickId: String, x: Float, y: Float) {}
        func ndsBottomScreenTouched(at normalizedPoint: CGPoint) {}
        func ndsBottomScreenTouchReleased() {}
    }

    private final class Semantic: Plain, DeltaSkinSemanticInputHandling {
        var semantic: [String] = []
        func semanticInput(_ name: String, pressed: Bool) { semantic.append((pressed ? "+" : "-") + name) }
    }

    @Test("Dotted names go to the semantic handler and never to buttonPressed")
    func sinkRoutesDottedNamesToTheSemanticHandler() {
        let handler = Semantic()
        let sink = DeltaSkinFormat2Sink(handler)
        sink.press("arcade.coin1")
        sink.release("arcade.coin1")
        sink.press("a")
        sink.release("a")
        #expect(handler.semantic == ["+arcade.coin1", "-arcade.coin1"])
        #expect(handler.buttons == ["+a", "-a"])
    }

    @Test("Without the protocol a dotted name is dropped")
    func sinkDropsDottedNamesWhenHandlerLacksTheProtocol() {
        let handler = Plain()
        let sink = DeltaSkinFormat2Sink(handler)
        sink.press("arcade.coin1")
        sink.release("arcade.coin1")
        #expect(handler.buttons.isEmpty)
    }
}
#endif
