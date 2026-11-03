#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

extension UIKitSerial {
    @Suite("toggleAltRepresentations input")
    struct AltRepresentationsToggleTests {
        /// A host handler that keeps the protocol's default `toggleAltRepresentations()`.
        private final class DefaultHandler: DeltaSkinInputHandling {
            let turboManager = TurboManager()
            let stickyManager = StickyButtonManager()
            var dsScreensSwapped = false
            var pressed: [String] = []
            func buttonPressed(_ buttonId: String) { pressed.append(buttonId) }
            func buttonReleased(_ buttonId: String) {}
            func analogStickMoved(_ stickId: String, x: Float, y: Float) {}
            func ndsBottomScreenTouched(at normalizedPoint: CGPoint) {}
            func ndsBottomScreenTouchReleased() {}
        }

        @Test("The default implementation posts the toggle request with the handler as the object")
        func defaultPostsNotification() {
            let handler = DefaultHandler()
            var received = 0
            let token = NotificationCenter.default.addObserver(
                forName: DeltaSkinAltRepresentationsToggle.requestedNotification, object: handler, queue: nil
            ) { _ in received += 1 }
            defer { NotificationCenter.default.removeObserver(token) }

            handler.toggleAltRepresentations()
            #expect(received == 1)
            #expect(handler.pressed.isEmpty)   // never forwarded as a gameplay press
            #expect(DeltaSkinAltRepresentationsToggle.input == "toggleAltRepresentations")
        }

        @Test("The preview handler flips its flag on each press")
        func previewHandlerFlips() {
            let handler = DeltaSkinPreviewInputHandler()
            #expect(!handler.usesAltRepresentations)
            handler.toggleAltRepresentations()
            #expect(handler.usesAltRepresentations)
            handler.toggleAltRepresentations()
            #expect(!handler.usesAltRepresentations)
            #expect(handler.altRepresentationsToggleCount == 2)
            #expect(handler.pressedButtons.isEmpty)
        }
    }
}
#endif
