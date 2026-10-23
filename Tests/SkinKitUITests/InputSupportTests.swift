#if canImport(UIKit)
import Foundation
import SkinKitCore
import Testing
import UIKit
@testable import SkinKitUI

extension UIKitSerial {
    @Suite("Thumbstick side resolution")
    struct ThumbstickSideTests {
        // Ported from Provenance's DeltaSkinNintendoHomeConsoleTests (skipped in SkinKitCore: it lived beside the
        // GameCube/Wii tables, which need PVCoreBridge).
        private let skinId = "starvingartist.ngc.gcpocket-indigo-button-1"

        @Test("Manic leftThumbstick* mapping resolves left")
        func left() {
            let input = DeltaSkinInput.directional([
                "up": "leftThumbstickUp", "down": "leftThumbstickDown",
                "left": "leftThumbstickLeft", "right": "leftThumbstickRight"
            ])
            #expect(DeltaSkinThumbstickSide.resolve(for: input, buttonId: skinId) == .left)
        }

        @Test("Manic rightThumbstick* mapping resolves right even though the id never says so")
        func right() {
            let input = DeltaSkinInput.directional([
                "up": "rightThumbstickUp", "down": "rightThumbstickDown",
                "left": "rightThumbstickLeft", "right": "rightThumbstickRight"
            ])
            let side = DeltaSkinThumbstickSide.resolve(for: input, buttonId: skinId)
            #expect(side == .right)
            #expect(side.analogStickId == "rightAnalog")
        }

        @Test("A plain D-pad mapping is not mistaken for a right stick")
        func dpadIsNotRight() {
            let input = DeltaSkinInput.directional(["up": "up", "down": "down", "left": "left", "right": "right"])
            #expect(DeltaSkinThumbstickSide.resolve(for: input, buttonId: skinId) == .left)
        }

        @Test("Falls back to the button id when the mapping carries no stick name")
        func idFallback() {
            let input = DeltaSkinInput.single("a")
            #expect(DeltaSkinThumbstickSide.resolve(for: input, buttonId: "rightstick") == .right)
            #expect(DeltaSkinThumbstickSide.resolve(for: input, buttonId: "leftstick") == .left)
            #expect(DeltaSkinThumbstickSide.left.analogStickId == "leftAnalog")
        }
    }

    @Suite("Input handling seam")
    struct InputHandlingTests {

        @Test("The preview handler records presses, releases, sticks and DS touches")
        func previewHandlerRecords() {
            let handler = DeltaSkinPreviewInputHandler()
            handler.buttonPressed("a")
            handler.buttonPressed("b")
            handler.buttonReleased("a")
            #expect(handler.pressedButtons == ["b"])

            handler.analogStickMoved("leftAnalog", x: 0.5, y: -1)
            #expect(handler.stickPositions["leftAnalog"] == CGPoint(x: 0.5, y: -1))

            handler.ndsBottomScreenTouched(at: CGPoint(x: 0.25, y: 0.75))
            #expect(handler.ndsTouch == CGPoint(x: 0.25, y: 0.75))
            handler.ndsBottomScreenTouchReleased()
            #expect(handler.ndsTouch == nil)
        }

        @Test("Through the protocol, the default role of any token is gameplay and a handler can override it")
        func roleDefault() {
            let preview: any DeltaSkinInputHandling = DeltaSkinPreviewInputHandler()
            #expect(preview.touchRole(forToken: "menu") == .gameplay)

            final class MenuAware: DeltaSkinInputHandling {
                let turboManager = TurboManager()
                let stickyManager = StickyButtonManager()
                let dsScreensSwapped = false
                func buttonPressed(_ buttonId: String) {}
                func buttonReleased(_ buttonId: String) {}
                func analogStickMoved(_ stickId: String, x: Float, y: Float) {}
                func ndsBottomScreenTouched(at normalizedPoint: CGPoint) {}
                func ndsBottomScreenTouchReleased() {}
                func touchRole(forToken token: String) -> TouchInputRole { token == "menu" ? .system : .gameplay }
            }
            let aware: any DeltaSkinInputHandling = MenuAware()
            #expect(aware.touchRole(forToken: "menu") == .system)
            #expect(aware.touchRole(forToken: "a") == .gameplay)
        }

        @Test("A double tap makes a button sticky, and a second double tap releases it")
        func stickyDoubleTap() {
            let sticky = StickyButtonManager()
            #expect(sticky.handlePress("a") == .press)
            #expect(sticky.handleRelease("a") == .release)
            // Second press inside the double-tap window: sticky on, and a fresh press goes to the core.
            #expect(sticky.handlePress("a") == .press)
            #expect(sticky.isSticky("a"))
            #expect(sticky.handleRelease("a") == .ignore)
            #expect(sticky.stickyButtons == ["a"])
            #expect(sticky.releaseAll() == ["a"])
            #expect(!sticky.isSticky("a"))
        }

        @Test("Turbo toggles per button and presses once on touch-down")
        func turboToggle() {
            let previous = DeltaSkinInteractionSettings.current
            defer { DeltaSkinInteractionSettings.current = previous }
            DeltaSkinInteractionSettings.current.isTurboEnabled = { true }

            let turbo = TurboManager()
            nonisolated(unsafe) var events: [String] = []
            turbo.buttonAction = { id, pressed in events.append("\(id):\(pressed)") }

            #expect(turbo.toggleTurbo(for: "a") == true)
            #expect(turbo.isTurboActive(for: "a"))
            turbo.buttonDown("a")
            turbo.buttonUp("a")
            #expect(events == ["a:true", "a:false"])
            #expect(turbo.toggleTurbo(for: "a") == false)
            #expect(!turbo.isTurboActive(for: "a"))
            // Not a turbo button: the manager stays out of it.
            turbo.buttonDown("b")
            turbo.buttonUp("b")
            #expect(events.count == 2)
        }

        @Test("The interaction settings default to Provenance's defaults and are replaceable")
        func settingsDefaults() {
            let defaults = DeltaSkinInteractionSettings()
            #expect(defaults.isButtonVibrationEnabled())
            #expect(!defaults.isButtonSoundEnabled())
            #expect(defaults.isTurboEnabled())
            #expect(!defaults.isStickyButtonsEnabled())
            #expect(!defaults.isMultiButtonTouchEnabled())
            #expect(defaults.turboRateHz() == 10)
            #expect(!defaults.isCaseCompanionSkinsEnabled())
        }

        @MainActor
        @Test("Button offsets persist per skin and reset")
        func buttonOffsets() {
            let offsets = DeltaSkinButtonOffsets.shared
            let skinId = "com.test.offsets.\(UUID().uuidString)"
            defer { offsets.resetOffsets(for: skinId) }
            #expect(!offsets.hasCustomOffsets(for: skinId))
            #expect(offsets.offset(for: "a", skinIdentifier: skinId) == .zero)
            offsets.setOffset(CGPoint(x: 4, y: -3), for: "a", skinIdentifier: skinId)
            #expect(offsets.offset(for: "a", skinIdentifier: skinId) == CGPoint(x: 4, y: -3))
            #expect(offsets.hasCustomOffsets(for: skinId))
            offsets.resetOffsets(for: skinId)
            #expect(offsets.offset(for: "a", skinIdentifier: skinId) == .zero)
            #expect(!offsets.hasCustomOffsets(for: skinId))
        }
    }
}

#endif
