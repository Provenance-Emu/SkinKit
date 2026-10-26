#if canImport(UIKit) && !os(tvOS)
import Foundation
import SkinKitCore
import SwiftUI
import Testing
import UIKit
@testable import SkinKitUI

/// iFly's skin behavior that SkinKitUI offers as opt-ins: combo hotspots, the empty-area hold, scaled
/// haptics, press feedback and D-pad feedback on change only. Each is tested off (the default, which is
/// Provenance's behavior) and on.
extension UIKitSerial {
    @Suite("Opt-in skin behavior", .serialized)
    @MainActor
    final class OptInSkinBehaviorTests {

        // MARK: - Recording handler

        final class Hold: DeltaSkinHoldHandling {
            var holdDelay: TimeInterval { 0.3 }
            var events: [String] = []
            var slides: [CGFloat] = []
            func holdDidBegin() { events.append("begin") }
            func holdDidSlide(dx: CGFloat) { slides.append(dx) }
            func holdDidEnd() { events.append("end") }
        }

        final class Handler: DeltaSkinInputHandling, ObservableObject {
            let turboManager = TurboManager()
            let stickyManager = StickyButtonManager()
            var dsScreensSwapped = false
            var pressed: Set<String> = []
            var hold: Hold?
            var holdHandler: (any DeltaSkinHoldHandling)? { hold }
            func buttonPressed(_ buttonId: String) { pressed.insert(buttonId) }
            func buttonReleased(_ buttonId: String) { pressed.remove(buttonId) }
            func analogStickMoved(_ stickId: String, x: Float, y: Float) {}
            func ndsBottomScreenTouched(at normalizedPoint: CGPoint) {}
            func ndsBottomScreenTouchReleased() {}
            func touchRole(forToken token: String) -> TouchInputRole { token == "menu" ? .system : .gameplay }
        }

        // MARK: - A skin with a combo, a system combo, a plain button, a system button, a D-pad and a screen

        private static let info = """
        {
          "name": "OptIn", "identifier": "com.example.optin", "debug": false,
          "gameTypeIdentifier": "public.aoshuang.game.dc",
          "representations": { "iphone": { "edgeToEdge": { "portrait": {
            "assets": { "resizable": "skin.pdf" },
            "mappingSize": { "width": 414, "height": 896 },
            "screens": [ { "inputFrame": { "x": 0, "y": 0, "width": 640, "height": 480 },
                           "outputFrame": { "x": 20, "y": 20, "width": 374, "height": 280 } } ],
            "items": [
              { "inputs": ["a", "b"], "frame": { "x": 20, "y": 600, "width": 60, "height": 60 } },
              { "inputs": ["x", "menu"], "frame": { "x": 140, "y": 600, "width": 60, "height": 60 } },
              { "inputs": ["start"], "frame": { "x": 260, "y": 600, "width": 60, "height": 60 } },
              { "inputs": { "up": "up", "down": "down", "left": "left", "right": "right" },
                "frame": { "x": 20, "y": 700, "width": 120, "height": 120 } }
            ]
          } } } }
        }
        """

        private static let traits = DeltaSkinTraits(device: .iphone, displayType: .edgeToEdge, orientation: .portrait)
        private static let size = CGSize(width: 414, height: 896)

        private func makeSkin() throws -> DeltaSkin {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("OptIn-\(UUID().uuidString).deltaskin", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(Self.info.utf8).write(to: dir.appendingPathComponent("info.json"))
            return try DeltaSkin(fileURL: dir)
        }

        private var savedSettings = DeltaSkinInteractionSettings.current
        private var windows: [UIWindow] = []

        init() {
            savedSettings = DeltaSkinInteractionSettings.current
            TestSupport.disableDefaultSkinFallback()
        }

        deinit {
            DeltaSkinInteractionSettings.current = savedSettings
        }

        /// Hosts the skin full-size in a window and returns the touch-detecting view.
        private func host(_ handler: Handler, allowsHold: Bool = false) async throws
            -> MultiTouchView.TouchDetectingView {
            let view = DeltaSkinView(skin: try makeSkin(), traits: Self.traits, isInEmulator: true,
                                     inputHandler: handler, allowsEmptyAreaHold: allowsHold)
                .frame(width: Self.size.width, height: Self.size.height)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(origin: .zero, size: Self.size))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            windows.append(window)
            var found: MultiTouchView.TouchDetectingView?
            for _ in 0..<40 {
                try await Task.sleep(nanoseconds: 100_000_000)
                controller.view.layoutIfNeeded()
                found = Self.find(MultiTouchView.TouchDetectingView.self, in: controller.view)
                if found != nil { break }
            }
            try await Task.sleep(nanoseconds: 300_000_000) // let onAppear record the view size
            return try #require(found)
        }

        private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
            if let match = view as? T { return match }
            for sub in view.subviews { if let match = find(type, in: sub) { return match } }
            return nil
        }

        private func touch(_ view: MultiTouchView.TouchDetectingView, _ phase: MultiTouchPhase, _ touch: UITouch,
                           at point: CGPoint) async throws {
            view.touchHandler?(phase, [TouchPoint(touch: touch, location: point)])
            try await Task.sleep(nanoseconds: 60_000_000)
        }

        private func settle(_ seconds: Double = 0.6) async throws {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }

        private let comboCenter = CGPoint(x: 50, y: 630)
        private let systemComboCenter = CGPoint(x: 170, y: 630)
        private let startCenter = CGPoint(x: 290, y: 630)
        private let emptyOnScreen = CGPoint(x: 200, y: 150)
        private let emptyOffScreen = CGPoint(x: 200, y: 400)

        // MARK: - Combo hotspots

        @Test("Off (default): a combo hotspot presses its first input only")
        func comboOff() async throws {
            DeltaSkinInteractionSettings.current = DeltaSkinInteractionSettings()
            let handler = Handler()
            let view = try await host(handler)
            let finger = UITouch()
            try await touch(view, .began, finger, at: comboCenter)
            #expect(handler.pressed == ["a"])
            try await touch(view, .ended, finger, at: comboCenter)
            #expect(handler.pressed.isEmpty)
        }

        @Test("On: a combo hotspot presses every input and releases them together")
        func comboOn() async throws {
            DeltaSkinInteractionSettings.current = DeltaSkinInteractionSettings(pressesComboInputs: { true })
            let handler = Handler()
            let view = try await host(handler)
            let finger = UITouch()
            try await touch(view, .began, finger, at: comboCenter)
            #expect(handler.pressed == ["a", "b"])
            try await touch(view, .ended, finger, at: comboCenter)
            #expect(handler.pressed.isEmpty)
        }

        @Test("On: a combo with a system member is a system control (touch-down only, no slide-in); off, it is gameplay")
        func comboRoleFollowsEveryMember() async throws {
            for on in [false, true] {
                DeltaSkinInteractionSettings.current = DeltaSkinInteractionSettings(pressesComboInputs: { on })
                let handler = Handler()
                let view = try await host(handler)
                // A finger that lands elsewhere and slides onto the combo.
                let finger = UITouch()
                try await touch(view, .began, finger, at: CGPoint(x: 350, y: 500))
                try await touch(view, .moved, finger, at: systemComboCenter)
                // Off: the combo's first input is "x", a gameplay token, so the slide reaches it.
                // On: "menu" is a member, so the slide must not.
                #expect(handler.pressed == (on ? [] : ["x"]), "pressesComboInputs \(on)")
                try await touch(view, .ended, finger, at: systemComboCenter)

                // Touching down on it presses the whole chord, system member included.
                let second = UITouch()
                try await touch(view, .began, second, at: systemComboCenter)
                #expect(handler.pressed == (on ? ["x", "menu"] : ["x"]), "pressesComboInputs \(on)")
                try await touch(view, .ended, second, at: systemComboCenter)
            }
        }

        // MARK: - Empty-area hold

        @Test("Off (default): resting on empty screen does nothing")
        func holdOff() async throws {
            let handler = Handler()
            handler.hold = Hold()
            let view = try await host(handler, allowsHold: false)
            let finger = UITouch()
            try await touch(view, .began, finger, at: emptyOnScreen)
            try await settle()
            try await touch(view, .ended, finger, at: emptyOnScreen)
            #expect(handler.hold?.events == [])
        }

        @Test("On: a finger resting on the empty screen fires the hold after the delay, reports its slide, and ends it on lift")
        func holdOn() async throws {
            let handler = Handler()
            let hold = Hold()
            handler.hold = hold
            let view = try await host(handler, allowsHold: true)
            let finger = UITouch()
            try await touch(view, .began, finger, at: emptyOnScreen)
            try await settle()
            #expect(hold.events == ["begin"])
            try await touch(view, .moved, finger, at: CGPoint(x: emptyOnScreen.x + 40, y: emptyOnScreen.y))
            #expect(hold.slides.last == 40)
            try await touch(view, .ended, finger, at: emptyOnScreen)
            #expect(hold.events == ["begin", "end"])
        }

        @Test("On, but no holdHandler: nothing happens")
        func holdWithoutHandler() async throws {
            let handler = Handler()
            let view = try await host(handler, allowsHold: true)
            let finger = UITouch()
            try await touch(view, .began, finger, at: emptyOnScreen)
            try await settle()
            try await touch(view, .ended, finger, at: emptyOnScreen)
            #expect(handler.pressed.isEmpty)
        }

        @Test("On: a touch on a control, or off the game screen, does not arm the hold")
        func holdNeedsEmptyScreen() async throws {
            let handler = Handler()
            let hold = Hold()
            handler.hold = hold
            let view = try await host(handler, allowsHold: true)
            for point in [startCenter, emptyOffScreen] {
                let finger = UITouch()
                try await touch(view, .began, finger, at: point)
                try await settle()
                try await touch(view, .ended, finger, at: point)
            }
            #expect(hold.events == [])
        }

        @Test("On: drifting onto a control before the delay cancels the hold; drifting within the empty area does not")
        func holdCancelsOnlyOntoAControl() async throws {
            let handler = Handler()
            let hold = Hold()
            handler.hold = hold
            let view = try await host(handler, allowsHold: true)

            let drifting = UITouch()
            try await touch(view, .began, drifting, at: emptyOnScreen)
            try await touch(view, .moved, drifting, at: CGPoint(x: 230, y: 160))
            try await settle()
            #expect(hold.events == ["begin"])
            try await touch(view, .ended, drifting, at: emptyOnScreen)

            hold.events = []
            let sliding = UITouch()
            try await touch(view, .began, sliding, at: CGPoint(x: 270, y: 290))
            try await touch(view, .moved, sliding, at: startCenter)
            try await settle()
            #expect(hold.events == [])
            try await touch(view, .ended, sliding, at: startCenter)
        }

        @Test("On: two resting fingers begin the hold once and end it when the last lifts; only the first slides it")
        func holdCountsFingers() async throws {
            let handler = Handler()
            let hold = Hold()
            handler.hold = hold
            let view = try await host(handler, allowsHold: true)
            let first = UITouch()
            let second = UITouch()
            try await touch(view, .began, first, at: emptyOnScreen)
            try await settle()
            try await touch(view, .began, second, at: CGPoint(x: 300, y: 150))
            try await settle()
            #expect(hold.events == ["begin"])

            hold.slides = []
            try await touch(view, .moved, second, at: CGPoint(x: 340, y: 150))
            #expect(hold.slides.isEmpty, "a later finger does not own the slide")
            try await touch(view, .moved, first, at: CGPoint(x: emptyOnScreen.x + 10, y: emptyOnScreen.y))
            #expect(hold.slides.last == 10)

            try await touch(view, .ended, first, at: emptyOnScreen)
            #expect(hold.events == ["begin"])
            try await touch(view, .ended, second, at: emptyOnScreen)
            #expect(hold.events == ["begin", "end"])
        }

        // MARK: - D-pad feedback on change only

        @Test("D-pad click: every move by default; only when a direction engages with dpadFeedbackOnChangeOnly")
        func dpadFeedback() async throws {
            for changeOnly in [false, true] {
                let clicks = Counter()
                DeltaSkinInteractionSettings.current = DeltaSkinInteractionSettings(
                    playButtonPressSound: { _, _ in clicks.increment() },
                    dpadFeedbackOnChangeOnly: { changeOnly }
                )
                let handler = Handler()
                let view = try await host(handler)
                let finger = UITouch()
                let dpadCenter = CGPoint(x: 80, y: 760)
                try await touch(view, .began, finger, at: CGPoint(x: dpadCenter.x + 50, y: dpadCenter.y))
                let afterPress = clicks.count
                #expect(afterPress >= 1, "changeOnly \(changeOnly)")
                // Wiggle within the same direction.
                try await touch(view, .moved, finger, at: CGPoint(x: dpadCenter.x + 48, y: dpadCenter.y))
                try await touch(view, .moved, finger, at: CGPoint(x: dpadCenter.x + 52, y: dpadCenter.y))
                if changeOnly {
                    #expect(clicks.count == afterPress, "no new direction, no click")
                } else {
                    #expect(clicks.count > afterPress, "a click per move")
                }
                // Now a different direction engages.
                let before = clicks.count
                try await touch(view, .moved, finger, at: CGPoint(x: dpadCenter.x - 50, y: dpadCenter.y))
                #expect(clicks.count > before, "a new direction always clicks")
                try await touch(view, .ended, finger, at: dpadCenter)
            }
        }

        // MARK: - Haptic intensity resolution

        @Test("Haptics: the default gates on vibration at the base intensity; a scaling hook replaces both")
        func hapticIntensity() {
            let off = DeltaSkinInteractionSettings(isButtonVibrationEnabled: { false })
            let on = DeltaSkinInteractionSettings(isButtonVibrationEnabled: { true })
            #expect(off.hapticIntensity(0.6) == nil)
            #expect(on.hapticIntensity(0.6) == 0.6)

            // A scaling hook decides on its own: vibration setting ignored, intensity scaled, nil means none.
            let scaled = DeltaSkinInteractionSettings(isButtonVibrationEnabled: { false },
                                                      scaledHapticIntensity: { $0 * 0.5 })
            #expect(scaled.hapticIntensity(1.0) == 0.5)
            let muted = DeltaSkinInteractionSettings(isButtonVibrationEnabled: { true },
                                                     scaledHapticIntensity: { _ in nil })
            #expect(muted.hapticIntensity(1.0) == nil)
        }

        @Test("Defaults leave every opt-in off")
        func defaultsAreOff() {
            let defaults = DeltaSkinInteractionSettings()
            #expect(!defaults.pressesComboInputs())
            #expect(!defaults.showsTouchFeedback())
            #expect(!defaults.dpadFeedbackOnChangeOnly())
            #expect(defaults.scaledHapticIntensity == nil)
            #expect(DeltaSkinPreviewInputHandler().holdHandler == nil)
        }

        // MARK: - Press feedback

        @Test("The press highlight and touch indicator draw")
        func feedbackViewsDraw() async throws {
            let highlight = DeltaSkinButtonHighlight(frame: CGRect(x: 100, y: 100, width: 80, height: 80),
                                                     mappingSize: CGSize(width: 414, height: 896),
                                                     previewSize: Self.size, buttonId: "a")
                .frame(width: Self.size.width, height: Self.size.height)
            let indicator = DeltaSkinTouchIndicator(at: CGPoint(x: 100, y: 100))
                .tint(.red)
                .frame(width: 200, height: 200)
            for view in [AnyView(highlight), AnyView(indicator)] {
                let controller = UIHostingController(rootView: view)
                let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 414, height: 896)))
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.layoutIfNeeded()
                #expect(controller.view.bounds.width > 0)
                window.isHidden = true
            }
        }

        @Test("Press feedback on: touching a button and lifting leaves no highlight behind, and nothing crashes")
        func feedbackOn() async throws {
            DeltaSkinInteractionSettings.current = DeltaSkinInteractionSettings(showsTouchFeedback: { true })
            let handler = Handler()
            let view = try await host(handler)
            let finger = UITouch()
            try await touch(view, .began, finger, at: comboCenter)
            #expect(handler.pressed == ["a"])
            try await touch(view, .ended, finger, at: comboCenter)
            try await settle(0.4)
            #expect(handler.pressed.isEmpty)
        }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }
}
#endif
